local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

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

local function getNumberAttr(vehicle, name, default)
	return tonumber(getAttr(vehicle, name, default)) or default
end

local function getStringAttr(vehicle, name, default)
	local value = getAttr(vehicle, name, default)
	if typeof(value) == "string" then
		return value
	end
	return default
end

local function approach(current, target, speed, dt)
	local delta = target - current
	local step = speed * dt
	if math.abs(delta) <= step then
		return target
	end
	return current + math.sign(delta) * step
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

local function getPart(vehicle, name)
	local part = vehicle:FindFirstChild(name, true)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function getOccupantPlayer(seat)
	local humanoid = seat.Occupant
	if not humanoid then
		return nil
	end
	return Players:GetPlayerFromCharacter(humanoid.Parent)
end

local function restoreCharacterVisible(character)
	if not character then
		return
	end

	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") then
			pcall(function()
				item.LocalTransparencyModifier = 0
			end)
		elseif item:IsA("Decal") then
			if item.Name ~= "face" then
				-- не чіпаємо системні штуки зайвий раз
			end
		end
	end
end

local function getHumanoid(player)
	local character = player.Character
	if not character then
		return nil, nil
	end

	return character:FindFirstChildOfClass("Humanoid"), character
end

local function ejectPlayerFromHelicopter(data, player)
	local humanoid, character = getHumanoid(player)
	if not humanoid or not character then
		return
	end

	humanoid.Sit = false
	humanoid.Jump = true
	restoreCharacterVisible(character)

	local ground = data.Ground
	local main = data.Main
	local exitHeight = getNumberAttr(data.Vehicle, "Exit_height", 3)
	local exitSide = getNumberAttr(data.Vehicle, "Exit_side_offset", 4)

	local baseCFrame = ground and ground.CFrame or main.CFrame
	local sideOffset = ground and (ground.Size.X / 2 + exitSide) or exitSide
	local exitCFrame = baseCFrame * CFrame.new(sideOffset, exitHeight, 0)

	if character.PrimaryPart then
		character:PivotTo(exitCFrame)
	end
end

local function canPlayerEnter(vehicle, player)
	local ownerUserId = tonumber(vehicle:GetAttribute("OwnerUserId"))
	if ownerUserId and ownerUserId ~= player.UserId then
		return false
	end

	return true
end

local function setupEnterPrompt(vehicle, data)
	local main = data.Main
	if not main then
		return
	end

	local oldPrompt = main:FindFirstChild("HelicopterEnterPrompt")
	if oldPrompt then
		oldPrompt:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HelicopterEnterPrompt"
	prompt.ActionText = "Enter / Exit"
	prompt.ObjectText = vehicle.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = getNumberAttr(vehicle, "Enter_distance", 10)
	prompt.RequiresLineOfSight = false
	prompt.Parent = main

	prompt.Triggered:Connect(function(player)
		if not vehicle.Parent then
			return
		end

		if not canPlayerEnter(vehicle, player) then
			return
		end

		local humanoid, character = getHumanoid(player)
		if not humanoid or not character then
			return
		end

		local seat = data.Seat
		if not seat or not seat.Parent then
			return
		end

		local occupantPlayer = getOccupantPlayer(seat)
		if occupantPlayer == player then
			ejectPlayerFromHelicopter(data, player)
			return
		end

		if seat.Occupant then
			return
		end

		seat:Sit(humanoid)
		restoreCharacterVisible(character)
	end)
end

local function anchorAll(vehicle)
	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = true
		end
	end
end

local function getAxisRotation(axis, degrees)
	local radians = math.rad(degrees)
	axis = string.upper(axis or "Y")

	if axis == "X" then
		return CFrame.Angles(radians, 0, 0)
	elseif axis == "Z" then
		return CFrame.Angles(0, 0, radians)
	end

	return CFrame.Angles(0, radians, 0)
end

local function spinPart(part, axis, sign, degrees)
	if not part or not part.Parent then
		return
	end

	part.CFrame = part.CFrame * getAxisRotation(axis, degrees * sign)
end

local function makeOverlapParams(vehicle, ownerPlayer)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local ignore = { vehicle }
	if ownerPlayer and ownerPlayer.Character then
		table.insert(ignore, ownerPlayer.Character)
	end

	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	return params
end

local function makeRayParams(vehicle, ownerPlayer)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local ignore = { vehicle }
	if ownerPlayer and ownerPlayer.Character then
		table.insert(ignore, ownerPlayer.Character)
	end

	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	return params
end

local function hasBlockingParts(vehicle, boxCFrame, boxSize, ownerPlayer)
	local params = makeOverlapParams(vehicle, ownerPlayer)
	local parts = workspace:GetPartBoundsInBox(boxCFrame, boxSize, params)

	for _, part in ipairs(parts) do
		if part:IsA("BasePart") and part.CanCollide then
			return true, part
		end
	end

	return false, nil
end

local function isGrounded(vehicle, groundPart, ownerPlayer)
	if not groundPart then
		return false
	end

	local rayParams = makeRayParams(vehicle, ownerPlayer)
	local downDistance = 0.45
	local size = groundPart.Size
	local cf = groundPart.CFrame

	local offsets = {
		Vector3.new(0, 0, 0),
		Vector3.new(size.X * 0.42, 0, size.Z * 0.42),
		Vector3.new(-size.X * 0.42, 0, size.Z * 0.42),
		Vector3.new(size.X * 0.42, 0, -size.Z * 0.42),
		Vector3.new(-size.X * 0.42, 0, -size.Z * 0.42),
	}

	for _, offset in ipairs(offsets) do
		local origin = (cf * CFrame.new(offset)).Position
		local result = workspace:Raycast(origin, Vector3.new(0, -(size.Y / 2 + downDistance), 0), rayParams)
		if result then
			return true
		end
	end

	return false
end

local function getMainTargetCFrame(data, position, yaw, pitch, roll)
	local bodyPitchOffset = math.rad(getNumberAttr(data.Vehicle, "Body_pitch_offset", 0))
	local bodyYawOffset = math.rad(getNumberAttr(data.Vehicle, "Body_yaw_offset", 0))
	local bodyRollOffset = math.rad(getNumberAttr(data.Vehicle, "Body_roll_offset", 0))

	-- У твоєї поточної моделі локальні осі Main не співпали з носом гелікоптера:
	-- старий pitch давав крен, а старий roll давав тангаж.
	-- Тому тут навмисно міняємо їх місцями:
	--   pitch -> Z
	--   roll  -> X
	return CFrame.new(position)
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(bodyPitchOffset, bodyYawOffset, bodyRollOffset)
		* CFrame.Angles(math.rad(roll), 0, math.rad(pitch))
end

local function getMainCFrameForCenter(data, centerPosition, yaw, pitch, roll)
	local orientationOnly = getMainTargetCFrame(data, Vector3.new(0, 0, 0), yaw, pitch, roll)

	if not data.Ground then
		return getMainTargetCFrame(data, centerPosition, yaw, pitch, roll)
	end

	-- Точка обертання = центр Ground_level.
	-- Так гелік не описує коло навколо кривого Pivot/PrimaryPart,
	-- а повертається навколо власного посадкового куба.
	local groundOffsetFromMain = (orientationOnly * data.MainToGround).Position
	local mainPosition = centerPosition - groundOffsetFromMain

	return getMainTargetCFrame(data, mainPosition, yaw, pitch, roll)
end

local function pivotVehicleToMain(data, targetMainCFrame)
	data.Vehicle:SetPrimaryPartCFrame(targetMainCFrame)
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
	anchorAll(vehicle)

	local pivot = vehicle:GetPivot()
	local _, yaw, _ = main.CFrame:ToOrientation()

	local data = {
		Vehicle = vehicle,
		Main = main,
		Seat = seat,
		Ground = getPart(vehicle, "Ground_level"),
		MainRotor = getPart(vehicle, "MainRotor"),
		TailRotor = getPart(vehicle, "TailRotor"),
		Owner = ownerPlayer,

		MainToPivot = main.CFrame:ToObjectSpace(pivot),
		MainToGround = getPart(vehicle, "Ground_level") and main.CFrame:ToObjectSpace(getPart(vehicle, "Ground_level").CFrame) or CFrame.new(),

		Yaw = yaw,
		ForwardSpeed = 0,
		SideSpeed = 0,
		VerticalSpeed = 0,
		Pitch = 0,
		Roll = 0,
		RotorSpeed = 0,
		CurrentTurn = 0,
	}

	activeHelicopters[vehicle] = data
	setupEnterPrompt(vehicle, data)

	print("[HelicopterDriveController] CENTER TURN E/FUEL helicopter registered:", vehicle.Name)
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
		if not main or not main.Parent or not seat or not seat.Parent then
			activeHelicopters[vehicle] = nil
			continue
		end

		local owner = data.Owner
		local occupantPlayer = getOccupantPlayer(seat)
		local hasPilot = occupantPlayer ~= nil and occupantPlayer == owner
		local currentFuel = tonumber(vehicle:GetAttribute("Current_fuel")) or 0
		local maxFuel = tonumber(vehicle:GetAttribute("Max_fuel")) or 0
		local fuelPerSecond = getNumberAttr(vehicle, "Fuel_per_second", 1)
		local hasFuel = maxFuel <= 0 or currentFuel > 0
		local hasControl = hasPilot and hasFuel

		local maxSpeed = getNumberAttr(vehicle, "Max_speed", 80)
		local reverseSpeed = getNumberAttr(vehicle, "Reverse_speed", 35)
		local sideSpeed = getNumberAttr(vehicle, "Side_speed", 45)
		local brakeAcceleration = getNumberAttr(vehicle, "Brake_acceleration", 55)
		local liftSpeed = getNumberAttr(vehicle, "Lift_speed", 35)
		local descendSpeed = getNumberAttr(vehicle, "Descend_speed", 25)
		local turnSpeed = getNumberAttr(vehicle, "Turn_speed", 1.8)
		local turnAcceleration = getNumberAttr(vehicle, "Turn_acceleration", 4)
		local maxPitchAngle = getNumberAttr(vehicle, "Max_pitch_angle", 12)
		local maxRollAngle = getNumberAttr(vehicle, "Max_roll_angle", 10)
		local tiltSmooth = getNumberAttr(vehicle, "Tilt_smooth", 6)
		local pitchSmooth = getNumberAttr(vehicle, "Pitch_smooth", tiltSmooth)
		local rollSmooth = getNumberAttr(vehicle, "Roll_smooth", tiltSmooth)
		local rotorIdleSpeed = getNumberAttr(vehicle, "Rotor_idle_speed", 300)
		local rotorFlightSpeed = getNumberAttr(vehicle, "Rotor_flight_speed", 1500)
		local rotorSmooth = getNumberAttr(vehicle, "Rotor_smooth", 8)
		local fallSpeed = getNumberAttr(vehicle, "Fall_speed", 25)

		local visualPitchSign = getNumberAttr(vehicle, "Visual_pitch_sign", -1)
		local visualRollSign = getNumberAttr(vehicle, "Visual_roll_sign", 1)
		local turnSign = getNumberAttr(vehicle, "Turn_sign", 1)
		local moveForwardSign = getNumberAttr(vehicle, "Move_forward_sign", -1)
		local sideMoveSign = getNumberAttr(vehicle, "Side_move_sign", -1)
		local controlYawOffset = math.rad(getNumberAttr(vehicle, "Control_yaw_offset", -90))
		local groundedNow = isGrounded(vehicle, data.Ground, owner)

		local throttle = 0
		local steer = 0
		local liftInput = 0

		if hasControl then
			throttle = seat.Throttle
			steer = seat.Steer
			if owner and playerInput[owner] then
				liftInput = playerInput[owner].Lift or 0
			end
		end

		local targetPitch = 0
		if throttle > 0 then
			targetPitch = -maxPitchAngle * visualPitchSign
		elseif throttle < 0 then
			targetPitch = maxPitchAngle * 0.65 * visualPitchSign
		end

		local targetRoll = -steer * maxRollAngle * visualRollSign

		data.Pitch = approach(data.Pitch, targetPitch, maxPitchAngle * pitchSmooth, dt)
		data.Roll = approach(data.Roll, targetRoll, maxRollAngle * rollSmooth, dt)

		local pitchRatio = math.clamp((-data.Pitch * visualPitchSign) / maxPitchAngle, -1, 1)
		local rollRatio = math.clamp((-data.Roll * visualRollSign) / maxRollAngle, -1, 1)

		local targetForwardSpeed = 0
		if pitchRatio > 0 then
			targetForwardSpeed = pitchRatio * maxSpeed
		elseif pitchRatio < 0 then
			targetForwardSpeed = pitchRatio * reverseSpeed
		end

		local targetSideSpeed = rollRatio * sideSpeed

		data.ForwardSpeed = approach(data.ForwardSpeed, targetForwardSpeed, brakeAcceleration, dt)
		data.SideSpeed = approach(data.SideSpeed, targetSideSpeed, brakeAcceleration, dt)

		local targetVerticalSpeed = 0
		if hasControl then
			if liftInput > 0 then
				targetVerticalSpeed = liftInput * liftSpeed
			elseif liftInput < 0 then
				targetVerticalSpeed = liftInput * descendSpeed
			end
		else
			if groundedNow then
				targetVerticalSpeed = 0
			else
				targetVerticalSpeed = -fallSpeed
			end
		end

		if groundedNow and targetVerticalSpeed < 0 then
			targetVerticalSpeed = 0
		end

		data.VerticalSpeed = approach(data.VerticalSpeed, targetVerticalSpeed, math.max(liftSpeed, descendSpeed, fallSpeed) * 4, dt)

		local yawTurnTarget = rollRatio * turnSpeed * turnSign
		data.CurrentTurn = approach(data.CurrentTurn or 0, yawTurnTarget, turnAcceleration, dt)
		data.Yaw += data.CurrentTurn * dt

		local controlYaw = data.Yaw + controlYawOffset
		local forward = CFrame.Angles(0, controlYaw, 0).LookVector * moveForwardSign
		local right = CFrame.Angles(0, controlYaw, 0).RightVector * sideMoveSign

		local currentCenterPosition = data.Ground and data.Ground.Position or main.Position
		local wantedMove = (forward * data.ForwardSpeed + right * data.SideSpeed + Vector3.new(0, data.VerticalSpeed, 0)) * dt
		if groundedNow and wantedMove.Y < 0 then
			wantedMove = Vector3.new(wantedMove.X, 0, wantedMove.Z)
			data.VerticalSpeed = 0
		end
		local wantedCenterPosition = currentCenterPosition + wantedMove

		local targetMainCFrame = getMainCFrameForCenter(data, wantedCenterPosition, data.Yaw, data.Pitch, data.Roll)

		local canMove = true
		if data.Ground then
			local targetGroundCFrame = targetMainCFrame * data.MainToGround
			local blocking = hasBlockingParts(vehicle, targetGroundCFrame, data.Ground.Size, owner)
			if blocking then
				canMove = false
			end
		end

		if canMove then
			pivotVehicleToMain(data, targetMainCFrame)
		else
			data.ForwardSpeed = 0
			data.SideSpeed = 0
			data.VerticalSpeed = 0
			local stopMainCFrame = getMainCFrameForCenter(data, currentCenterPosition, data.Yaw, data.Pitch, data.Roll)
			pivotVehicleToMain(data, stopMainCFrame)
		end

		local displaySpeed = math.sqrt(data.ForwardSpeed * data.ForwardSpeed + data.SideSpeed * data.SideSpeed + data.VerticalSpeed * data.VerticalSpeed)
		vehicle:SetAttribute("Current_speed", displaySpeed)
		vehicle:SetAttribute("Is_grounded", groundedNow)

		if hasControl and maxFuel > 0 and fuelPerSecond > 0 then
			vehicle:SetAttribute("Current_fuel", math.max(0, currentFuel - fuelPerSecond * dt))
		end

		local rotorTarget = 0
		if hasControl then
			local movementAmount = math.clamp((math.abs(data.ForwardSpeed) + math.abs(data.SideSpeed) + math.abs(data.VerticalSpeed)) / math.max(maxSpeed, 1), 0, 1)
			rotorTarget = rotorIdleSpeed + (rotorFlightSpeed - rotorIdleSpeed) * movementAmount
		else
			rotorTarget = 0
		end

		data.RotorSpeed = approach(data.RotorSpeed, rotorTarget, math.max(rotorSmooth, 1) * rotorFlightSpeed, dt)

		local mainRotorAxis = getStringAttr(vehicle, "MainRotor_axis", "Y")
		local mainRotorSign = getNumberAttr(vehicle, "MainRotor_axis_sign", 1)
		local tailRotorAxis = getStringAttr(vehicle, "TailRotor_axis", "Z")
		local tailRotorSign = getNumberAttr(vehicle, "TailRotor_axis_sign", 1)

		spinPart(data.MainRotor, mainRotorAxis, mainRotorSign, data.RotorSpeed * dt)
		spinPart(data.TailRotor, tailRotorAxis, tailRotorSign, data.RotorSpeed * dt * 1.4)
	end
end)

return HelicopterDriveController
