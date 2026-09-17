local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WarehouseManager = require(script.Parent.WarehouseManager)
local ProjectileManager = require(script.Parent.ProjectileManager)

local RocketLauncherController = {}

local ACTIVE_VEHICLES_FOLDER_NAME = "ActiveVehicles"
local AIRCRAFT_FIRE_REMOTE_NAME = "AircraftWeaponAction"

-- Real project ammo layout.
local AMMO_FOLDERS = {
	{ Family = "Vehicles", Folder = "VAmmo" },
	{ Family = "Heli", Folder = "HAmmo" },
	{ Family = "Planes", Folder = "PAmmo" },
}

-- Global delay from pressing Fire until the rocket physically leaves the tube.
local LAUNCH_DELAY = 1

local registeredLaunchers = {}
local started = false

-- While a plane is occupied, PlaneClient moves it visually on the pilot's client.
-- The server-side model can therefore remain near its spawn position.
-- AircraftWeaponClient streams the current visual vehicle pivot here so rockets
-- can be reconstructed from the aircraft's ACTUAL visible position/orientation.
local aircraftPoseByPlayer = {}
local AIRCRAFT_POSE_TIMEOUT = 0.35

local function axisToLocalVector(axis)
	axis = tostring(axis or "-Z")

	if axis == "X" then
		return Vector3.xAxis
	elseif axis == "-X" then
		return -Vector3.xAxis
	elseif axis == "Y" then
		return Vector3.yAxis
	elseif axis == "-Y" then
		return -Vector3.yAxis
	elseif axis == "Z" then
		return Vector3.zAxis
	elseif axis == "-Z" then
		return -Vector3.zAxis
	end

	return -Vector3.zAxis
end

local function isAmmoSocket(part)
	return part
		and part:IsA("BasePart")
		and string.match(part.Name, "^Ammo_module%d*$") ~= nil
		and part:GetAttribute("Allowed_ammo") ~= nil
		and part:GetAttribute("Allowed_ammo_type") ~= nil
end

local function getAmmoSockets(launcher)
	local sockets = {}

	for _, item in ipairs(launcher:GetChildren()) do
		if isAmmoSocket(item) then
			table.insert(sockets, item)
		end
	end

	table.sort(sockets, function(a, b)
		local function indexOf(name)
			if name == "Ammo_module" then
				return 0
			end

			return tonumber(string.match(name, "^Ammo_module(%d+)$")) or 9999
		end

		return indexOf(a.Name) < indexOf(b.Name)
	end)

	return sockets
end

local function getLoadedRocket(socket)
	for _, child in ipairs(socket:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("LoadedAmmo") == true then
			return child
		end
	end

	return nil
end

local function getAmmoFolders()
	local result = {}

	for _, entry in ipairs(AMMO_FOLDERS) do
		local familyFolder = ReplicatedStorage:FindFirstChild(entry.Family)
		if familyFolder and familyFolder:IsA("Folder") then
			local ammoFolder = familyFolder:FindFirstChild(entry.Folder)
			if ammoFolder and ammoFolder:IsA("Folder") then
				table.insert(result, ammoFolder)
			end
		end
	end

	return result
end

local function getCompatibleAmmoTemplate(socket)
	local allowedAmmo = tostring(socket:GetAttribute("Allowed_ammo") or "")
	local allowedType = tostring(socket:GetAttribute("Allowed_ammo_type") or "")

	for _, ammoFolder in ipairs(getAmmoFolders()) do
		-- First: exact name lookup.
		local exact = ammoFolder:FindFirstChild(allowedType)
		if exact
			and exact:IsA("Model")
			and tostring(exact:GetAttribute("Ammo") or "") == allowedAmmo
			and tostring(exact:GetAttribute("Ammo_type") or "") == allowedType
		then
			return exact
		end

		-- Fallback: search by attributes.
		for _, candidate in ipairs(ammoFolder:GetChildren()) do
			if candidate:IsA("Model")
				and tostring(candidate:GetAttribute("Ammo") or "") == allowedAmmo
				and tostring(candidate:GetAttribute("Ammo_type") or "") == allowedType
			then
				return candidate
			end
		end
	end

	return nil
end

local function prepareLoadedRocket(rocket)
	local main = rocket:FindFirstChild("Main", true)
	if not main or not main:IsA("BasePart") then
		return nil
	end

	rocket.PrimaryPart = main

	for _, item in ipairs(rocket:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = false
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.Massless = true
			item.AssemblyLinearVelocity = Vector3.zero
			item.AssemblyAngularVelocity = Vector3.zero
		end
	end

	return main
end

local function syncCounts(launcher)
	local sockets = getAmmoSockets(launcher)
	local loaded = 0
	local pending = 0

	for _, socket in ipairs(sockets) do
		if getLoadedRocket(socket) then
			loaded += 1
		end

		if socket:GetAttribute("LaunchPending") == true then
			pending += 1
		end
	end

	launcher:SetAttribute("Rocket_current", loaded)
	launcher:SetAttribute("Rocket_max", #sockets)
	launcher:SetAttribute("Rocket_pending", pending)
end

local function loadSocket(socket, template)
	if getLoadedRocket(socket) then
		return false
	end

	if socket:GetAttribute("LaunchPending") == true then
		return false
	end

	template = template or getCompatibleAmmoTemplate(socket)
	if not template then
		warn(
			"[RocketLauncherController] No compatible ammo for socket:",
			socket:GetFullName(),
			"Allowed_ammo:", socket:GetAttribute("Allowed_ammo"),
			"Allowed_ammo_type:", socket:GetAttribute("Allowed_ammo_type")
		)
		return false
	end

	local rocket = template:Clone()
	rocket.Name = template.Name
	rocket:SetAttribute("LoadedAmmo", true)
	rocket.Parent = socket

	local main = prepareLoadedRocket(rocket)
	if not main then
		warn("[RocketLauncherController] Ammo template has no Main:", template:GetFullName())
		rocket:Destroy()
		return false
	end

	-- The rocket is physically centered on the Ammo_module.
	rocket:PivotTo(socket.CFrame)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "AmmoWeld"
	weld.Part0 = socket
	weld.Part1 = main
	weld.Parent = main

	return true
end

local function findVehicleOfLauncher(launcher)
	local current = launcher

	while current and current ~= Workspace do
		if current:IsA("Model")
			and current.Parent
			and current.Parent.Name == "ActiveVehicles"
		then
			return current
		end

		current = current.Parent
	end

	return nil
end

function RocketLauncherController.IsRocketLauncher(launcher)
	if not launcher or not launcher:IsA("Model") then
		return false
	end

	for _, socket in ipairs(getAmmoSockets(launcher)) do
		if tostring(socket:GetAttribute("Allowed_ammo")) == "Rocket" then
			return true
		end
	end

	return false
end

function RocketLauncherController.RegisterLauncher(launcher, fillInitial)
	if not RocketLauncherController.IsRocketLauncher(launcher) then
		return false
	end

	if not registeredLaunchers[launcher] then
		registeredLaunchers[launcher] = {
			LastFireCommand = -math.huge,
		}

		print("[RocketLauncherController] Registered:", launcher:GetFullName())
	end

	-- First registration = the launcher spawns fully loaded for free.
	if fillInitial ~= false and launcher:GetAttribute("InitialRocketFillDone") ~= true then
		for _, socket in ipairs(getAmmoSockets(launcher)) do
			loadSocket(socket)
		end

		launcher:SetAttribute("InitialRocketFillDone", true)
	end

	syncCounts(launcher)
	return true
end

function RocketLauncherController.GetLoadedCount(launcher)
	syncCounts(launcher)
	return tonumber(launcher:GetAttribute("Rocket_current")) or 0
end

function RocketLauncherController.GetMaxCount(launcher)
	syncCounts(launcher)
	return tonumber(launcher:GetAttribute("Rocket_max")) or 0
end

function RocketLauncherController.GetNextEmptySocket(launcher)
	for _, socket in ipairs(getAmmoSockets(launcher)) do
		if not getLoadedRocket(socket)
			and socket:GetAttribute("LaunchPending") ~= true
		then
			return socket
		end
	end

	return nil
end

function RocketLauncherController.TryRefillOne(launcher, provider)
	if not RocketLauncherController.IsRocketLauncher(launcher) then
		return false
	end

	RocketLauncherController.RegisterLauncher(launcher, false)

	local socket = RocketLauncherController.GetNextEmptySocket(launcher)
	if not socket then
		syncCounts(launcher)
		return false
	end

	local template = getCompatibleAmmoTemplate(socket)
	if not template then
		return false
	end

	local cargoCost = math.max(
		0,
		tonumber(template:GetAttribute("Cargo_cost")) or 0
	)

	if cargoCost > 0 then
		if not provider then
			return false
		end

		if not WarehouseManager.CanPayCargo(provider, cargoCost) then
			return false
		end

		if not WarehouseManager.PayCargo(provider, cargoCost) then
			return false
		end
	end

	local loaded = loadSocket(socket, template)
	syncCounts(launcher)

	if loaded then
		print(
			"[RocketLauncherController] Refilled:",
			launcher.Name,
			socket.Name,
			template.Name,
			"Cargo:", cargoCost
		)
	end

	return loaded
end

local function findNextReadySocket(launcher)
	for _, socket in ipairs(getAmmoSockets(launcher)) do
		if getLoadedRocket(socket)
			and socket:GetAttribute("LaunchPending") ~= true
		then
			return socket
		end
	end

	return nil
end

local function isAircraftVehicle(vehicle)
	return vehicle
		and (
			vehicle:GetAttribute("Plane") == true
			or vehicle:GetAttribute("VehicleType") == "Plane"
			or vehicle:GetAttribute("VehicleType") == "Helicopter"
		)
end

local function getLiveAircraftPivot(player, vehicle)
	local state = aircraftPoseByPlayer[player]
	if not state or state.Vehicle ~= vehicle then
		return nil
	end

	if os.clock() - state.Time > AIRCRAFT_POSE_TIMEOUT then
		return nil
	end

	if typeof(state.CFrame) ~= "CFrame" then
		return nil
	end

	return state.CFrame
end

local function getLiveAircraftVelocity(player, vehicle)
	local state = aircraftPoseByPlayer[player]
	if not state or state.Vehicle ~= vehicle then
		return Vector3.zero
	end

	if os.clock() - state.Time > AIRCRAFT_POSE_TIMEOUT then
		return Vector3.zero
	end

	if typeof(state.Velocity) ~= "Vector3" then
		return Vector3.zero
	end

	return state.Velocity
end

local function reconstructFromVehiclePivot(vehicle, liveVehiclePivot, worldCFrame)
	-- Convert the server-side spawn-relative transform into the live client pose.
	local serverVehiclePivot = vehicle:GetPivot()
	local localCFrame = serverVehiclePivot:ToObjectSpace(worldCFrame)
	return liveVehiclePivot * localCFrame
end

local function releaseRocket(player, vehicle, launcher, socket)
	if not launcher.Parent
		or not socket.Parent
		or socket:GetAttribute("LaunchPending") ~= true
	then
		return
	end

	local rocket = getLoadedRocket(socket)
	if not rocket or not rocket.Parent then
		socket:SetAttribute("LaunchPending", false)
		syncCounts(launcher)
		return
	end

	local main = rocket.PrimaryPart or rocket:FindFirstChild("Main", true)
	if not main or not main:IsA("BasePart") then
		socket:SetAttribute("LaunchPending", false)
		rocket:Destroy()
		syncCounts(launcher)
		return
	end

	-- Direction/origin are taken at the ACTUAL launch moment.
	local launchAxis = socket:GetAttribute("Launch_axis") or "-Z"
	local directionSource = socket.CFrame
	local launchCFrame = rocket:GetPivot()

	if isAircraftVehicle(vehicle) then
		local launcherMain =
			launcher.PrimaryPart
			or launcher:FindFirstChild("Main", true)

		local liveVehiclePivot = getLiveAircraftPivot(player, vehicle)

		if launcherMain and launcherMain:IsA("BasePart") then
			launchAxis =
				launcher:GetAttribute("Launch_axis")
				or launcherMain:GetAttribute("Launch_axis")
				or "-X"

			if liveVehiclePivot then
				directionSource =
					reconstructFromVehiclePivot(
						vehicle,
						liveVehiclePivot,
						launcherMain.CFrame
					)
			else
				directionSource = launcherMain.CFrame
			end
		end

		if liveVehiclePivot then
			launchCFrame =
				reconstructFromVehiclePivot(
					vehicle,
					liveVehiclePivot,
					rocket:GetPivot()
				)
		end
	end

	local direction =
		directionSource:VectorToWorldSpace(
			axisToLocalVector(launchAxis)
		).Unit

	local weld = main:FindFirstChild("AmmoWeld")
	if weld then
		weld:Destroy()
	end

	socket:SetAttribute("LaunchPending", false)
	rocket:SetAttribute("LoadedAmmo", false)

	ProjectileManager.FireRocketModel({
		Owner = player,
		Weapon = vehicle,
		Launcher = launcher,
		Rocket = rocket,
		OriginCFrame = launchCFrame,
		Direction = direction,
		LaunchAxis = launchAxis,
		CarrierVelocity =
			isAircraftVehicle(vehicle)
			and getLiveAircraftVelocity(player, vehicle)
			or Vector3.zero,
	})

	syncCounts(launcher)

	print(
		"[RocketLauncherController] LAUNCH:",
		launcher.Name,
		socket.Name,
		rocket.Name
	)
end

function RocketLauncherController.Fire(player, vehicle, launcher)
	if not RocketLauncherController.IsRocketLauncher(launcher) then
		return false
	end

	RocketLauncherController.RegisterLauncher(launcher, false)

	local state = registeredLaunchers[launcher]
	if not state then
		return false
	end

	local fireRate =
		tonumber(launcher:GetAttribute("FireRate"))
		or tonumber(launcher:GetAttribute("Fire_rate"))
		or 0.5

	fireRate = math.max(0, fireRate)

	local now = os.clock()
	if now - state.LastFireCommand < fireRate then
		return false
	end

	local socket = findNextReadySocket(launcher)
	if not socket then
		syncCounts(launcher)
		return false
	end

	state.LastFireCommand = now
	socket:SetAttribute("LaunchPending", true)
	syncCounts(launcher)

	local delayTime =
		tonumber(launcher:GetAttribute("Launch_delay"))
		or LAUNCH_DELAY

	delayTime = math.max(0, delayTime)

	task.delay(delayTime, function()
		releaseRocket(player, vehicle, launcher, socket)
	end)

	return true
end

local function scanActiveVehicles()
	local activeVehicles =
		Workspace:FindFirstChild(ACTIVE_VEHICLES_FOLDER_NAME)

	if not activeVehicles then
		return
	end

	for _, vehicle in ipairs(activeVehicles:GetChildren()) do
		if vehicle:IsA("Model") then
			local mounted = vehicle:FindFirstChild("MountedModules")

			if mounted then
				for _, module in ipairs(mounted:GetChildren()) do
					if module:IsA("Model")
						and RocketLauncherController.IsRocketLauncher(module)
					then
						RocketLauncherController.RegisterLauncher(module, true)
					end
				end
			end
		end
	end
end


local function getAircraftFireRemote()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	local remote = remotes:FindFirstChild(AIRCRAFT_FIRE_REMOTE_NAME)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = AIRCRAFT_FIRE_REMOTE_NAME
		remote.Parent = remotes
	end

	return remote
end

local function getControlledAircraft(player)
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local seat = humanoid.SeatPart
	if not seat then
		return nil
	end

	local current = seat
	while current and current ~= Workspace do
		if current:IsA("Model")
			and current.Parent
			and current.Parent.Name == ACTIVE_VEHICLES_FOLDER_NAME
		then
			local isPlane =
				current:GetAttribute("Plane") == true
				or current:GetAttribute("VehicleType") == "Plane"

			local isHelicopter =
				current:GetAttribute("VehicleType") == "Helicopter"

			if isPlane or isHelicopter then
				return current
			end

			return nil
		end

		current = current.Parent
	end

	return nil
end

local function getAircraftRocketLaunchers(vehicle)
	local result = {}
	local mounted = vehicle and vehicle:FindFirstChild("MountedModules")
	if not mounted then
		return result
	end

	for _, module in ipairs(mounted:GetDescendants()) do
		if module:IsA("Model")
			and RocketLauncherController.IsRocketLauncher(module)
		then
			table.insert(result, module)
		end
	end

	table.sort(result, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)

	return result
end

function RocketLauncherController.Start()
	if started then
		return
	end

	started = true

	local aircraftFireRemote = getAircraftFireRemote()
	aircraftFireRemote.OnServerEvent:Connect(function(player, action, payload)
		local vehicle = getControlledAircraft(player)

		if action == "Pose" then
			if not vehicle then
				aircraftPoseByPlayer[player] = nil
				return
			end

			local poseCFrame = nil
			local carrierVelocity = Vector3.zero

			if typeof(payload) == "CFrame" then
				-- Backward compatibility with the previous client.
				poseCFrame = payload
			elseif typeof(payload) == "table" then
				if typeof(payload.CFrame) == "CFrame" then
					poseCFrame = payload.CFrame
				end

				if typeof(payload.Velocity) == "Vector3" then
					carrierVelocity = payload.Velocity
				end
			end

			if not poseCFrame then
				aircraftPoseByPlayer[player] = nil
				return
			end

			aircraftPoseByPlayer[player] = {
				Vehicle = vehicle,
				CFrame = poseCFrame,
				Velocity = carrierVelocity,
				Time = os.clock(),
			}
			return
		end

		if action ~= "FireRocket" or not vehicle then
			return
		end

		local launchers = getAircraftRocketLaunchers(vehicle)
		local fired = 0

		for _, launcher in ipairs(launchers) do
			if RocketLauncherController.Fire(player, vehicle, launcher) then
				fired += 1
			end
		end

		if fired > 0 then
			print(
				"[RocketLauncherController] Aircraft fire LIVE POSE:",
				player.Name,
				vehicle.Name,
				"launchers:",
				fired
			)
		end
	end)

	-- A light periodic scan is enough and also covers modules attached later.
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt

		if accumulator < 0.5 then
			return
		end

		accumulator = 0
		scanActiveVehicles()

		for launcher in pairs(registeredLaunchers) do
			if not launcher.Parent then
				registeredLaunchers[launcher] = nil
			else
				syncCounts(launcher)
			end
		end
	end)
end

return RocketLauncherController
