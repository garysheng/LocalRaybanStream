import SwiftUI
import MWDATCore

struct ContentView: View {
    @AppStorage("server_host") private var serverHost: String = "192.168.1.100"
    @AppStorage("server_port") private var serverPort: Int = 3000
    
    @StateObject private var streamManager = StreamManager()
    @StateObject private var webManager = WebStreamManager()
    
    @State private var showSettings = false
    @State private var isRegistered = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LocalRaybanStream")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Stream to Browser")
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
                
                // Live indicator
                if streamManager.isStreaming {
                    VStack {
                        HStack {
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
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(12)
                }
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
                    icon: "server.rack",
                    title: "Server",
                    status: webManager.connectionStatus,
                    isActive: webManager.isStreaming
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
                            await streamManager.stopStreaming()
                            webManager.stopStreaming()
                        } else {
                            webManager.updateServerURL(host: serverHost, port: serverPort)
                            webManager.startStreaming()
                            await streamManager.startStreaming()
                        }
                    }
                } label: {
                    Label(
                        streamManager.isStreaming ? "Stop Stream" : "Start Stream",
                        systemImage: streamManager.isStreaming ? "stop.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(streamManager.isStreaming ? .red : .green)
                .controlSize(.large)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .onAppear {
            streamManager.webManager = webManager
        }
        .onOpenURL { url in
            Task {
                try? await Wearables.shared.handleUrl(url)
                isRegistered = true
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(serverHost: $serverHost, serverPort: $serverPort)
        }
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
                .lineLimit(1)
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
