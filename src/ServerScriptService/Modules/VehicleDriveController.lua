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
		Speed = tonumber(getAttr(vehicle, "Speed", 40)) or 40,
		Speed_reverse = tonumber(getAttr(vehicle, "Speed_reverse", 10)) or 10,

		Acceleration = tonumber(getAttr(vehicle, "Acceleration", 10)) or 10,
		Brake_force = tonumber(getAttr(vehicle, "Brake_force", 40)) or 40,

		Steer_angle = tonumber(getAttr(vehicle, "Steer_angle", 28)) or 28,
		Steer_speed = tonumber(getAttr(vehicle, "Steer_speed", 7)) or 7,
		Steer_invert = getAttr(vehicle, "Steer_invert", true),

		Obstacle_check_distance = tonumber(getAttr(vehicle, "Obstacle_check_distance", 4)) or 4,

		Max_fuel = tonumber(getAttr(vehicle, "Max_fuel", 100)) or 100,
		Fuel_per_stud = tonumber(getAttr(vehicle, "Fuel_per_stud", 0.01)) or 0.01,
	}
end

local function moveTowards(current, target, step)
	if current < target then
		return math.min(current + step, target)
	elseif current > target then
		return math.max(current - step, target)
	end
	return current
end

local function getAxisForward(cframe, axisName)
	axisName = tostring(axisName or "-Z")

	if axisName == "Z" then
		return cframe.LookVector
	elseif axisName == "-Z" then
		return -cframe.LookVector
	elseif axisName == "X" then
		return cframe.RightVector
	elseif axisName == "-X" then
		return -cframe.RightVector
	end

	return -cframe.LookVector
end

local function flatUnit(vector, fallback)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.001 then
		return fallback or Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function yawFromForward(forward)
	forward = flatUnit(forward, Vector3.new(0, 0, -1))
	return math.atan2(-forward.X, -forward.Z)
end

local function forwardFromYaw(yaw)
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
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
	local halfWidth = math.max(main.Size.X, main.Size.Z) * 0.45

	local origins = {
		main.Position + Vector3.new(0, 0.8, 0),
		main.Position + right * halfWidth + Vector3.new(0, 0.8, 0),
		main.Position - right * halfWidth + Vector3.new(0, 0.8, 0),
	}

	for _, origin in ipairs(origins) do
		local result = workspace:Raycast(origin, forward * distance, params)
		if result and findBlockingObject(result.Instance) then
			return true
		end
	end

	return false
end

local function consumeFuel(vehicle, data, cfg, dt)
	local currentFuel = vehicle:GetAttribute("Current_fuel")

	if currentFuel == nil then
		currentFuel = cfg.Max_fuel
		vehicle:SetAttribute("Current_fuel", currentFuel)
	end

	if currentFuel <= 0 then
		data.CurrentSpeed = 0
		return false
	end

	if math.abs(data.CurrentSpeed) > 0.5 then
		local distance = math.abs(data.CurrentSpeed) * dt
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

local function makeVehicleArcadeSafe(vehicle)
	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = true
			item.Massless = true
			item.AssemblyLinearVelocity = Vector3.zero
			item.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function getModelPivotOffset(vehicle, main)
	return main.CFrame:ToObjectSpace(vehicle:GetPivot())
end

local function buildMainCFrame(position, yaw, axisName)
	local visualForward = forwardFromYaw(yaw)
	local mainCFrame

	axisName = tostring(axisName or "-Z")

	if axisName == "Z" then
		mainCFrame = CFrame.lookAt(position, position + visualForward)
	elseif axisName == "-Z" then
		mainCFrame = CFrame.lookAt(position, position - visualForward)
	elseif axisName == "X" then
		mainCFrame = CFrame.lookAt(position, position + visualForward) * CFrame.Angles(0, math.rad(90), 0)
	elseif axisName == "-X" then
		mainCFrame = CFrame.lookAt(position, position + visualForward) * CFrame.Angles(0, math.rad(-90), 0)
	else
		mainCFrame = CFrame.lookAt(position, position + visualForward)
	end

	return mainCFrame
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

	makeVehicleArcadeSafe(vehicle)

	local axisName = tostring(getAttr(vehicle, "Drive_forward_axis", "-Z"))
	local currentForward = getAxisForward(main.CFrame, axisName)
	local currentYaw = yawFromForward(currentForward)

	activeVehicles[vehicle] = {
		Main = main,
		Seat = seat,
		Owner = ownerPlayer,

		CurrentSpeed = 0,
		CurrentSteer = 0,

		Yaw = currentYaw,
		Position = main.Position,
		DriveForwardAxis = axisName,
		PivotOffset = getModelPivotOffset(vehicle, main),
	}

	vehicle:SetAttribute("Current_speed", 0)

	print("[VehicleDriveController] Vehicle registered:", vehicle.Name, "Axis:", axisName)
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
		local hasFuel = consumeFuel(vehicle, data, cfg, dt)

		local throttle = seat.Throttle
		local steer = seat.Steer

		if not hasFuel then
			throttle = 0
		end

		if cfg.Steer_invert == true then
			steer = -steer
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
		data.CurrentSteer = moveTowards(data.CurrentSteer, steer, cfg.Steer_speed * dt)

		local forward = forwardFromYaw(data.Yaw)
		local moveDirection = forward
		if data.CurrentSpeed < 0 then
			moveDirection = -forward
		end

		if math.abs(data.CurrentSpeed) > 1 then
			if isObstacleAhead(vehicle, main, moveDirection, cfg.Obstacle_check_distance) then
				data.CurrentSpeed = 0
			end
		end

		if math.abs(data.CurrentSpeed) > 0.5 then
			local reverseMultiplier = 1
			if data.CurrentSpeed < 0 then
				reverseMultiplier = -1
			end

			local turnRate = math.rad(cfg.Steer_angle) * data.CurrentSteer * reverseMultiplier
			data.Yaw += turnRate * dt
		end

		forward = forwardFromYaw(data.Yaw)
		data.Position += forward * data.CurrentSpeed * dt

		local mainCFrame = buildMainCFrame(data.Position, data.Yaw, data.DriveForwardAxis)
		local modelPivot = mainCFrame * data.PivotOffset

		vehicle:PivotTo(modelPivot)

		vehicle:SetAttribute("Current_speed", math.abs(data.CurrentSpeed))
	end
end)

return VehicleDriveController
