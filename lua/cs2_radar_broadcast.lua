-- cs2_radar_broadcast.lua
-- Real-time radar data broadcaster to web dashboard

local http = require("http")
local json = require("json")

-- CONFIG
local RADAR_URL = "wss://your-radar-app.onrender.com/ws"  -- REPLACE THIS after deploying to Render
local UPDATE_RATE = 0.1  -- seconds between updates (10 updates/sec)

local ws_conn = nil
local last_update = 0

-- Map name cache
local current_map = ""

-- Establish WebSocket connection
local function connect_ws()
    local ok, conn = pcall(function()
        return http.websocket_connect(RADAR_URL)
    end)
    if ok and conn then
        ws_conn = conn
        print("[Radar] Connected to " .. RADAR_URL)
    else
        print("[Radar] Connection failed, retrying in 5s...")
        ws_conn = nil
    end
end

-- Get current map name
local function get_map_name()
    local map = engine.get_level_name()
    if map then
        return map:match("([^/]+)$"):gsub("%.bsp$", "")
    end
    return "unknown"
end

-- Build radar data packet
local function build_radar_data()
    local local_player = entitylist.get_local_player()
    if not local_player or not local_player:is_alive() then
        return nil
    end

    local data = {
        timestamp = os.time(),
        map = get_map_name(),
        local_team = local_player:get_team(),
        allies = {},
        enemies = {}
    }

    -- Collect teammates (including self)
    for _, p in ipairs(entitylist.get_players()) do
        if p:is_alive() and not p:is_dormant() then
            local pos = p:get_origin()
            local angles = p:get_view_angles()

            local player_data = {
                name = p:get_name(),
                x = math.floor(pos.x),
                y = math.floor(pos.y),
                z = math.floor(pos.z),
                yaw = math.floor(angles.y),
                health = p:get_health(),
                armor = p:get_armor(),
                has_defuser = p:has_defuser(),
                is_scoped = p:is_scoped(),
                is_flashed = p:is_flashed()
            }

            if p:get_team() == data.local_team then
                table.insert(data.allies, player_data)
            else
                table.insert(data.enemies, player_data)
            end
        end
    end

    return data
end

-- Send data over WebSocket
local function send_radar_update()
    if not ws_conn then
        connect_ws()
        return
    end

    local data = build_radar_data()
    if not data then return end

    local payload = json.encode(data)
    local ok, err = pcall(function()
        ws_conn:send(payload)
    end)

    if not ok then
        print("[Radar] Send failed: " .. tostring(err))
        ws_conn = nil
    end
end

-- Main update loop
client.set_callback("on_paint", function()
    if not engine.is_in_game() then return end

    local now = globals.realtime()
    if now - last_update < UPDATE_RATE then return end
    last_update = now

    send_radar_update()
end)

-- Cleanup on unload
client.set_callback("on_shutdown", function()
    if ws_conn then
        ws_conn:close()
        print("[Radar] Disconnected")
    end
end)

print("[Radar] Broadcaster loaded. Connecting to " .. RADAR_URL)
