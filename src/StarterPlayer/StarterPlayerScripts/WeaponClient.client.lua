local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local weaponRemote = remotes:WaitForChild("WeaponActionRequest")

local gui = Instance.new("ScreenGui")
gui.Name = "WeaponHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "StatusFrame"
frame.AnchorPoint = Vector2.new(1, 1)
frame.Position = UDim2.new(1, -24, 1, -24)
frame.Size = UDim2.fromOffset(260, 150)
frame.BackgroundTransparency = 0.25
frame.BorderSizePixel = 1
frame.Parent = gui

local function makeLabel(name, y, text)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(8, y)
	label.Size = UDim2.new(1, -16, 0, 24)
	label.Font = Enum.Font.SourceSans
	label.TextSize = 20
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = frame
	return label
end

local healthLabel = makeLabel("HealthLabel", 6, "Health: -- / --")
local ammoLabel = makeLabel("AmmoLabel", 32, "Ammo: -- / --")
local regMagLabel = makeLabel("RegMagLabel", 58, "Regular mags: -- / --")
local utraMagLabel = makeLabel("UtraMagLabel", 84, "Utra mags: -- / --")
local hintLabel = makeLabel("HintLabel", 112, "X - holster weapon")

local firing = false

local function getEquippedWeapon()
	local character = player.Character
	if not character then return nil end

	local folder = character:FindFirstChild("EquippedWeapon")
	if not folder then return nil end

	return folder:FindFirstChildWhichIsA("Model")
end

local function getCameraPitch()
	camera = workspace.CurrentCamera
	if not camera then
		return 0
	end

	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local flatMagnitude = flat.Magnitude

	if flatMagnitude < 0.001 then
		if look.Y >= 0 then
			return math.rad(89)
		end
		return math.rad(-89)
	end

	return math.atan2(look.Y, flatMagnitude)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = true
		weaponRemote:FireServer("Fire")
	elseif input.KeyCode == Enum.KeyCode.R then
		weaponRemote:FireServer("Reload")
	elseif input.KeyCode == Enum.KeyCode.X then
		weaponRemote:FireServer("ToggleWeapon")
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = false
	end
end)

local fireAccumulator = 0
local aimAccumulator = 0
local lastAimPitch = nil

RunService.RenderStepped:Connect(function(dt)
	fireAccumulator += dt
	aimAccumulator += dt

	if aimAccumulator >= 0.05 then
		aimAccumulator = 0

		local aimPitch = getCameraPitch()
		if lastAimPitch == nil or math.abs(aimPitch - lastAimPitch) > 0.002 then
			lastAimPitch = aimPitch
			weaponRemote:FireServer("AimPitch", aimPitch)
		end
	end

	if firing and fireAccumulator >= 0.05 then
		fireAccumulator = 0
		weaponRemote:FireServer("Fire")
	end

	local character = player.Character
	local weapon = getEquippedWeapon()

	local currentHealth = character and tonumber(character:GetAttribute("Current_health")) or 0
	local maxHealth = character and tonumber(character:GetAttribute("Max_health")) or 0
	healthLabel.Text = string.format("Health: %d / %d", math.floor(currentHealth + 0.5), math.floor(maxHealth + 0.5))

	local currentAmmo = weapon and tonumber(weapon:GetAttribute("Current_ammo")) or 0
	local magazineSize = weapon and tonumber(weapon:GetAttribute("Magazine_size")) or 0
	ammoLabel.Text = string.format("Ammo: %d / %d", math.floor(currentAmmo + 0.5), math.floor(magazineSize + 0.5))

	local regCurrent = character and tonumber(character:GetAttribute("Reg_mag_current")) or 0
	local regMax = character and tonumber(character:GetAttribute("Reg_mag_max")) or 0
	regMagLabel.Text = string.format("Regular mags: %d / %d", math.floor(regCurrent + 0.5), math.floor(regMax + 0.5))

	local utraCurrent = character and tonumber(character:GetAttribute("Utra_mag_current")) or 0
	local utraMax = character and tonumber(character:GetAttribute("Utra_mag_max")) or 0
	utraMagLabel.Text = string.format("Utra mags: %d / %d", math.floor(utraCurrent + 0.5), math.floor(utraMax + 0.5))

	if weapon then
		hintLabel.Text = "X - holster weapon"
	else
		hintLabel.Text = "X - draw weapon"
	end
end)
