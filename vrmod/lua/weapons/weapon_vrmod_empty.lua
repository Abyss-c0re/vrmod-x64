SWEP.PrintName = "Empty Hand"
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.Spawnable = true
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = ""
SWEP.DrawAmmo = false
SWEP.Primary.Ammo = "none"
SWEP.Primary.ClipSize = 0
SWEP.Primary.DefaultClip = 0
SWEP.Secondary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
function SWEP:Initialize()
	self:SetHoldType("fist")
end

function SWEP:PrimaryAttack()
end

function SWEP:SecondaryAttack()
end