local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local function setupPhysics(vehicle, main)
	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = false

			if item == main then
				item.CanCollide = true
				item.Massless = false
				item.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0, 1, 1)
			else
				item.CanCollide = false
				item.Massless = true
			end
		end
	end
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
		warn("[HelicopterDriveController] Driver_seat VehicleSeat not found:", vehicle.Name)
		return
	end

	setupPhysics(vehicle, main)

	main:SetNetworkOwner(ownerPlayer)

	activeHelicopters[vehicle] = {
		Main = main,
		Seat = seat,
		Owner = ownerPlayer,

		CurrentSpeed = 0,
		CurrentLift = 0,
		CurrentTurn = 0,
	}

	print("[HelicopterDriveController] Stable physical helicopter registered:", vehicle.Name)
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

		local speed = tonumber(getAttr(vehicle, "Speed", 120)) or 120
		local speedReverse = tonumber(getAttr(vehicle, "Speed_reverse", 40)) or 40
		local liftSpeed = tonumber(getAttr(vehicle, "Lift_speed", 40)) or 40
		local turnSpeed = tonumber(getAttr(vehicle, "Turn_speed", 1.5)) or 1.5
		local acceleration = tonumber(getAttr(vehicle, "Acceleration", 60)) or 60
		local fuelPerSecond = tonumber(getAttr(vehicle, "Fuel_per_second", 0.05)) or 0.05

		local throttle = seat.Throttle
		local steer = seat.Steer
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

		local targetLift = liftInput * liftSpeed
		local targetTurn = -steer * turnSpeed

		local speedStep = acceleration * dt
		local liftStep = acceleration * dt
		local turnStep = turnSpeed * dt * 4

		data.CurrentSpeed += math.clamp(targetSpeed - data.CurrentSpeed, -speedStep, speedStep)
		data.CurrentLift += math.clamp(targetLift - data.CurrentLift, -liftStep, liftStep)
		data.CurrentTurn += math.clamp(targetTurn - data.CurrentTurn, -turnStep, turnStep)

		local look = main.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)

		if flatLook.Magnitude < 0.1 then
			flatLook = Vector3.zAxis
		else
			flatLook = flatLook.Unit
		end

		main.AssemblyLinearVelocity = Vector3.new(
			flatLook.X * data.CurrentSpeed,
			data.CurrentLift,
			flatLook.Z * data.CurrentSpeed
		)

		main.AssemblyAngularVelocity = Vector3.new(
			0,
			data.CurrentTurn,
			0
		)

		local pos = main.Position
		local _, yaw, _ = main.CFrame:ToOrientation()
		local stableCFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)

		main.CFrame = stableCFrame

		if maxFuel > 0 and currentFuel > 0 then
			local moving =
				math.abs(data.CurrentSpeed) > 1
				or math.abs(data.CurrentLift) > 1
				or math.abs(data.CurrentTurn) > 0.05

			if moving then
				vehicle:SetAttribute("Current_fuel", math.max(0, currentFuel - fuelPerSecond * dt))
			end
		end
	end
end)

return HelicopterDriveController