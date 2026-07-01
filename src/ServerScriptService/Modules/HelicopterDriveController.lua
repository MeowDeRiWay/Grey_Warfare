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

	main:SetNetworkOwner(nil)
	main.Anchored = true

	activeHelicopters[vehicle] = {
		Main = main,
		Seat = seat,
		Owner = ownerPlayer,

		Yaw = main.Orientation.Y,
		Velocity = Vector3.zero,
	}

	print("[HelicopterDriveController] Arcade helicopter registered:", vehicle.Name)
end

function HelicopterDriveController.UnregisterVehicle(vehicle)
	local data = activeHelicopters[vehicle]

	if data and data.Main and data.Main.Parent then
		data.Main.Anchored = false
	end

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

		local speed = tonumber(getAttr(vehicle, "Speed", 120)) or 120
		local speedReverse = tonumber(getAttr(vehicle, "Speed_reverse", 40)) or 40
		local strafeSpeed = tonumber(getAttr(vehicle, "Strafe_speed", 60)) or 60
		local liftSpeed = tonumber(getAttr(vehicle, "Lift_speed", 40)) or 40
		local turnSpeed = tonumber(getAttr(vehicle, "Turn_speed", 2)) or 2
		local acceleration = tonumber(getAttr(vehicle, "Acceleration", 80)) or 80
		local fuelPerSecond = tonumber(getAttr(vehicle, "Fuel_per_second", 0.05)) or 0.05

		local throttle = seat.Throttle
		local steer = seat.Steer

		if currentFuel <= 0 then
			throttle = 0
			steer = 0
		end

		data.Yaw -= steer * turnSpeed * 60 * dt

		local yawCFrame = CFrame.Angles(0, math.rad(data.Yaw), 0)
		local forward = yawCFrame.LookVector
		local right = yawCFrame.RightVector

		local targetVelocity = Vector3.zero

		if throttle > 0 then
			targetVelocity += forward * speed
			targetVelocity += Vector3.yAxis * liftSpeed
		elseif throttle < 0 then
			targetVelocity -= forward * speedReverse
			targetVelocity -= Vector3.yAxis * liftSpeed
		end

		local alpha = math.clamp(acceleration * dt / math.max(speed, 1), 0, 1)
		data.Velocity = data.Velocity:Lerp(targetVelocity, alpha)

		local newPosition = main.Position + data.Velocity * dt

		if newPosition.Y < 1 then
			newPosition = Vector3.new(newPosition.X, 5, newPosition.Z)
			data.Velocity = Vector3.new(data.Velocity.X, 0, data.Velocity.Z)
		end

		vehicle:PivotTo(
			CFrame.new(newPosition) * CFrame.Angles(0, math.rad(data.Yaw), 0)
		)

		if maxFuel > 0 and currentFuel > 0 then
			local moving = data.Velocity.Magnitude > 0.5

			if moving then
				local used = fuelPerSecond * dt
				vehicle:SetAttribute("Current_fuel", math.max(0, currentFuel - used))
			end
		end
	end
end)

return HelicopterDriveController