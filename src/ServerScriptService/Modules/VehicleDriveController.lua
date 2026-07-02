local RunService = game:GetService("RunService")

local VehicleDriveController = {}

local activeVehicles = {}

local WORLD_UP = Vector3.yAxis

local DEFAULTS = {
	Speed = 40,
	Speed_reverse = 10,
	Acceleration = 10,
	Brake_force = 40,
	Steer_angle = 28,
	Steer_speed = 7,
	Obstacle_check_distance = 4,
	Max_fuel = 100,
	Fuel_per_stud = 0.01,
	Can_flip = true,
	Flip_time = 2,
	Drive_forward_axis = "-X",
	Steer_invert = true,
}

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
		Speed = tonumber(getAttr(vehicle, "Speed", DEFAULTS.Speed)) or DEFAULTS.Speed,
		Speed_reverse = tonumber(getAttr(vehicle, "Speed_reverse", DEFAULTS.Speed_reverse)) or DEFAULTS.Speed_reverse,

		Acceleration = tonumber(getAttr(vehicle, "Acceleration", DEFAULTS.Acceleration)) or DEFAULTS.Acceleration,
		Brake_force = tonumber(getAttr(vehicle, "Brake_force", DEFAULTS.Brake_force)) or DEFAULTS.Brake_force,

		Steer_angle = tonumber(getAttr(vehicle, "Steer_angle", DEFAULTS.Steer_angle)) or DEFAULTS.Steer_angle,
		Steer_speed = tonumber(getAttr(vehicle, "Steer_speed", DEFAULTS.Steer_speed)) or DEFAULTS.Steer_speed,
		Steer_invert = getAttr(vehicle, "Steer_invert", DEFAULTS.Steer_invert) == true,

		Obstacle_check_distance = tonumber(getAttr(vehicle, "Obstacle_check_distance", DEFAULTS.Obstacle_check_distance)) or DEFAULTS.Obstacle_check_distance,

		Max_fuel = tonumber(getAttr(vehicle, "Max_fuel", DEFAULTS.Max_fuel)) or DEFAULTS.Max_fuel,
		Fuel_per_stud = tonumber(getAttr(vehicle, "Fuel_per_stud", DEFAULTS.Fuel_per_stud)) or DEFAULTS.Fuel_per_stud,

		Can_flip = getAttr(vehicle, "Can_flip", DEFAULTS.Can_flip) == true,
		Flip_time = tonumber(getAttr(vehicle, "Flip_time", DEFAULTS.Flip_time)) or DEFAULTS.Flip_time,

		Drive_forward_axis = tostring(getAttr(vehicle, "Drive_forward_axis", DEFAULTS.Drive_forward_axis)),
	}
end

local function axisToLocalVector(axisName)
	if axisName == "X" then
		return Vector3.xAxis
	elseif axisName == "-X" then
		return -Vector3.xAxis
	elseif axisName == "Y" then
		return Vector3.yAxis
	elseif axisName == "-Y" then
		return -Vector3.yAxis
	elseif axisName == "Z" then
		return Vector3.zAxis
	elseif axisName == "-Z" then
		return -Vector3.zAxis
	end

	return -Vector3.xAxis
end

local function getForwardAttachment(vehicle)
	local attachment = vehicle:FindFirstChild("Forward", true)
	if attachment and attachment:IsA("Attachment") then
		return attachment
	end

	attachment = vehicle:FindFirstChild("ForwardAttachment", true)
	if attachment and attachment:IsA("Attachment") then
		return attachment
	end

	return nil
end

local function flattenVector(vector, fallback)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.01 then
		return fallback or Vector3.zAxis
	end
	return flat.Unit
end

local function getForward(vehicle, main, cfg)
	local forwardAttachment = getForwardAttachment(vehicle)

	if forwardAttachment then
		local dir = forwardAttachment.WorldPosition - main.Position
		if dir.Magnitude > 0.05 then
			return flattenVector(dir, main.CFrame.LookVector)
		end
	end

	local localAxis = axisToLocalVector(cfg.Drive_forward_axis)
	return flattenVector(main.CFrame:VectorToWorldSpace(localAxis), main.CFrame.LookVector)
end

local function getYawFromForward(forward)
	return math.atan2(-forward.X, -forward.Z)
end

local function getForwardFromYaw(yaw)
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

local function moveTowards(current, target, step)
	if current < target then
		return math.min(current + step, target)
	elseif current > target then
		return math.max(current - step, target)
	end
	return current
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

local function isObstacleAhead(vehicle, main, forward, distance)
	if distance <= 0 then
		return false
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { vehicle }

	local right = WORLD_UP:Cross(forward)
	if right.Magnitude < 0.01 then
		right = main.CFrame.RightVector
	else
		right = right.Unit
	end

	local halfWidth = math.max(1, math.min(main.Size.X, main.Size.Z) * 0.45)
	local rayHeight = math.max(0.5, main.Size.Y * 0.25)

	local origins = {
		main.Position + Vector3.new(0, rayHeight, 0),
		main.Position + right * halfWidth + Vector3.new(0, rayHeight, 0),
		main.Position - right * halfWidth + Vector3.new(0, rayHeight, 0),
	}

	for _, origin in ipairs(origins) do
		local result = workspace:Raycast(origin, forward * distance, params)
		if result and findBlockingObject(result.Instance) then
			return true
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

	currentFuel = tonumber(currentFuel) or 0

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

local function zeroPhysics(part)
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
end

local function prepareArcadeVehicle(vehicle)
	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") then
			zeroPhysics(item)
			item.Anchored = true
			item.Massless = true

			-- Аркадна машина рухається через PivotTo.
			-- Фізичні колізії Roblox тут вимкнені, а перешкоди ловимо Raycast'ами через BlocksVehicle.
			item.CanCollide = false
		end
	end
end

local function pivotVehicleByMain(vehicle, main, targetMainCFrame)
	local currentPivot = vehicle:GetPivot()
	local delta = targetMainCFrame * main.CFrame:Inverse()
	vehicle:PivotTo(delta * currentPivot)
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

	prepareArcadeVehicle(vehicle)

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

	print("[VehicleDriveController] Vehicle registered ARCADE ANCHORED:", vehicle.Name)
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

		if cfg.Steer_invert then
			steer = -steer
		end

		local targetSpeed = 0
		if throttle > 0 then
			targetSpeed = cfg.Speed
		elseif throttle < 0 then
			targetSpeed = -cfg.Speed_reverse
		end

		local speedStep = cfg.Acceleration * dt
		if throttle == 0 then
			speedStep = cfg.Brake_force * dt
		end

		data.CurrentSpeed = moveTowards(data.CurrentSpeed, targetSpeed, speedStep)
		data.CurrentSteer = moveTowards(data.CurrentSteer, steer, cfg.Steer_speed * dt)

		local forward = getForward(vehicle, main, cfg)
		local yaw = getYawFromForward(forward)

		if math.abs(data.CurrentSpeed) > 0.5 then
			local reverseMul = 1
			if data.CurrentSpeed < 0 then
				reverseMul = -1
			end

			local turnRate = math.rad(cfg.Steer_angle) * data.CurrentSteer * reverseMul
			yaw += turnRate * dt
		end

		local newForward = getForwardFromYaw(yaw)
		local moveForward = newForward
		if data.CurrentSpeed < 0 then
			moveForward = -newForward
		end

		if math.abs(data.CurrentSpeed) > 1 then
			if isObstacleAhead(vehicle, main, moveForward, cfg.Obstacle_check_distance) then
				data.CurrentSpeed = 0
			end
		end

		local currentPos = main.Position
		local newPos = currentPos + newForward * data.CurrentSpeed * dt
		local targetMainCFrame = CFrame.lookAt(newPos, newPos + newForward)

		pivotVehicleByMain(vehicle, main, targetMainCFrame)

		vehicle:SetAttribute("Current_speed", math.abs(data.CurrentSpeed))

		if cfg.Can_flip == true then
			local upDot = main.CFrame.UpVector:Dot(WORLD_UP)

			if upDot < 0.4 then
				data.FlippedTime += dt
			else
				data.FlippedTime = 0
			end

			if data.FlippedTime >= cfg.Flip_time then
				local pos = main.Position + Vector3.new(0, 3, 0)
				local fixedForward = flattenVector(main.CFrame.LookVector, Vector3.zAxis)
				local fixedCFrame = CFrame.lookAt(pos, pos + fixedForward)

				pivotVehicleByMain(vehicle, main, fixedCFrame)

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
