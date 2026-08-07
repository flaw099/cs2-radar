# CS2 Real-Time Radar Broadcaster

broadcasts live player positions from cs2 to a web dashboard for your team.

## setup

### 1. deploy the web server (free hosting)

**option a: render.com (recommended)**
1. push this project to github
2. go to [render.com](https://render.com) and sign up
3. click "New Web Service"
4. connect your github repo
5. settings:
   - environment: `Node`
   - build command: `npm install`
   - start command: `npm start`
6. deploy
7. copy your url: `https://your-app-name.onrender.com`

**option b: railway.app**
1. push to github
2. go to [railway.app](https://railway.app)
3. "new project" → "deploy from github"
4. select repo
5. copy your url

**option c: fly.io**
```bash
npm install -g flyctl
flyctl launch
flyctl deploy
```

### 2. configure the lua script

edit `lua/cs2_radar_broadcast.lua` line 7:
```lua
local RADAR_URL = "wss://your-actual-url.onrender.com/ws"
```

### 3. load in cs2

copy `cs2_radar_broadcast.lua` to your cheat's lua folder and load it.

### 4. share with team

send them your url: `https://your-app-name.onrender.com`

everyone who opens it sees the live radar.

## features

- real-time player positions (allies green, enemies red)
- health, armor, defuser status
- player direction indicators
- auto-reconnect on disconnect
- works with any CS2 map

## how it works

lua script → websocket → server → broadcast → all browsers

## troubleshooting

**connection failed**
- check RADAR_URL in lua script matches your deployed url
- make sure it starts with `wss://` not `https://`

**players not showing**
- adjust MAP_BOUNDS in index.html for your specific map
- check console for errors

**site won't load**
- render.com free tier spins down after inactivity
- first load takes ~30 seconds to wake up

## local testing

```bash
npm install
npm start
```

open `http://localhost:3000`

change lua script to:
```lua
local RADAR_URL = "ws://localhost:3000/ws"
```
