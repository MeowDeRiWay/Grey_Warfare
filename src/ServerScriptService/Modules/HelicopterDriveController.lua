local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HelicopterDriveController = {}

local activeHelicopters = {}
local playerInput = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local helicopterControlRemote = remotes:WaitForChild("HelicopterControl")

local DEFAULT_FALL_SPEED = 18
local LANDING_RAY_DISTANCE = 4
local LANDING_GAP = 0.08

local function getAttr(vehicle, name, default)
	local value = vehicle:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

local function getDriverSeat(vehicle)
	local seat = vehicle:FindFirstChild("Driver_seat", true)
	if seat and (seat:IsA("VehicleSeat") or seat:IsA("Seat")) then
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

local function getLandingPart(vehicle, main)
	local landing = vehicle:FindFirstChild("Ground_level", true)
	if landing and landing:IsA("BasePart") then
		return landing
	end
	return main
end

local function setArcadePhysics(vehicle)
	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") then
			-- Аркада: не даємо фізиці Roblox трусити модель.
			item.Anchored = true
			item.CanTouch = true
			item.AssemblyLinearVelocity = Vector3.zero
			item.AssemblyAngularVelocity = Vector3.zero

			-- Колізію лишаємо тільки для Main/Ground_level, але рух все одно через PivotTo.
			if item.Name == "Main" or item.Name == "Ground_level" then
				item.CanCollide = true
			else
				item.CanCollide = false
			end
		end
	end
end

local function clearVelocities(vehicle)
	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") then
			item.AssemblyLinearVelocity = Vector3.zero
			item.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function hasDriver(seat)
	return seat and seat.Occupant ~= nil
end

local function buildRaycastParams(vehicle)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { vehicle }
	params.IgnoreWater = true
	return params
end

local function getLandingHit(vehicle, landingPart, extraDistance)
	local distance = extraDistance or LANDING_RAY_DISTANCE
	local origin = landingPart.Position
	local direction = Vector3.new(0, -distance, 0)
	return workspace:Raycast(origin, direction, buildRaycastParams(vehicle))
end

local function pivotKeepingYaw(vehicle, main, position, yaw)
	vehicle:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
	clearVelocities(vehicle)
end

helicopterControlRemote.OnServerEvent:Connect(function(player, input)
	if typeof(input) ~= "table" then
		return
	end

	playerInput[player] = {
		Lift = math.clamp(tonumber(input.Lift) or 0, 0, 1),
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
		warn("[HelicopterDriveController] Driver_seat not found:", vehicle.Name)
		return
	end

	vehicle.PrimaryPart = main
	local landingPart = getLandingPart(vehicle, main)
	setArcadePhysics(vehicle)

	local _, yaw, _ = main.CFrame:ToOrientation()

	activeHelicopters[vehicle] = {
		Main = main,
		Seat = seat,
		LandingPart = landingPart,
		Owner = ownerPlayer,

		CurrentSpeed = 0,
		CurrentTurn = 0,
		Yaw = yaw,
		HoverY = main.Position.Y,
		IsLanded = false,
	}

	print("[HelicopterDriveController] SAFE arcade helicopter registered:", vehicle.Name)
end

function HelicopterDriveController.UnregisterVehicle(vehicle)
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
		local landingPart = data.LandingPart
		local owner = data.Owner

		if not main or not main.Parent or not seat or not seat.Parent or not landingPart or not landingPart.Parent then
			activeHelicopters[vehicle] = nil
			continue
		end

		setArcadePhysics(vehicle)

		local currentFuel = tonumber(vehicle:GetAttribute("Current_fuel")) or 0
		local maxFuel = tonumber(vehicle:GetAttribute("Max_fuel")) or 0

		local speed = tonumber(getAttr(vehicle, "Speed", 70)) or 70
		local speedReverse = tonumber(getAttr(vehicle, "Speed_reverse", 25)) or 25
		local liftSpeed = tonumber(getAttr(vehicle, "Lift_speed", 18)) or 18
		local turnSpeed = tonumber(getAttr(vehicle, "Turn_speed", 1.6)) or 1.6
		local acceleration = tonumber(getAttr(vehicle, "Acceleration", 45)) or 45
		local fuelPerSecond = tonumber(getAttr(vehicle, "Fuel_per_second", 0.05)) or 0.05
		local fallSpeed = tonumber(getAttr(vehicle, "Fall_speed", DEFAULT_FALL_SPEED)) or DEFAULT_FALL_SPEED

		local pos = main.Position

		if not hasDriver(seat) then
			data.CurrentSpeed = 0
			data.CurrentTurn = 0

			local hit = getLandingHit(vehicle, landingPart, math.max(LANDING_RAY_DISTANCE, fallSpeed * dt + 2))

			if hit then
				local gap = landingPart.Position.Y - pos.Y
				local targetMainY = hit.Position.Y - gap + LANDING_GAP
				local newPos = Vector3.new(pos.X, targetMainY, pos.Z)

				pivotKeepingYaw(vehicle, main, newPos, data.Yaw)
				data.HoverY = newPos.Y
				data.IsLanded = true
			else
				local newPos = pos - Vector3.new(0, fallSpeed * dt, 0)
				pivotKeepingYaw(vehicle, main, newPos, data.Yaw)
				data.HoverY = newPos.Y
				data.IsLanded = false
			end

			continue
		end

		local throttle = 0
		local steer = 0

		if seat:IsA("VehicleSeat") then
			throttle = seat.Throttle
			steer = seat.Steer
		end

		local liftInput = 0
		if owner and playerInput[owner] then
			liftInput = playerInput[owner].Lift or 0
		end

		if currentFuel <= 0 then
			throttle = 0
			steer = 0
			liftInput = 0
		end

		local targetSpeed = 0
		if throttle > 0 then
			targetSpeed = speed
		elseif throttle < 0 then
			targetSpeed = -speedReverse
		end

		local speedStep = acceleration * dt
		data.CurrentSpeed += math.clamp(targetSpeed - data.CurrentSpeed, -speedStep, speedStep)

		data.Yaw += (-steer * turnSpeed * dt)

		local look = (CFrame.Angles(0, data.Yaw, 0)).LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude < 0.1 then
			flatLook = Vector3.zAxis
		else
			flatLook = flatLook.Unit
		end

		local newY = data.HoverY
		if liftInput > 0 then
			newY += liftSpeed * liftInput * dt
		end

		local move = flatLook * data.CurrentSpeed * dt
		local newPos = Vector3.new(pos.X + move.X, newY, pos.Z + move.Z)

		-- Щоб після посадки не сидіти всередині землі, перший кадр з водієм піднімаємо hover до поточної висоти.
		if data.IsLanded then
			data.IsLanded = false
			newPos = Vector3.new(pos.X, pos.Y + 0.05, pos.Z)
			newY = newPos.Y
		end

		data.HoverY = newY
		pivotKeepingYaw(vehicle, main, newPos, data.Yaw)

		if maxFuel > 0 and currentFuel > 0 then
			local moving = math.abs(data.CurrentSpeed) > 1 or liftInput > 0 or math.abs(steer) > 0
			if moving then
				vehicle:SetAttribute("Current_fuel", math.max(0, currentFuel - fuelPerSecond * dt))
			end
		end
	end
end)

return HelicopterDriveController
