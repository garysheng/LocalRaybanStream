import SwiftUI
import MWDATCore
import UIKit

struct ContentView: View {
    @AppStorage("server_host") private var serverHost: String = "192.168.1.100"
    @AppStorage("server_port") private var serverPort: Int = 3000
    
    @StateObject private var streamManager = StreamManager()
    @StateObject private var webManager = WebStreamManager()
    @StateObject private var visionAnalyzer = VisionAnalyzer()
    @StateObject private var audioManager = AudioManager()
    
    @State private var showSettings = false
    @State private var isRegistered = false
    @State private var analysisStatus: AnalysisStatus = .idle
    @State private var analysisTimer: Timer?
    @State private var isStartingStream = false
    
    enum AnalysisStatus: Equatable {
        case idle
        case analyzing
        case safe
        case violationShoes
        case violationGloves
        case violationBoth
        case error(String)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PolicyAngel")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("PPE Compliance Monitor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                        .font(.title3)
                }
            }
            .padding(.horizontal)
            
            // Video Preview
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black)
                
                if let videoImage = streamManager.currentFrame {
                    Image(uiImage: videoImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(12)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.gray)
                        Text("Glasses Offline")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                    }
                }
                
                // Status indicators overlay
                VStack {
                    HStack {
                        // Live indicator
                        if streamManager.isStreaming {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                Text("LIVE")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.red.opacity(0.9))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        
                        Spacer()
                        
                        // Analysis status badge
                        analysisStatusBadge
                    }
                    Spacer()
                }
                .padding(12)
            }
            .frame(height: 400)
            .padding(.horizontal)
            
            // Status Cards
            HStack(spacing: 12) {
                StatusCard(
                    icon: "eyeglasses",
                    title: "Glasses",
                    status: streamManager.status,
                    isActive: streamManager.isStreaming
                )
                StatusCard(
                    icon: "hand.raised.fill",
                    title: "PPE Status",
                    status: safetyStatusText,
                    isActive: analysisStatus == .safe
                )
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Controls
            VStack(spacing: 12) {
                if !isRegistered {
                    Button {
                        try? Wearables.shared.startRegistration()
                    } label: {
                        Label("Connect to Glasses", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                
                Button {
                    Task {
                        if streamManager.isStreaming {
                            stopAnalysisTimer()
                            await streamManager.stopStreaming()
                            webManager.stopStreaming()
                            analysisStatus = .idle
                            isStartingStream = false
                        } else {
                            guard !isStartingStream else { return }
                            isStartingStream = true
                            webManager.updateServerURL(host: serverHost, port: serverPort)
                            webManager.startStreaming()
                            await streamManager.startStreaming()
                            // Always start the timer - it will wait for frames
                            startAnalysisTimer()
                            isStartingStream = false
                        }
                    }
                } label: {
                    Label(
                        streamManager.isStreaming ? "Stop Monitoring" : (isStartingStream ? "Starting..." : "Start Monitoring"),
                        systemImage: streamManager.isStreaming ? "stop.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(streamManager.isStreaming ? .red : .green)
                .controlSize(.large)
                .disabled(isStartingStream && !streamManager.isStreaming)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .onAppear {
            streamManager.webManager = webManager
        }
        .onDisappear {
            stopAnalysisTimer()
        }
        .onOpenURL { url in
            Task {
                try? await Wearables.shared.handleUrl(url)
                isRegistered = true
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                serverHost: $serverHost,
                serverPort: $serverPort
            )
        }
    }
    
    @ViewBuilder
    private var analysisStatusBadge: some View {
        switch analysisStatus {
        case .idle, .analyzing:
            EmptyView()
        case .safe:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                Text("SAFE")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.green.opacity(0.9))
            .foregroundColor(.white)
            .cornerRadius(6)
        case .violationShoes:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                Text("SHOES REQUIRED")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.red.opacity(0.9))
            .foregroundColor(.white)
            .cornerRadius(6)
        case .violationGloves:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                Text("GLOVES REQUIRED")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.orange.opacity(0.9))
            .foregroundColor(.white)
            .cornerRadius(6)
        case .violationBoth:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                Text("PPE VIOLATION")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.red.opacity(0.9))
            .foregroundColor(.white)
            .cornerRadius(6)
        case .error:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                Text("ERROR")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.gray.opacity(0.9))
            .foregroundColor(.white)
            .cornerRadius(6)
        }
    }
    
    private var safetyStatusText: String {
        switch analysisStatus {
        case .idle, .analyzing:
            return "Monitoring"
        case .safe:
            return "PPE compliant"
        case .violationShoes:
            return "⚠️ Shoes required!"
        case .violationGloves:
            return "⚠️ Gloves required!"
        case .violationBoth:
            return "⚠️ Shoes & gloves required!"
        case .error(let msg):
            return "Error: \(msg)"
        }
    }
    
    private func analyzeCurrentFrame() async {
        // Skip if already analyzing
        guard !visionAnalyzer.isAnalyzing else { return }
        guard let frame = streamManager.currentFrame else { return }
        
        if let result = await visionAnalyzer.analyzeFrame(frame) {
            if result.isViolation {
                switch result.violationType {
                case .noShoes:
                    analysisStatus = .violationShoes
                    triggerHapticWarning()
                    audioManager.playWarning(for: .shoes)
                    webManager.sendViolation(type: "shoes", message: "Shoes required!")
                case .noGloves:
                    analysisStatus = .violationGloves
                    triggerHapticWarning()
                    audioManager.playWarning(for: .gloves)
                    webManager.sendViolation(type: "gloves", message: "Gloves required!")
                case .both:
                    analysisStatus = .violationBoth
                    triggerHapticWarning()
                    audioManager.playWarnings(shoes: true, gloves: true)
                    webManager.sendViolation(type: "both", message: "Shoes and gloves required!")
                case .none:
                    analysisStatus = .safe
                    webManager.clearViolation()
                }
            } else if result.hasLegsOrFeet || result.hasHands {
                analysisStatus = .safe
                webManager.clearViolation()
            } else {
                // Nothing to check visible
                analysisStatus = .safe
                webManager.clearViolation()
            }
        } else {
            analysisStatus = .error(visionAnalyzer.lastError ?? "Unknown error")
        }
    }
    
    private func startAnalysisTimer() {
        // Analyze every 2 seconds
        analysisTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                await analyzeCurrentFrame()
            }
        }
    }
    
    private func stopAnalysisTimer() {
        analysisTimer?.invalidate()
        analysisTimer = nil
    }
    
    /// Use haptic feedback instead of audio to avoid interrupting wearables session
    private func triggerHapticWarning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @Binding var serverHost: String
    @Binding var serverPort: Int
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Server Configuration") {
                    HStack {
                        Text("Host")
                        Spacer()
                        TextField("IP Address", text: $serverHost)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("Port", value: $serverPort, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                }
                
                Section {
                    Text("Enter the IP address of the computer running the server.\n\nRun 'npm start' in the server folder and check the console for your network IP.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("Quick Actions") {
                    Button("Disconnect Glasses") {
                        try? Wearables.shared.startUnregistration()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Status Card Component
struct StatusCard: View {
    let icon: String
    let title: String
    let status: String
    let isActive: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(isActive ? .green : .secondary)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            Text(status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    ContentView()
}
