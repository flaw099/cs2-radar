// server.js - WebSocket radar server
const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const path = require('path');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// Serve static files
app.use(express.static('public'));

// Store latest radar state
let latestRadarData = null;

// WebSocket connections
wss.on('connection', (ws, req) => {
    const ip = req.socket.remoteAddress;
    console.log(`[WS] Client connected: ${ip}`);

    // Send cached data immediately to new clients
    if (latestRadarData) {
        ws.send(JSON.stringify(latestRadarData));
    }

    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);
            latestRadarData = data;

            // Broadcast to all connected clients (your teammates)
            wss.clients.forEach(client => {
                if (client !== ws && client.readyState === WebSocket.OPEN) {
                    client.send(message);
                }
            });
        } catch (e) {
            console.error('[WS] Parse error:', e);
        }
    });

    ws.on('close', () => {
        console.log(`[WS] Client disconnected: ${ip}`);
    });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    console.log(`[Server] Running on port ${PORT}`);
});
