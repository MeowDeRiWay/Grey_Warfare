local RunService = game:GetService("RunService")

local VehicleDriveController = {}

local activeVehicles = {}

local function getAttr(vehicle, name, fallback)
	local value = vehicle:GetAttribute(name)

	if value == nil then
		return fallback
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

local function getConfig(vehicle)
	return {
		Speed = getAttr(vehicle, "Speed"),
		Speed_reverse = getAttr(vehicle, "Speed_reverse"),

		Acceleration = getAttr(vehicle, "Acceleration"),
		Brake_force = getAttr(vehicle, "Brake_force"),

		Steer_angle = getAttr(vehicle, "Steer_angle"),
		Steer_speed = getAttr(vehicle, "Steer_speed"),

		Suspension_force = getAttr(vehicle, "Suspension_force"),
		Suspension_damping = getAttr(vehicle, "Suspension_damping"),
		Suspension_height = getAttr(vehicle, "Suspension_height"),

		Flip_force = getAttr(vehicle, "Flip_force"),
		Flip_time = getAttr(vehicle, "Flip_time"),
		Can_flip = getAttr(vehicle, "Can_flip"),
	}
end

function VehicleDriveController.RegisterVehicle(vehicle, ownerPlayer)
	local main = getMain(vehicle)
	local seat = getDriverSeat(vehicle)

	if not main then
		warn("[VehicleDriveController] Main not found:", vehicle.Name)
		return
	end

	if not seat then
		warn("[VehicleDriveController] Driver_seat VehicleSeat not found:", vehicle.Name)
		return
	end

	main:SetNetworkOwner(ownerPlayer)

	activeVehicles[vehicle] = {
		Main = main,
		Seat = seat,
		Owner = ownerPlayer,

		CurrentSpeed = 0,
		CurrentSteer = 0,
		FlippedTime = 0,
	}

	print("[VehicleDriveController] Vehicle registered:", vehicle.Name)
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

		local cfg = getConfig(vehicle)

		local throttle = seat.Throttle
		local steer = seat.Steer

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

		if data.CurrentSpeed < targetSpeed then
			data.CurrentSpeed = math.min(data.CurrentSpeed + speedStep, targetSpeed)
		elseif data.CurrentSpeed > targetSpeed then
			data.CurrentSpeed = math.max(data.CurrentSpeed - speedStep, targetSpeed)
		end

		local targetSteer = steer
		local steerStep = cfg.Steer_speed * dt

		if data.CurrentSteer < targetSteer then
			data.CurrentSteer = math.min(data.CurrentSteer + steerStep, targetSteer)
		elseif data.CurrentSteer > targetSteer then
			data.CurrentSteer = math.max(data.CurrentSteer - steerStep, targetSteer)
		end

		local forward = main.CFrame.LookVector
		local currentVelocity = main.AssemblyLinearVelocity

		main.AssemblyLinearVelocity = Vector3.new(
			forward.X * data.CurrentSpeed,
			currentVelocity.Y,
			forward.Z * data.CurrentSpeed
		)

		local steerPower = math.rad(cfg.Steer_angle) * data.CurrentSteer

		main.AssemblyAngularVelocity = Vector3.new(
			main.AssemblyAngularVelocity.X,
			-steerPower,
			main.AssemblyAngularVelocity.Z
		)

		if cfg.Can_flip == true then
			local upDot = main.CFrame.UpVector:Dot(Vector3.yAxis)

			if upDot < 0.35 then
				data.FlippedTime += dt
			else
				data.FlippedTime = 0
			end

			if data.FlippedTime >= cfg.Flip_time then
				local pos = main.Position
				local look = main.CFrame.LookVector
				local flatLook = Vector3.new(look.X, 0, look.Z)

				if flatLook.Magnitude < 0.1 then
					flatLook = Vector3.zAxis
				else
					flatLook = flatLook.Unit
				end

				main.AssemblyAngularVelocity = Vector3.zero
				main.AssemblyLinearVelocity = Vector3.new(0, 8, 0)
				main.CFrame = CFrame.lookAt(pos + Vector3.new(0, 2, 0), pos + flatLook + Vector3.new(0, 2, 0))

				data.CurrentSpeed = 0
				data.CurrentSteer = 0
				data.FlippedTime = 0

				print("[VehicleDriveController] Vehicle flipped back:", vehicle.Name)
			end
		end
	end
end)

return VehicleDriveController