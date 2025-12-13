# SpecBridge Web Stream — Design Document

## Overview

**SpecBridge Web Stream** is a minimal fork of SpecBridge that replaces Twitch RTMP streaming with direct HTTP-based video streaming to a local web server. The web server then serves the live feed to any browser client.

This enables developers to quickly prototype custom viewing experiences for Ray-Ban Meta glasses without relying on third-party streaming platforms.

## Goals

1. **Simplicity** — Minimal moving parts. No RTMP, no HLS segmentation, no transcoding.
2. **Low Latency** — Sub-second latency for local network usage.
3. **Easy Setup** — Single command to run the server, build the iOS app, open a browser.
4. **Developer-Friendly** — Clean architecture that's easy to extend.

## Architecture

```
┌─────────────────────┐      ┌─────────────────────┐      ┌─────────────────────┐
│   Ray-Ban Meta      │      │    iOS App          │      │    Web Server       │
│   Smart Glasses     │─────▶│    (SpecBridge      │─────▶│    (Node.js)        │
│                     │ BT   │     Web Fork)       │ HTTP │                     │
└─────────────────────┘      └─────────────────────┘      └─────────────────────┘
                                                                    │
                                                                    │ WebSocket
                                                                    ▼
                                                          ┌─────────────────────┐
                                                          │    Browser Client   │
                                                          │    (React/Vanilla)  │
                                                          └─────────────────────┘
```

### Data Flow

1. **Glasses → iPhone**: Video frames via Meta Wearables DAT SDK over Bluetooth
2. **iPhone → Server**: JPEG frames via HTTP POST to `/api/frame`
3. **Server → Browser**: JPEG frames via WebSocket broadcast

## Project Structure

```
SpecBridgeWeb/
├── ios/                          # iOS app (fork of SpecBridge)
│   ├── SpecBridgeWeb.xcodeproj
│   └── SpecBridgeWeb/
│       ├── SpecBridgeWebApp.swift
│       ├── ContentView.swift
│       ├── StreamManager.swift   # Connects to glasses
│       └── WebStreamManager.swift # POSTs frames to server (replaces TwitchManager)
│
├── server/                       # Node.js backend
│   ├── package.json
│   ├── server.js                 # Express + WebSocket server
│   └── public/
│       └── index.html            # Simple viewer page
│
└── README.md
```

## iOS App Changes

### Files to Keep (from SpecBridge)
- `SpecBridgeApp.swift` → Rename to `SpecBridgeWebApp.swift`
- `StreamManager.swift` → Keep as-is (handles glasses connection)
- `Info.plist` → Keep (Meta SDK config)

### Files to Replace
- `SpecBridge.swift` (TwitchManager) → Replace with `WebStreamManager.swift`
- `ContentView.swift` → Simplify UI (no stream key needed)

### New: WebStreamManager.swift

Replaces TwitchManager. Instead of RTMP, it POSTs JPEG frames to the web server.

```swift
import Foundation
import UIKit
import AVFoundation

@MainActor
class WebStreamManager: ObservableObject {
    @Published var isStreaming = false
    @Published var connectionStatus = "Disconnected"
    
    private var serverURL: URL
    private let session = URLSession.shared
    
    // Throttle: send max ~15 fps to avoid overwhelming network
    private var lastFrameTime: Date = .distantPast
    private let minFrameInterval: TimeInterval = 1.0 / 15.0
    
    init(serverHost: String = "192.168.1.100", port: Int = 3000) {
        self.serverURL = URL(string: "http://\(serverHost):\(port)/api/frame")!
    }
    
    func updateServerURL(host: String, port: Int) {
        self.serverURL = URL(string: "http://\(host):\(port)/api/frame")!
    }
    
    func startStreaming() {
        isStreaming = true
        connectionStatus = "Streaming"
    }
    
    func stopStreaming() {
        isStreaming = false
        connectionStatus = "Disconnected"
    }
    
    func processVideoFrame(_ buffer: CMSampleBuffer) {
        guard isStreaming else { return }
        
        // Throttle frames
        let now = Date()
        guard now.timeIntervalSince(lastFrameTime) >= minFrameInterval else { return }
        lastFrameTime = now
        
        // Convert CMSampleBuffer to JPEG
        guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.7) else { return }
        
        // POST to server
        Task {
            var request = URLRequest(url: serverURL)
            request.httpMethod = "POST"
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            request.httpBody = jpegData
            
            do {
                let (_, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    await MainActor.run {
                        self.connectionStatus = "Error: \(httpResponse.statusCode)"
                    }
                }
            } catch {
                await MainActor.run {
                    self.connectionStatus = "Connection Error"
                }
            }
        }
    }
}
```

### Simplified ContentView.swift

```swift
import SwiftUI
import MWDATCore

struct ContentView: View {
    @AppStorage("server_host") private var serverHost: String = "192.168.1.100"
    @AppStorage("server_port") private var serverPort: Int = 3000
    
    @StateObject private var streamManager = StreamManager()
    @StateObject private var webManager = WebStreamManager()
    
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Video Preview
            ZStack {
                Color.black
                if let videoImage = streamManager.currentFrame {
                    Image(uiImage: videoImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Text("Glasses Offline")
                        .foregroundStyle(.gray)
                }
            }
            .frame(height: 400)
            .cornerRadius(12)
            
            // Status
            VStack(spacing: 8) {
                Text("Glasses: \(streamManager.status)")
                Text("Server: \(webManager.connectionStatus)")
                    .foregroundStyle(webManager.isStreaming ? .green : .gray)
            }
            .font(.subheadline)
            
            // Controls
            HStack(spacing: 16) {
                Button("Connect Glasses") {
                    try? Wearables.shared.startRegistration()
                }
                .buttonStyle(.bordered)
                
                Button(streamManager.isStreaming ? "Stop" : "Start") {
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
                }
                .buttonStyle(.borderedProminent)
                .tint(streamManager.isStreaming ? .red : .green)
                
                Button("Settings") {
                    showSettings = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .onAppear {
            streamManager.webManager = webManager
        }
        .onOpenURL { url in
            Task { try? await Wearables.shared.handleUrl(url) }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(serverHost: $serverHost, serverPort: $serverPort)
        }
    }
}

struct SettingsView: View {
    @Binding var serverHost: String
    @Binding var serverPort: Int
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Server Configuration") {
                    TextField("Host IP", text: $serverHost)
                        .keyboardType(.decimalPad)
                    TextField("Port", value: $serverPort, format: .number)
                        .keyboardType(.numberPad)
                }
                
                Section {
                    Text("Enter the IP address of the computer running the web server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
```

### Modified StreamManager.swift

Minor change: replace `twitchManager` reference with `webManager`.

```swift
// Replace this line:
var twitchManager: TwitchManager?

// With:
var webManager: WebStreamManager?

// And in the video frame handler:
self?.webManager?.processVideoFrame(buffer)
```

## Node.js Server

### package.json

```json
{
  "name": "specbridge-web-server",
  "version": "1.0.0",
  "description": "Simple web server for SpecBridge video streaming",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "node --watch server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.14.2"
  }
}
```

### server.js

```javascript
const express = require('express');
const { WebSocketServer } = require('ws');
const http = require('http');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Store latest frame for new connections
let latestFrame = null;

// Serve static files
app.use(express.static(path.join(__dirname, 'public')));

// Parse raw binary body for frame uploads
app.use('/api/frame', express.raw({ type: 'image/jpeg', limit: '5mb' }));

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', hasFrame: latestFrame !== null });
});

// Receive frames from iOS app
app.post('/api/frame', (req, res) => {
  if (!req.body || req.body.length === 0) {
    return res.status(400).json({ error: 'No frame data' });
  }
  
  latestFrame = req.body;
  
  // Broadcast to all WebSocket clients
  const base64Frame = latestFrame.toString('base64');
  wss.clients.forEach(client => {
    if (client.readyState === 1) { // OPEN
      client.send(JSON.stringify({
        type: 'frame',
        data: base64Frame,
        timestamp: Date.now()
      }));
    }
  });
  
  res.json({ status: 'ok' });
});

// Create HTTP server
const server = http.createServer(app);

// Create WebSocket server
const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws) => {
  console.log('Client connected');
  
  // Send latest frame immediately if available
  if (latestFrame) {
    ws.send(JSON.stringify({
      type: 'frame',
      data: latestFrame.toString('base64'),
      timestamp: Date.now()
    }));
  }
  
  ws.on('close', () => {
    console.log('Client disconnected');
  });
});

// Start server
server.listen(PORT, '0.0.0.0', () => {
  console.log(`SpecBridge Web Server running on port ${PORT}`);
  console.log(`Open http://localhost:${PORT} in your browser`);
  console.log(`WebSocket available at ws://localhost:${PORT}/ws`);
});
```

### public/index.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SpecBridge Viewer</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    
    body {
      background: #0a0a0a;
      color: #fff;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 24px;
    }
    
    h1 {
      font-size: 1.5rem;
      font-weight: 600;
      margin-bottom: 8px;
    }
    
    .status {
      font-size: 0.875rem;
      color: #888;
      margin-bottom: 24px;
    }
    
    .status.connected {
      color: #4ade80;
    }
    
    .video-container {
      background: #1a1a1a;
      border-radius: 12px;
      overflow: hidden;
      max-width: 100%;
      box-shadow: 0 4px 24px rgba(0, 0, 0, 0.5);
    }
    
    #videoFrame {
      display: block;
      max-width: 100%;
      max-height: 70vh;
    }
    
    .placeholder {
      width: 360px;
      height: 640px;
      display: flex;
      align-items: center;
      justify-content: center;
      color: #555;
      font-size: 1rem;
    }
    
    .stats {
      margin-top: 16px;
      font-size: 0.75rem;
      color: #666;
    }
  </style>
</head>
<body>
  <h1>SpecBridge Viewer</h1>
  <p class="status" id="status">Connecting...</p>
  
  <div class="video-container">
    <img id="videoFrame" alt="Live Feed" style="display: none;">
    <div class="placeholder" id="placeholder">Waiting for stream...</div>
  </div>
  
  <p class="stats" id="stats"></p>

  <script>
    const ws = new WebSocket(`ws://${window.location.host}/ws`);
    const videoFrame = document.getElementById('videoFrame');
    const placeholder = document.getElementById('placeholder');
    const statusEl = document.getElementById('status');
    const statsEl = document.getElementById('stats');
    
    let frameCount = 0;
    let lastFrameTime = 0;
    
    ws.onopen = () => {
      statusEl.textContent = 'Connected';
      statusEl.classList.add('connected');
    };
    
    ws.onclose = () => {
      statusEl.textContent = 'Disconnected';
      statusEl.classList.remove('connected');
    };
    
    ws.onmessage = (event) => {
      const msg = JSON.parse(event.data);
      
      if (msg.type === 'frame') {
        videoFrame.src = 'data:image/jpeg;base64,' + msg.data;
        videoFrame.style.display = 'block';
        placeholder.style.display = 'none';
        
        // Update stats
        frameCount++;
        const now = Date.now();
        if (lastFrameTime > 0) {
          const fps = (1000 / (now - lastFrameTime)).toFixed(1);
          statsEl.textContent = `Frames: ${frameCount} | ~${fps} fps`;
        }
        lastFrameTime = now;
      }
    };
  </script>
</body>
</html>
```

## Setup & Usage

### 1. Start the Web Server

```bash
cd server
npm install
npm start
```

Note your computer's local IP address (e.g., `192.168.1.100`).

### 2. Build & Run the iOS App

1. Open `ios/SpecBridgeWeb.xcodeproj` in Xcode
2. Update signing with your Apple ID
3. Build and run on your iPhone
4. In the app settings, enter your computer's IP address

### 3. Connect and Stream

1. Tap "Connect Glasses" to register with Meta View
2. Tap "Start" to begin streaming
3. Open `http://localhost:3000` in any browser on your network

## Performance Considerations

### Frame Rate & Bandwidth

| Setting | Frame Rate | Approx. Bandwidth |
|---------|------------|-------------------|
| Low     | 15 fps     | ~2-3 Mbps         |
| Medium  | 24 fps     | ~4-5 Mbps         |
| High    | 30 fps     | ~6-8 Mbps         |

The iOS app throttles to 15 fps by default to balance quality and latency.

### Latency

Expected end-to-end latency: **100-300ms** on local network.

- Glasses → iPhone: ~50-100ms (Bluetooth)
- iPhone → Server: ~10-50ms (WiFi/LAN)
- Server → Browser: ~10-50ms (WebSocket)

## Limitations

1. **Local Network Only** — HTTP without HTTPS means this only works on trusted networks
2. **No Audio** — This version only streams video; audio would require additional WebRTC implementation
3. **Single Stream** — One glasses connection at a time
4. **Square Crop** — Inherits the same aspect ratio issue from original SpecBridge

## Future Enhancements

1. **WebRTC** — Replace HTTP+WebSocket with WebRTC for lower latency and audio support
2. **HTTPS** — Add TLS for secure streaming over public networks
3. **Multi-Viewer Stats** — Dashboard showing connected viewers
4. **Recording** — Save streams to disk on the server
5. **Cloud Deployment** — Deploy server to a VPS for remote access

## Alternative: MJPEG Stream

For even simpler viewing (no JavaScript required), the server could expose an MJPEG endpoint:

```javascript
app.get('/stream.mjpeg', (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'multipart/x-mixed-replace; boundary=frame',
    'Cache-Control': 'no-cache',
  });
  
  const sendFrame = () => {
    if (latestFrame) {
      res.write(`--frame\r\n`);
      res.write(`Content-Type: image/jpeg\r\n\r\n`);
      res.write(latestFrame);
      res.write(`\r\n`);
    }
  };
  
  const interval = setInterval(sendFrame, 66); // ~15fps
  req.on('close', () => clearInterval(interval));
});
```

Then view at: `http://localhost:3000/stream.mjpeg`

---

## License

MIT License (same as original SpecBridge)

