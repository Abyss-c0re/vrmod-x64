vrmod = vrmod or {}
vrmod.logger = vrmod.logger or {}
-- ConVars for log levels
local cv_console = CreateConVar("vrmod_log_console", "3", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Minimum log level for console (0=OFF, 1=ERROR, 2=WARN, 3=INFO, 4=DEBUG)")
local cv_file = CreateConVar("vrmod_log_file", "4", FCVAR_REPLICATED + FCVAR_ARCHIVE, "Minimum log level for file (0=OFF, 1=ERROR, 2=WARN, 3=INFO, 4=DEBUG)")
-- Level table
local levels = {
    ERROR = 1,
    WARN = 2,
    INFO = 3,
    DEBUG = 4,
}

local levelColors = {
    DEBUG = Color(150, 150, 150),
    INFO = Color(0, 200, 0),
    WARN = Color(255, 200, 0),
    ERROR = Color(255, 0, 0),
}

-- Helpers
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

-- File init
local logDir = "vrmod_logs"
if not file.Exists(logDir, "DATA") then file.CreateDir(logDir) end
local side = SERVER and "server" or "client"
local logFileName = string.format("%s/vrmod_%s_%s.txt", logDir, side, os.date("%Y%m%d_%H%M%S"))
local function writeFileLine(line)
    file.Append(logFileName, line .. "\n")
end

-- Core log function (local only)
local function Log(level, fmt, ...)
    local lvlNum = levels[level]
    if not lvlNum then return end
    local prefix = string.format("[VRMod][%s][%s]", CLIENT and "Client" or "Server", level)
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
    -- Console output (if allowed)
    if lvlNum <= cv_console:GetInt() then
        local col = levelColors[level] or color_white
        MsgC(col, line .. "\n")
    end

    -- File output (if allowed)
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