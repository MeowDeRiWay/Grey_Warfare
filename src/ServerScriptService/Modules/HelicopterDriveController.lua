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

local function getLandingHit(vehicle, landingPart, extraDistance, ownerPlayer)
	local distance = extraDistance or LANDING_RAY_DISTANCE
	local origin = landingPart.Position
	local direction = Vector3.new(0, -distance, 0)
	return workspace:Raycast(origin, direction, buildRaycastParams(vehicle, ownerPlayer))
end

local function getCollisionBoxSize(vehicle)
	local size = vehicle:GetExtentsSize()
	return Vector3.new(
		math.max(0.5, size.X - COLLISION_PADDING),
		math.max(0.5, size.Y - COLLISION_PADDING),
		math.max(0.5, size.Z - COLLISION_PADDING)
	)
end

local function castMove(vehicle, main, ownerPlayer, fromPos, yaw, displacement)
	if displacement.Magnitude < MIN_CAST_DISTANCE then
		return fromPos, false
	end

	local boxCFrame = CFrame.new(fromPos) * CFrame.Angles(0, yaw, 0)
	local hit = workspace:Blockcast(
		boxCFrame,
		getCollisionBoxSize(vehicle),
		displacement,
		buildRaycastParams(vehicle, ownerPlayer)
	)

	if not hit then
		return fromPos + displacement, false
	end

	local safeDistance = math.max(0, hit.Distance - 0.08)
	local safePos = fromPos + displacement.Unit * safeDistance
	return safePos, true, hit
end

local function getLandingOffset(main, landingPart)
	-- Ground_level не довіряємо: якщо він у шаблоні стоїть збоку/криво,
	-- ставимо його прямо під Main. Це наш чистий посадковий хітбокс.
	if landingPart == main then
		return CFrame.new()
	end

	local y = -((main.Size.Y / 2) + (landingPart.Size.Y / 2) + 0.05)
	return CFrame.new(0, y, 0)
end

local function alignLandingPart(main, landingPart, landingOffset)
	if landingPart ~= main then
		landingPart.CFrame = main.CFrame * landingOffset
	end
end

local function pivotKeepingYaw(vehicle, main, landingPart, landingOffset, position, yaw)
	vehicle:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
	alignLandingPart(main, landingPart, landingOffset)
	clearVelocities(vehicle)
end

helicopterControlRemote.OnServerEvent:Connect(function(player, input)
	if typeof(input) ~= "table" then
		return
	end

	playerInput[player] = {
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
	alignLandingPart(main, landingPart, landingOffset)

	local _, yaw, _ = main.CFrame:ToOrientation()

	activeHelicopters[vehicle] = {
		Main = main,
		Seat = seat,
		LandingPart = landingPart,
		LandingOffset = landingOffset,
		Owner = ownerPlayer,

		CurrentSpeed = 0,
		Yaw = yaw,
		HoverY = main.Position.Y,
		IsLanded = false,
		SpawnGraceLeft = SPAWN_GRACE_TIME,
	}

	print("[HelicopterDriveController] SAFE ZX arcade helicopter registered:", vehicle.Name)
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
		alignLandingPart(main, landingPart, landingOffset)

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

			-- Перші кадри після спавну не даємо геліку падати,
			-- бо seatOwner ще садить персонажа, інакше модель встигає провалитись/приземлитись криво.
			if data.SpawnGraceLeft and data.SpawnGraceLeft > 0 then
				data.SpawnGraceLeft -= dt
				data.HoverY = pos.Y
				pivotKeepingYaw(vehicle, main, landingPart, landingOffset, pos, data.Yaw)
				continue
			end

			local hit = getLandingHit(vehicle, landingPart, math.max(LANDING_RAY_DISTANCE, fallSpeed * dt + 2), owner)

			if hit then
				local gap = landingPart.Position.Y - pos.Y
				local targetMainY = hit.Position.Y - gap + LANDING_GAP
				local newPos = Vector3.new(pos.X, targetMainY, pos.Z)

				pivotKeepingYaw(vehicle, main, landingPart, landingOffset, newPos, data.Yaw)
				data.HoverY = newPos.Y
				data.IsLanded = true
			else
				local newPos = pos - Vector3.new(0, fallSpeed * dt, 0)
				pivotKeepingYaw(vehicle, main, landingPart, landingOffset, newPos, data.Yaw)
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

		local verticalMove = 0
		if liftInput ~= 0 then
			verticalMove = liftSpeed * liftInput * dt
		end

		local horizontalMove = flatLook * data.CurrentSpeed * dt
		local desiredMove = Vector3.new(horizontalMove.X, verticalMove, horizontalMove.Z)
		local newPos, blocked, hit = castMove(vehicle, main, owner, pos, data.Yaw, desiredMove)

		if blocked then
			-- Аркада: врізався — просто зупинився, без вибуху фізики.
			data.CurrentSpeed = 0

			-- Якщо вперлись знизу в землю/платформу, вважаємо це нормальною посадкою.
			if hit and hit.Normal.Y > 0.45 then
				data.IsLanded = true
			else
				data.IsLanded = false
			end
		else
			data.IsLanded = false
		end

		-- Додаткова перевірка посадки при спуску X: не даємо пройти крізь землю навіть тонким хітбоксом.
		if liftInput < 0 then
			alignLandingPart(main, landingPart, landingOffset)
			local landingHit = getLandingHit(vehicle, landingPart, math.max(LANDING_RAY_DISTANCE, math.abs(verticalMove) + 2), owner)
			if landingHit then
				local gap = landingPart.Position.Y - pos.Y
				local targetMainY = landingHit.Position.Y - gap + LANDING_GAP
				if newPos.Y <= targetMainY then
					newPos = Vector3.new(newPos.X, targetMainY, newPos.Z)
					data.CurrentSpeed = 0
					data.IsLanded = true
				end
			end
		end

		data.HoverY = newPos.Y
		pivotKeepingYaw(vehicle, main, landingPart, landingOffset, newPos, data.Yaw)

		if maxFuel > 0 and currentFuel > 0 then
			local moving = math.abs(data.CurrentSpeed) > 1 or math.abs(liftInput) > 0 or math.abs(steer) > 0
			if moving then
				vehicle:SetAttribute("Current_fuel", math.max(0, currentFuel - fuelPerSecond * dt))
			end
		end
	end
end)

return HelicopterDriveController
