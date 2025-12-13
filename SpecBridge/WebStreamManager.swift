//
//  WebStreamManager.swift
//  SpecBridge
//
//  Web streaming alternative to TwitchManager.
//  POSTs JPEG frames to a local web server instead of RTMP.
//

import Foundation
import Combine
import UIKit
import AVFoundation

@MainActor
class WebStreamManager: ObservableObject {
    @Published var isStreaming = false
    @Published var connectionStatus = "Disconnected"
    
    private var serverURL: URL
    private let session: URLSession
    
    // Throttle: send max ~15 fps to avoid overwhelming network
    private var lastFrameTime: Date = .distantPast
    private let minFrameInterval: TimeInterval = 1.0 / 15.0
    
    // CIContext for efficient image conversion (reuse for performance)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // Track frames sent
    private var framesSent: Int = 0
    private var lastErrorTime: Date = .distantPast
    
    init(serverHost: String = "192.168.1.100", port: Int = 3000) {
        self.serverURL = URL(string: "http://\(serverHost):\(port)/api/frame")!
        
        // Configure URLSession for low latency
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }
    
    func updateServerURL(host: String, port: Int) {
        self.serverURL = URL(string: "http://\(host):\(port)/api/frame")!
        print("Server URL updated to: \(serverURL)")
    }
    
    func startStreaming() {
        isStreaming = true
        connectionStatus = "Streaming"
        framesSent = 0
        print("WebStreamManager: Started streaming to \(serverURL)")
    }
    
    func stopStreaming() {
        isStreaming = false
        connectionStatus = "Disconnected"
        print("WebStreamManager: Stopped streaming. Total frames sent: \(framesSent)")
    }
    
    nonisolated func processVideoFrame(_ buffer: CMSampleBuffer) {
        // Get pixel buffer synchronously (must happen immediately, buffer is not retained)
        guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else {
            print("Failed to get image buffer")
            return
        }
        
        // Convert to CIImage and then to JPEG synchronously
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        
        // Create a local CIContext for this conversion
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("Failed to create CGImage")
            return
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.6) else {
            print("Failed to create JPEG data")
            return
        }
        
        // Now send asynchronously
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard self.isStreaming else { return }
            
            // Throttle frames
            let now = Date()
            guard now.timeIntervalSince(self.lastFrameTime) >= self.minFrameInterval else { return }
            self.lastFrameTime = now
            
            await self.sendFrame(jpegData)
        }
    }
    
    private func sendFrame(_ data: Data) async {
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        
        do {
            let (_, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    await MainActor.run {
                        self.framesSent += 1
                        if self.connectionStatus != "Streaming" {
                            self.connectionStatus = "Streaming"
                        }
                    }
                } else {
                    await handleError("HTTP \(httpResponse.statusCode)")
                }
            }
        } catch {
            await handleError(error.localizedDescription)
        }
    }
    
    private func handleError(_ message: String) async {
        let now = Date()
        // Only update UI every 2 seconds to avoid spam
        if now.timeIntervalSince(lastErrorTime) > 2 {
            lastErrorTime = now
            await MainActor.run {
                self.connectionStatus = "Error: \(message)"
            }
            print("WebStreamManager error: \(message)")
        }
    }
}

