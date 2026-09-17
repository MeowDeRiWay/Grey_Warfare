local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local aircraftWeaponRemote = remotes:WaitForChild("AircraftWeaponAction")

local function getControlledAircraft()
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local seat = humanoid.SeatPart
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
			local isPlane =
				current:GetAttribute("Plane") == true
				or current:GetAttribute("VehicleType") == "Plane"

			local isHelicopter =
				current:GetAttribute("VehicleType") == "Helicopter"

			if isPlane or isHelicopter then
				return current
			end

			return nil
		end

		current = current.Parent
	end

	return nil
end


local POSE_SEND_RATE = 0.05
local poseAccumulator = 0

RunService.RenderStepped:Connect(function(dt)
	poseAccumulator += dt
	if poseAccumulator < POSE_SEND_RATE then
		return
	end
	poseAccumulator = 0

	local vehicle = getControlledAircraft()
	if not vehicle then
		return
	end

	-- Send the actual client-visible aircraft pose AND its inherited velocity.
	-- Plane/heli local -X is treated as forward in the current arcade setup.
	local pivot = vehicle:GetPivot()
	local currentSpeed =
		math.max(
			0,
			tonumber(vehicle:GetAttribute("Current_speed")) or 0
		)

	local velocity =
		(-pivot.RightVector) * currentSpeed

	aircraftWeaponRemote:FireServer("Pose", {
		CFrame = pivot,
		Velocity = velocity,
	})
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	if not getControlledAircraft() then
		return
	end

	aircraftWeaponRemote:FireServer("FireRocket")
end)

print("[AircraftWeaponClient] LIVE POSE + inherited velocity + rocket fire loaded")
