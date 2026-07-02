local RunService = game:GetService("RunService")

local VehicleDriveController = {}

local activeVehicles = {}

local function getAttr(vehicle, name, default)
	local value = vehicle:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

local function getMain(vehicle)
	local main = vehicle:FindFirstChild("Main", true)
	if main and main:IsA("BasePart") then
		return main
	end
	return nil
end

local function getDriverSeat(vehicle)
	local seat = vehicle:FindFirstChild("Driver_seat", true)
	if seat and seat:IsA("VehicleSeat") then
		return seat
	end

	seat = vehicle:FindFirstChild("VehicleSeat", true)
	if seat and seat:IsA("VehicleSeat") then
		return seat
	end

	return nil
end

local function getConfig(vehicle)
	return {
		Speed = getAttr(vehicle, "Speed", 40),
		Speed_reverse = getAttr(vehicle, "Speed_reverse", 10),

		Acceleration = getAttr(vehicle, "Acceleration", 10),
		Brake_force = getAttr(vehicle, "Brake_force", 40),

		Steer_angle = getAttr(vehicle, "Steer_angle", 28),
		Steer_speed = getAttr(vehicle, "Steer_speed", 7),

		Can_flip = getAttr(vehicle, "Can_flip", true),
		Flip_time = getAttr(vehicle, "Flip_time", 2),

		Obstacle_check_distance = getAttr(vehicle, "Obstacle_check_distance", 4),

		Max_fuel = getAttr(vehicle, "Max_fuel", 100),
		Fuel_per_stud = getAttr(vehicle, "Fuel_per_stud", 0.01),
	}
end

local function findBlockingObject(hitPart)
	local current = hitPart

	while current and current ~= workspace do
		if current:GetAttribute("BlocksVehicle") == true then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function isObstacleAhead(vehicle, main, direction, distance)
	if distance <= 0 then
		return false
	end

	if direction.Magnitude < 0.1 then
		return false
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { vehicle }

	local forward = direction.Unit
	local right = main.CFrame.RightVector

	local origins = {
		main.Position + Vector3.new(0, 0.8, 0),
		main.Position + right * (main.Size.X * 0.45) + Vector3.new(0, 0.8, 0),
		main.Position - right * (main.Size.X * 0.45) + Vector3.new(0, 0.8, 0),
	}

	for _, origin in ipairs(origins) do
		local result = workspace:Raycast(origin, forward * distance, params)

		if result then
			if findBlockingObject(result.Instance) then
				return true
			end
		end
	end

	return false
end

local function consumeFuel(vehicle, data, main, cfg)
	local currentFuel = vehicle:GetAttribute("Current_fuel")

	if currentFuel == nil then
		currentFuel = cfg.Max_fuel
		vehicle:SetAttribute("Current_fuel", currentFuel)
	end

	local distance = (main.Position - data.LastPosition).Magnitude
	data.LastPosition = main.Position

	if currentFuel <= 0 then
		data.CurrentSpeed = 0
		return false
	end

	if distance > 0.01 and math.abs(data.CurrentSpeed) > 0.5 then
		local used = distance * cfg.Fuel_per_stud
		local newFuel = math.max(0, currentFuel - used)
		vehicle:SetAttribute("Current_fuel", newFuel)

		if newFuel <= 0 then
			data.CurrentSpeed = 0
			return false
		end
	end

	return true
end

local function moveTowards(current, target, step)
	if current < target then
		return math.min(current + step, target)
	elseif current > target then
		return math.max(current - step, target)
	end

	return current
end

function VehicleDriveController.RegisterVehicle(vehicle, ownerPlayer)
	local main = getMain(vehicle)
	local seat = getDriverSeat(vehicle)

	if not main then
		warn("[VehicleDriveController] Main not found:", vehicle.Name)
		return
	end

	if not seat then
		warn("[VehicleDriveController] VehicleSeat not found:", vehicle.Name)
		return
	end

	pcall(function()
		main:SetNetworkOwner(ownerPlayer)
	end)

	activeVehicles[vehicle] = {
		Main = main,
		Seat = seat,
		Owner = ownerPlayer,

		CurrentSpeed = 0,
		CurrentSteer = 0,

		LastPosition = main.Position,
		FlippedTime = 0,
	}

	vehicle:SetAttribute("Current_speed", 0)

	print("[VehicleDriveController] Vehicle registered:", vehicle.Name)
end

function VehicleDriveController.UnregisterVehicle(vehicle)
	activeVehicles[vehicle] = nil
end

RunService.Heartbeat:Connect(function(dt)
	for vehicle, data in pairs(activeVehicles) do
		if not vehicle.Parent then
			activeVehicles[vehicle] = nil
			continue
		end

		local main = data.Main
		local seat = data.Seat

		if not main or not main.Parent or not seat or not seat.Parent then
			activeVehicles[vehicle] = nil
			continue
		end

		local cfg = getConfig(vehicle)
		local hasFuel = consumeFuel(vehicle, data, main, cfg)

		local throttle = seat.Throttle
		local steer = seat.Steer

		if not hasFuel then
			throttle = 0
		end

		local targetSpeed = 0

		if throttle > 0 then
			targetSpeed = cfg.Speed
		elseif throttle < 0 then
			targetSpeed = -cfg.Speed_reverse
		end

		local speedStep
		if throttle == 0 then
			speedStep = cfg.Brake_force * dt
		else
			speedStep = cfg.Acceleration * dt
		end

		data.CurrentSpeed = moveTowards(data.CurrentSpeed, targetSpeed, speedStep)

		local steerStep = cfg.Steer_speed * dt
		data.CurrentSteer = moveTowards(data.CurrentSteer, steer, steerStep)

		local forward = main.CFrame.LookVector
		local flatForward = Vector3.new(forward.X, 0, forward.Z)

		if flatForward.Magnitude < 0.01 then
			flatForward = Vector3.zAxis
		else
			flatForward = flatForward.Unit
		end

		local moveDirection = flatForward
		if data.CurrentSpeed < 0 then
			moveDirection = -flatForward
		end

		if math.abs(data.CurrentSpeed) > 1 then
			if isObstacleAhead(vehicle, main, moveDirection, cfg.Obstacle_check_distance) then
				data.CurrentSpeed = 0
			end
		end

		local pos = main.Position
		local yaw = math.atan2(-flatForward.X, -flatForward.Z)

		if math.abs(data.CurrentSpeed) > 0.5 then
			local steerDirection = 1
			if data.CurrentSpeed < 0 then
				steerDirection = -1
			end

			local turnRate = math.rad(cfg.Steer_angle) * data.CurrentSteer * steerDirection
			yaw += turnRate * dt
		end

		local newForward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
		local newPos = pos + newForward * data.CurrentSpeed * dt

		main.AssemblyLinearVelocity = Vector3.zero
		main.AssemblyAngularVelocity = Vector3.zero

		main.CFrame = CFrame.lookAt(newPos, newPos + newForward)

		vehicle:SetAttribute("Current_speed", math.abs(data.CurrentSpeed))

		if cfg.Can_flip == true then
			local upDot = main.CFrame.UpVector:Dot(Vector3.yAxis)

			if upDot < 0.4 then
				data.FlippedTime += dt
			else
				data.FlippedTime = 0
			end

			if data.FlippedTime >= cfg.Flip_time then
				local currentPos = main.Position
				local look = main.CFrame.LookVector
				local flatLook = Vector3.new(look.X, 0, look.Z)

				if flatLook.Magnitude < 0.1 then
					flatLook = Vector3.zAxis
				else
					flatLook = flatLook.Unit
				end

				main.CFrame = CFrame.lookAt(
					currentPos + Vector3.new(0, 3, 0),
					currentPos + Vector3.new(0, 3, 0) + flatLook
				)

				data.CurrentSpeed = 0
				data.CurrentSteer = 0
				data.FlippedTime = 0
				data.LastPosition = main.Position

				print("[VehicleDriveController] Vehicle flipped back:", vehicle.Name)
			end
		end
	end
end)

return VehicleDriveController