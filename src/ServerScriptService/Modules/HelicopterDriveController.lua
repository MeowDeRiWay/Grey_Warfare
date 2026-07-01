local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HelicopterDriveController = {}

local activeHelicopters = {}
local playerInput = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local helicopterControlRemote = remotes:WaitForChild("HelicopterControl")

local function getAttr(vehicle, name, default)
	local value = vehicle:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

local function getDriverSeat(vehicle)
	local seat = vehicle:FindFirstChild("Driver_seat", true)
	if seat and seat:IsA("VehicleSeat") then
		return seat
	end
	return nil
end

local function getMain(vehicle)
	local main = vehicle:FindFirstChild("Main", true)
	if main and main:IsA("BasePart") then
		return main
	end
	return nil
end

local function canMoveTo(vehicle, targetCFrame)
	local size = vehicle:GetExtentsSize() * 0.95

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { vehicle }

	local parts = workspace:GetPartBoundsInBox(targetCFrame, size, params)

	for _, part in ipairs(parts) do
		if part.CanCollide then
			return false
		end
	end

	return true
end

helicopterControlRemote.OnServerEvent:Connect(function(player, input)
	if typeof(input) ~= "table" then
		return
	end

	playerInput[player] = {
		Lift = tonumber(input.Lift) or 0,
	}
end)

function HelicopterDriveController.RegisterVehicle(vehicle, ownerPlayer)
	local main = getMain(vehicle)
	local seat = getDriverSeat(vehicle)

	if not main then
		warn("[HelicopterDriveController] Main not found:", vehicle.Name)
		return
	end

	if not seat then
		warn("[HelicopterDriveController] Driver_seat VehicleSeat not found:", vehicle.Name)
		return
	end

	main:SetNetworkOwner(nil)
	main.Anchored = true

	activeHelicopters[vehicle] = {
		Main = main,
		Seat = seat,
		Owner = ownerPlayer,

		Yaw = main.Orientation.Y,
		Velocity = Vector3.zero,
	}

	print("[HelicopterDriveController] Arcade helicopter registered:", vehicle.Name)
end

function HelicopterDriveController.UnregisterVehicle(vehicle)
	local data = activeHelicopters[vehicle]

	if data and data.Main and data.Main.Parent then
		data.Main.Anchored = false
	end

	activeHelicopters[vehicle] = nil
end

RunService.Heartbeat:Connect(function(dt)
	for vehicle, data in pairs(activeHelicopters) do
		if not vehicle.Parent then
			activeHelicopters[vehicle] = nil
			continue
		end

		local main = data.Main
		local seat = data.Seat
		local owner = data.Owner

		if not main or not main.Parent or not seat or not seat.Parent then
			activeHelicopters[vehicle] = nil
			continue
		end

		local currentFuel = tonumber(vehicle:GetAttribute("Current_fuel")) or 0
		local maxFuel = tonumber(vehicle:GetAttribute("Max_fuel")) or 0

		local speed = tonumber(getAttr(vehicle, "Speed", 120)) or 120
		local speedReverse = tonumber(getAttr(vehicle, "Speed_reverse", 40)) or 40
		local liftSpeed = tonumber(getAttr(vehicle, "Lift_speed", 40)) or 40
		local turnSpeed = tonumber(getAttr(vehicle, "Turn_speed", 2)) or 2
		local acceleration = tonumber(getAttr(vehicle, "Acceleration", 80)) or 80
		local fuelPerSecond = tonumber(getAttr(vehicle, "Fuel_per_second", 0.05)) or 0.05

		local throttle = seat.Throttle
		local steer = seat.Steer
		local lift = 0

		if owner and playerInput[owner] then
			lift = playerInput[owner].Lift or 0
		end

		if currentFuel <= 0 then
			throttle = 0
			steer = 0
			lift = 0
		end

		data.Yaw -= steer * turnSpeed * 60 * dt

		local yawCFrame = CFrame.Angles(0, math.rad(data.Yaw), 0)
		local forward = yawCFrame.LookVector

		local targetVelocity = Vector3.zero

		if throttle > 0 then
			targetVelocity += forward * speed
		elseif throttle < 0 then
			targetVelocity -= forward * speedReverse
		end

		if lift > 0 then
			targetVelocity += Vector3.yAxis * liftSpeed
		elseif lift < 0 then
			targetVelocity -= Vector3.yAxis * liftSpeed
		end

		local alpha = math.clamp(acceleration * dt / math.max(speed, 1), 0, 1)
		data.Velocity = data.Velocity:Lerp(targetVelocity, alpha)

		local newPosition = main.Position + data.Velocity * dt
		local targetCFrame = CFrame.new(newPosition) * CFrame.Angles(0, math.rad(data.Yaw), 0)

		if canMoveTo(vehicle, targetCFrame) then
			vehicle:PivotTo(targetCFrame)
		else
			local horizontalPosition = Vector3.new(newPosition.X, main.Position.Y, newPosition.Z)
			local horizontalCFrame = CFrame.new(horizontalPosition) * CFrame.Angles(0, math.rad(data.Yaw), 0)

			if canMoveTo(vehicle, horizontalCFrame) then
				vehicle:PivotTo(horizontalCFrame)
			end

			if data.Velocity.Y < 0 then
				data.Velocity = Vector3.new(data.Velocity.X, 0, data.Velocity.Z)
			end
		end

		if maxFuel > 0 and currentFuel > 0 then
			local moving = data.Velocity.Magnitude > 0.5

			if moving then
				local used = fuelPerSecond * dt
				vehicle:SetAttribute("Current_fuel", math.max(0, currentFuel - used))
			end
		end
	end
end)

return HelicopterDriveController