local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local turretRemote = ReplicatedStorage:WaitForChild("TurretActionRequest")

-- IMPORTANT:
-- Camera, FOV, mouse lock and sight camera are owned ONLY by
-- CameraController.client.lua.
-- This file owns turret input/aim/fire only.

local AIM_SEND_RATE = 0.05
local FIRE_SEND_RATE = 0.05

local aimAccumulator = 0
local fireAccumulator = 0
local firing = false

local function getControlledVehicle()
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart or nil
	if not seat then
		return nil
	end

	local activeVehicles = workspace:FindFirstChild("ActiveVehicles")
	if not activeVehicles then
		return nil
	end

	local current = seat
	while current and current ~= workspace do
		if current:IsA("Model") and current.Parent == activeVehicles then
			if current:GetAttribute("Plane") == true
				or current:GetAttribute("VehicleType") == "Plane"
			then
				return nil
			end
			return current
		end
		current = current.Parent
	end

	return nil
end

local function getTurretModels(vehicle)
	local result = {}
	if not vehicle then
		return result
	end

	local mountedModules = vehicle:FindFirstChild("MountedModules")
	if not mountedModules then
		return result
	end

	for _, item in ipairs(mountedModules:GetDescendants()) do
		if item:IsA("Model")
			and (
				item:GetAttribute("ModuleRole") == "Turret"
				or item:GetAttribute("Turret") == true
			)
		then
			table.insert(result, item)
		end
	end

	return result
end

local function canControlTurret()
	local vehicle = getControlledVehicle()
	if not vehicle or #getTurretModels(vehicle) == 0 then
		return nil
	end
	return vehicle
end

local function turretSightIsActive()
	return player:GetAttribute("CameraSightMode") == "Turret"
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not canControlTurret() then
			return
		end

		firing = true
		fireAccumulator = 0
		turretRemote:FireServer("Fire")
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = false
	end
end)

RunService.RenderStepped:Connect(function(dt)
	aimAccumulator += dt
	fireAccumulator += dt

	local vehicle = canControlTurret()
	if not vehicle then
		firing = false
		return
	end

	if turretSightIsActive() then
		-- Sight itself follows the turret, so world-space Aim would create
		-- a feedback loop. In sight mode mouse delta directly moves the turret.
		local mouseDelta = UserInputService:GetMouseDelta()
		if mouseDelta.Magnitude > 0 then
			local zoom = math.max(
				1,
				tonumber(player:GetAttribute("CameraSightZoom")) or 1
			)

			turretRemote:FireServer(
				"AimDelta",
				mouseDelta / zoom
			)
		end
	elseif aimAccumulator >= AIM_SEND_RATE then
		aimAccumulator = 0

		-- CameraController owns the camera. We only read its centre ray.
		local camera = workspace.CurrentCamera
		if camera then
			local viewportSize = camera.ViewportSize
			local centerRay = camera:ViewportPointToRay(
				viewportSize.X * 0.5,
				viewportSize.Y * 0.5
			)

			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude

			local exclude = {}
			if player.Character then
				table.insert(exclude, player.Character)
			end
			table.insert(exclude, vehicle)
			rayParams.FilterDescendantsInstances = exclude

			local maxAimDistance =
				tonumber(vehicle:GetAttribute("Turret_aim_distance"))
				or 20000

			local rayResult = workspace:Raycast(
				centerRay.Origin,
				centerRay.Direction * maxAimDistance,
				rayParams
			)

			local aimPoint =
				rayResult
				and rayResult.Position
				or (
					centerRay.Origin
					+ centerRay.Direction * maxAimDistance
				)

			turretRemote:FireServer("Aim", aimPoint)
		end
	end

	if firing and fireAccumulator >= FIRE_SEND_RATE then
		fireAccumulator = 0
		turretRemote:FireServer("Fire")
	end
end)

player.CharacterAdded:Connect(function()
	firing = false
end)
