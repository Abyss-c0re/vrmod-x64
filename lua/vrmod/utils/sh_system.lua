g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
-- Local storage for original hooks
local originalHooks = {}
-- Local helper: block a hook
local function blockHook(hookName, identifier)
    local hooks = hook.GetTable()[hookName]
    if not hooks or not hooks[identifier] then return end
    originalHooks[hookName] = originalHooks[hookName] or {}
    if not originalHooks[hookName][identifier] then originalHooks[hookName][identifier] = hooks[identifier] end
    -- Replace with noop
    hook.Add(hookName, identifier, function() end)
end

-- Local helper: unblock a hook
local function unblockHook(hookName, identifier)
    if originalHooks[hookName] and originalHooks[hookName][identifier] then hook.Add(hookName, identifier, originalHooks[hookName][identifier]) end
end

-- Public API: toggle a hook on/off
function vrmod.utils.ToggleHook(hookName, identifier, state)
    if state then
        unblockHook(hookName, identifier)
    else
        blockHook(hookName, identifier)
    end
end