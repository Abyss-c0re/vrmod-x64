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
function vrmod.utils.BlockInputActions(hookName, identifier, actions, condition)
    filterHook(hookName, identifier, actions, condition)
end

-- Public API: unblock previously filtered hook (restores original)
function vrmod.utils.UnblockInputActions(hookName, identifier)
    unblockHook(hookName, identifier)
end

if CLIENT then
    -- Wrap climb input cache ONCE. Re-hooking every Think nested wrappers forever
    -- and starved primaryfire edges used by pause hub / quick menu clicks.
    local climbingHookID = "vrmod_brush_climbing_inputcache"
    local rightHandActions = {
        ["boolean_right_pickup"] = true,
        ["boolean_primaryfire"] = true,
        ["boolean_secondaryfire"] = true,
    }
    local climbWrapDone = false
    hook.Add("Think", "vrmod_climbing_hook_blocker_weapon", function()
        if climbWrapDone then return end
        local cv = GetConVar("vrmod_brushclimb_enable")
        if not cv or not cv:GetBool() then return end
        local hooks = hook.GetTable()["VRMod_Input"]
        if not hooks or not hooks[climbingHookID] then return end
        local originalHook = hooks[climbingHookID]
        if not isfunction(originalHook) then return end
        -- Do not wrap an already-wrapped function
        if originalHook._vrmodClimbWeaponWrap then
            climbWrapDone = true
            return
        end
        climbWrapDone = true
        local wrapped
        wrapped = function(action, pressed)
            local ply = LocalPlayer()
            if rightHandActions[action] and vrmod.UsingEmptyHands and not vrmod.UsingEmptyHands(ply) then
                return -- block right-hand climbing while holding a weapon
            end
            return originalHook(action, pressed)
        end
        wrapped._vrmodClimbWeaponWrap = true
        hook.Add("VRMod_Input", climbingHookID, wrapped)
    end)
    hook.Add("VRMod_Exit", "vrmod_climbing_hook_blocker_reset", function()
        climbWrapDone = false
    end)
end