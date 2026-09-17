local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local weaponRemote = remotes:WaitForChild("WeaponActionRequest")

-- Цей скрипт і далі відповідає за керування особистою зброєю.
-- Власний старий WeaponHud прибраний: його відображення тепер робить
-- HUDController.client.lua, щоб не було двох HUD одночасно.

local firing = false

local function getEquippedWeapon()
	local character = player.Character
	if not character then return nil end

	local folder = character:FindFirstChild("EquippedWeapon")
	if not folder then return nil end

	return folder:FindFirstChildWhichIsA("Model")
end

local function isInVehicle()
	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil
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
		return look.Y >= 0 and math.rad(89) or math.rad(-89)
	end

	return math.atan2(look.Y, flatMagnitude)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- Особистою зброєю не керуємо, коли гравець сидить у транспорті.
	-- Так LMB/R не конфліктують з турелями.
	if isInVehicle() then
		return
	end

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
	if isInVehicle() then
		firing = false
		lastAimPitch = nil
		return
	end

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

	-- Сам HUD навмисно тут більше не малюється.
	-- Дані про HP, ammo та магазини читає HUDController.client.lua.
	getEquippedWeapon()
end)
