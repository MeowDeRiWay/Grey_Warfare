local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local turretRemote =
	ReplicatedStorage:WaitForChild("TurretActionRequest")

local AIM_SEND_RATE = 0.05
local FIRE_SEND_RATE = 0.05

local aimAccumulator = 0
local fireAccumulator = 0
local firing = false

-- Sight camera state
local sightMode = false
local activeSightModel = nil
local activeSightPart = nil

local savedCameraType = nil
local savedCameraSubject = nil
local savedFieldOfView = nil
local savedMouseBehavior = nil
local savedMouseIconEnabled = nil

-- Vehicle camera state.
-- Roblox default camera still expects RMB for rotation, so LockCenter alone is not enough.
-- While seated in ActiveVehicles we run our own Scriptable orbit camera from MouseDelta.
local vehicleCameraActive = false
local vehicleCameraVehicle = nil

local vehicleCameraYaw = 0
local vehicleCameraPitch = math.rad(-12)
local vehicleCameraDistance = 12

local savedVehicleCameraType = nil
local savedVehicleCameraSubject = nil
local savedVehicleCameraFov = nil
local savedVehicleMouseBehavior = nil
local savedVehicleMouseIconEnabled = nil

local CAMERA_SENSITIVITY = 0.0035
local CAMERA_MIN_PITCH = math.rad(-75)
local CAMERA_MAX_PITCH = math.rad(75)

local function getVehicleCameraTarget(vehicle)
	if not vehicle then
		return nil
	end

	local main = vehicle:FindFirstChild("Main", true)
	if main and main:IsA("BasePart") then
		return main
	end

	if vehicle.PrimaryPart and vehicle.PrimaryPart:IsA("BasePart") then
		return vehicle.PrimaryPart
	end

	local seat = vehicle:FindFirstChild("Driver_seat", true)
		or vehicle:FindFirstChild("VehicleSeat", true)

	if seat and seat:IsA("BasePart") then
		return seat
	end

	return vehicle:FindFirstChildWhichIsA("BasePart", true)
end

local function enterVehicleCamera(vehicle)
	if vehicleCameraActive then
		vehicleCameraVehicle = vehicle
		return
	end

	local targetPart = getVehicleCameraTarget(vehicle)
	if not targetPart then
		return
	end

	vehicleCameraActive = true
	vehicleCameraVehicle = vehicle

	savedVehicleCameraType = camera.CameraType
	savedVehicleCameraSubject = camera.CameraSubject
	savedVehicleCameraFov = camera.FieldOfView
	savedVehicleMouseBehavior = UserInputService.MouseBehavior
	savedVehicleMouseIconEnabled = UserInputService.MouseIconEnabled

	local cameraHeight =
		tonumber(vehicle:GetAttribute("Camera_height"))
		or 2.5

	local focus =
		targetPart.Position
		+ Vector3.new(0, cameraHeight, 0)

	local offset = camera.CFrame.Position - focus
	local distance = offset.Magnitude

	if distance < 1 then
		distance =
			tonumber(vehicle:GetAttribute("Camera_distance"))
			or 12
	end

	vehicleCameraDistance = math.clamp(
		distance,
		tonumber(vehicle:GetAttribute("Camera_min_distance")) or 5,
		tonumber(vehicle:GetAttribute("Camera_max_distance")) or 35
	)

	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude > 0.001 then
		vehicleCameraYaw = math.atan2(offset.X, offset.Z)
	end

	if distance > 0.001 then
		vehicleCameraPitch = math.asin(
			math.clamp(offset.Y / distance, -1, 1)
		)
	end

	vehicleCameraPitch =
		math.clamp(
			vehicleCameraPitch,
			CAMERA_MIN_PITCH,
			CAMERA_MAX_PITCH
		)

	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
end

local function exitVehicleCamera()
	if not vehicleCameraActive then
		return
	end

	vehicleCameraActive = false
	vehicleCameraVehicle = nil

	camera.CameraType =
		savedVehicleCameraType
		or Enum.CameraType.Custom

	if savedVehicleCameraSubject then
		camera.CameraSubject = savedVehicleCameraSubject
	end

	if savedVehicleCameraFov then
		camera.FieldOfView = savedVehicleCameraFov
	end

	UserInputService.MouseBehavior =
		savedVehicleMouseBehavior
		or Enum.MouseBehavior.Default

	if savedVehicleMouseIconEnabled ~= nil then
		UserInputService.MouseIconEnabled =
			savedVehicleMouseIconEnabled
	else
		UserInputService.MouseIconEnabled = true
	end

	savedVehicleCameraType = nil
	savedVehicleCameraSubject = nil
	savedVehicleCameraFov = nil
	savedVehicleMouseBehavior = nil
	savedVehicleMouseIconEnabled = nil
end

local function updateVehicleCamera(vehicle, mouseDelta)
	if not vehicleCameraActive or sightMode then
		return
	end

	local targetPart = getVehicleCameraTarget(vehicle)
	if not targetPart then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	mouseDelta = mouseDelta or Vector2.zero

	local sensitivity =
		tonumber(vehicle:GetAttribute("Camera_sensitivity"))
		or CAMERA_SENSITIVITY

	vehicleCameraYaw -= mouseDelta.X * sensitivity
	vehicleCameraPitch -= mouseDelta.Y * sensitivity

	vehicleCameraPitch =
		math.clamp(
			vehicleCameraPitch,
			CAMERA_MIN_PITCH,
			CAMERA_MAX_PITCH
		)

	local cameraHeight =
		tonumber(vehicle:GetAttribute("Camera_height"))
		or 2.5

	local focus =
		targetPart.Position
		+ Vector3.new(0, cameraHeight, 0)

	local rotation =
		CFrame.fromEulerAnglesYXZ(
			vehicleCameraPitch,
			vehicleCameraYaw,
			0
		)

	local offset =
		rotation:VectorToWorldSpace(
			Vector3.new(0, 0, vehicleCameraDistance)
		)

	local desiredPosition = focus + offset

	-- Camera collision: do not let the camera sit behind a wall.
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local exclude = { vehicle }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	rayParams.FilterDescendantsInstances = exclude

	local result =
		workspace:Raycast(
			focus,
			desiredPosition - focus,
			rayParams
		)

	local cameraPosition = desiredPosition

	if result then
		local direction =
			(desiredPosition - focus).Unit

		cameraPosition =
			result.Position
			- direction * 0.35
	end

	camera.CFrame =
		CFrame.lookAt(
			cameraPosition,
			focus
		)
end

local function getControlledVehicle()
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid =
		character:FindFirstChildOfClass("Humanoid")

	if not humanoid then
		return nil
	end

	local seat = humanoid.SeatPart
	if not seat then
		return nil
	end

	local activeVehicles =
		workspace:FindFirstChild("ActiveVehicles")

	if not activeVehicles then
		return nil
	end

	local current = seat

	while current and current ~= workspace do
		if current:IsA("Model")
			and current.Parent == activeVehicles
		then
			-- Літаки мають власний PlaneClient, який повністю керує
			-- камерою та мишкою. TurretClient не повинен перехоплювати
			-- Scriptable camera для Plane=true / VehicleType="Plane".
			if current:GetAttribute("Plane") == true
				or current:GetAttribute("VehicleType") == "Plane"
			then
				return nil
			end

			return current
		end

		current = current.Parent
	end

	return nil
end

local function getTurretModels(vehicle)
	local result = {}

	local mountedModules =
		vehicle:FindFirstChild("MountedModules")

	if not mountedModules then
		return result
	end

	for _, item in ipairs(mountedModules:GetDescendants()) do
		if item:IsA("Model")
			and (
				item:GetAttribute("ModuleRole") == "Turret"
				or item:GetAttribute("Turret") == true
			)
		then
			table.insert(result, item)
		end
	end

	return result
end

local function vehicleHasTurret(vehicle)
	return #getTurretModels(vehicle) > 0
end

local function canControlTurret()
	local vehicle = getControlledVehicle()

	if not vehicle then
		return nil
	end

	if not vehicleHasTurret(vehicle) then
		return nil
	end

	return vehicle
end

local function findSight(vehicle)
	for _, turret in ipairs(getTurretModels(vehicle)) do
		local sight = turret:FindFirstChild("Sight", true)

		if sight and sight:IsA("Model") then
			local sightPart =
				sight.PrimaryPart
				or sight:FindFirstChildWhichIsA("BasePart", true)

			if sightPart then
				return sight, sightPart
			end
		end
	end

	return nil, nil
end

local function calculateZoomedFov(baseFov, zoom)
	zoom = math.max(1, tonumber(zoom) or 1)

	-- Справжнє оптичне збільшення:
	-- zoom x2 не просто ділить FOV навпіл,
	-- а перераховує його через кут огляду.
	local halfAngle =
		math.rad(baseFov) * 0.5

	return math.deg(
		2 * math.atan(
			math.tan(halfAngle) / zoom
		)
	)
end

local function exitSightMode()
	if not sightMode then
		return
	end

	sightMode = false
	activeSightModel = nil
	activeSightPart = nil

	if savedCameraType then
		camera.CameraType = savedCameraType
	end

	if savedCameraSubject then
		camera.CameraSubject = savedCameraSubject
	end

	if savedFieldOfView then
		camera.FieldOfView = savedFieldOfView
	end

	if savedMouseBehavior then
		UserInputService.MouseBehavior = savedMouseBehavior
	end

	if savedMouseIconEnabled ~= nil then
		UserInputService.MouseIconEnabled = savedMouseIconEnabled
	end

	savedCameraType = nil
	savedCameraSubject = nil
	savedFieldOfView = nil
	savedMouseBehavior = nil
	savedMouseIconEnabled = nil
end

local function enterSightMode()
	local vehicle = canControlTurret()

	if not vehicle then
		return
	end

	local sightModel, sightPart =
		findSight(vehicle)

	if not sightModel or not sightPart then
		warn(
			"[TurretClient] Sight model or Sight part not found"
		)
		return
	end

	savedCameraType = camera.CameraType
	savedCameraSubject = camera.CameraSubject
	savedFieldOfView = camera.FieldOfView
	savedMouseBehavior = UserInputService.MouseBehavior
	savedMouseIconEnabled = UserInputService.MouseIconEnabled

	activeSightModel = sightModel
	activeSightPart = sightPart
	sightMode = true

	local zoom =
		tonumber(sightModel:GetAttribute("Zoom")) or 1

	camera.CameraType = Enum.CameraType.Scriptable

	-- У Sight режимі миша більше не задає Mouse.Hit.
	-- Вона фіксується по центру, а башта керується MouseDelta.
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	camera.FieldOfView =
		calculateZoomedFov(
			savedFieldOfView,
			zoom
		)
end

local function toggleSightMode()
	if sightMode then
		exitSightMode()
	else
		enterSightMode()
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not canControlTurret() then
			return
		end

		firing = true
		fireAccumulator = 0

		-- Перший постріл без затримки.
		turretRemote:FireServer("Fire")

	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		toggleSightMode()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = false
	end
end)

player.CharacterAdded:Connect(function()
	exitSightMode()
	exitVehicleCamera()
end)

RunService.RenderStepped:Connect(function(dt)
	aimAccumulator += dt
	fireAccumulator += dt

	-- Camera/free-look is tied to being in a vehicle, NOT to having a turret.
	local controlledVehicle = getControlledVehicle()

	-- IMPORTANT:
	-- read MouseDelta ONCE and feed the same input both to camera and turret.
	-- This guarantees that the turret follows the player's look even with
	-- the cursor locked in the center.
	local frameMouseDelta = UserInputService:GetMouseDelta()

	if controlledVehicle then
		if not vehicleCameraActive then
			enterVehicleCamera(controlledVehicle)
		else
			vehicleCameraVehicle = controlledVehicle
		end

		if not sightMode then
			updateVehicleCamera(controlledVehicle, frameMouseDelta)
		end
	else
		if sightMode then
			exitSightMode()
		end
		exitVehicleCamera()
	end

	local vehicle = canControlTurret()

	if not vehicle then
		firing = false

		if sightMode then
			exitSightMode()
		end

		return
	end

	if sightMode then
		if not activeSightModel
			or not activeSightModel.Parent
			or not activeSightPart
			or not activeSightPart.Parent
		then
			exitSightMode()
		else
			-- Sight camera standard:
			-- visual forward of the normalized Sight model = local -X.
			-- Keep camera position exactly at the Sight part, but look along
			-- the actual sight forward instead of Roblox LookVector (-Z).
			local sightAxis =
				activeSightPart:GetAttribute("Sight_axis")
				or activeSightModel:GetAttribute("Sight_axis")
				or "-X"

			local localForward
			if sightAxis == "X" then
				localForward = Vector3.xAxis
			elseif sightAxis == "-X" then
				localForward = -Vector3.xAxis
			elseif sightAxis == "Y" then
				localForward = Vector3.yAxis
			elseif sightAxis == "-Y" then
				localForward = -Vector3.yAxis
			elseif sightAxis == "Z" then
				localForward = Vector3.zAxis
			else
				localForward = -Vector3.zAxis
			end

			local forward =
				activeSightPart.CFrame:VectorToWorldSpace(localForward).Unit

			camera.CFrame =
				CFrame.lookAt(
					activeSightPart.Position,
					activeSightPart.Position + forward,
					activeSightPart.CFrame.UpVector
				)

			local zoom =
				tonumber(
					activeSightModel:GetAttribute("Zoom")
				) or 1

			camera.FieldOfView =
				calculateZoomedFov(
					savedFieldOfView or 70,
					zoom
				)
		end
	end

	if sightMode then
		-- Важливо: НЕ використовуємо mouse.Hit у Sight.
		-- Інакше виходить feedback loop:
		-- башта рухає камеру -> Mouse.Hit зміщується ->
		-- башта знову рухається і постійно задирається.
		local mouseDelta = frameMouseDelta

		if mouseDelta.Magnitude > 0 then
			local zoom =
				tonumber(
					activeSightModel:GetAttribute("Zoom")
				) or 1

			zoom = math.max(1, zoom)

			-- При великому zoom рух робимо точнішим.
			turretRemote:FireServer(
				"AimDelta",
				mouseDelta / zoom
			)
		end

	else
		-- Third-person aiming should follow the CAMERA CENTER, not raw MouseDelta.
		-- MouseDelta can drift relative to the orbit camera because camera
		-- sensitivity and turret sensitivity are different.
		--
		-- Now that the turret anchoring problem is fixed, world-space Aim is
		-- the correct source of truth for third person.
		if aimAccumulator >= AIM_SEND_RATE then
			aimAccumulator = 0

			local viewportSize = camera.ViewportSize
			local centerRay = camera:ViewportPointToRay(
				viewportSize.X * 0.5,
				viewportSize.Y * 0.5
			)

			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude

			local exclude = {}
			if player.Character then
				table.insert(exclude, player.Character)
			end
			if vehicle then
				table.insert(exclude, vehicle)
			end
			rayParams.FilterDescendantsInstances = exclude

			local maxAimDistance =
				tonumber(vehicle:GetAttribute("Turret_aim_distance"))
				or 20000

			local rayResult = workspace:Raycast(
				centerRay.Origin,
				centerRay.Direction * maxAimDistance,
				rayParams
			)

			local aimPoint
			if rayResult then
				aimPoint = rayResult.Position
			else
				aimPoint =
					centerRay.Origin
					+ centerRay.Direction * maxAimDistance
			end

			turretRemote:FireServer(
				"Aim",
				aimPoint
			)
		end
	end

	if firing and fireAccumulator >= FIRE_SEND_RATE then
		fireAccumulator = 0
		turretRemote:FireServer("Fire")
	end
end)
