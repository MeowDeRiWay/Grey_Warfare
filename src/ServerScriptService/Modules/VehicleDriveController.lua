local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VehicleDamageManager = require(script.Parent.VehicleDamageManager)
VehicleDamageManager.Start()

local VehicleDriveController = {}

local activeVehicles = {}

local DEFAULT_RAY_START_HEIGHT = 4
local DEFAULT_RAY_LENGTH = 12
local DEFAULT_SUSPENSION_LERP = 8
local DEFAULT_MAX_TILT_DEGREES = 18
local DEFAULT_GROUND_PROBE_RADIUS = 0.35
local DEFAULT_SUSPENSION_UP_LERP = 28
local DEFAULT_GROUND_CLEARANCE = 0.18

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
		Collision_box_scale = tonumber(getAttr(vehicle, "Collision_box_scale", 0.96)) or 0.96,
		Collision_sweep_step = tonumber(getAttr(vehicle, "Collision_sweep_step", 0.75)) or 0.75,

		Fuel_max = tonumber(getAttr(vehicle, "Fuel_max", 100)) or 100,
		Fuel_per_stud = tonumber(getAttr(vehicle, "Fuel_per_stud", 0.01)) or 0.01,

		Suspension_enabled = getAttr(vehicle, "Suspension_enabled", true),
		Suspension_ray_start_height = tonumber(getAttr(vehicle, "Suspension_ray_start_height", DEFAULT_RAY_START_HEIGHT)) or DEFAULT_RAY_START_HEIGHT,
		Suspension_ray_length = tonumber(getAttr(vehicle, "Suspension_ray_length", DEFAULT_RAY_LENGTH)) or DEFAULT_RAY_LENGTH,
		Suspension_lerp = tonumber(getAttr(vehicle, "Suspension_lerp", DEFAULT_SUSPENSION_LERP)) or DEFAULT_SUSPENSION_LERP,
		Suspension_up_lerp = tonumber(getAttr(vehicle, "Suspension_up_lerp", DEFAULT_SUSPENSION_UP_LERP)) or DEFAULT_SUSPENSION_UP_LERP,
		Suspension_probe_radius = tonumber(getAttr(vehicle, "Suspension_probe_radius", DEFAULT_GROUND_PROBE_RADIUS)) or DEFAULT_GROUND_PROBE_RADIUS,
		Suspension_ground_clearance = tonumber(getAttr(vehicle, "Suspension_ground_clearance", DEFAULT_GROUND_CLEARANCE)) or DEFAULT_GROUND_CLEARANCE,
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

-- Forward declaration: collision sweep uses this before its implementation below.
local buildMainCFrame

local function findBlockingObject(hitPart)
	-- IMPORTANT: only the exact Part/MeshPart carrying BlocksVehicle=true blocks.
	-- We intentionally do NOT inherit the attribute from parent Models, because
	-- warehouses contain trigger/zone parts that must remain passable.
	if hitPart and hitPart:IsA("BasePart") and hitPart:GetAttribute("BlocksVehicle") == true then
		return hitPart
	end
	return nil
end

local function getActiveGroundVehicleFromPart(part, selfVehicle)
	if not part or not part:IsA("BasePart") then
		return nil
	end

	local folder = Workspace:FindFirstChild("ActiveVehicles")
	if not folder then
		return nil
	end

	local current = part
	while current and current.Parent ~= folder do
		current = current.Parent
	end

	if not current or current == selfVehicle or not current:IsA("Model") then
		return nil
	end

	local otherData = activeVehicles[current]
	if not otherData or otherData.Main ~= part then
		-- Vehicle-to-vehicle collision is Main vs Main only. Wheels, modules and
		-- decorative parts do not enlarge the collision body.
		return nil
	end

	return current
end

local function getBlockingObjectAtMainCFrame(vehicle, main, targetMainCFrame, cfg)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { vehicle }
	params.MaxParts = 100

	local scale = math.clamp(tonumber(cfg.Collision_box_scale) or 0.96, 0.1, 1)
	local boxSize = Vector3.new(
		math.max(0.05, main.Size.X * scale),
		math.max(0.05, main.Size.Y * scale),
		math.max(0.05, main.Size.Z * scale)
	)

	local parts = Workspace:GetPartBoundsInBox(targetMainCFrame, boxSize, params)
	for _, part in ipairs(parts) do
		-- Buildings: only the exact tagged Part/MeshPart blocks.
		local blocker = findBlockingObject(part)
		if blocker then
			return blocker, part, nil
		end

		-- Ground vehicles block one another even without BlocksVehicle.
		-- We deliberately use only the other vehicle's Main as its collision body.
		local otherVehicle = getActiveGroundVehicleFromPart(part, vehicle)
		if otherVehicle then
			return otherVehicle, part, otherVehicle
		end
	end

	return nil, nil, nil
end

local function sweepMainForBlockingObject(vehicle, main, fromPosition, toPosition, yaw, axisName, pitch, roll, cfg)
	local delta = toPosition - fromPosition
	local distance = delta.Magnitude

	if distance < 0.0001 then
		return nil, nil
	end

	local stepLength = math.max(0.1, tonumber(cfg.Collision_sweep_step) or 0.75)
	local steps = math.max(1, math.ceil(distance / stepLength))

	for step = 1, steps do
		local alpha = step / steps
		local testPosition = fromPosition:Lerp(toPosition, alpha)
		local testMainCFrame = buildMainCFrame(testPosition, yaw, axisName, pitch, roll)
		local blocker, hitPart, otherVehicle = getBlockingObjectAtMainCFrame(vehicle, main, testMainCFrame, cfg)
		if blocker then
			return blocker, hitPart, otherVehicle
		end
	end

	return nil, nil, nil
end

local function getGroundVehicleVelocity(data)
	if not data then
		return Vector3.zero
	end

	return forwardFromYaw(data.Yaw) * (tonumber(data.CurrentSpeed) or 0)
end

local function clearVehicleContactIfSeparated(data)
	local otherVehicle = data.LastVehicleCollision
	if not otherVehicle then
		return
	end

	local otherData = activeVehicles[otherVehicle]
	local origin = data.LastVehicleCollisionPosition
	local otherOrigin = data.LastOtherVehicleCollisionPosition

	if not otherData or not otherVehicle.Parent then
		data.LastVehicleCollision = nil
		data.LastVehicleCollisionPosition = nil
		data.LastOtherVehicleCollisionPosition = nil
		return
	end

	-- Keep one impact as one impact while the vehicles remain at the crash point.
	-- Re-arm after either vehicle has moved at least 1.5 studs away.
	if (origin and (data.Position - origin).Magnitude > 1.5)
		or (otherOrigin and (otherData.Position - otherOrigin).Magnitude > 1.5)
	then
		data.LastVehicleCollision = nil
		data.LastVehicleCollisionPosition = nil
		data.LastOtherVehicleCollisionPosition = nil
	end
end

local function applyVehicleToVehicleImpact(vehicle, data, otherVehicle)
	local otherData = activeVehicles[otherVehicle]
	if not otherData then
		return
	end

	-- Both cars use the same relative closing speed. Example: 30 studs/s head-on
	-- against 30 studs/s = 60 studs/s impact for both vehicles.
	local relativeSpeed = (getGroundVehicleVelocity(data) - getGroundVehicleVelocity(otherData)).Magnitude

	-- One contact must not drain HP every Heartbeat. Mark both ends of the pair.
	if data.LastVehicleCollision ~= otherVehicle and otherData.LastVehicleCollision ~= vehicle then
		VehicleDamageManager.ApplyCollisionDamage(vehicle, relativeSpeed)
		VehicleDamageManager.ApplyCollisionDamage(otherVehicle, relativeSpeed)

		print(
			"[VehicleDriveController] VEHICLE COLLISION:",
			vehicle.Name,
			"<->",
			otherVehicle.Name,
			"RelativeSpeed:",
			relativeSpeed
		)
	end

	data.LastVehicleCollision = otherVehicle
	data.LastVehicleCollisionPosition = data.Position
	data.LastOtherVehicleCollisionPosition = otherData.Position

	otherData.LastVehicleCollision = vehicle
	otherData.LastVehicleCollisionPosition = otherData.Position
	otherData.LastOtherVehicleCollisionPosition = data.Position

	-- Arcade vehicles stop dead on impact.
	data.CurrentSpeed = 0
	otherData.CurrentSpeed = 0
end

local function consumeFuel(vehicle, data, cfg, dt)
	local currentFuel = vehicle:GetAttribute("Fuel_cur")

	if currentFuel == nil then
		currentFuel = cfg.Fuel_max
		vehicle:SetAttribute("Fuel_cur", currentFuel)
	end

	if currentFuel <= 0 then
		data.CurrentSpeed = 0
		return false
	end

	if math.abs(data.CurrentSpeed) > 0.5 then
		local distance = math.abs(data.CurrentSpeed) * dt
		local used = distance * cfg.Fuel_per_stud
		local newFuel = math.max(0, currentFuel - used)
		vehicle:SetAttribute("Fuel_cur", newFuel)

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

-- IMPORTANT: move the whole vehicle by the delta from the CURRENT Main CFrame.
-- Do not cache Model pivot offset: models with imported parts / unusual pivots can
-- visually "explode" when pitch/roll are applied around a stale or remote pivot.
local function pivotVehicleByMain(vehicle, main, targetMainCFrame)
	local currentPivot = vehicle:GetPivot()
	local delta = targetMainCFrame * main.CFrame:Inverse()
	vehicle:PivotTo(delta * currentPivot)
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

buildMainCFrame = function(position, yaw, axisName, pitch, roll)
	return visualToMainCFrame(buildVisualCFrame(position, yaw, pitch, roll), axisName)
end

local function looksLikeWheel(part)
	if not part:IsA("BasePart") then
		return false
	end

	if part:GetAttribute("Wheel") == true then
		return true
	end

	local name = string.lower(part.Name)
	return string.find(name, "wheel", 1, true) ~= nil
		or string.find(name, "tire", 1, true) ~= nil
		or string.find(name, "tyre", 1, true) ~= nil
end

local function collectWheels(vehicle, main)
	local candidates = {}

	for _, item in ipairs(vehicle:GetDescendants()) do
		if looksLikeWheel(item) then
			local localPos = main.CFrame:PointToObjectSpace(item.Position)
			local smallestAxis = math.min(item.Size.X, item.Size.Y, item.Size.Z)
			local autoProbeRadius = math.clamp(smallestAxis * 0.30, 0.15, 0.65)

			table.insert(candidates, {
				Part = item,
				LocalPosition = localPos,
				ExplicitSide = tostring(item:GetAttribute("WheelSide") or ""),
				ExplicitIndex = tonumber(item:GetAttribute("WheelIndex")),
				ProbeRadius = autoProbeRadius,
			})
		end
	end

	if #candidates == 0 then
		return {}
	end

	local axisName = tostring(getAttr(vehicle, "Drive_forward_axis", "-Z"))
	local forwardLocal
	if axisName == "X" then
		forwardLocal = Vector3.xAxis
	elseif axisName == "-X" then
		forwardLocal = -Vector3.xAxis
	elseif axisName == "Z" then
		forwardLocal = Vector3.zAxis
	else
		forwardLocal = -Vector3.zAxis
	end

	local rightLocal = forwardLocal:Cross(Vector3.yAxis)
	-- Right vector must match buildVisualCFrame/LookAt orientation; previous cross order inverted L/R.
	if rightLocal.Magnitude < 0.01 then
		rightLocal = Vector3.xAxis
	else
		rightLocal = rightLocal.Unit
	end

	local forwardDots = {}
	for _, wheel in ipairs(candidates) do
		wheel.ForwardDot = wheel.LocalPosition:Dot(forwardLocal)
		wheel.RightDot = wheel.LocalPosition:Dot(rightLocal)
		table.insert(forwardDots, wheel.ForwardDot)
	end

	table.sort(forwardDots)
	local splitForward = 0
	if #forwardDots >= 2 then
		local mid = math.floor(#forwardDots / 2)
		if #forwardDots % 2 == 0 then
			splitForward = (forwardDots[mid] + forwardDots[mid + 1]) * 0.5
		else
			splitForward = forwardDots[mid + 1]
		end
	end

	local wheels = {}
	for _, wheel in ipairs(candidates) do
		local side = wheel.ExplicitSide
		if side ~= "L" and side ~= "R" then
			side = wheel.RightDot < 0 and "L" or "R"
		end

		local index = wheel.ExplicitIndex
		if index == nil then
			-- 0 = передня вісь, 1 = задня.
			index = wheel.ForwardDot >= splitForward and 0 or 1
		end

		table.insert(wheels, {
			Part = wheel.Part,
			Side = side,
			Index = index,
			LocalPosition = wheel.LocalPosition,
			ProbeRadius = wheel.ProbeRadius,
		})
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

local function makeGroundRaycastParams(vehicle)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { vehicle }
	params.IgnoreWater = false
	return params
end

local function rayGround(params, samplePosition, cfg)
	local startHeight = math.max(0.5, cfg.Suspension_ray_start_height)
	local rayLength = math.max(startHeight + 1, cfg.Suspension_ray_length)
	local origin = samplePosition + Vector3.yAxis * startHeight
	local direction = Vector3.new(0, -rayLength, 0)
	return workspace:Raycast(origin, direction, params)
end

-- One thin ray can fall exactly into a seam between imported road meshes.
-- Probe a small footprint around each wheel and use the highest real surface hit.
-- This still reads the visible Part/MeshPart itself; there are no invisible support parts.
local function getWheelGroundHeight(vehicle, wheel, baseMainCFrame, cfg)
	local worldPosition = baseMainCFrame:PointToWorldSpace(wheel.LocalPosition)

	-- Use horizontal axes from the supplied vehicle frame so the footprint follows the car.
	local right = flatUnit(baseMainCFrame.RightVector, Vector3.xAxis)
	local forward = flatUnit(baseMainCFrame.LookVector, Vector3.new(0, 0, -1))

	local radius = tonumber(cfg.Suspension_probe_radius) or DEFAULT_GROUND_PROBE_RADIUS
	if wheel.ProbeRadius then
		radius = math.max(radius, wheel.ProbeRadius)
	end
	radius = math.clamp(radius, 0, 0.75)

	local samples = {
		worldPosition,
		worldPosition + right * radius,
		worldPosition - right * radius,
		worldPosition + forward * radius,
		worldPosition - forward * radius,
	}

	local params = makeGroundRaycastParams(vehicle)
	local highestY = nil
	for _, samplePosition in ipairs(samples) do
		local result = rayGround(params, samplePosition, cfg)
		if result then
			local y = result.Position.Y
			if highestY == nil or y > highestY then
				highestY = y
			end
		end
	end

	return highestY
end

local function calculateInitialRideHeight(vehicle, main, wheels)
	if #wheels == 0 then
		return 0
	end

	local cfg = getConfig(vehicle)
	local heights = {}

	for _, wheel in ipairs(wheels) do
		local groundY = getWheelGroundHeight(vehicle, wheel, main.CFrame, cfg)
		if groundY then
			table.insert(heights, groundY)
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
		local groundY = getWheelGroundHeight(vehicle, wheel, baseMainCFrame, cfg)

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

	local targetY = averageGroundY + data.RideHeight + cfg.Suspension_ground_clearance

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

	local downAlpha = math.clamp(cfg.Suspension_lerp * dt, 0, 1)
	local upAlpha = math.clamp(cfg.Suspension_up_lerp * dt, 0, 1)
	local poseAlpha = targetY > data.Position.Y and upAlpha or downAlpha

	data.Pitch = lerpNumber(data.Pitch, targetPitch, poseAlpha)
	data.Roll = lerpNumber(data.Roll, targetRoll, poseAlpha)

	-- Rising onto a road/curb must react much faster than falling off it.
	-- Otherwise the arcade PivotTo movement can visually push wheels through the mesh
	-- for several frames before the old lerp catches up.
	local smoothY = lerpNumber(data.Position.Y, targetY, poseAlpha)
	if targetY > data.Position.Y and math.abs(targetY - smoothY) < 0.03 then
		smoothY = targetY
	end

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
	VehicleDamageManager.RegisterVehicle(vehicle)

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

		clearVehicleContactIfSeparated(data)

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

		if math.abs(data.CurrentSpeed) > 0.5 then
			local reverseMultiplier = 1
			if data.CurrentSpeed < 0 then
				reverseMultiplier = -1
			end

			local turnRate = math.rad(cfg.Steer_angle) * data.CurrentSteer * reverseMultiplier
			data.Yaw += turnRate * dt
		end

		forward = forwardFromYaw(data.Yaw)

		local impactSpeed = math.abs(data.CurrentSpeed)
		local proposedPosition = data.Position + forward * data.CurrentSpeed * dt
		local blocker = nil
		local otherVehicle = nil

		if impactSpeed > 0.01 then
			blocker, _, otherVehicle = sweepMainForBlockingObject(
				vehicle,
				main,
				data.Position,
				proposedPosition,
				data.Yaw,
				data.DriveForwardAxis,
				data.Pitch,
				data.Roll,
				cfg
			)
		end

		if blocker then
			if otherVehicle then
				-- Main vs Main: stop both and damage both by relative speed.
				applyVehicleToVehicleImpact(vehicle, data, otherVehicle)
				data.LastBlockingObject = nil
			else
				-- Main vs exact BlocksVehicle Part: old building collision behaviour.
				if data.LastBlockingObject ~= blocker then
					VehicleDamageManager.ApplyCollisionDamage(vehicle, impactSpeed)
				end

				data.LastBlockingObject = blocker
				data.CurrentSpeed = 0
			end
		else
			data.LastBlockingObject = nil
			data.Position = proposedPosition
		end

		local newY, pitch, roll = updateSuspension(vehicle, data, cfg, dt)
		data.Position = Vector3.new(data.Position.X, newY, data.Position.Z)

		local mainCFrame = buildMainCFrame(data.Position, data.Yaw, data.DriveForwardAxis, pitch, roll)

		-- Same stable Main-relative movement used by the old arcade anchored fix.
		pivotVehicleByMain(vehicle, main, mainCFrame)

		vehicle:SetAttribute("Current_speed", math.abs(data.CurrentSpeed))
	end
end)

return VehicleDriveController
