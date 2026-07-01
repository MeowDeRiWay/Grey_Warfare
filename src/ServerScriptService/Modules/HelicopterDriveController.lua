local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HelicopterDriveController = {}

local activeHelicopters = {}
local playerInput = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local helicopterControlRemote = remotes:WaitForChild("HelicopterControl")

local DEFAULT_FALL_SPEED = -35
local TOUCH_CHECK_INTERVAL = 0.08

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

local function isOwnPart(vehicle, part)
	return part and part:IsDescendantOf(vehicle)
end

local function touchesWorld(vehicle, landingPart)
	if not landingPart or not landingPart.Parent then
		return false
	end

	for _, part in ipairs(landingPart:GetTouchingParts()) do
		if part:IsA("BasePart") and not isOwnPart(vehicle, part) and part.CanCollide then
			return true
		end
	end

	return false
end

local function setAnchored(vehicle, anchored)
	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = anchored
		end
	end
end

local function setupPhysics(vehicle, main, landingPart)
	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = false
			item.CanTouch = true

			if item == main then
				item.CanCollide = true
				item.Massless = false
				item.CustomPhysicalProperties = PhysicalProperties.new(1, 0.35, 0, 1, 1)
			elseif item == landingPart then
				item.CanCollide = true
				item.Massless = true
				item.CustomPhysicalProperties = PhysicalProperties.new(1, 0.4, 0, 1, 1)
			else
				item.CanCollide = false
				item.Massless = true
			end
		end
	end
end

local function hasDriver(seat)
	if not seat then
		return false
	end

	return seat.Occupant ~= nil
end

helicopterControlRemote.OnServerEvent:Connect(function(player, input)
	if typeof(input) ~= "table" then
		return
	end

	playerInput[player] = {
		Lift = math.clamp(tonumber(input.Lift) or 0, 0, 1),
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

	local landingPart = getLandingPart(vehicle, main)

	setupPhysics(vehicle, main, landingPart)

	pcall(function()
		main:SetNetworkOwner(ownerPlayer)
	end)

	activeHelicopters[vehicle] = {
		Main = main,
		Seat = seat,
		LandingPart = landingPart,
		Owner = ownerPlayer,

		CurrentSpeed = 0,
		CurrentTurn = 0,
		HoverY = main.Position.Y,
		IsLanded = false,
		TouchTimer = 0,
	}

	print("[HelicopterDriveController] Arcade helicopter registered:", vehicle.Name)
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
		local owner = data.Owner

		if not main or not main.Parent or not seat or not seat.Parent then
			activeHelicopters[vehicle] = nil
			continue
		end

		local currentFuel = tonumber(vehicle:GetAttribute("Current_fuel")) or 0
		local maxFuel = tonumber(vehicle:GetAttribute("Max_fuel")) or 0

		local speed = tonumber(getAttr(vehicle, "Speed", 90)) or 90
		local speedReverse = tonumber(getAttr(vehicle, "Speed_reverse", 30)) or 30
		local liftSpeed = tonumber(getAttr(vehicle, "Lift_speed", 28)) or 28
		local turnSpeed = tonumber(getAttr(vehicle, "Turn_speed", 1.4)) or 1.4
		local acceleration = tonumber(getAttr(vehicle, "Acceleration", 55)) or 55
		local fuelPerSecond = tonumber(getAttr(vehicle, "Fuel_per_second", 0.05)) or 0.05
		local fallSpeed = tonumber(getAttr(vehicle, "Fall_speed", DEFAULT_FALL_SPEED)) or DEFAULT_FALL_SPEED

		local driverInside = hasDriver(seat)

		if not driverInside then
			data.CurrentSpeed = 0
			data.CurrentTurn = 0

			if data.IsLanded then
				main.AssemblyLinearVelocity = Vector3.zero
				main.AssemblyAngularVelocity = Vector3.zero
				continue
			end

			setAnchored(vehicle, false)

			data.TouchTimer += dt
			if data.TouchTimer >= TOUCH_CHECK_INTERVAL then
				data.TouchTimer = 0

				if touchesWorld(vehicle, landingPart) then
					data.IsLanded = true
					main.AssemblyLinearVelocity = Vector3.zero
					main.AssemblyAngularVelocity = Vector3.zero
					setAnchored(vehicle, true)
					continue
				end
			end

			local pos = main.Position
			local _, yaw, _ = main.CFrame:ToOrientation()

			main.AssemblyLinearVelocity = Vector3.new(0, fallSpeed, 0)
			main.AssemblyAngularVelocity = Vector3.zero
			main.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)

			continue
		end

		if data.IsLanded or main.Anchored then
			data.IsLanded = false
			setAnchored(vehicle, false)
			data.HoverY = main.Position.Y
		end

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

		local targetTurn = -steer * turnSpeed

		local speedStep = acceleration * dt
		local turnStep = turnSpeed * dt * 4

		data.CurrentSpeed += math.clamp(targetSpeed - data.CurrentSpeed, -speedStep, speedStep)
		data.CurrentTurn += math.clamp(targetTurn - data.CurrentTurn, -turnStep, turnStep)

		local pos = main.Position
		local _, yaw, _ = main.CFrame:ToOrientation()

		local newY = data.HoverY
		local yVelocity = 0

		if liftInput > 0 then
			newY = pos.Y + (liftSpeed * liftInput * dt)
			data.HoverY = newY
			yVelocity = liftSpeed * liftInput
		end

		local stableCFrame = CFrame.new(pos.X, newY, pos.Z) * CFrame.Angles(0, yaw, 0)
		main.CFrame = stableCFrame

		local look = stableCFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)

		if flatLook.Magnitude < 0.1 then
			flatLook = Vector3.zAxis
		else
			flatLook = flatLook.Unit
		end

		main.AssemblyLinearVelocity = Vector3.new(
			flatLook.X * data.CurrentSpeed,
			yVelocity,
			flatLook.Z * data.CurrentSpeed
		)

		main.AssemblyAngularVelocity = Vector3.new(0, data.CurrentTurn, 0)

		if maxFuel > 0 and currentFuel > 0 then
			local moving =
				math.abs(data.CurrentSpeed) > 1
				or math.abs(yVelocity) > 1
				or math.abs(data.CurrentTurn) > 0.05

			if moving then
				vehicle:SetAttribute("Current_fuel", math.max(0, currentFuel - fuelPerSecond * dt))
			end
		end
	end
end)

return HelicopterDriveController
