//
//  AudioManager.swift
//  SpecBridge
//
//  Handles audio playback through the PHONE SPEAKER (not Bluetooth).
//  This avoids interrupting the wearables Bluetooth session.
//

import Foundation
import AVFoundation
import Combine

enum ViolationSound {
    case shoes
    case gloves
}

@MainActor
class AudioManager: ObservableObject {
    @Published var isPlaying = false
    
    private var shoesPlayer: AVAudioPlayer?
    private var glovesPlayer: AVAudioPlayer?
    
    // Track last play time for each violation type (10 second cooldown)
    private var lastShoesAlertTime: Date = .distantPast
    private var lastGlovesAlertTime: Date = .distantPast
    private let cooldownInterval: TimeInterval = 10.0
    
    init() {
        prepareAudio()
    }
    
    private func prepareAudio() {
        // Prepare shoes audio
        if let shoesURL = Bundle.main.url(forResource: "shoes", withExtension: "mp3") {
            do {
                shoesPlayer = try AVAudioPlayer(contentsOf: shoesURL)
                shoesPlayer?.prepareToPlay()
                shoesPlayer?.volume = 1.0
                print("AudioManager: shoes.mp3 prepared successfully")
            } catch {
                print("AudioManager: Failed to prepare shoes.mp3 - \(error.localizedDescription)")
            }
        } else {
            print("AudioManager: shoes.mp3 not found in bundle")
        }
        
        // Prepare gloves audio
        if let glovesURL = Bundle.main.url(forResource: "gloves", withExtension: "mp3") {
            do {
                glovesPlayer = try AVAudioPlayer(contentsOf: glovesURL)
                glovesPlayer?.prepareToPlay()
                glovesPlayer?.volume = 1.0
                print("AudioManager: gloves.mp3 prepared successfully")
            } catch {
                print("AudioManager: Failed to prepare gloves.mp3 - \(error.localizedDescription)")
            }
        } else {
            print("AudioManager: gloves.mp3 not found in bundle")
        }
    }
    
    /// Force audio to play through phone speaker, not Bluetooth
    private func forcePhoneSpeaker() {
        do {
            // Override audio route to force speaker output
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
            print("AudioManager: Forced output to phone speaker")
        } catch {
            print("AudioManager: Failed to override audio port - \(error)")
        }
    }
    
    /// Restore normal audio routing after playback
    private func restoreAudioRoute() {
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
        } catch {
            print("AudioManager: Failed to restore audio port - \(error)")
        }
    }
    
    func playWarning(for sound: ViolationSound) {
        let now = Date()
        
        // Force audio through phone speaker to avoid interrupting Bluetooth
        forcePhoneSpeaker()
        
        switch sound {
        case .shoes:
            guard now.timeIntervalSince(lastShoesAlertTime) >= cooldownInterval else {
                print("AudioManager: Shoes alert on cooldown")
                return
            }
            
            guard let player = shoesPlayer else {
                print("AudioManager: No shoes player available")
                return
            }
            
            // Just play without any audio session manipulation
            player.currentTime = 0
            let success = player.play()
            print("AudioManager: Playing shoes warning - success: \(success)")
            
            if success {
                lastShoesAlertTime = now
                isPlaying = true
                updatePlayingState(after: player.duration)
            }
            
        case .gloves:
            guard now.timeIntervalSince(lastGlovesAlertTime) >= cooldownInterval else {
                print("AudioManager: Gloves alert on cooldown")
                return
            }
            
            guard let player = glovesPlayer else {
                print("AudioManager: No gloves player available")
                return
            }
            
            player.currentTime = 0
            let success = player.play()
            print("AudioManager: Playing gloves warning - success: \(success)")
            
            if success {
                lastGlovesAlertTime = now
                isPlaying = true
                updatePlayingState(after: player.duration)
            }
        }
    }
    
    func playWarnings(shoes: Bool, gloves: Bool) {
        if shoes {
            playWarning(for: .shoes)
        }
        if gloves {
            if shoes {
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    playWarning(for: .gloves)
                }
            } else {
                playWarning(for: .gloves)
            }
        }
    }
    
    private func updatePlayingState(after duration: TimeInterval) {
        Task {
            try? await Task.sleep(for: .seconds(duration + 0.1))
            await MainActor.run {
                if shoesPlayer?.isPlaying != true && glovesPlayer?.isPlaying != true {
                    self.isPlaying = false
                    // Restore normal audio routing after playback
                    self.restoreAudioRoute()
                }
            }
        }
    }
    
    func stopAudio() {
        shoesPlayer?.stop()
        glovesPlayer?.stop()
        isPlaying = false
    }
}
