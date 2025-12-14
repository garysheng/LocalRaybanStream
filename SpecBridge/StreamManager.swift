import Foundation
import SwiftUI
import Combine
import UIKit
import AVFoundation
import MWDATCore
import MWDATCamera

@MainActor
class StreamManager: ObservableObject {
    @Published var currentFrame: UIImage?
    @Published var status = "Ready to Stream"
    @Published var isStreaming = false
    
    private var streamSession: StreamSession?
    private var token: AnyListenerToken?
    
    // Reference to web stream manager
    var webManager: WebStreamManager?
    
    private func configureAudio() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Sets iOS to allow Bluetooth audio (prevents "Video Paused" error)
            // .mixWithOthers allows warning audio to play without interrupting the stream
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("Audio session configured successfully")
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    func startStreaming() async {
        // Check if already streaming
        guard !isStreaming else {
            print("Already streaming, ignoring start request")
            return
        }
        
        status = "Checking permissions..."
        
        // Check current permission status
        let currentStatus = try? await Wearables.shared.checkPermissionStatus(.camera)
        print("Current camera permission status: \(String(describing: currentStatus))")
        
        if currentStatus != .granted {
            status = "Requesting permission..."
            print("Requesting camera permission...")
            
            do {
                let requestResult = try await Wearables.shared.requestPermission(.camera)
                print("Permission request result: \(requestResult)")
                
                if requestResult != .granted {
                    status = "Permission denied. Open Meta AI app to grant access."
                    return
                }
            } catch {
                print("Permission request error: \(error)")
                status = "Permission error. Try again."
                return
            }
        }
        
        status = "Configuring Audio..."
        configureAudio()
        
        status = "Configuring session..."
        let selector = AutoDeviceSelector(wearables: Wearables.shared)
        
        // Low resolution is often better for smooth live streaming latency
        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .low,
            frameRate: 24
        )
        
        let session = StreamSession(streamSessionConfig: config, deviceSelector: selector)
        self.streamSession = session
        
        // --- VIDEO HANDLING ---
        token = session.videoFramePublisher.listen { [weak self] frame in
            // 1. Create the visual image for the iPhone screen
            if let image = frame.makeUIImage() {
                Task { @MainActor in
                    self?.currentFrame = image
                    self?.status = "Streaming Live"
                    self?.isStreaming = true
                }
            }
            
            // 2. Extract the RAW buffer and send to web server
            let buffer = frame.sampleBuffer
            self?.webManager?.processVideoFrame(buffer)
        }
        
        status = "Starting stream..."
        await session.start()
    }
    
    func stopStreaming() async {
        status = "Stopping..."
        await streamSession?.stop()
        
        webManager?.stopStreaming()
        
        status = "Ready to Stream"
        isStreaming = false
        currentFrame = nil
    }
}
