vrmod = vrmod or {}
vrmod.logger = vrmod.logger or {}
vrmod.debug_cvars = vrmod.debug_cvars or {}
-- ConVars for log levels
local cv_console = CreateConVar("vrmod_log_console", "3", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Minimum log level for console (0=OFF, 1=ERROR, 2=WARN, 3=INFO, 4=DEBUG)")
local cv_file = CreateConVar("vrmod_log_file", "0", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Minimum log level for file (0=OFF, 1=ERROR, 2=WARN, 3=INFO, 4=DEBUG)")
-- Subsystem convars
for subsystem, _ in pairs(vrmod.status or {}) do
    local name = "vrmod_debug_" .. subsystem
    if not vrmod.debug_cvars[subsystem] then
        local convar = CreateConVar(name, "0", FCVAR_ARCHIVE + FCVAR_REPLICATED, "Enable debug for VRMod subsystem: " .. subsystem)
        vrmod.debug_cvars[subsystem] = convar
    end
end

-- Log levels
local levels = {
    ERROR = 1,
    WARN = 2,
    INFO = 3,
    DEBUG = 4,
}

-- Colors for log levels
local levelColors = {
    DEBUG = Color(150, 150, 150),
    INFO = Color(0, 200, 0),
    WARN = Color(255, 200, 0),
    ERROR = Color(255, 0, 0),
}

-- Side colors
local sideColors = {
    SERVER = Color(0, 150, 255),
    CLIENT = Color(255, 100, 255),
}

-- Subsystem colors
local subsystemColors = {} -- dynamically assigned
-- Generate a color for a subsystem
local function getSubsystemColor(name)
    if subsystemColors[name] then return subsystemColors[name] end
    local r = math.random(50, 255)
    local g = math.random(50, 255)
    local b = math.random(50, 255)
    local col = Color(r, g, b)
    subsystemColors[name] = col
    return col
end

-- Helper to stringify values
local function tostr(v)
    if istable(v) then
        local parts = {}
        for k, val in pairs(v) do
            table.insert(parts, tostring(k) .. "=" .. tostr(val))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif IsEntity and IsEntity(v) and v:IsValid() then
        return string.format("Entity[%s:%s]", v:GetClass(), v:EntIndex())
    elseif IsEntity and IsEntity(v) then
        return "Entity[INVALID]"
    elseif isvector and isvector(v) then
        return string.format("Vector(%.2f, %.2f, %.2f)", v.x, v.y, v.z)
    elseif isangle and isangle(v) then
        return string.format("Angle(%.2f, %.2f, %.2f)", v.p, v.y, v.r)
    else
        return tostring(v)
    end
end

-- Subsystem detection
local function detectSubsystem()
    local lvl = 3
    while true do
        local info = debug.getinfo(lvl, "S")
        if not info then break end
        if info.short_src then
            local src = string.lower(info.short_src)
            if src:find("vrmod/") and not src:find("vrmod/logger.lua") then
                local match = src:match("vrmod/([^/]+)/[^/]+%.lua$")
                if match and vrmod.status and vrmod.status[match] ~= nil then return match end
            end
        end

        lvl = lvl + 1
    end
    return "unknown"
end

-- File init
local logDir = "vrmod_logs"
if not file.Exists(logDir, "DATA") then file.CreateDir(logDir) end
local side = SERVER and "SERVER" or "CLIENT"
local logFileName = string.format("%s/vrmod_%s_%s.txt", logDir, side:lower(), os.date("%Y%m%d_%H%M%S"))
local function writeFileLine(line)
    file.Append(logFileName, line .. "\n")
end

-- Core log function
local function Log(level, fmt, ...)
    local lvlNum = levels[level]
    if not lvlNum then return end
    local subsystem = detectSubsystem()
    -- Subsystem-specific debug control
    if lvlNum == levels.DEBUG then
        local cv = vrmod.debug_cvars[subsystem]
        if not (cv and cv:GetBool()) then return end
    end

    local prefix = string.format("[VR][%s][%s][%s]", side, subsystem:upper(), level)
    local msg
    if select("#", ...) > 0 then
        local args = {...}
        for i = 1, #args do
            args[i] = tostr(args[i])
        end

        if type(fmt) == "string" and fmt:find("%%") then
            msg = string.format(fmt, unpack(args))
        else
            table.insert(args, 1, fmt)
            msg = table.concat(args, " ")
        end
    else
        msg = tostr(fmt)
    end

    local line = string.format("%s %s", prefix, msg)
    -- Console output
    if lvlNum <= cv_console:GetInt() then
        local colLvl = levelColors[level] or color_white
        local colSide = sideColors[side] or color_white
        local colSub = getSubsystemColor(subsystem)
        MsgC(colSide, "[" .. side .. "] ", colSub, "[" .. subsystem:upper() .. "] ", -- <-- uppercase here
            colLvl, "[" .. level .. "] ", color_white, msg .. "\n")
    end

    -- File output
    if lvlNum <= cv_file:GetInt() then writeFileLine(os.date("[%H:%M:%S] ") .. line) end
end

-- Public shorthands
function vrmod.logger.Debug(fmt, ...)
    Log("DEBUG", fmt, ...)
end

function vrmod.logger.Info(fmt, ...)
    Log("INFO", fmt, ...)
end

function vrmod.logger.Warn(fmt, ...)
    Log("WARN", fmt, ...)
end

function vrmod.logger.Err(fmt, ...)
    Log("ERROR", fmt, ...)
end