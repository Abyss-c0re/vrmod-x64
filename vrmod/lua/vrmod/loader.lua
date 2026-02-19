function VRMod_Loader(folder)
    -- Ensure folder ends with a slash (pure Lua, no EndWith)
    if folder:sub(-1) ~= "/" then folder = folder .. "/" end
    -- Determine subsystem name (last folder)
    local parts = string.Explode("/", string.TrimRight(folder, "/"))
    local subsystemName = parts[#parts] or folder
    -- Helper function to include files
    local function includeFile(f)
        local path = folder .. f
        if f:StartWith("sh_") then
            if SERVER then AddCSLuaFile(path) end
            include(path)
            --MsgC(Color(150, 0, 200), "[VRMod] [SH] ", color_white, f, "\n")
            return
        end

        if f:StartWith("sv_") then
            if SERVER then
                include(path)
                --MsgC(Color(200, 150, 0), "[VRMod] [SV] ", color_white, f, "\n")
            end
            return
        end

        if f:StartWith("cl_") then
            if SERVER then
                AddCSLuaFile(path)
                --MsgC(Color(0, 180, 255), "[VRMod] [->CL] ", color_white, f, "\n")
            else
                include(path)
                --MsgC(Color(0, 180, 255), "[VRMod] [CL] ", color_white, f, "\n")
            end
            return
        end
    end

    -- Scan files in folder
    local files, _ = file.Find(folder .. "*.lua", "LUA")
    table.sort(files)
    -- Separate by prefix to guarantee load order
    local sh_files, sv_files, cl_files = {}, {}, {}
    for _, f in ipairs(files) do
        if f ~= "loader.lua" and f ~= "init.lua" then
            if f:StartWith("sh_") then
                table.insert(sh_files, f)
            elseif f:StartWith("sv_") then
                table.insert(sv_files, f)
            elseif f:StartWith("cl_") then
                table.insert(cl_files, f)
            end
        end
    end

    -- Include files in order: shared -> server -> client
    for _, f in ipairs(sh_files) do
        includeFile(f)
    end

    for _, f in ipairs(sv_files) do
        includeFile(f)
    end

    for _, f in ipairs(cl_files) do
        includeFile(f)
    end

    -- Mark subsystem as loaded
    vrmod = vrmod or {}
    vrmod.status = vrmod.status or {}
    vrmod.status[subsystemName] = true
    -- Final log
    MsgC(Color(0, 200, 0), "[VRMod] Subsystem initialized: ", color_white, string.upper(subsystemName), "\n")
end