# LocalRaybanStream

Stream live video from Ray-Ban Meta smart glasses to any web browser.

> **Fork of [SpecBridge](https://github.com/jasondukes/SpecBridge)** by Jason Dukes.  
> Original streams to Twitch. This version streams to a local web server instead.

## How It Works

```
Ray-Ban Meta Glasses → iPhone App → Node.js Server → Browser
         (Bluetooth)      (HTTP POST)     (WebSocket)
```

The iOS app captures video frames from your glasses and POSTs them as JPEGs to a simple Node.js server. The server broadcasts frames to all connected browsers via WebSocket.

## Prerequisites

- **Mac** with Xcode 15+
- **iPhone** running iOS 17+
- **Ray-Ban Meta Smart Glasses** (Gen 2) with Developer Mode enabled
- **Meta View app** installed and paired with your glasses

### Enable Developer Mode on Glasses

1. Open **Meta View** app on your iPhone
2. Go to **Devices** → **Settings** → **General** → **About**
3. Tap the **Version** number 5 times
4. Toggle **Developer Mode** on

## Quick Start

### 1. Start the Server

```bash
cd server
npm install
npm start
```

Note the network IP displayed (e.g., `192.168.1.100`).

### 2. Build the iOS App

1. Open `SpecBridge.xcodeproj` in Xcode
2. Select your Apple ID under **Signing & Capabilities**
3. Connect your iPhone and click **Run**

### 3. Configure and Stream

1. Tap **Settings** (gear icon) in the app
2. Enter your server's IP address (from step 1)
3. Tap **Connect to Glasses** → approve in Meta View app
4. Tap **Start Stream**

### 4. View in Browser

Open `http://<server-ip>:3000` on any device on your network.

## Server Endpoints

| Endpoint | Description |
|----------|-------------|
| `/` | Web viewer with live feed |
| `/stream.mjpeg` | MJPEG stream (embeddable in `<img>` tags) |
| `/ws` | WebSocket for real-time frames |
| `/api/health` | Health check with stats |

## Project Structure

```
LocalRaybanStream/
├── SpecBridge/                 # iOS app
│   ├── SpecBridgeApp.swift     # App entry point
│   ├── ContentView.swift       # UI
│   ├── StreamManager.swift     # Glasses connection
│   └── WebStreamManager.swift  # HTTP frame posting
│
├── server/                     # Node.js server
│   ├── server.js               # Express + WebSocket
│   └── public/index.html       # Web viewer
│
└── SpecBridge.xcodeproj        # Xcode project
```

## Performance

| Metric | Value |
|--------|-------|
| Frame Rate | ~15 fps |
| Latency | 100-300ms (local network) |
| Bandwidth | ~2-3 Mbps |

## Known Issues

- **Square Crop**: Video is cropped to 1:1 instead of full 9:16 (inherited from original SpecBridge)
- **No Audio**: Video only; audio streaming would require WebRTC
- **Local Network Only**: HTTP means no remote streaming without additional setup

## Credits

- **Original SpecBridge**: [Jason Dukes](https://github.com/jasondukes/SpecBridge)
- **Meta Wearables DAT SDK**: [Meta](https://www.ray-ban.com/usa/discover-ray-ban-meta/clp)

## License

MIT License. See [LICENSE](LICENSE) for details.
