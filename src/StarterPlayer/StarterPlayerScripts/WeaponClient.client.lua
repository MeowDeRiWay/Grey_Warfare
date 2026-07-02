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

local label = Instance.new("TextLabel")
label.Name = "AmmoLabel"
label.AnchorPoint = Vector2.new(1, 1)
label.Position = UDim2.new(1, -24, 1, -24)
label.Size = UDim2.fromOffset(170, 42)
label.BackgroundTransparency = 0.25
label.BorderSizePixel = 1
label.TextScaled = true
label.Text = "Пістолет: -- / --"
label.Parent = gui

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

	local weapon = getEquippedWeapon()
	if not weapon then
		label.Text = "Пістолет: -- / --"
		return
	end

	local currentAmmo = tonumber(weapon:GetAttribute("Current_ammo")) or 0
	local magazineSize = tonumber(weapon:GetAttribute("Magazine_size")) or 0
	label.Text = string.format("Пістолет: %d / %d", currentAmmo, magazineSize)
end)
