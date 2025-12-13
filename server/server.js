const express = require('express');
const { WebSocketServer } = require('ws');
const http = require('http');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Store latest frame for new connections
let latestFrame = null;
let frameCount = 0;

// Serve static files
app.use(express.static(path.join(__dirname, 'public')));

// Parse raw binary body for frame uploads
app.use('/api/frame', express.raw({ type: 'image/jpeg', limit: '5mb' }));

// Health check
app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    hasFrame: latestFrame !== null,
    frameCount,
    clients: wss.clients.size
  });
});

// Receive frames from iOS app
app.post('/api/frame', (req, res) => {
  if (!req.body || req.body.length === 0) {
    console.log('Received empty frame request');
    return res.status(400).json({ error: 'No frame data' });
  }
  
  latestFrame = req.body;
  frameCount++;
  
  // Log every 30 frames (~2 seconds at 15fps)
  if (frameCount % 30 === 1) {
    console.log(`Frame ${frameCount} received (${(req.body.length / 1024).toFixed(1)} KB), broadcasting to ${wss.clients.size} clients`);
  }
  
  // Broadcast to all WebSocket clients
  const base64Frame = latestFrame.toString('base64');
  const message = JSON.stringify({
    type: 'frame',
    data: base64Frame,
    timestamp: Date.now(),
    frameId: frameCount
  });
  
  wss.clients.forEach(client => {
    if (client.readyState === 1) { // WebSocket.OPEN
      client.send(message);
    }
  });
  
  res.json({ status: 'ok', frameId: frameCount });
});

// MJPEG stream endpoint (alternative to WebSocket)
app.get('/stream.mjpeg', (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'multipart/x-mixed-replace; boundary=frame',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive'
  });
  
  const sendFrame = () => {
    if (latestFrame) {
      res.write('--frame\r\n');
      res.write('Content-Type: image/jpeg\r\n\r\n');
      res.write(latestFrame);
      res.write('\r\n');
    }
  };
  
  // Send at ~15fps
  const interval = setInterval(sendFrame, 66);
  
  req.on('close', () => {
    clearInterval(interval);
  });
});

// Create HTTP server
const server = http.createServer(app);

// Create WebSocket server
const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws, req) => {
  const clientIp = req.socket.remoteAddress;
  console.log(`Client connected: ${clientIp}`);
  
  // Send latest frame immediately if available
  if (latestFrame) {
    ws.send(JSON.stringify({
      type: 'frame',
      data: latestFrame.toString('base64'),
      timestamp: Date.now(),
      frameId: frameCount
    }));
  }
  
  ws.on('close', () => {
    console.log(`Client disconnected: ${clientIp}`);
  });
  
  ws.on('error', (err) => {
    console.error(`WebSocket error: ${err.message}`);
  });
});

// Get local IP for display
function getLocalIP() {
  const { networkInterfaces } = require('os');
  const nets = networkInterfaces();
  
  for (const name of Object.keys(nets)) {
    for (const net of nets[name]) {
      if (net.family === 'IPv4' && !net.internal) {
        return net.address;
      }
    }
  }
  return 'localhost';
}

// Start server
server.listen(PORT, '0.0.0.0', () => {
  const localIP = getLocalIP();
  console.log('');
  console.log('╔═══════════════════════════════════════════════════════╗');
  console.log('║         LocalRaybanStream Server Running              ║');
  console.log('╠═══════════════════════════════════════════════════════╣');
  console.log(`║  Local:    http://localhost:${PORT}                      ║`);
  console.log(`║  Network:  http://${localIP}:${PORT}                  ║`);
  console.log('╠═══════════════════════════════════════════════════════╣');
  console.log('║  Endpoints:                                           ║');
  console.log('║    • Web Viewer:  /                                   ║');
  console.log('║    • WebSocket:   /ws                                 ║');
  console.log('║    • MJPEG:       /stream.mjpeg                       ║');
  console.log('║    • Health:      /api/health                         ║');
  console.log('╚═══════════════════════════════════════════════════════╝');
  console.log('');
  console.log(`Configure your iOS app with: ${localIP}:${PORT}`);
  console.log('');
});

