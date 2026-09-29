local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

--[[
	CAMERA CONTROLLER — SINGLE SOURCE OF TRUTH
	==========================================

	This is the ONLY client file allowed to:
	- set CurrentCamera.CameraType / CameraSubject / CFrame / FieldOfView;
	- lock/unlock the mouse or hide/show the mouse cursor;
	- decide infantry / vehicle / aircraft camera position;
	- enter and leave optical sights.

	GAME RULE:
	The game is first-person only. There is no third-person vehicle camera.

	SIGHT SEQUENCE
	--------------
	1. RMB is pressed.
	2. CameraController determines what the player currently controls.
	3. Priority:
	   A) vehicle turret sight (implemented now);
	   B) infantry/rifle sight (reserved for later).
	4. The selected sight supplies a Sight BasePart and Zoom attribute.
	5. CameraSightMode is published on LocalPlayer:
	      "None"   = ordinary first person
	      "Turret" = turret optic
	      "Rifle"  = future infantry optic
	6. While a turret sight is active:
	   - camera position is exactly the Sight part;
	   - camera looks along Sight_axis;
	   - FOV is converted using optical Zoom;
	   - TurretClient reads CameraSightMode and uses AimDelta.
	7. RMB again, leaving the seat, losing the sight, or respawning exits sight.
	8. Future rifle sights MUST be integrated here. WeaponClient must never
	   manipulate the camera directly.
]]

local CAMERA_BIND_NAME = "GreyWarfareCameraController"
local CAMERA_PRIORITY = Enum.RenderPriority.Last.Value - 1

local DEFAULT_FOV = 70
local LOOK_SENSITIVITY = 0.0035

local MIN_PITCH = math.rad(-85)
local MAX_PITCH = math.rad(85)
local VEHICLE_MAX_YAW = math.rad(150)

-- Custom Soldier rig has no Head; Eyes is the camera anchor.
-- Infantry eye position uses the Eyes model/part when available.
local INFANTRY_EYE_LOCAL_OFFSET = Vector3.new(0, 0, 0)

-- Ground vehicle first-person position relative to Driver_seat.
-- Can be overridden by attributes on seat or vehicle:
-- FirstPerson_right / FirstPerson_height / FirstPerson_forward
local VEHICLE_RIGHT = 0
local VEHICLE_HEIGHT = 1.35
local VEHICLE_FORWARD = -0.15

-- Plane first-person position relative to Driver_seat when it exists.
-- Same attributes can override these defaults.
local PLANE_RIGHT = 0
local PLANE_HEIGHT = 1.35
local PLANE_FORWARD = -0.15

local yaw = 0
local pitch = 0
local vehicleYaw = 0
local vehiclePitch = 0

local lastContext = "None"
local lastSeat = nil

local sightMode = "None"
local activeSightModel = nil
local activeSightPart = nil
local baseFov = DEFAULT_FOV

local planeFreeLook = false
local planeLookYaw = 0
local planeLookPitch = 0

-- Q toggles mouse cursor release globally.
-- While released, mouse movement does not rotate the camera.
local cursorReleased = false

local function setPublishedSight(mode, zoom)
	sightMode = mode or "None"
	player:SetAttribute("CameraSightMode", sightMode)
	player:SetAttribute("CameraSightZoom", tonumber(zoom) or 1)
end

local function getCharacter()
	return player.Character
end

local function getHumanoid()
	local character = getCharacter()
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function getRoot()
	local character = getCharacter()
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function getEyesPart()
	local character = getCharacter()
	if not character then
		return nil
	end

	local eyes = character:FindFirstChild("Eyes")
	if not eyes then
		return nil
	end

	if eyes:IsA("BasePart") then
		return eyes
	end

	if eyes:IsA("Model") then
		if eyes.PrimaryPart and eyes.PrimaryPart:IsA("BasePart") then
			return eyes.PrimaryPart
		end
		return eyes:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

local function getSeat()
	local humanoid = getHumanoid()
	return humanoid and humanoid.SeatPart or nil
end

local function getVehicleFromSeat(seat)
	if not seat then
		return nil
	end

	local activeVehicles = workspace:FindFirstChild("ActiveVehicles")
	if not activeVehicles then
		return nil
	end

	local current = seat
	while current and current ~= workspace do
		if current:IsA("Model") and current.Parent == activeVehicles then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function isPlane(vehicle)
	return vehicle ~= nil
		and (
			vehicle:GetAttribute("Plane") == true
			or vehicle:GetAttribute("VehicleType") == "Plane"
		)
end

local function getContext()
	local seat = getSeat()
	local vehicle = getVehicleFromSeat(seat)

	if vehicle then
		if isPlane(vehicle) then
			return "Plane", seat, vehicle
		end
		return "Vehicle", seat, vehicle
	end

	return "Infantry", nil, nil
end

local function getNumberAttr(primary, secondary, name, default)
	local value = primary and primary:GetAttribute(name)
	if value == nil and secondary then
		value = secondary:GetAttribute(name)
	end
	if value == nil then
		return default
	end
	return tonumber(value) or default
end

local function setCharacterFirstPersonVisibility()
	local character = getCharacter()
	if not character then
		return
	end

	local body = character:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		body.LocalTransparencyModifier = 0
	end

	-- Camera can sit inside the custom rectangular Helmet.
	-- Hide only Helmet locally so it cannot cover the whole screen.
	local helmet = character:FindFirstChild("Helmet")
	if helmet and helmet:IsA("BasePart") then
		helmet.LocalTransparencyModifier = 1
	end
end

local function calculateZoomedFov(normalFov, zoom)
	zoom = math.max(1, tonumber(zoom) or 1)
	local halfAngle = math.rad(normalFov) * 0.5
	return math.deg(
		2 * math.atan(
			math.tan(halfAngle) / zoom
		)
	)
end

local function getTurretModels(vehicle)
	local result = {}
	if not vehicle then
		return result
	end

	local mountedModules = vehicle:FindFirstChild("MountedModules")
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

local function findTurretSight(vehicle)
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

local function findRifleSight()
	-- RESERVED FOR FUTURE RIFLE OPTICS.
	-- When rifle sights are added, resolve the equipped weapon's Sight model here
	-- and return: sightModel, sightPart.
	return nil, nil
end

local function exitSight()
	activeSightModel = nil
	activeSightPart = nil
	baseFov = DEFAULT_FOV
	setPublishedSight("None", 1)
end

local function tryEnterSight()
	local context, _, vehicle = getContext()

	if context == "Vehicle" then
		local sightModel, sightPart = findTurretSight(vehicle)
		if sightModel and sightPart then
			activeSightModel = sightModel
			activeSightPart = sightPart
			baseFov = camera.FieldOfView
			local zoom = tonumber(sightModel:GetAttribute("Zoom")) or 1
			setPublishedSight("Turret", zoom)
			return true
		end
	elseif context == "Infantry" then
		local sightModel, sightPart = findRifleSight()
		if sightModel and sightPart then
			activeSightModel = sightModel
			activeSightPart = sightPart
			baseFov = camera.FieldOfView
			local zoom = tonumber(sightModel:GetAttribute("Zoom")) or 1
			setPublishedSight("Rifle", zoom)
			return true
		end
	end

	return false
end

local function toggleSight()
	if sightMode ~= "None" then
		exitSight()
	else
		tryEnterSight()
	end
end

local function getSightForward(sightModel, sightPart)
	local sightAxis =
		sightPart:GetAttribute("Sight_axis")
		or sightModel:GetAttribute("Sight_axis")
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

	return sightPart.CFrame:VectorToWorldSpace(localForward).Unit
end

local function updateSightCamera()
	if sightMode == "None" then
		return false
	end

	if not activeSightModel
		or not activeSightModel.Parent
		or not activeSightPart
		or not activeSightPart.Parent
	then
		exitSight()
		return false
	end

	if sightMode == "Turret" then
		local context, _, vehicle = getContext()
		if context ~= "Vehicle" or not vehicle then
			exitSight()
			return false
		end
	elseif sightMode == "Rifle" then
		local context = getContext()
		if context ~= "Infantry" then
			exitSight()
			return false
		end
	end

	local forward = getSightForward(activeSightModel, activeSightPart)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(
		activeSightPart.Position,
		activeSightPart.Position + forward,
		activeSightPart.CFrame.UpVector
	)

	local zoom =
		tonumber(activeSightModel:GetAttribute("Zoom"))
		or tonumber(player:GetAttribute("CameraSightZoom"))
		or 1

	player:SetAttribute("CameraSightZoom", zoom)
	camera.FieldOfView = calculateZoomedFov(baseFov, zoom)

	return true
end

local function syncContext(context, seat)
	if context == lastContext and seat == lastSeat then
		return
	end

	-- A sight never survives a context/seat change.
	exitSight()

	lastContext = context
	lastSeat = seat
	vehicleYaw = 0
	vehiclePitch = 0
	planeLookYaw = 0
	planeLookPitch = 0

	if context ~= "Plane" then
		planeFreeLook = false
		player:SetAttribute("PlaneFreeLook", false)
	end

	if context == "Infantry" then
		local root = getRoot()
		if root then
			local look = root.CFrame.LookVector
			yaw = math.atan2(-look.X, -look.Z)
			pitch = 0
		end
	end
end

local function updateInfantryCamera(mouseDelta)
	local character = getCharacter()
	local root = getRoot()
	if not character or not root then
		return
	end

	yaw -= mouseDelta.X * LOOK_SENSITIVITY
	pitch = math.clamp(
		pitch - mouseDelta.Y * LOOK_SENSITIVITY,
		MIN_PITCH,
		MAX_PITCH
	)

	-- First-person body follows horizontal camera yaw.
	local rootPosition = root.Position
	root.CFrame =
		CFrame.new(rootPosition)
		* CFrame.Angles(0, yaw, 0)

	local eyesPart = getEyesPart()
	local helmet = character:FindFirstChild("Helmet")
	local eyePosition

	-- Eyes is the authoritative first-person camera anchor.
	if eyesPart then
		eyePosition = eyesPart.Position
	elseif helmet and helmet:IsA("BasePart") then
		-- Temporary fallback for characters that do not have Eyes yet.
		eyePosition =
			helmet.CFrame:PointToWorldSpace(
				INFANTRY_EYE_LOCAL_OFFSET
			)
	else
		eyePosition =
			root.Position
			+ Vector3.new(0, 0.65, 0)
	end

	local rotation =
		CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(pitch, 0, 0)

	camera.CFrame =
		CFrame.new(eyePosition)
		* rotation
end

local function updateVehicleCamera(seat, vehicle, mouseDelta)
	if not seat or not vehicle then
		return
	end

	vehicleYaw = math.clamp(
		vehicleYaw - mouseDelta.X * LOOK_SENSITIVITY,
		-VEHICLE_MAX_YAW,
		VEHICLE_MAX_YAW
	)

	vehiclePitch = math.clamp(
		vehiclePitch - mouseDelta.Y * LOOK_SENSITIVITY,
		MIN_PITCH,
		MAX_PITCH
	)

	-- IMPORTANT:
	-- Sitting must never move the camera origin to Driver_seat/Main/model pivot.
	-- The seated Soldier is carried by the seat, so Eyes remains the authoritative
	-- first-person camera position exactly as it is while on foot.
	local eyesPart = getEyesPart()
	local eyePosition = eyesPart and eyesPart.Position

	if not eyePosition then
		-- Fallback only for an incomplete character. This is intentionally based on
		-- the character, not on the vehicle, so the camera can never jump to a vehicle pivot.
		local root = getRoot()
		if root then
			eyePosition = root.Position + Vector3.new(0, 0.65, 0)
		else
			return
		end
	end

	-- Keep vehicle look relative to the seat orientation, but position it at Eyes.
	-- This preserves the existing vehicle orientation/costumes while fixing camera origin.
	local seatRotation = seat.CFrame.Rotation
	camera.CFrame =
		CFrame.new(eyePosition)
		* seatRotation
		* CFrame.Angles(0, vehicleYaw, 0)
		* CFrame.Angles(vehiclePitch, 0, 0)
end

local function getPlaneEye(seat, vehicle)
	-- Same first-person rule as every other context: camera origin is Soldier Eyes.
	local eyesPart = getEyesPart()
	if eyesPart then
		return eyesPart.Position
	end

	local root = getRoot()
	if root then
		return root.Position + Vector3.new(0, 0.65, 0)
	end

	-- Last-resort fallback for a broken/missing character only.
	if seat and seat:IsA("BasePart") then
		return seat.Position
	end

	local main = vehicle and vehicle:FindFirstChild("Main", true)
	if main and main:IsA("BasePart") then
		return main.Position
	end

	return vehicle:GetPivot().Position
end

local function updatePlaneCamera(seat, vehicle, mouseDelta)
	if not vehicle then
		return
	end

	local eyePosition = getPlaneEye(seat, vehicle)
	local pivot = vehicle:GetPivot()
	local forward = -pivot.RightVector
	local up = pivot.UpVector

	if planeFreeLook then
		planeLookYaw -= mouseDelta.X * LOOK_SENSITIVITY
		planeLookPitch = math.clamp(
			planeLookPitch - mouseDelta.Y * LOOK_SENSITIVITY,
			MIN_PITCH,
			MAX_PITCH
		)

		-- Build free-look around aircraft forward/up basis.
		local base = CFrame.lookAt(
			eyePosition,
			eyePosition + forward,
			up
		)

		camera.CFrame =
			base
			* CFrame.Angles(0, planeLookYaw, 0)
			* CFrame.Angles(planeLookPitch, 0, 0)
	else
		planeLookYaw = 0
		planeLookPitch = 0

		camera.CFrame = CFrame.lookAt(
			eyePosition,
			eyePosition + forward,
			up
		)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		toggleSight()
		return
	end

	if input.KeyCode == Enum.KeyCode.Q then
		cursorReleased = not cursorReleased
		player:SetAttribute("CameraCursorReleased", cursorReleased)

		if cursorReleased then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		else
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		end
		return
	end

	-- Plane free-look moved from Q to L.
	if input.KeyCode == Enum.KeyCode.L then
		local context = getContext()
		if context == "Plane" then
			planeFreeLook = not planeFreeLook
			player:SetAttribute("PlaneFreeLook", planeFreeLook)
		end
	end
end)

RunService:BindToRenderStep(
	CAMERA_BIND_NAME,
	CAMERA_PRIORITY,
	function()
		camera = workspace.CurrentCamera
		if not camera then
			return
		end

		local context, seat, vehicle = getContext()
		syncContext(context, seat)

		-- Single global first-person input policy.
		-- Q can release the cursor without giving camera ownership to another script.
		if cursorReleased then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		else
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		end

		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = DEFAULT_FOV

		setCharacterFirstPersonVisibility()

		if updateSightCamera() then
			return
		end

		local mouseDelta = cursorReleased and Vector2.zero or UserInputService:GetMouseDelta()

		if context == "Vehicle" then
			updateVehicleCamera(seat, vehicle, mouseDelta)
		elseif context == "Plane" then
			updatePlaneCamera(seat, vehicle, mouseDelta)
		else
			updateInfantryCamera(mouseDelta)
		end
	end
)

player.CharacterAdded:Connect(function()
	exitSight()
	lastContext = "None"
	lastSeat = nil
	yaw = 0
	pitch = 0
	vehicleYaw = 0
	vehiclePitch = 0
	planeLookYaw = 0
	planeLookPitch = 0
	planeFreeLook = false
	cursorReleased = false
	player:SetAttribute("PlaneFreeLook", false)
	player:SetAttribute("CameraCursorReleased", false)
end)

setPublishedSight("None", 1)
player:SetAttribute("PlaneFreeLook", false)
player:SetAttribute("CameraCursorReleased", false)
