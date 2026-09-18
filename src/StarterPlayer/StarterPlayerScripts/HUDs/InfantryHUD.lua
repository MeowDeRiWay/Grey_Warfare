local Players = game:GetService("Players")
local Shared = require(script.Parent.HUDShared)

local InfantryHUD = {}
local player = Players.LocalPlayer
local gui
local hp
local ammo
local mags
local hints

local function equippedWeapon()
	local character = player.Character
	if not character then
		return nil
	end
	local folder = character:FindFirstChild("EquippedWeapon")
	return folder and folder:FindFirstChildWhichIsA("Model") or nil
end

function InfantryHUD.Create(playerGui)
	gui = Shared.makeGui(playerGui, "InfantryHUD", 10)
	local panel = Shared.makePanel(gui, "Panel", UDim2.new(0, 18, 1, -18), UDim2.new(0, 370, 0, 156))
	Shared.makeText(panel, "Title", UDim2.new(0, 12, 0, 8), UDim2.new(1, -24, 0, 26), 20).Text = "INFANTRY"
	hp = Shared.makeText(panel, "HP", UDim2.new(0, 12, 0, 40), UDim2.new(1, -24, 0, 24), 18)
	ammo = Shared.makeText(panel, "Ammo", UDim2.new(0, 12, 0, 66), UDim2.new(1, -24, 0, 24), 18)
	mags = Shared.makeText(panel, "Mags", UDim2.new(0, 12, 0, 92), UDim2.new(1, -24, 0, 24), 18)
	hints = Shared.makeText(panel, "Hints", UDim2.new(0, 12, 0, 120), UDim2.new(1, -24, 0, 24), 15)
	return gui
end

function InfantryHUD.SetEnabled(value)
	if gui then gui.Enabled = value end
end

function InfantryHUD.Update()
	local character = player.Character
	local humanoid = Shared.getHumanoid(player)
	if not character or not humanoid then
		return
	end

	local currentHealth = Shared.getNumber(character, {"HP_cur"}, humanoid.Health)
	local maxHealth = Shared.getNumber(character, {"HP_max"}, humanoid.MaxHealth)
	hp.Text = string.format("HP      %d / %d", math.floor(currentHealth + 0.5), math.floor(maxHealth + 0.5))

	local weapon = equippedWeapon()
	if weapon then
		local current = Shared.getNumber(weapon, {"Current_ammo"}, 0)
		local max = Shared.getNumber(weapon, {"Magazine_size"}, 0)
		ammo.Text = string.format("AMMO    %d / %d", math.floor(current + 0.5), math.floor(max + 0.5))
		hints.Text = "LMB — Fire   |   R — Reload   |   X — Holster"
	else
		ammo.Text = "AMMO    —"
		hints.Text = "X — Draw weapon"
	end

	local reg = Shared.getNumber(character, {"Reg_mag_current"}, 0)
	local regMax = Shared.getNumber(character, {"Reg_mag_max"}, 0)
	local ultra = Shared.getNumber(character, {"Utra_mag_current", "Ultra_mag_current"}, 0)
	local ultraMax = Shared.getNumber(character, {"Utra_mag_max", "Ultra_mag_max"}, 0)
	mags.Text = string.format("MAGS    %d/%d   |   ULTRA %d/%d", reg, regMax, ultra, ultraMax)
end

return InfantryHUD
