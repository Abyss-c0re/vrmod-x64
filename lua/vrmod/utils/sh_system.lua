g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}
-- Hook blocker: temporary block 3rd party hooks 
local originalHooks = {}
-- Local: completely block a hook
local function blockHook(hookName, identifier)
    local hooks = hook.GetTable()[hookName]
    if not hooks or not hooks[identifier] then return end
    originalHooks[hookName] = originalHooks[hookName] or {}
    if not originalHooks[hookName][identifier] then originalHooks[hookName][identifier] = hooks[identifier] end
    hook.Add(hookName, identifier, function() end)
end

-- Local: restore a hook entirely
local function unblockHook(hookName, identifier)
    if originalHooks[hookName] and originalHooks[hookName][identifier] then hook.Add(hookName, identifier, originalHooks[hookName][identifier]) end
end

-- Local: wrap a hook to block certain actions conditionally
local function filterHook(hookName, identifier, actionsToBlock, conditionFunc)
    local hooks = hook.GetTable()[hookName]
    if not hooks or not hooks[identifier] then return end
    originalHooks[hookName] = originalHooks[hookName] or {}
    if not originalHooks[hookName][identifier] then originalHooks[hookName][identifier] = hooks[identifier] end
    local originalHook = originalHooks[hookName][identifier]
    hook.Add(hookName, identifier, function(action, pressed)
        if actionsToBlock[action] and conditionFunc(action, pressed) then
            return -- block this action for this hook
        end
        return originalHook(action, pressed)
    end)
end

-- Public API: toggle full hook on/off
function vrmod.utils.ToggleHook(hookName, identifier, state)
    if state then
        unblockHook(hookName, identifier)
    else
        blockHook(hookName, identifier)
    end
end

-- Blocking access to actions inside VRModInput hook
-- Usage: -- Block primary fire only when menuFocus is true
-- vrmod.utils.BlockInputActions(
--     "VRMod_Input",
--     "hook_name",
--     { ["boolean_primaryfire"] = true },
--     function(action, pressed)
--         return g_VR.menuFocus
--     end
-- )
-- -- Handle input normally
-- HandleInput() -- 3rd-party hook won’t see primary fire if menuFocus is true
-- -- Later, restore full functionality
-- vrmod.utils.UnblockInputActions("VRMod_Input", "hook_name")
-- HandleInput() -- 3rd-party hook now sees all actions
-- Public API: block specific actions under a condition
function vrmod.utils.BlockInputActions(hookName, identifier, actions, condition)
    filterHook(hookName, identifier, actions, condition)
end

-- Public API: unblock previously filtered hook (restores original)
function vrmod.utils.UnblockInputActions(hookName, identifier)
    unblockHook(hookName, identifier)
end