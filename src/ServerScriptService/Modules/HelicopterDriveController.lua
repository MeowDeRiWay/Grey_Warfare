local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HelicopterDriveController = {}

local activeHelicopters = {}
local playerInput = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local helicopterControlRemote = remotes:WaitForChild("HelicopterControl")

local EPS = 0.001

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

local function getStringAttr(vehicle, name, default)
	local value = getAttr(vehicle, name, default)
	if typeof(value) ~= "string" then
		return default
	end
	return value
end

local function approach(current, target, speed, dt)
	local step = speed * dt
	local diff = target - current
	if math.abs(diff) <= step then
		return target
	end
	return current + math.sign(diff) * step
end

local function expApproach(current, target, smooth, dt)
	local alpha = 1 - math.exp(-math.max(smooth, 0) * dt)
	return current + (target - current) * alpha
end

local function getDriverSeat(vehicle)
	local seat = vehicle:FindFirstChild("Driver_seat", true)
	if seat and seat:IsA("VehicleSeat") then
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

local function setupArcadeParts(vehicle)
	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = item.Name == "Ground_level"
		end
	end
end

local function getBoxSize(data)
	if data.GroundLevel and data.GroundLevel.Parent then
		return data.GroundLevel.Size
	end
	return data.ModelSize
end

local function getGroundBoxCFrame(data, candidatePivot)
	if not data.GroundLevel or not data.GroundLevel.Parent then
		return candidatePivot
	end

	local groundLocal = data.InitialPivot:ToObjectSpace(data.GroundLevel.CFrame)
	return candidatePivot * groundLocal
end

local function getOverlapParams(vehicle)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { vehicle }
	params.RespectCanCollide = true
	return params
end

local function getRaycastParams(vehicle)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { vehicle }
	params.RespectCanCollide = true
	return params
end

local function isBoxBlocked(vehicle, cframe, size)
	local parts = Workspace:GetPartBoundsInBox(cframe, size, getOverlapParams(vehicle))
	for _, part in ipairs(parts) do
		if part:IsA("BasePart") and part.CanCollide then
			return true, part
		end
	end
	return false, nil
end

local function canMoveTo(vehicle, data, candidatePivot)
	local boxCFrame = getGroundBoxCFrame(data, candidatePivot)
	local boxSize = getBoxSize(data) * 0.96
	local blocked = isBoxBlocked(vehicle, boxCFrame, boxSize)
	return not blocked
end

local function hasDriver(data)
	local seat = data.Seat
	if not seat or not seat.Parent then
		return false
	end
	return seat.Occupant ~= nil
end

local function rotatePartAroundOwnAxis(part, axisName, sign, degrees)
	if not part or not part.Parent then
		return
	end

	local radians = math.rad(degrees * sign)
	axisName = string.upper(axisName or "Y")

	if axisName == "X" then
		part.CFrame = part.CFrame * CFrame.Angles(radians, 0, 0)
	elseif axisName == "Z" then
		part.CFrame = part.CFrame * CFrame.Angles(0, 0, radians)
	else
		part.CFrame = part.CFrame * CFrame.Angles(0, radians, 0)
	end
end

helicopterControlRemote.OnServerEvent:Connect(function(player, input)
	if typeof(input) ~= "table" then
		return
	end

	playerInput[player] = {
		Lift = math.clamp(tonumber(input.Lift) or 0, -1, 1), -- Z = 1, X = -1
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
		warn("[HelicopterDriveController] Driver_seat VehicleSeat not found:", vehicle.Name)
		return
	end

	setupArcadeParts(vehicle)

	local pivot = vehicle:GetPivot()
	local _, startYaw, _ = main.CFrame:ToOrientation()

	activeHelicopters[vehicle] = {
		Vehicle = vehicle,
		Main = main,
		Seat = seat,
		Owner = ownerPlayer,
		GroundLevel = getPart(vehicle, "Ground_level"),
		MainRotor = getPart(vehicle, "MainRotor"),
		TailRotor = getPart(vehicle, "TailRotor"),

		InitialPivot = pivot,
		MainLocal = pivot:ToObjectSpace(main.CFrame),
		ModelSize = vehicle:GetExtentsSize(),

		Position = pivot.Position,
		Yaw = startYaw,

		ForwardSpeed = 0,
		SideSpeed = 0,
		VerticalSpeed = 0,
		CurrentPitch = 0,
		CurrentRoll = 0,
		RotorSpeed = 0,
		Landed = false,
	}

	print("[HelicopterDriveController] TILT side-fixed helicopter registered:", vehicle.Name)
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
		local owner = data.Owner

		if not main or not main.Parent or not seat or not seat.Parent then
			activeHelicopters[vehicle] = nil
			continue
		end

		local currentFuel = tonumber(vehicle:GetAttribute("Current_fuel")) or 0
		local maxFuel = tonumber(vehicle:GetAttribute("Max_fuel")) or 0
		local hasPilot = hasDriver(data)
		local canFly = hasPilot and currentFuel > 0

		local maxSpeed = getNumberAttr(vehicle, "Max_speed", 80)
		local reverseSpeed = getNumberAttr(vehicle, "Reverse_speed", 35)
		local sideSpeedMax = getNumberAttr(vehicle, "Side_speed", 45)
		local brakeAcceleration = getNumberAttr(vehicle, "Brake_acceleration", 55)
		local liftSpeed = getNumberAttr(vehicle, "Lift_speed", 35)
		local descendSpeed = getNumberAttr(vehicle, "Descend_speed", 25)
		local turnSpeed = getNumberAttr(vehicle, "Turn_speed", 1.8)
		local turnAcceleration = getNumberAttr(vehicle, "Turn_acceleration", 4)
		local maxPitchAngle = getNumberAttr(vehicle, "Max_pitch_angle", 12)
		local maxRollAngle = getNumberAttr(vehicle, "Max_roll_angle", 10)
		local tiltSmooth = getNumberAttr(vehicle, "Tilt_smooth", 6)
		local rotorIdleSpeed = getNumberAttr(vehicle, "Rotor_idle_speed", 300)
		local rotorFlightSpeed = getNumberAttr(vehicle, "Rotor_flight_speed", 1500)
		local rotorSmooth = getNumberAttr(vehicle, "Rotor_smooth", 8)
		local fuelPerSecond = getNumberAttr(vehicle, "Fuel_per_second", 0.05)

		local controlYawOffset = math.rad(getNumberAttr(vehicle, "Control_yaw_offset", 0))
		local bodyPitchOffset = math.rad(getNumberAttr(vehicle, "Body_pitch_offset", 0))
		local bodyYawOffset = math.rad(getNumberAttr(vehicle, "Body_yaw_offset", 0))
		local bodyRollOffset = math.rad(getNumberAttr(vehicle, "Body_roll_offset", 0))

		local visualPitchSign = getNumberAttr(vehicle, "Visual_pitch_sign", 1)
		local visualRollSign = getNumberAttr(vehicle, "Visual_roll_sign", 1)
		local moveForwardSign = getNumberAttr(vehicle, "Move_forward_sign", -1)
		local sideMoveSign = getNumberAttr(vehicle, "Side_move_sign", -1)
		local turnSign = getNumberAttr(vehicle, "Turn_sign", 1)

		local mainRotorAxis = getStringAttr(vehicle, "MainRotor_axis", "Y")
		local mainRotorSign = getNumberAttr(vehicle, "MainRotor_axis_sign", 1)
		local tailRotorAxis = getStringAttr(vehicle, "TailRotor_axis", "Z")
		local tailRotorSign = getNumberAttr(vehicle, "TailRotor_axis_sign", 1)

		local throttle = 0
		local steer = 0
		local liftInput = 0

		if canFly then
			throttle = math.clamp(seat.Throttle, -1, 1)
			steer = math.clamp(seat.Steer, -1, 1)
			if owner and playerInput[owner] then
				liftInput = playerInput[owner].Lift or 0
			end
		end

		local targetPitch = throttle * maxPitchAngle * visualPitchSign
		local targetRoll = steer * maxRollAngle * visualRollSign

		data.CurrentPitch = expApproach(data.CurrentPitch, targetPitch, tiltSmooth, dt)
		data.CurrentRoll = expApproach(data.CurrentRoll, targetRoll, tiltSmooth, dt)

		local forwardRatio = math.clamp(data.CurrentPitch / math.max(maxPitchAngle, EPS), -1, 1) * visualPitchSign
		local sideRatio = math.clamp(data.CurrentRoll / math.max(maxRollAngle, EPS), -1, 1) * visualRollSign

		local targetForwardSpeed = 0
		if forwardRatio > 0 then
			targetForwardSpeed = forwardRatio * maxSpeed * moveForwardSign
		elseif forwardRatio < 0 then
			targetForwardSpeed = forwardRatio * reverseSpeed * moveForwardSign
		end

		local targetSideSpeed = sideRatio * sideSpeedMax * sideMoveSign

		local speedChange = brakeAcceleration * dt
		data.ForwardSpeed += math.clamp(targetForwardSpeed - data.ForwardSpeed, -speedChange, speedChange)
		data.SideSpeed += math.clamp(targetSideSpeed - data.SideSpeed, -speedChange, speedChange)

		local targetVerticalSpeed = 0
		if canFly then
			if liftInput > 0 then
				targetVerticalSpeed = liftInput * liftSpeed
			elseif liftInput < 0 then
				targetVerticalSpeed = liftInput * descendSpeed
			end
		else
			targetVerticalSpeed = -descendSpeed
		end

		data.VerticalSpeed = approach(data.VerticalSpeed, targetVerticalSpeed, brakeAcceleration, dt)

		local yawInput = sideRatio * turnSpeed * turnSign
		local yawStep = math.clamp(yawInput, -turnAcceleration, turnAcceleration) * dt
		data.Yaw += yawStep

		local yawCFrame = CFrame.Angles(0, data.Yaw + controlYawOffset, 0)
		local forwardVector = yawCFrame.LookVector
		local rightVector = yawCFrame.RightVector
		local moveDelta =
			(forwardVector * data.ForwardSpeed + rightVector * data.SideSpeed + Vector3.yAxis * data.VerticalSpeed) * dt

		local candidatePosition = data.Position + moveDelta
		local visualRotation =
			CFrame.Angles(0, data.Yaw, 0)
			* CFrame.Angles(bodyPitchOffset + math.rad(data.CurrentPitch), bodyYawOffset, bodyRollOffset + math.rad(data.CurrentRoll))

		local candidatePivot = CFrame.new(candidatePosition) * visualRotation

		if canMoveTo(vehicle, data, candidatePivot) then
			data.Position = candidatePosition
			data.Landed = false
		else
			-- Пробуємо відсікти рух по осях окремо, щоб не проходив крізь стіни, але міг ковзнути вздовж них.
			local horizontalDelta = forwardVector * data.ForwardSpeed * dt
			local sideDelta = rightVector * data.SideSpeed * dt
			local verticalDelta = Vector3.yAxis * data.VerticalSpeed * dt

			local testPosition = data.Position

			local testPivot = CFrame.new(testPosition + horizontalDelta) * visualRotation
			if canMoveTo(vehicle, data, testPivot) then
				testPosition += horizontalDelta
			else
				data.ForwardSpeed = 0
			end

			testPivot = CFrame.new(testPosition + sideDelta) * visualRotation
			if canMoveTo(vehicle, data, testPivot) then
				testPosition += sideDelta
			else
				data.SideSpeed = 0
			end

			testPivot = CFrame.new(testPosition + verticalDelta) * visualRotation
			if canMoveTo(vehicle, data, testPivot) then
				testPosition += verticalDelta
				data.Landed = false
			else
				if data.VerticalSpeed < 0 then
					data.Landed = true
				end
				data.VerticalSpeed = 0
			end

			data.Position = testPosition
			candidatePivot = CFrame.new(data.Position) * visualRotation
		end

		vehicle:PivotTo(candidatePivot)

		local moving =
			math.abs(data.ForwardSpeed) > 1
			or math.abs(data.SideSpeed) > 1
			or math.abs(data.VerticalSpeed) > 1
			or math.abs(yawInput) > 0.05

		local targetRotorSpeed = 0
		if hasPilot then
			if moving or canFly then
				targetRotorSpeed = rotorFlightSpeed
			else
				targetRotorSpeed = rotorIdleSpeed
			end
		end

		data.RotorSpeed = expApproach(data.RotorSpeed, targetRotorSpeed, rotorSmooth, dt)
		rotatePartAroundOwnAxis(data.MainRotor, mainRotorAxis, mainRotorSign, data.RotorSpeed * dt)
		rotatePartAroundOwnAxis(data.TailRotor, tailRotorAxis, tailRotorSign, data.RotorSpeed * dt)

		if maxFuel > 0 and currentFuel > 0 and moving then
			vehicle:SetAttribute("Current_fuel", math.max(0, currentFuel - fuelPerSecond * dt))
		end
	end
end)

return HelicopterDriveController
