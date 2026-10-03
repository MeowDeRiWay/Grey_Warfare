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
local DEFAULT_OBSTACLE_BOUNCE_FACTOR = 0.25

local function getAttr(vehicle, name, default)
	local value = vehicle:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

local function getMain(vehicle)
	local main = vehicle:FindFirstChild("Main")
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
		Suspension_ground_clearance = tonumber(getAttr(vehicle, "Ground_clearance", getAttr(vehicle, "Suspension_ground_clearance", DEFAULT_GROUND_CLEARANCE))) or DEFAULT_GROUND_CLEARANCE,
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
	axisName = tostring(axisName or "Z")

	if axisName == "Z" then
		return -cframe.LookVector
	elseif axisName == "-Z" then
		return cframe.LookVector
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
		-- Vehicle-to-vehicle collision is Main vs Main only. Modules and
		-- decorative parts do not enlarge the collision body.
		return nil
	end

	return current
end

local function getBlockingObjectAtMainCFrame(vehicle, main, targetMainCFrame, cfg)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { vehicle }
	params.MaxParts = 0

	local scale = math.clamp(tonumber(cfg.Collision_box_scale) or 0.96, 0.1, 1)
	local boxSize = Vector3.new(
		math.max(0.05, main.Size.X * scale),
		math.max(0.05, main.Size.Y * scale),
		math.max(0.05, main.Size.Z * scale)
	)

	local parts = Workspace:GetPartBoundsInBox(targetMainCFrame, boxSize, params)
	for _, part in ipairs(parts) do
		-- Main-vs-Main vehicle collision is kept. World geometry is no longer
		-- controlled by BlocksVehicle; body probes decide whether terrain/parts
		-- are climbable.
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
			item.CanTouch = not (item:IsA("Seat") or item:IsA("VehicleSeat"))
			item.Massless = true
			item.AssemblyLinearVelocity = Vector3.zero
			item.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

-- The anchored chassis has one immutable layout relative to Main.
-- Keep mounted modules outside this snapshot: their motors must remain movable.
local function captureChassisLayout(vehicle, main)
 local layout = {}
 local mounted = vehicle:FindFirstChild("MountedModules")
 for _, part in ipairs(vehicle:GetDescendants()) do
  if part:IsA("BasePart") and not (mounted and part:IsDescendantOf(mounted)) then
   layout[part] = main.CFrame:ToObjectSpace(part.CFrame)
  end
 end
 -- Physical chassis welds are redundant for anchored scripted parts. Remove only
 -- constraints whose two endpoints both belong to this fixed chassis.
 for _, joint in ipairs(vehicle:GetDescendants()) do
  if joint:IsA("WeldConstraint") and layout[joint.Part0] and layout[joint.Part1] then
   joint:Destroy()
  end
 end
 return layout
end

local function pivotVehicleByMain(vehicle, main, targetMainCFrame, layout)
 local delta = targetMainCFrame * main.CFrame:Inverse()
 local mounted = vehicle:FindFirstChild("MountedModules")
 if mounted then
  -- Snapshot before changing any chassis part: attached assemblies may respond
  -- to socket transforms, and must not receive the chassis delta twice.
  local targets = {}
  for _, module in ipairs(mounted:GetChildren()) do
   if module:IsA("Model") then
    targets[module] = delta * module:GetPivot()
   end
  end
  for part, offset in pairs(layout) do
   if part.Parent and part:IsDescendantOf(vehicle) then
    part.CFrame = targetMainCFrame * offset
   end
  end
  for module, target in pairs(targets) do
   if module.Parent then module:PivotTo(target) end
  end
 else
  for part, offset in pairs(layout) do
   if part.Parent and part:IsDescendantOf(vehicle) then
    part.CFrame = targetMainCFrame * offset
   end
  end
 end
end

local function buildVisualCFrame(position, yaw, pitch, roll)
	local visualForward = forwardFromYaw(yaw)
	return CFrame.lookAt(position, position + visualForward) * CFrame.Angles(pitch or 0, 0, roll or 0)
end

local function visualToMainCFrame(visualCFrame, axisName)
	axisName = tostring(axisName or "Z")

	if axisName == "Z" then
		return visualCFrame * CFrame.Angles(0, math.rad(180), 0)
	elseif axisName == "-Z" then
		return visualCFrame
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

-- Four numerical support points derived from Main; no wheel Instances required.
local function collectGroundProbes(vehicle, main)
 local axis = tostring(getAttr(vehicle, "Drive_forward_axis", "Z"))
 local yaw = yawFromForward(getAxisForward(main.CFrame, axis))
 local frame = buildMainCFrame(Vector3.zero, yaw, axis, 0, 0)
 local visual = buildVisualCFrame(Vector3.zero, yaw, 0, 0)
 local width = (axis == "X" or axis == "-X") and main.Size.Z or main.Size.X
 local length = (axis == "X" or axis == "-X") and main.Size.X or main.Size.Z
 local probes = {}
 for _, side in ipairs({-1, 1}) do
  for _, front in ipairs({-1, 1}) do
   local worldOffset = visual.RightVector * side * width * 0.45
    + visual.LookVector * front * length * 0.45
   table.insert(probes, {
    LocalPosition = frame:VectorToObjectSpace(worldOffset),
    Side = side < 0 and "L" or "R", Index = front > 0 and 0 or 1,
   })
  end
 end
 return probes, width * 0.9, length * 0.9
end

local function raycastVisibleObstacle(origin, direction, distance, vehicle)
	-- Fully transparent helper/trigger parts must not stop a vehicle.
	-- Recast after each transparent hit so a real wall behind an invisible zone
	-- is still detected.
	local ignored = { vehicle }
	local remaining = distance
	local currentOrigin = origin

	for _ = 1, 32 do
		if remaining <= 0.001 then
			return nil
		end

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignored
		params.IgnoreWater = true

		local result = Workspace:Raycast(currentOrigin, direction * remaining, params)
		if not result then
			return nil
		end

		local hit = result.Instance
		if hit and hit:IsA("BasePart") and (hit.Transparency >= 1 or hit.CanCollide == false) then
			table.insert(ignored, hit)

			local travelled = (result.Position - currentOrigin).Magnitude
			remaining -= travelled + 0.01
			currentOrigin = result.Position + direction * 0.01
		else
			return result
		end
	end

	return nil
end

local function getTallBodyObstacle(vehicle, data, cfg, movementDirection, travelDistance)
 if movementDirection.Magnitude < 0.001 then return nil end
 local frame = buildMainCFrame(data.Position, data.Yaw, data.DriveForwardAxis, data.Pitch, data.Roll)
 local direction = movementDirection.Unit
 local stepHeight = math.max(0.01, tonumber(vehicle:GetAttribute("Ground_step_height")) or math.min(0.35, data.Main.Size.Y * 0.25))
 -- Sweep a small grid across the body, including its centre and upper edge.
 -- Distance always covers the whole frame, including slow server frames.
 local offsets = {}
 local localDirection = frame:VectorToObjectSpace(direction)
 local alongX = math.abs(localDirection.X) > math.abs(localDirection.Z)
 local sign = (alongX and localDirection.X or localDirection.Z) >= 0 and 1 or -1
 for _, side in ipairs({-0.48, -0.24, 0, 0.24, 0.48}) do
  for _, y in ipairs({-data.Main.Size.Y / 2 + stepHeight, 0, data.Main.Size.Y * 0.45}) do
   table.insert(offsets, alongX
    and Vector3.new(sign * data.Main.Size.X * 0.48, y, side * data.Main.Size.Z)
    or Vector3.new(side * data.Main.Size.X, y, sign * data.Main.Size.Z * 0.48))
  end
 end
 for _, offset in ipairs(offsets) do
  local origin = frame:PointToWorldSpace(offset)
  local result = raycastVisibleObstacle(origin, direction, travelDistance + 0.05, vehicle)
  if result then
   -- Sloping terrain is checked from support normals below. Near-vertical faces block.
   if result.Normal.Y < math.cos(math.rad(math.clamp(tonumber(vehicle:GetAttribute("Ground_slope_limit")) or 45, 0, 89))) or (result.Instance:IsA("BasePart")
    and result.Instance:GetAttribute("BlocksVehicle") == true) then
    return result.Instance
   end
  end
 end
 return nil
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

local function isIgnoredVehicleSurface(part)
	if not part or not part:IsA("BasePart") then
		return false
	end

	-- Helper/trigger geometry is not terrain for the arcade vehicle physics.
	return part.Transparency >= 1 or part.CanCollide == false
end

local function rayGround(vehicle, samplePosition, cfg)
	local startHeight = math.max(0.5, cfg.Suspension_ray_start_height)
	local rayLength = math.max(startHeight + 1, cfg.Suspension_ray_length)
	local direction = Vector3.new(0, -1, 0)
	local currentOrigin = samplePosition + Vector3.yAxis * startHeight
	local remaining = rayLength
	local ignored = { vehicle }

	-- Continue through invisible/non-collidable parts so a real road below them
	-- can still be found by the suspension.
	for _ = 1, 32 do
		if remaining <= 0.001 then
			return nil
		end

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignored
		params.IgnoreWater = false

		local result = workspace:Raycast(currentOrigin, direction * remaining, params)
		if not result then
			return nil
		end

		local hit = result.Instance
		if isIgnoredVehicleSurface(hit) then
			table.insert(ignored, hit)

			local travelled = (result.Position - currentOrigin).Magnitude
			remaining -= travelled + 0.01
			currentOrigin = result.Position + direction * 0.01
		else
			return result
		end
	end

	return nil
end

local function updateGroundPose(vehicle, data, cfg, dt)
 local frame = buildMainCFrame(data.Position, data.Yaw, data.DriveForwardAxis, 0, 0)
 local all, left, right, front, back = {}, {}, {}, {}, {}
 local samples = {}
 local steep = false
 local slopeLimit = math.cos(math.rad(math.clamp(tonumber(vehicle:GetAttribute("Ground_slope_limit")) or 45, 0, 89)))
 for _, probe in ipairs(data.GroundProbes) do
  local pos = frame:PointToWorldSpace(probe.LocalPosition)
  local hit = rayGround(vehicle, pos, cfg)
  if hit then
   if hit.Normal.Y < slopeLimit then steep = true end
   local h = hit.Position.Y
   table.insert(samples, {Height = h, Offset = probe.LocalPosition})
   table.insert(all, h)
   table.insert(probe.Side == "L" and left or right, h)
   table.insert(probe.Index == 0 and front or back, h)
  end
 end
 local centerHit = rayGround(vehicle, data.Position, cfg)
 if centerHit then
  table.insert(all, centerHit.Position.Y)
  table.insert(samples, {Height = centerHit.Position.Y, Offset = Vector3.zero})
  if centerHit.Normal.Y < slopeLimit then steep = true end
 end
 if steep then return data.Position.Y, data.Pitch, data.Roll, true end
 local ground = average(all)
 if not ground then
  data.FallSpeed = (data.FallSpeed or 0) + 9.8 * dt
  return data.Position.Y - data.FallSpeed * dt, data.Pitch, data.Roll, false
 end
 data.FallSpeed = 0
 local targetPitch, targetRoll = 0, 0
 local l, r, f, b = average(left), average(right), average(front), average(back)
 if f and b then targetPitch = math.atan((f - b) / math.max(0.01, data.GroundLength)) end
 if l and r then targetRoll = math.atan((r - l) / math.max(0.01, data.GroundWidth)) end
 targetPitch = clampAngle(targetPitch, cfg.Suspension_max_tilt)
 targetRoll = clampAngle(targetRoll, cfg.Suspension_max_tilt)
 if cfg.Suspension_enabled == false then targetPitch, targetRoll = 0, 0 end
 local alpha = 1 - math.exp(-math.max(0, cfg.Suspension_lerp) * dt)
 data.Pitch = lerpNumber(data.Pitch, targetPitch, alpha)
 data.Roll = lerpNumber(data.Roll, targetRoll, alpha)
 -- Fit the underside to the support plane; do not add the highest terrain
 -- height and the full tilt extent together (that makes slopes look like hovering).
 local tilted = buildMainCFrame(Vector3.zero, data.Yaw, data.DriveForwardAxis, data.Pitch, data.Roll)
 local targetY = -math.huge
 for _, sample in ipairs(samples) do
  local bottomOffset = sample.Offset - Vector3.yAxis * data.RideHeight
  local requiredY = sample.Height - tilted:VectorToWorldSpace(bottomOffset).Y
  targetY = math.max(targetY, requiredY)
 end
 targetY += cfg.Suspension_ground_clearance
 -- Lift immediately to avoid penetrating curbs, smooth only downward travel.
 local newY = targetY >= data.Position.Y and targetY or lerpNumber(data.Position.Y, targetY, alpha)
 return newY, data.Pitch, data.Roll, false
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
	vehicle.PrimaryPart = main
	local chassisLayout = captureChassisLayout(vehicle, main)
	VehicleDamageManager.RegisterVehicle(vehicle)

	local axisName = tostring(getAttr(vehicle, "Drive_forward_axis", "Z"))
	local currentForward = getAxisForward(main.CFrame, axisName)
	local currentYaw = yawFromForward(currentForward)
	local probes, width, length = collectGroundProbes(vehicle, main)
	local rideHeight = math.max(main.Size.Y / 2, tonumber(vehicle:GetAttribute("Ground_body_height")) or main.Size.Y / 2)

	activeVehicles[vehicle] = {
		Main = main,
		ChassisLayout = chassisLayout,
		Seat = seat,
		Owner = ownerPlayer,

		CurrentSpeed = 0,
		CurrentSteer = 0,

		Yaw = currentYaw,
		Pitch = 0,
		Roll = 0,
		Position = main.Position,
		DriveForwardAxis = axisName,

		GroundProbes = probes,
		RideHeight = rideHeight,
		GroundWidth = width,
		GroundLength = length,
	}

	vehicle:SetAttribute("Current_speed", 0)

	print(
		"[VehicleDriveController] Vehicle registered:",
		vehicle.Name,
		"Axis:",
		axisName,
		"GroundProbes:",
		#probes,
		"RideHeight:",
		rideHeight
	)
end

function VehicleDriveController.UnregisterVehicle(vehicle)
	activeVehicles[vehicle] = nil
end

RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 0.1)
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
		local hasFuel = (tonumber(vehicle:GetAttribute("Fuel_cur")) or cfg.Fuel_max) > 0

		local throttle = seat.Occupant and seat.Throttle or 0
		local steer = seat.Occupant and seat.Steer or 0

		if not hasFuel then
			data.CurrentSpeed = 0
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
		local movement = forward * data.CurrentSpeed * dt
		local previousPosition = data.Position
		local previousPitch, previousRoll = data.Pitch, data.Roll
		local proposedPosition = data.Position + movement
		local otherVehicle = nil

		-- Sweep Main against other active ground vehicles.
		if movement.Magnitude > 0.0001 then
			local _, _, detectedVehicle = sweepMainForBlockingObject(
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
			otherVehicle = detectedVehicle
		end

		local hardObstacleThisFrame = false

		if otherVehicle then
			applyVehicleToVehicleImpact(vehicle, data, otherVehicle)
			data.LastBodyObstacle = nil
		else
			local tallObstacle = nil

			if impactSpeed > 0.01 and movement.Magnitude > 0.0001 then
				tallObstacle = getTallBodyObstacle(
					vehicle,
					data,
					cfg,
					movement,
					movement.Magnitude
				)
			end

			if tallObstacle then
				hardObstacleThisFrame = true

				-- Hard impact: damage once per continuous contact, then rebound in the
				-- opposite direction at a fraction of the pre-impact speed.
				--
				-- IMPORTANT: suspension is frozen for this frame below. Without that,
				-- repeatedly holding throttle against a wall lets the suspension solve
				-- upward a tiny amount on every impact and the vehicle can "ratchet"
				-- itself up a vertical obstacle.
				if data.LastBodyObstacle ~= tallObstacle then
					VehicleDamageManager.ApplyCollisionDamage(vehicle, impactSpeed)
				end

				data.LastBodyObstacle = tallObstacle

				local incomingSpeed = data.CurrentSpeed
				local bounceSpeed = math.abs(incomingSpeed) * DEFAULT_OBSTACLE_BOUNCE_FACTOR
				if incomingSpeed > 0 then
					data.CurrentSpeed = -bounceSpeed
				elseif incomingSpeed < 0 then
					data.CurrentSpeed = bounceSpeed
				else
					data.CurrentSpeed = 0
				end
			else
				data.LastBodyObstacle = nil
				data.Position = proposedPosition
			end
		end

		local pitch = data.Pitch or 0
		local roll = data.Roll or 0

		if not hardObstacleThisFrame then
			local newY
			local steep
   newY, pitch, roll, steep = updateGroundPose(vehicle, data, cfg, dt)
   if steep then
    data.Position = previousPosition
    data.Pitch, data.Roll = previousPitch, previousRoll
    pitch, roll = previousPitch, previousRoll
    data.CurrentSpeed = 0
   else
    data.Position = Vector3.new(data.Position.X, newY, data.Position.Z)
   end
		else
			-- Do not let a hard obstacle become suspension "ground".
			-- Keep the exact pre-impact chassis height/tilt for the impact frame.
			data.TargetRideHeight = data.Position.Y
		end

		local mainCFrame = buildMainCFrame(data.Position, data.Yaw, data.DriveForwardAxis, pitch, roll)

		-- Restore the fixed chassis layout; move mounted modules separately.
		pivotVehicleByMain(vehicle, main, mainCFrame, data.ChassisLayout)

		local travelled = data.Position - previousPosition
		consumeFuel(vehicle, {CurrentSpeed = Vector3.new(travelled.X, 0, travelled.Z).Magnitude / math.max(dt, 0.0001)}, cfg, dt)
		vehicle:SetAttribute("Current_speed", math.abs(data.CurrentSpeed))
	end
end)

return VehicleDriveController
