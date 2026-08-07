-- cs2_radar_broadcast.lua
-- Real-time radar data broadcaster to web dashboard using FFI + WinHTTP

local ffi = require("ffi")

-- WinHTTP FFI definitions
pcall(function() ffi.cdef[[
    typedef void* HINTERNET;
    typedef unsigned long DWORD;
    typedef const wchar_t* LPCWSTR;
    typedef unsigned short WORD;
    typedef int BOOL;

    HINTERNET WinHttpOpen(LPCWSTR, DWORD, LPCWSTR, LPCWSTR, DWORD);
    HINTERNET WinHttpConnect(HINTERNET, LPCWSTR, unsigned short, DWORD);
    HINTERNET WinHttpOpenRequest(HINTERNET, LPCWSTR, LPCWSTR, LPCWSTR, LPCWSTR, LPCWSTR*, DWORD);
    BOOL WinHttpSetOption(HINTERNET, DWORD, void*, DWORD);
    BOOL WinHttpSendRequest(HINTERNET, LPCWSTR, DWORD, void*, DWORD, DWORD, DWORD);
    BOOL WinHttpReceiveResponse(HINTERNET, void*);
    BOOL WinHttpQueryDataAvailable(HINTERNET, DWORD*);
    BOOL WinHttpReadData(HINTERNET, void*, DWORD, DWORD*);
    BOOL WinHttpCloseHandle(HINTERNET);

    int MultiByteToWideChar(unsigned int, DWORD, const char*, int, wchar_t*, int);
    int WideCharToMultiByte(unsigned int, DWORD, const wchar_t*, int, char*, int, const char*, BOOL*);
]] end)

local winhttp = ffi.load("winhttp")

-- CONFIG
local SERVER_HOST = "cs2-radar.onrender.com"
local SERVER_PORT = 443
local SERVER_PATH = "/radar"
local UPDATE_RATE = 0.1  -- seconds between updates

local session_handle = nil
local connect_handle = nil
local last_update = 0
local last_connect_attempt = 0
local connection_ready = false

-- UTF-8 to wide string conversion
local function utf8_to_wide(str)
    local len = winhttp.MultiByteToWideChar(65001, 0, str, #str, nil, 0)
    if len == 0 then return nil end
    local wbuf = ffi.new("wchar_t[?]", len + 1)
    winhttp.MultiByteToWideChar(65001, 0, str, #str, wbuf, len)
    wbuf[len] = 0
    return wbuf
end

-- Wide string to UTF-8 conversion
local function wide_to_utf8(wstr, wlen)
    local len = winhttp.WideCharToMultiByte(65001, 0, wstr, wlen, nil, 0, nil, nil)
    if len == 0 then return "" end
    local buf = ffi.new("char[?]", len + 1)
    winhttp.WideCharToMultiByte(65001, 0, wstr, wlen, buf, len, nil, nil)
    return ffi.string(buf, len)
end

-- Initialize WinHTTP session
local function init_session()
    if session_handle then return true end

    local user_agent = utf8_to_wide("CS2-Radar/1.0")
    session_handle = winhttp.WinHttpOpen(
        user_agent,
        0, -- WINHTTP_ACCESS_TYPE_DEFAULT_PROXY
        nil,
        nil,
        0
    )

    if session_handle == nil or session_handle == ffi.cast("HINTERNET", 0) then
        client.log("[Radar] Failed to initialize WinHTTP session")
        return false
    end

    client.log("[Radar] WinHTTP session initialized")
    return true
end

-- Connect to server
local function connect_server()
    if not init_session() then return false end
    if connect_handle then return true end

    local host_wide = utf8_to_wide(SERVER_HOST)
    connect_handle = winhttp.WinHttpConnect(
        session_handle,
        host_wide,
        SERVER_PORT,
        0
    )

    if connect_handle == nil or connect_handle == ffi.cast("HINTERNET", 0) then
        client.log("[Radar] Failed to connect to " .. SERVER_HOST)
        return false
    end

    connection_ready = true
    client.log("[Radar] Connected to " .. SERVER_HOST .. ":" .. SERVER_PORT)
    return true
end

-- Simple JSON encoding (no dependencies)
local function json_encode(t)
    local function encode_string(s)
        s = tostring(s)
        s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
        return '"' .. s .. '"'
    end

    local function encode_value(v)
        local t = type(v)
        if t == "string" then
            return encode_string(v)
        elseif t == "number" then
            return tostring(v)
        elseif t == "boolean" then
            return v and "true" or "false"
        elseif t == "table" then
            -- check if array
            local is_array = true
            local count = 0
            for k, _ in pairs(v) do
                count = count + 1
                if type(k) ~= "number" or k < 1 or k > count then
                    is_array = false
                    break
                end
            end

            if is_array and count > 0 then
                local parts = {}
                for i = 1, count do
                    parts[i] = encode_value(v[i])
                end
                return "[" .. table.concat(parts, ",") .. "]"
            else
                local parts = {}
                for k, val in pairs(v) do
                    if type(k) == "string" then
                        table.insert(parts, encode_string(k) .. ":" .. encode_value(val))
                    end
                end
                return "{" .. table.concat(parts, ",") .. "}"
            end
        else
            return "null"
        end
    end

    return encode_value(t)
end

-- Get current map name
local function get_map_name()
    local map_cvar = cvar.get_string("map")
    if map_cvar and map_cvar ~= "" then
        return map_cvar
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

    -- Collect all players
    local players = entitylist.get_players()
    for _, p in ipairs(players) do
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
                armor = p:get_armor()
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

-- Send HTTP POST with radar data
local function send_radar_update()
    if not connection_ready then
        local now = globals.curtime()
        if now - last_connect_attempt > 5.0 then  -- retry every 5 seconds
            last_connect_attempt = now
            connect_server()
        end
        return
    end

    local data = build_radar_data()
    if not data then return end

    local json_data = json_encode(data)

    -- Open request
    local verb = utf8_to_wide("POST")
    local path = utf8_to_wide(SERVER_PATH)
    local version = utf8_to_wide("HTTP/1.1")

    local request_handle = winhttp.WinHttpOpenRequest(
        connect_handle,
        verb,
        path,
        version,
        nil,
        nil,
        0x00800000 -- WINHTTP_FLAG_SECURE (HTTPS)
    )

    if request_handle == nil or request_handle == ffi.cast("HINTERNET", 0) then
        client.log("[Radar] Failed to open request")
        connection_ready = false
        connect_handle = nil
        return
    end

    -- Set headers
    local headers = utf8_to_wide("Content-Type: application/json\r\n")

    -- Send request
    local send_ok = winhttp.WinHttpSendRequest(
        request_handle,
        headers,
        0xFFFFFFFF, -- use headers string length
        ffi.cast("void*", json_data),
        #json_data,
        #json_data,
        0
    )

    if send_ok ~= 0 then
        winhttp.WinHttpReceiveResponse(request_handle, nil)
    end

    winhttp.WinHttpCloseHandle(request_handle)
end

-- Main update loop
client.set_callback("on_paint", function()
    if not engine.is_in_game() then return end

    local now = globals.curtime()
    if now - last_update < UPDATE_RATE then return end
    last_update = now

    send_radar_update()
end)

-- Cleanup on unload
client.set_callback("on_unload", function()
    if connect_handle then
        winhttp.WinHttpCloseHandle(connect_handle)
    end
    if session_handle then
        winhttp.WinHttpCloseHandle(session_handle)
    end
    client.log("[Radar] Disconnected and cleaned up")
end)

client.log("[Radar] Broadcaster loaded. Target: https://" .. SERVER_HOST .. ":" .. SERVER_PORT .. SERVER_PATH)
