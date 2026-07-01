local RunService = game:GetService("RunService")

local HelicopterDriveController = {}

local activeHelicopters = {}

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

	main:SetNetworkOwner(ownerPlayer)

	activeHelicopters[vehicle] = {
		Main = main,
		Seat = seat,
		Owner = ownerPlayer,

		CurrentForwardSpeed = 0,
		CurrentTurn = 0,
		TargetHeight = main.Position.Y,
	}

	print("[HelicopterDriveController] Helicopter registered:", vehicle.Name)
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

		local currentFuel = tonumber(vehicle:GetAttribute("Current_fuel")) or 0
		local maxFuel = tonumber(vehicle:GetAttribute("Max_fuel")) or 0

		local speed = tonumber(getAttr(vehicle, "Speed", 80)) or 80
		local speedReverse = tonumber(getAttr(vehicle, "Speed_reverse", 30)) or 30
		local acceleration = tonumber(getAttr(vehicle, "Acceleration", 40)) or 40
		local turnSpeed = tonumber(getAttr(vehicle, "Turn_speed", 2)) or 2
		local liftSpeed = tonumber(getAttr(vehicle, "Lift_speed", 25)) or 25
		local hoverPower = tonumber(getAttr(vehicle, "Hover_power", 8)) or 8
		local fuelPerSecond = tonumber(getAttr(vehicle, "Fuel_per_second", 0.05)) or 0.05

		local throttle = seat.Throttle
		local steer = seat.Steer

		if currentFuel <= 0 then
			throttle = 0
			steer = 0
		end

		local targetForwardSpeed = 0

		if throttle > 0 then
			targetForwardSpeed = speed
			data.TargetHeight += liftSpeed * dt
		elseif throttle < 0 then
			targetForwardSpeed = -speedReverse
			data.TargetHeight -= liftSpeed * dt
		end

		data.TargetHeight = math.max(6, data.TargetHeight)

		local speedStep = acceleration * dt

		if data.CurrentForwardSpeed < targetForwardSpeed then
			data.CurrentForwardSpeed = math.min(data.CurrentForwardSpeed + speedStep, targetForwardSpeed)
		elseif data.CurrentForwardSpeed > targetForwardSpeed then
			data.CurrentForwardSpeed = math.max(data.CurrentForwardSpeed - speedStep, targetForwardSpeed)
		end

		local targetTurn = steer * turnSpeed

		if data.CurrentTurn < targetTurn then
			data.CurrentTurn = math.min(data.CurrentTurn + turnSpeed * dt, targetTurn)
		elseif data.CurrentTurn > targetTurn then
			data.CurrentTurn = math.max(data.CurrentTurn - turnSpeed * dt, targetTurn)
		end

		local forward = main.CFrame.LookVector
		local currentVelocity = main.AssemblyLinearVelocity

		local heightError = data.TargetHeight - main.Position.Y
		local verticalVelocity = math.clamp(heightError * hoverPower, -liftSpeed, liftSpeed)

		main.AssemblyLinearVelocity = Vector3.new(
			forward.X * data.CurrentForwardSpeed,
			verticalVelocity,
			forward.Z * data.CurrentForwardSpeed
		)

		main.AssemblyAngularVelocity = Vector3.new(
			0,
			-data.CurrentTurn,
			0
		)

		local look = main.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)

		if flatLook.Magnitude > 0.1 then
			local pos = main.Position
			local targetCFrame = CFrame.lookAt(pos, pos + flatLook.Unit)
			main.CFrame = main.CFrame:Lerp(targetCFrame, math.clamp(dt * 4, 0, 1))
		end

		if maxFuel > 0 and currentFuel > 0 then
			local moving = math.abs(data.CurrentForwardSpeed) > 1 or math.abs(data.CurrentTurn) > 0.05
			local hovering = main.Position.Y > 5

			if moving or hovering then
				local used = fuelPerSecond * dt
				local newFuel = math.max(0, currentFuel - used)
				vehicle:SetAttribute("Current_fuel", newFuel)
			end
		end
	end
end)

return HelicopterDriveController