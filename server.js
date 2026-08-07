// server.js - WebSocket radar server
const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const path = require('path');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// Parse JSON bodies
app.use(express.json());

// Serve static files
app.use(express.static('public'));

// Store latest radar state
let latestRadarData = null;

// HTTP POST endpoint for Lua script
app.post('/radar', (req, res) => {
    try {
        const data = req.body;
        latestRadarData = data;

        console.log(`[Radar] Received update: ${data.allies.length} allies, ${data.enemies.length} enemies on ${data.map}`);

        // Broadcast to all connected WebSocket clients
        const message = JSON.stringify(data);
        wss.clients.forEach(client => {
            if (client.readyState === WebSocket.OPEN) {
                client.send(message);
            }
        });

        res.status(200).json({ status: 'ok' });
    } catch (e) {
        console.error('[Radar] POST error:', e);
        res.status(400).json({ status: 'error', message: e.message });
    }
});

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
