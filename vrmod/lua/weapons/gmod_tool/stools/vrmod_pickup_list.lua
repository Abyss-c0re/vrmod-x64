TOOL.Category = "VRMod"
TOOL.Name = "VR Pickup Lists"
TOOL.Command = nil
TOOL.ConfigName = ""
if CLIENT then
    function TOOL:BuildCPanel()
        -- Title
        local header = vgui.Create("DLabel")
        header:SetText("VRMod Pickup Lists")
        header:SetFont("DermaLarge")
        header:SetColor(Color(255, 255, 255))
        header:SizeToContents()
        header:Dock(TOP)
        header:DockMargin(5, 5, 5, 5)
        self.Panel:AddItem(header)
        -- Description
        local desc = vgui.Create("DLabel")
        desc:SetText("Edit VR pickup whitelist and blacklist for VRMod.\n\nControls:")
        desc:SetWrap(true)
        desc:SetAutoStretchVertical(true)
        desc:SetColor(Color(200, 200, 200))
        desc:Dock(TOP)
        desc:DockMargin(5, 0, 5, 5)
        self.Panel:AddItem(desc)
        -- Controls list
        local controls = vgui.Create("DLabel")
        controls:SetText("• LMB: Add prop to WHITELIST\n• RMB: Add prop to BLACKLIST\n• R: Remove from list")
        controls:SetWrap(true)
        controls:SetAutoStretchVertical(true)
        controls:SetColor(Color(180, 180, 255))
        controls:Dock(TOP)
        controls:DockMargin(10, 0, 5, 5)
        self.Panel:AddItem(controls)
        -- Optional: show hot reload notice
        local notice = vgui.Create("DLabel")
        notice:SetText("Changes are applied immediately to all players")
        notice:SetWrap(true)
        notice:SetAutoStretchVertical(true)
        notice:SetColor(Color(180, 255, 180))
        notice:Dock(TOP)
        notice:DockMargin(5, 0, 5, 5)
        self.Panel:AddItem(notice)
    end

    -- Bottom hint box
    language.Add("tool.vrmod_pickuplist.0", "LMB: Whitelist | RMB: Blacklist | R: Remove")
    function TOOL:GetInstructionText(trace)
        return language.GetPhrase("tool.vrmod_pickuplist.0")
    end
end

local function GetKey(ent)
    return ent:GetClass():lower() .. "|" .. (ent:GetModel() or ""):lower()
end

function TOOL:LeftClick(trace)
    if not IsValid(trace.Entity) or CLIENT then return false end
    local key = GetKey(trace.Entity)
    vrmod.pickupLists.whitelist[key] = true
    vrmod.pickupLists.blacklist[key] = nil
    vrmod.SavePickupLists()
    net.Start("vrmod_pickuplists_reload")
    net.Broadcast()
    self:GetOwner():ChatPrint("Added to VR pickup WHITELIST")
    return true
end

function TOOL:RightClick(trace)
    if not IsValid(trace.Entity) or CLIENT then return false end
    local key = GetKey(trace.Entity)
    vrmod.pickupLists.blacklist[key] = true
    vrmod.pickupLists.whitelist[key] = nil
    vrmod.SavePickupLists()
    net.Start("vrmod_pickuplists_reload")
    net.Broadcast()
    self:GetOwner():ChatPrint("Added to VR pickup BLACKLIST")
    return true
end

function TOOL:Reload(trace)
    if not IsValid(trace.Entity) or CLIENT then return false end
    local key = GetKey(trace.Entity)
    vrmod.pickupLists.whitelist[key] = nil
    vrmod.pickupLists.blacklist[key] = nil
    vrmod.SavePickupLists()
    net.Start("vrmod_pickuplists_reload")
    net.Broadcast()
    self:GetOwner():ChatPrint("Removed from VR pickup lists")
    return true
end