-- ArcVR ammo lives on the weapon (LoadedRounds / Chambered / Magazine), not Clip1.
-- Drop must copy that state by value. Pickup must not read it off an entity
-- that was already removed. Reload pose runs once per stereo frame; the held
-- mag is drawn per eye (a stereo-frame stamp hid it on the second eye).
g_VR = g_VR or {}
vrmod = vrmod or {}
vrmod.utils = vrmod.utils or {}

local function clamp_int(n, lo, hi)
	n = math.floor(tonumber(n) or 0)
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

local function copy_atts(src)
	local atts = {}
	if type(src) ~= "table" then return atts end
	for i, name in pairs(src) do
		if type(i) == "number" and i >= 0 and i <= 255 then
			if type(name) == "string" then
				atts[i] = name
			else
				atts[i] = ""
			end
		end
	end
	return atts
end

--- Right eye must not run VRThink. A second pass spends FrameTime and
--- rebuilds the slide from a viewmodel matrix the left eye already moved.
function vrmod.utils.ArcVrReloadThink_ShouldRun(eye)
	return eye ~= "right"
end

--- Held mag / attachment prop: skip only when THIS eye already drew it.
--- Same stereo frame + other eye still needs a draw.
function vrmod.utils.ArcVrHoldDraw_AlreadyPainted(opts)
	opts = type(opts) == "table" and opts or {}
	if opts.drawn_frame == nil or opts.frame == nil then return false end
	if opts.drawn_frame ~= opts.frame then return false end
	if opts.eye == nil and opts.drawn_eye == nil then return true end
	if opts.eye == nil or opts.drawn_eye == nil then return false end
	return opts.drawn_eye == opts.eye
end

--- Clip1 refill on drop deletes ArcVR reserve ammo. ArcVR does not use Clip1.
function vrmod.utils.ArcVrDrop_ShouldRefillClip(wep)
	if type(wep) ~= "table" then return true end
	if wep.ArcticVR or wep.ArcticVRNade then return false end
	return true
end

--- Magazine id. ArcVR stores a string, or the mag entity (MagID / Name).
local function mag_id(mag)
	if type(mag) == "string" then
		if mag == "" then return nil end
		return mag
	end
	if type(mag) ~= "table" then return nil end
	local id = mag.MagID
	if type(id) ~= "string" or id == "" then id = mag.Name end
	if type(id) ~= "string" or id == "" then return nil end
	return id
end

function vrmod.utils.ArcVrDrop_CopyState(wep)
	if type(wep) ~= "table" or not wep.ArcticVR then return nil end
	local atts = {}
	if type(wep.Attachments) == "table" then
		for i, slot in pairs(wep.Attachments) do
			if type(i) == "number" and i >= 0 and i <= 255 and type(slot) == "table" then
				local name = slot.Installed
				atts[i] = (type(name) == "string" and name) or ""
			end
		end
	end
	local mag = mag_id(wep.Magazine)
	return {
		LoadedRounds = clamp_int(wep.LoadedRounds, 0, 65535),
		Chambered = clamp_int(wep.Chambered, 0, 255),
		EmptyChambered = clamp_int(wep.EmptyChambered, 0, 255),
		Magazine = mag,
		SlideLockedBack = wep.SlideLockedBack and true or false,
		Firemode = clamp_int(wep.Firemode, -128, 127),
		AttInstalled = atts,
	}
end

function vrmod.utils.ArcVrDrop_CloneState(snap)
	if type(snap) ~= "table" then return nil end
	local mag = mag_id(snap.Magazine)
	return {
		LoadedRounds = clamp_int(snap.LoadedRounds, 0, 65535),
		Chambered = clamp_int(snap.Chambered, 0, 255),
		EmptyChambered = clamp_int(snap.EmptyChambered, 0, 255),
		Magazine = mag,
		SlideLockedBack = snap.SlideLockedBack and true or false,
		Firemode = clamp_int(snap.Firemode, -128, 127),
		AttInstalled = copy_atts(snap.AttInstalled),
	}
end

function vrmod.utils.ArcVrDrop_ApplyState(wep, snap)
	snap = vrmod.utils.ArcVrDrop_CloneState(snap)
	if type(wep) ~= "table" or not snap then return false end
	wep.LoadedRounds = snap.LoadedRounds
	wep.Chambered = snap.Chambered
	wep.EmptyChambered = snap.EmptyChambered
	wep.Magazine = snap.Magazine
	wep.SlideLockedBack = snap.SlideLockedBack
	wep.Firemode = snap.Firemode
	if type(wep.Attachments) == "table" then
		for i, slot in pairs(wep.Attachments) do
			if type(i) == "number" and type(slot) == "table" and snap.AttInstalled[i] ~= nil then
				local name = snap.AttInstalled[i]
				slot.Installed = (name ~= "" and name) or nil
			end
		end
	end
	wep.avrSnapshot = snap
	return true
end

function vrmod.utils.ArcVrDrop_ReserveRounds(snap)
	snap = vrmod.utils.ArcVrDrop_CloneState(snap)
	if not snap then return 0 end
	return snap.LoadedRounds + snap.Chambered
end
