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
local SPAWN_GRACE_TIME = 0.45
local COLLISION_PADDING = 0.15
local MIN_CAST_DISTANCE = 0.02
local EPSILON = 0.001

local function getAttr(vehicle, name, default)
	local value = vehicle:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

local function getNumberAttr(vehicle, name, default)
	local value = tonumber(getAttr(vehicle, name, default))
	if value == nil then
		return default
	end
	return value
end

local function approach(current, target, speed, dt)
	local step = speed * dt
	if math.abs(target - current) <= step then
		return target
	end
	return current + math.sign(target - current) * step
end

local function lerpNumber(current, target, smooth, dt)
	local alpha = math.clamp(smooth * dt, 0, 1)
	return current + (target - current) * alpha
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

local function findPart(vehicle, names)
	for _, name in ipairs(names) do
		local part = vehicle:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function setArcadePhysics(vehicle)
	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanTouch = true
			item.AssemblyLinearVelocity = Vector3.zero
			item.AssemblyAngularVelocity = Vector3.zero

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

local function buildRaycastParams(vehicle, ownerPlayer)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local excluded = { vehicle }
	if ownerPlayer and ownerPlayer.Character then
		table.insert(excluded, ownerPlayer.Character)
	end

	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = true
	return params
end

local function buildOverlapParams(vehicle, ownerPlayer)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local excluded = { vehicle }
	if ownerPlayer and ownerPlayer.Character then
		table.insert(excluded, ownerPlayer.Character)
	end

	params.FilterDescendantsInstances = excluded
	params.MaxParts = 30
	params.RespectCanCollide = true
	return params
end

local function getWallCollisionBoxSize(vehicle)
	local size = vehicle:GetExtentsSize()
	return Vector3.new(
		math.max(0.5, size.X - COLLISION_PADDING),
		math.max(0.5, math.min(size.Y - COLLISION_PADDING, 2.5)),
		math.max(0.5, size.Z - COLLISION_PADDING)
	)
end

local function isBoxClear(vehicle, ownerPlayer, position, yaw)
	local boxCFrame = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local touching = workspace:GetPartBoundsInBox(
		boxCFrame,
		getWallCollisionBoxSize(vehicle),
		buildOverlapParams(vehicle, ownerPlayer)
	)

	return #touching == 0
end

local function getLandingHit(vehicle, landingPart, extraDistance, ownerPlayer)
	local distance = extraDistance or LANDING_RAY_DISTANCE
	local origin = landingPart.Position
	local direction = Vector3.new(0, -distance, 0)
	return workspace:Raycast(origin, direction, buildRaycastParams(vehicle, ownerPlayer))
end

local function castMove(vehicle, ownerPlayer, fromPos, yaw, displacement)
	if displacement.Magnitude < MIN_CAST_DISTANCE then
		return fromPos, false, nil
	end

	local boxCFrame = CFrame.new(fromPos) * CFrame.Angles(0, yaw, 0)
	local hit = workspace:Blockcast(
		boxCFrame,
		getWallCollisionBoxSize(vehicle),
		displacement,
		buildRaycastParams(vehicle, ownerPlayer)
	)

	if not hit then
		return fromPos + displacement, false, nil
	end

	local safeDistance = math.max(0, hit.Distance - 0.08)
	local safePos = fromPos + displacement.Unit * safeDistance
	return safePos, true, hit
end

local function getLandingOffset(main, landingPart)
	if landingPart == main then
		return CFrame.new()
	end

	local y = -((main.Size.Y / 2) + (landingPart.Size.Y / 2) + 0.05)
	return CFrame.new(0, y, 0)
end

local function alignLandingPart(main, landingPart, landingOffset, yaw)
	if landingPart ~= main then
		-- Ground_level лишаємо рівним кубом під гелікоптером, без тангажу/крену.
		landingPart.CFrame = CFrame.new(main.Position) * CFrame.Angles(0, yaw, 0) * landingOffset
	end
end

local function pivotVisual(vehicle, main, landingPart, landingOffset, position, yaw, pitch, roll)
	local cframe = CFrame.new(position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(pitch), 0, math.rad(roll))
	vehicle:PivotTo(cframe)
	alignLandingPart(main, landingPart, landingOffset, yaw)
	clearVelocities(vehicle)
end

local function spinPartAroundLocalAxis(part, axis, degrees)
	if not part then
		return
	end

	local radians = math.rad(degrees)
	if axis == "X" then
		part.CFrame = part.CFrame * CFrame.Angles(radians, 0, 0)
	elseif axis == "Y" then
		part.CFrame = part.CFrame * CFrame.Angles(0, radians, 0)
	else
		part.CFrame = part.CFrame * CFrame.Angles(0, 0, radians)
	end
end

local function updateRotors(vehicle, data, dt, hasPilot, isMoving)
	local idleSpeed = getNumberAttr(vehicle, "Rotor_idle_speed", 300)
	local flightSpeed = getNumberAttr(vehicle, "Rotor_flight_speed", 1500)
	local rotorSmooth = getNumberAttr(vehicle, "Rotor_smooth", 8)

	local targetRotorSpeed = 0
	if hasPilot then
		targetRotorSpeed = idleSpeed
		if isMoving then
			targetRotorSpeed = flightSpeed
		end
	end

	data.RotorSpeed = lerpNumber(data.RotorSpeed or 0, targetRotorSpeed, rotorSmooth, dt)

	if math.abs(data.RotorSpeed) > EPSILON then
		local spin = data.RotorSpeed * dt
		spinPartAroundLocalAxis(data.MainRotor, "Y", spin)
		spinPartAroundLocalAxis(data.TailRotor, "X", spin)
	end
end

helicopterControlRemote.OnServerEvent:Connect(function(player, input)
	if typeof(input) ~= "table" then
		return
	end

	playerInput[player] = {
		-- Z = +1, X = -1. Клавіші лишаються старі: Z/X.
		Lift = math.clamp(tonumber(input.Lift) or 0, -1, 1),
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
	local landingOffset = getLandingOffset(main, landingPart)

	setArcadePhysics(vehicle)

	local _, yaw, _ = main.CFrame:ToOrientation()
	alignLandingPart(main, landingPart, landingOffset, yaw)

	activeHelicopters[vehicle] = {
		Main = main,
		Seat = seat,
		LandingPart = landingPart,
		LandingOffset = landingOffset,
		MainRotor = findPart(vehicle, { "MainRotor", "Rotor_main", "Main_rotor" }),
		TailRotor = findPart(vehicle, { "TailRotor", "Rotor_tail", "Tail_rotor" }),
		Owner = ownerPlayer,

		Yaw = yaw,
		Pitch = 0,
		Roll = 0,
		RotorSpeed = 0,
		HoverY = main.Position.Y,
		IsLanded = false,
		SpawnGraceLeft = SPAWN_GRACE_TIME,
	}

	print("[HelicopterDriveController] TILT arcade helicopter registered:", vehicle.Name)
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
		local landingOffset = data.LandingOffset
		local owner = data.Owner

		if not main or not main.Parent or not seat or not seat.Parent or not landingPart or not landingPart.Parent then
			activeHelicopters[vehicle] = nil
			continue
		end

		setArcadePhysics(vehicle)

		local currentFuel = tonumber(vehicle:GetAttribute("Current_fuel")) or 0
		local maxFuel = tonumber(vehicle:GetAttribute("Max_fuel")) or 0

		local maxSpeed = getNumberAttr(vehicle, "Max_speed", getNumberAttr(vehicle, "Speed", 80))
		local reverseSpeed = getNumberAttr(vehicle, "Reverse_speed", getNumberAttr(vehicle, "Speed_reverse", 35))
		local liftSpeed = getNumberAttr(vehicle, "Lift_speed", 35)
		local descendSpeed = getNumberAttr(vehicle, "Descend_speed", 25)
		local turnSpeed = getNumberAttr(vehicle, "Turn_speed", 1.8)
		local turnAcceleration = getNumberAttr(vehicle, "Turn_acceleration", 4)
		local tiltSmooth = getNumberAttr(vehicle, "Tilt_smooth", 6)
		local maxPitchAngle = getNumberAttr(vehicle, "Max_pitch_angle", 12)
		local maxRollAngle = getNumberAttr(vehicle, "Max_roll_angle", 10)
		local fuelPerSecond = getNumberAttr(vehicle, "Fuel_per_second", 0.05)
		local fallSpeed = getNumberAttr(vehicle, "Fall_speed", DEFAULT_FALL_SPEED)

		local pos = main.Position
		local pilot = hasDriver(seat)

		if not pilot then
			data.Pitch = approach(data.Pitch or 0, 0, maxPitchAngle * tiltSmooth, dt)
			data.Roll = approach(data.Roll or 0, 0, maxRollAngle * tiltSmooth, dt)
			updateRotors(vehicle, data, dt, false, false)

			if data.SpawnGraceLeft and data.SpawnGraceLeft > 0 then
				data.SpawnGraceLeft -= dt
				data.HoverY = pos.Y
				pivotVisual(vehicle, main, landingPart, landingOffset, pos, data.Yaw, data.Pitch, data.Roll)
				continue
			end

			local hit = getLandingHit(vehicle, landingPart, math.max(LANDING_RAY_DISTANCE, fallSpeed * dt + 2), owner)

			if hit then
				local gap = landingPart.Position.Y - pos.Y
				local targetMainY = hit.Position.Y - gap + LANDING_GAP
				local newPos = Vector3.new(pos.X, targetMainY, pos.Z)

				pivotVisual(vehicle, main, landingPart, landingOffset, newPos, data.Yaw, data.Pitch, data.Roll)
				data.HoverY = newPos.Y
				data.IsLanded = true
			else
				local newPos = pos - Vector3.new(0, fallSpeed * dt, 0)
				pivotVisual(vehicle, main, landingPart, landingOffset, newPos, data.Yaw, data.Pitch, data.Roll)
				data.HoverY = newPos.Y
				data.IsLanded = false
			end

			continue
		end

		data.SpawnGraceLeft = 0

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

		-- W/S задають бажаний тангаж. Швидкість далі береться саме з поточного кута.
		local targetPitch = 0
		if throttle > 0 then
			targetPitch = -maxPitchAngle
		elseif throttle < 0 then
			targetPitch = maxPitchAngle
		end

		-- A/D задають бажаний крен. Поворот береться саме з поточного крену.
		local targetRoll = -steer * maxRollAngle

		data.Pitch = approach(data.Pitch or 0, targetPitch, maxPitchAngle * tiltSmooth, dt)
		data.Roll = approach(data.Roll or 0, targetRoll, maxRollAngle * tiltSmooth, dt)

		local pitchRatio = 0
		if maxPitchAngle > EPSILON then
			pitchRatio = math.clamp(-(data.Pitch or 0) / maxPitchAngle, -1, 1)
		end

		local rollRatio = 0
		if maxRollAngle > EPSILON then
			rollRatio = math.clamp(-(data.Roll or 0) / maxRollAngle, -1, 1)
		end

		local forwardSpeed = 0
		if pitchRatio >= 0 then
			forwardSpeed = pitchRatio * maxSpeed
		else
			forwardSpeed = pitchRatio * reverseSpeed
		end

		local targetTurnSpeed = rollRatio * turnSpeed
		data.CurrentTurnSpeed = approach(data.CurrentTurnSpeed or 0, targetTurnSpeed, turnAcceleration, dt)

		local oldYaw = data.Yaw
		local wantedYaw = data.Yaw + ((data.CurrentTurnSpeed or 0) * dt)

		if isBoxClear(vehicle, owner, pos, wantedYaw) then
			data.Yaw = wantedYaw
		else
			data.Yaw = oldYaw
			data.CurrentTurnSpeed = 0
			data.Roll = 0
		end

		local look = (CFrame.Angles(0, data.Yaw, 0)).LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude < 0.1 then
			flatLook = Vector3.zAxis
		else
			flatLook = flatLook.Unit
		end

		local verticalSpeed = 0
		if liftInput > 0 then
			verticalSpeed = liftSpeed
		elseif liftInput < 0 then
			verticalSpeed = -descendSpeed
		end

		local horizontalMove = flatLook * forwardSpeed * dt
		local verticalMove = verticalSpeed * dt
		local desiredMove = Vector3.new(horizontalMove.X, verticalMove, horizontalMove.Z)
		local newPos, blocked, hit = castMove(vehicle, owner, pos, data.Yaw, desiredMove)

		if not blocked and not isBoxClear(vehicle, owner, newPos, data.Yaw) then
			newPos = pos
			blocked = true
		end

		if blocked then
			-- Аркада: врізався — просто зупинився/вирівнявся без фізичного вибуху.
			data.Pitch = 0
			data.Roll = 0
			data.CurrentTurnSpeed = 0

			if hit and hit.Normal.Y > 0.45 then
				data.IsLanded = true
			else
				data.IsLanded = false
			end
		else
			data.IsLanded = false
		end

		-- Додаткова перевірка посадки при спуску X.
		if liftInput < 0 then
			alignLandingPart(main, landingPart, landingOffset, data.Yaw)
			local landingHit = getLandingHit(vehicle, landingPart, math.max(LANDING_RAY_DISTANCE, math.abs(verticalMove) + 2), owner)
			if landingHit then
				local gap = landingPart.Position.Y - pos.Y
				local targetMainY = landingHit.Position.Y - gap + LANDING_GAP
				if newPos.Y <= targetMainY then
					newPos = Vector3.new(newPos.X, targetMainY, newPos.Z)
					data.Pitch = 0
					data.Roll = 0
					data.CurrentTurnSpeed = 0
					data.IsLanded = true
				end
			end
		end

		local isMoving = math.abs(forwardSpeed) > 1 or math.abs(verticalSpeed) > 0 or math.abs(data.CurrentTurnSpeed or 0) > 0.05
		data.HoverY = newPos.Y
		pivotVisual(vehicle, main, landingPart, landingOffset, newPos, data.Yaw, data.Pitch, data.Roll)
		updateRotors(vehicle, data, dt, true, isMoving)

		if maxFuel > 0 and currentFuel > 0 then
			if isMoving then
				vehicle:SetAttribute("Current_fuel", math.max(0, currentFuel - fuelPerSecond * dt))
			end
		end
	end
end)

return HelicopterDriveController
