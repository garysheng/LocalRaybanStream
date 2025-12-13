# LocalRaybanStream Server

A simple Node.js server that receives video frames from the iOS app and broadcasts them to web browsers via WebSocket.

## Quick Start

```bash
# Install dependencies
npm install

# Start the server
npm start
```

The server will display your local network IP. Configure this in the iOS app settings.

## Endpoints

| Endpoint | Description |
|----------|-------------|
| `/` | Web viewer UI |
| `/ws` | WebSocket connection for real-time frames |
| `/stream.mjpeg` | MJPEG stream (works in `<img>` tags) |
| `/api/health` | Health check with stats |
| `/api/frame` | POST endpoint for iOS app |

## Usage

1. Start the server: `npm start`
2. Note the network IP displayed in the console
3. Open the iOS app and go to Settings
4. Enter the server IP and port (default: 3000)
5. Start streaming from the iOS app
6. Open `http://<server-ip>:3000` in any browser

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | 3000 | Server port |

## Architecture

```
iOS App --[HTTP POST JPEG]--> Node Server --[WebSocket]--> Browser(s)
```

The server keeps the latest frame in memory and broadcasts it to all connected WebSocket clients. New clients receive the most recent frame immediately upon connection.

