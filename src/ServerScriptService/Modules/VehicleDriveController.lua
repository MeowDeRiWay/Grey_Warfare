local RunService = game:GetService("RunService")

local VehicleDriveController = {}

local activeVehicles = {}

local DEFAULT_RAY_START_HEIGHT = 4
local DEFAULT_RAY_LENGTH = 12
local DEFAULT_SUSPENSION_LERP = 8
local DEFAULT_MAX_TILT_DEGREES = 18

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

		Suspension_enabled = getAttr(vehicle, "Suspension_enabled", true),
		Suspension_ray_start_height = tonumber(getAttr(vehicle, "Suspension_ray_start_height", DEFAULT_RAY_START_HEIGHT)) or DEFAULT_RAY_START_HEIGHT,
		Suspension_ray_length = tonumber(getAttr(vehicle, "Suspension_ray_length", DEFAULT_RAY_LENGTH)) or DEFAULT_RAY_LENGTH,
		Suspension_lerp = tonumber(getAttr(vehicle, "Suspension_lerp", DEFAULT_SUSPENSION_LERP)) or DEFAULT_SUSPENSION_LERP,
		Suspension_max_tilt = tonumber(getAttr(vehicle, "Suspension_max_tilt", DEFAULT_MAX_TILT_DEGREES)) or DEFAULT_MAX_TILT_DEGREES,
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

local function buildVisualCFrame(position, yaw, pitch, roll)
	local visualForward = forwardFromYaw(yaw)
	return CFrame.lookAt(position, position + visualForward) * CFrame.Angles(pitch or 0, 0, roll or 0)
end

local function visualToMainCFrame(visualCFrame, axisName)
	axisName = tostring(axisName or "-Z")

	if axisName == "Z" then
		return visualCFrame
	elseif axisName == "-Z" then
		return visualCFrame * CFrame.Angles(0, math.rad(180), 0)
	elseif axisName == "X" then
		return visualCFrame * CFrame.Angles(0, math.rad(90), 0)
	elseif axisName == "-X" then
		return visualCFrame * CFrame.Angles(0, math.rad(-90), 0)
	end

	return visualCFrame
end

local function buildMainCFrame(position, yaw, axisName, pitch, roll)
	return visualToMainCFrame(buildVisualCFrame(position, yaw, pitch, roll), axisName)
end

local function collectWheels(vehicle, main)
	local wheels = {}

	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") and item:GetAttribute("Wheel") == true then
			local side = tostring(item:GetAttribute("WheelSide") or "")
			local index = tonumber(item:GetAttribute("WheelIndex")) or 0

			table.insert(wheels, {
				Part = item,
				Side = side,
				Index = index,
				LocalPosition = main.CFrame:PointToObjectSpace(item.Position),
			})
		end
	end

	return wheels
end

local function average(values)
	if #values == 0 then
		return nil
	end

	local total = 0
	for _, value in ipairs(values) do
		total += value
	end
	return total / #values
end

local function clampAngle(angle, maxDegrees)
	local maxRadians = math.rad(math.max(0, maxDegrees or DEFAULT_MAX_TILT_DEGREES))
	return math.clamp(angle, -maxRadians, maxRadians)
end

local function lerpNumber(a, b, alpha)
	return a + (b - a) * alpha
end

local function getWheelGroundHeight(vehicle, worldPosition, cfg)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { vehicle }

	local origin = worldPosition + Vector3.yAxis * cfg.Suspension_ray_start_height
	local direction = Vector3.new(0, -cfg.Suspension_ray_length, 0)
	local result = workspace:Raycast(origin, direction, params)

	if result then
		return result.Position.Y
	end

	return nil
end

local function calculateInitialRideHeight(vehicle, main, wheels)
	if #wheels == 0 then
		return 0
	end

	local heights = {}
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { vehicle }

	for _, wheel in ipairs(wheels) do
		local worldPosition = main.CFrame:PointToWorldSpace(wheel.LocalPosition)
		local result = workspace:Raycast(worldPosition + Vector3.yAxis * DEFAULT_RAY_START_HEIGHT, Vector3.new(0, -DEFAULT_RAY_LENGTH, 0), params)
		if result then
			table.insert(heights, result.Position.Y)
		end
	end

	local groundY = average(heights)
	if not groundY then
		return 0
	end

	return main.Position.Y - groundY
end

local function updateSuspension(vehicle, data, cfg, dt)
	if cfg.Suspension_enabled ~= true or #data.Wheels < 3 then
		data.Pitch = moveTowards(data.Pitch, 0, dt * 2)
		data.Roll = moveTowards(data.Roll, 0, dt * 2)
		return data.Position.Y, data.Pitch, data.Roll
	end

	local baseMainCFrame = buildMainCFrame(data.Position, data.Yaw, data.DriveForwardAxis, 0, 0)

	local allHeights = {}
	local leftHeights = {}
	local rightHeights = {}
	local frontHeights = {}
	local backHeights = {}

	local minIndex = math.huge
	local maxIndex = -math.huge

	for _, wheel in ipairs(data.Wheels) do
		if wheel.Index < minIndex then
			minIndex = wheel.Index
		end
		if wheel.Index > maxIndex then
			maxIndex = wheel.Index
		end
	end

	local leftPositions = {}
	local rightPositions = {}
	local frontPositions = {}
	local backPositions = {}

	for _, wheel in ipairs(data.Wheels) do
		local worldPosition = baseMainCFrame:PointToWorldSpace(wheel.LocalPosition)
		local groundY = getWheelGroundHeight(vehicle, worldPosition, cfg)

		if groundY then
			table.insert(allHeights, groundY)

			if wheel.Side == "L" then
				table.insert(leftHeights, groundY)
				table.insert(leftPositions, worldPosition)
			elseif wheel.Side == "R" then
				table.insert(rightHeights, groundY)
				table.insert(rightPositions, worldPosition)
			end

			if wheel.Index == minIndex then
				table.insert(frontHeights, groundY)
				table.insert(frontPositions, worldPosition)
			elseif wheel.Index == maxIndex then
				table.insert(backHeights, groundY)
				table.insert(backPositions, worldPosition)
			end
		end
	end

	local averageGroundY = average(allHeights)
	if not averageGroundY then
		data.Pitch = moveTowards(data.Pitch, 0, dt * 2)
		data.Roll = moveTowards(data.Roll, 0, dt * 2)
		return data.Position.Y, data.Pitch, data.Roll
	end

	local targetY = averageGroundY + data.RideHeight

	local leftY = average(leftHeights)
	local rightY = average(rightHeights)
	local frontY = average(frontHeights)
	local backY = average(backHeights)

	local width = data.WheelTrackWidth
	local length = data.WheelBaseLength

	local targetRoll = 0
	if leftY and rightY and width > 0.1 then
		-- Праве колесо вище => кузов нахиляється вліво/вправо по аркадній площині.
		targetRoll = math.atan((rightY - leftY) / width)
	end

	local targetPitch = 0
	if frontY and backY and length > 0.1 then
		-- Перед вище => морда піднімається.
		targetPitch = math.atan((frontY - backY) / length)
	end

	targetPitch = clampAngle(targetPitch, cfg.Suspension_max_tilt)
	targetRoll = clampAngle(targetRoll, cfg.Suspension_max_tilt)

	local alpha = math.clamp(cfg.Suspension_lerp * dt, 0, 1)
	data.Pitch = lerpNumber(data.Pitch, targetPitch, alpha)
	data.Roll = lerpNumber(data.Roll, targetRoll, alpha)

	local smoothY = lerpNumber(data.Position.Y, targetY, alpha)
	return smoothY, data.Pitch, data.Roll
end

local function calculateWheelDimensions(wheels, mainCFrame, yaw, axisName)
	if #wheels < 2 then
		return 1, 1
	end

	local visualCFrame = buildVisualCFrame(mainCFrame.Position, yaw, 0, 0)
	local visualRight = visualCFrame.RightVector
	local visualForward = visualCFrame.LookVector

	local minRight = math.huge
	local maxRight = -math.huge
	local minForward = math.huge
	local maxForward = -math.huge

	for _, wheel in ipairs(wheels) do
		local worldPosition = mainCFrame:PointToWorldSpace(wheel.LocalPosition)
		local relative = worldPosition - mainCFrame.Position

		local rightDot = relative:Dot(visualRight)
		local forwardDot = relative:Dot(visualForward)

		minRight = math.min(minRight, rightDot)
		maxRight = math.max(maxRight, rightDot)
		minForward = math.min(minForward, forwardDot)
		maxForward = math.max(maxForward, forwardDot)
	end

	local width = math.max(1, maxRight - minRight)
	local length = math.max(1, maxForward - minForward)
	return width, length
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
	local wheels = collectWheels(vehicle, main)
	local rideHeight = tonumber(vehicle:GetAttribute("Suspension_body_height")) or calculateInitialRideHeight(vehicle, main, wheels)
	local width, length = calculateWheelDimensions(wheels, main.CFrame, currentYaw, axisName)

	activeVehicles[vehicle] = {
		Main = main,
		Seat = seat,
		Owner = ownerPlayer,

		CurrentSpeed = 0,
		CurrentSteer = 0,

		Yaw = currentYaw,
		Pitch = 0,
		Roll = 0,
		Position = main.Position,
		DriveForwardAxis = axisName,
		PivotOffset = getModelPivotOffset(vehicle, main),

		Wheels = wheels,
		RideHeight = rideHeight,
		WheelTrackWidth = width,
		WheelBaseLength = length,
	}

	vehicle:SetAttribute("Current_speed", 0)

	print(
		"[VehicleDriveController] Vehicle registered:",
		vehicle.Name,
		"Axis:",
		axisName,
		"Wheels:",
		#wheels,
		"RideHeight:",
		rideHeight
	)
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

		local newY, pitch, roll = updateSuspension(vehicle, data, cfg, dt)
		data.Position = Vector3.new(data.Position.X, newY, data.Position.Z)

		local mainCFrame = buildMainCFrame(data.Position, data.Yaw, data.DriveForwardAxis, pitch, roll)
		local modelPivot = mainCFrame * data.PivotOffset

		vehicle:PivotTo(modelPivot)

		vehicle:SetAttribute("Current_speed", math.abs(data.CurrentSpeed))
	end
end)

return VehicleDriveController
