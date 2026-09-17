local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ProjectileManager = require(script.Parent.ProjectileManager)
local RocketLauncherController = require(script.Parent.RocketLauncherController)

RocketLauncherController.Start()

local TurretController = {}

local REMOTE_NAME = "TurretActionRequest"
local activeTurrets = {}

-- =========================================
-- REMOTE
-- =========================================

local turretRemote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)

if not turretRemote then
	turretRemote = Instance.new("RemoteEvent")
	turretRemote.Name = REMOTE_NAME
	turretRemote.Parent = ReplicatedStorage
end

-- =========================================
-- HELPERS
-- =========================================

local function getPart(model, name)
	local part = model:FindFirstChild(name, true)

	if part and part:IsA("BasePart") then
		return part
	end

	return nil
end

local function isTurret(model)
	if not model or not model:IsA("Model") then
		return false
	end

	return model:GetAttribute("ModuleRole") == "Turret"
		or model:GetAttribute("Turret") == true
end

local function playerDrivesVehicle(player, vehicle)
	if not player or not vehicle then
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	local seat = humanoid.SeatPart
	if not seat then
		return false
	end

	return seat:IsDescendantOf(vehicle)
end

local function getTurrets(vehicle)
	local result = {}

	local mountedModules = vehicle:FindFirstChild("MountedModules")
	if not mountedModules then
		return result
	end

	for _, item in ipairs(mountedModules:GetDescendants()) do
		if item:IsA("Model") and isTurret(item) then
			table.insert(result, item)
		end
	end

	return result
end

local function axisToLocalVector(axis)
	axis = tostring(axis or "-X")

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

	return -Vector3.xAxis
end

local function getBarrelDirection(turret, barrel)
	local axis = barrel:GetAttribute("Barrel_axis")
		or turret:GetAttribute("Barrel_axis")
		or "-X"

	return barrel.CFrame:VectorToWorldSpace(
		axisToLocalVector(axis)
	).Unit
end

-- =========================================
-- MOTOR SETUP
-- =========================================

local function destroyBlockingWelds(turret, main, horizontal, vertical, barrel)
	-- Видаляємо ТІЛЬКИ старі weld-и між основними рухомими
	-- деталями самої башти.
	--
	-- Важливо: weld-и прицілу Sight, декорацій тощо
	-- тепер не чіпаємо.
	local coreParts = {
		[main] = true,
		[horizontal] = true,
		[vertical] = true,
	}

	if barrel then
		coreParts[barrel] = true
	end

	for _, item in ipairs(turret:GetDescendants()) do
		if item:IsA("WeldConstraint") then
			if item.Name == "ModuleWeld"
				or item.Name == "BarrelWeld"
				or item.Name == "SightWeld"
			then
				continue
			end

			local part0 = item.Part0
			local part1 = item.Part1

			if coreParts[part0] and coreParts[part1] then
				item:Destroy()
			end
		end
	end
end

local function setupSight(turret, vertical)
	local sight = turret:FindFirstChild("Sight", true)

	if not sight or not sight:IsA("Model") then
		return
	end

	for _, item in ipairs(sight:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = false
			item.CanCollide = false
			item.Massless = true

			-- Щоб повторний RegisterTurret не створював дублікати.
			local oldWeld = item:FindFirstChild("SightWeld")

			if oldWeld then
				oldWeld:Destroy()
			end

			-- Приціл кріпимо до вертикальної частини башти,
			-- тому він повторює і Yaw, і Pitch ствола.
			local weld = Instance.new("WeldConstraint")
			weld.Name = "SightWeld"
			weld.Part0 = vertical
			weld.Part1 = item
			weld.Parent = item
		end
	end
end

local function createMotor(name, part0, part1)
	local oldMotor = part0:FindFirstChild(name)

	if oldMotor and oldMotor:IsA("Motor6D") then
		oldMotor:Destroy()
	end

	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1

	-- Зберігаємо поточне взаємне положення деталей.
	motor.C0 = part0.CFrame:ToObjectSpace(part1.CFrame)
	motor.C1 = CFrame.identity
	motor.Parent = part0

	return motor
end

local function keepTurretMovable(turret, main)
	-- VehicleDriveController / HelicopterDriveController use an anchored
	-- arcade vehicle and may anchor EVERY BasePart in the vehicle after
	-- modules have already been registered.
	--
	-- A Motor6D cannot rotate an anchored Part1 assembly. Even one anchored
	-- Sight/decor part welded to the moving turret can freeze the whole chain.
	--
	-- Keep only turret Main anchored. Everything else in the turret is allowed
	-- to move through Motor6D/WeldConstraint while Main follows vehicle PivotTo.
	for _, item in ipairs(turret:GetDescendants()) do
		if item:IsA("BasePart") and item ~= main then
			if item.Anchored then
				item.Anchored = false
			end

			item.CanCollide = false
			item.Massless = true
		end
	end
end


-- =========================================
-- AMMO MODULE AUTO-WELD
-- =========================================

local function setupAmmoModuleWelds(turret, vertical)
	-- One BasePart marked Ammo_part = true is the common mount.
	-- Every BasePart marked Ammo_module = true inside THIS turret
	-- is welded to that common mount.
	local ammoPart = nil
	local ammoModules = {}

	for _, item in ipairs(turret:GetDescendants()) do
		if item:IsA("BasePart") then
			if item:GetAttribute("Ammo_part") == true then
				if ammoPart and ammoPart ~= item then
					warn(
						"[TurretController] More than one Ammo_part=true:",
						turret:GetFullName()
					)
					return
				end

				ammoPart = item
			end

			if item:GetAttribute("Ammo_module") == true then
				table.insert(ammoModules, item)
			end
		end
	end

	-- Ordinary gun turret / launcher without this optional weld system.
	if not ammoPart then
		return
	end

	if #ammoModules == 0 then
		warn(
			"[TurretController] Ammo_part=true found, but no Ammo_module=true parts:",
			turret:GetFullName()
		)
		return
	end

	-- Ammo_part itself must also be attached to the moving pitch assembly.
	-- Otherwise keepTurretMovable() unanchors it and the whole rocket rack
	-- simply falls away on the next physics frame.
	ammoPart.Anchored = false
	ammoPart.CanCollide = false
	ammoPart.Massless = true

	local oldMountWeld = ammoPart:FindFirstChild("AmmoPartWeld")
	if oldMountWeld then
		oldMountWeld:Destroy()
	end

	local mountWeld = Instance.new("WeldConstraint")
	mountWeld.Name = "AmmoPartWeld"
	mountWeld.Part0 = vertical
	mountWeld.Part1 = ammoPart
	mountWeld.Parent = ammoPart

	local created = 0

	for _, ammoModule in ipairs(ammoModules) do
		if ammoModule == ammoPart then
			warn(
				"[TurretController] Part cannot be both Ammo_part and Ammo_module:",
				ammoModule:GetFullName()
			)
			continue
		end

		ammoModule.Anchored = false
		ammoModule.CanCollide = false
		ammoModule.Massless = true

		local oldWeld = ammoModule:FindFirstChild("AmmoModuleWeld")

		if oldWeld and oldWeld:IsA("WeldConstraint") then
			local correctPair =
				(oldWeld.Part0 == ammoPart and oldWeld.Part1 == ammoModule)
				or
				(oldWeld.Part1 == ammoPart and oldWeld.Part0 == ammoModule)

			if correctPair then
				continue
			end

			oldWeld:Destroy()
		elseif oldWeld then
			oldWeld:Destroy()
		end

		local weld = Instance.new("WeldConstraint")
		weld.Name = "AmmoModuleWeld"
		weld.Part0 = ammoPart
		weld.Part1 = ammoModule
		weld.Parent = ammoModule

		created += 1
	end

	print(
		"[TurretController] Ammo welds ready:",
		turret.Name,
		"Modules:",
		#ammoModules,
		"New welds:",
		created
	)
end

local function setupTurret(turret)
	if activeTurrets[turret] then
		return activeTurrets[turret]
	end

	if not isTurret(turret) then
		return nil
	end

	local main = getPart(turret, "Main")
	local horizontal = getPart(turret, "Tur_hor_opt")
	local vertical = getPart(turret, "Tur_vert_opt")
	local barrel = getPart(turret, "Barrel")
	local isRocketLauncher =
		RocketLauncherController.IsRocketLauncher(turret)

	if not main then
		warn("[TurretController] Main not found:", turret:GetFullName())
		return nil
	end

	if not horizontal then
		warn("[TurretController] Tur_hor_opt not found:", turret:GetFullName())
		return nil
	end

	if not vertical then
		warn("[TurretController] Tur_vert_opt not found:", turret:GetFullName())
		return nil
	end

	-- Gun turrets still require Barrel.
	-- Rocket launchers use Ammo_module* instead and intentionally have no Barrel.
	if not barrel and not isRocketLauncher then
		warn("[TurretController] Barrel not found:", turret:GetFullName())
		return nil
	end

	destroyBlockingWelds(turret, main, horizontal, vertical, barrel)

	-- Optional automatic weld system for launcher socket parts.
	setupAmmoModuleWelds(turret, vertical)

	-- Main stays controlled by the arcade vehicle/module system.
	horizontal.Anchored = false
	vertical.Anchored = false

	horizontal.CanCollide = false
	vertical.CanCollide = false

	horizontal.Massless = true
	vertical.Massless = true

	if barrel then
		barrel.Anchored = false
		barrel.CanCollide = false
		barrel.Massless = true
	end

	local yawMotor = createMotor(
		"TurretYawMotor",
		main,
		horizontal
	)

	local pitchMotor = createMotor(
		"TurretPitchMotor",
		horizontal,
		vertical
	)

	if barrel then
		local oldBarrelWeld = vertical:FindFirstChild("BarrelWeld")
		if oldBarrelWeld then
			oldBarrelWeld:Destroy()
		end

		local barrelWeld = Instance.new("WeldConstraint")
		barrelWeld.Name = "BarrelWeld"
		barrelWeld.Part0 = vertical
		barrelWeld.Part1 = barrel
		barrelWeld.Parent = vertical
	end

	if isRocketLauncher then
		RocketLauncherController.RegisterLauncher(turret, true)
	end

	-- Sight автоматично прив'язується до вертикального вузла.
	setupSight(turret, vertical)

	-- Vehicle controller may have anchored module descendants earlier.
	keepTurretMovable(turret, main)

	local data = {
		Turret = turret,

		Main = main,
		Horizontal = horizontal,
		Vertical = vertical,
		Barrel = barrel,
		IsRocketLauncher = isRocketLauncher,

		YawMotor = yawMotor,
		PitchMotor = pitchMotor,

		BaseYawC0 = yawMotor.C0,
		BasePitchC0 = pitchMotor.C0,

		CurrentYaw = 0,
		CurrentPitch = 0,

		TargetYaw = 0,
		TargetPitch = 0,

		LastShotTime = 0,
		Reloading = false,
	}

	activeTurrets[turret] = data

	print(
		"[TurretController] Motors:",
		yawMotor.Part0.Name,
		"->",
		yawMotor.Part1.Name,
		"|",
		pitchMotor.Part0.Name,
		"->",
		pitchMotor.Part1.Name
	)

	print("[TurretController] Registered:", turret.Name)

	return data
end

-- =========================================
-- ANGLES
-- =========================================

local function normalizeAngle(angle)
	return math.atan2(
		math.sin(angle),
		math.cos(angle)
	)
end

local function moveAngleTowards(current, target, maxDelta)
	local difference = normalizeAngle(target - current)

	if math.abs(difference) <= maxDelta then
		return target
	end

	return current + math.sign(difference) * maxDelta
end

local function moveTowards(current, target, maxDelta)
	if math.abs(target - current) <= maxDelta then
		return target
	end

	return current + math.sign(target - current) * maxDelta
end

local function calculateTargetAngles(data, worldTarget)
	local main = data.Main

	if not main or not main.Parent then
		return nil, nil
	end

	local worldDirection = worldTarget - main.Position

	if worldDirection.Magnitude < 0.01 then
		return nil, nil
	end

	local localDirection =
		main.CFrame:VectorToObjectSpace(worldDirection.Unit)

	local horizontalDistance = math.sqrt(
		localDirection.X * localDirection.X
			+ localDirection.Z * localDirection.Z
	)

	-- Для нашої моделі турелі нейтральний напрямок ствола = -X.
	-- Цей варіант уже перевірений в Studio.
	local yaw = math.atan2(
		localDirection.Z,
		-localDirection.X
	)

	local pitch = math.atan2(
		localDirection.Y,
		horizontalDistance
	)

	return yaw, pitch
end

local function applyLimits(turret, yaw, pitch)
	local minPitch = math.rad(
		tonumber(turret:GetAttribute("MinPitch")) or -10
	)

	local maxPitch = math.rad(
		tonumber(turret:GetAttribute("MaxPitch")) or 45
	)

	pitch = math.clamp(pitch, minPitch, maxPitch)

	local minYawAttribute = turret:GetAttribute("MinYaw")
	local maxYawAttribute = turret:GetAttribute("MaxYaw")

	if minYawAttribute ~= nil and maxYawAttribute ~= nil then
		local minYaw = math.rad(tonumber(minYawAttribute) or -180)
		local maxYaw = math.rad(tonumber(maxYawAttribute) or 180)

		yaw = math.clamp(yaw, minYaw, maxYaw)
	else
		yaw = normalizeAngle(yaw)
	end

	return yaw, pitch
end

-- =========================================
-- AIM
-- =========================================

local function aimTurret(turret, worldTarget)
	local data = activeTurrets[turret] or setupTurret(turret)

	if not data then
		return
	end

	local yaw, pitch = calculateTargetAngles(data, worldTarget)

	if yaw == nil or pitch == nil then
		return
	end

	yaw, pitch = applyLimits(turret, yaw, pitch)

	data.TargetYaw = yaw
	data.TargetPitch = pitch
end

local function aimTurretDelta(turret, mouseDelta)
	local data = activeTurrets[turret] or setupTurret(turret)

	if not data then
		return
	end

	-- Чутливість у градусах на 1 pixel MouseDelta.
	-- У Sight клієнт додатково ділить delta на Zoom.
	local sensitivity = math.rad(0.08)

	local yaw =
		data.TargetYaw
		- mouseDelta.X * sensitivity

	local pitch =
		data.TargetPitch
		- mouseDelta.Y * sensitivity

	yaw, pitch = applyLimits(turret, yaw, pitch)

	data.TargetYaw = yaw
	data.TargetPitch = pitch
end

-- =========================================
-- FIRE / RELOAD
-- =========================================

local function reloadTurret(data)
	if data.Reloading then
		return false
	end

	local turret = data.Turret

	local magazineSize =
		tonumber(turret:GetAttribute("Magazine_size")) or 0

	local currentMagazines =
		tonumber(turret:GetAttribute("Current_magazines")) or 0

	if magazineSize <= 0 or currentMagazines <= 0 then
		return false
	end

	-- Один запасний магазин витрачається в момент початку перезарядки.
	turret:SetAttribute(
		"Current_magazines",
		math.max(0, currentMagazines - 1)
	)

	data.Reloading = true

	local reloadTime =
		tonumber(turret:GetAttribute("Reload_time")) or 1

	task.delay(reloadTime, function()
		if not turret.Parent then
			return
		end

		turret:SetAttribute("Current_ammo", magazineSize)
		data.Reloading = false
	end)

	return true
end

local function fireTurret(player, vehicle, turret)
	local data = activeTurrets[turret] or setupTurret(turret)

	if not data then
		return
	end

	if data.IsRocketLauncher then
		RocketLauncherController.Fire(
			player,
			vehicle,
			turret
		)
		return
	end

	if data.Reloading then
		return
	end

	local barrel = data.Barrel
	if not barrel or not barrel.Parent then
		return
	end

	local fireRate =
		tonumber(turret:GetAttribute("FireRate"))
		or tonumber(turret:GetAttribute("Fire_rate"))
		or 0.15

	local now = os.clock()

	if now - data.LastShotTime < fireRate then
		return
	end

	local currentAmmo =
		tonumber(turret:GetAttribute("Current_ammo")) or 0

	if currentAmmo <= 0 then
		reloadTurret(data)
		return
	end

	data.LastShotTime = now

	currentAmmo -= 1
	turret:SetAttribute("Current_ammo", currentAmmo)

	local direction = getBarrelDirection(turret, barrel)

	local projectileSize =
		tonumber(turret:GetAttribute("Projectile_size")) or 0.3

	-- Точка старту трохи винесена вперед від центра Barrel,
	-- щоб снаряд не народжувався всередині геометрії ствола.
	local origin =
		barrel.Position
		+ direction * math.max(0.25, projectileSize)

	ProjectileManager.FireBullet({
		Owner = player,

		-- Ігноруємо всю машину в raycast, а не лише саму башту.
		Weapon = vehicle,

		Origin = origin,
		Direction = direction,

		Speed =
			tonumber(turret:GetAttribute("Projectile_speed")) or 20,

		Drag =
			tonumber(turret:GetAttribute("Projectile_drag")) or 0,

		Damage =
			tonumber(turret:GetAttribute("Damage")) or 20,

		Size = projectileSize,
	})

	-- Після останнього пострілу починаємо перезарядку автоматично.
	if currentAmmo <= 0 then
		reloadTurret(data)
	end
end

-- =========================================
-- FIND CONTROLLED VEHICLE
-- =========================================

local function findControlledVehicle(player)
	local activeVehicles = Workspace:FindFirstChild("ActiveVehicles")

	if not activeVehicles then
		return nil
	end

	for _, vehicle in ipairs(activeVehicles:GetChildren()) do
		if vehicle:IsA("Model")
			and playerDrivesVehicle(player, vehicle)
		then
			return vehicle
		end
	end

	return nil
end

-- =========================================
-- REMOTE INPUT
-- =========================================

turretRemote.OnServerEvent:Connect(function(player, action, value)
	local controlledVehicle = findControlledVehicle(player)

	if not controlledVehicle then
		return
	end

	local turrets = getTurrets(controlledVehicle)

	if action == "Aim" then
		if typeof(value) ~= "Vector3" then
			return
		end

		if value.Magnitude > 1000000 then
			return
		end

		for _, turret in ipairs(turrets) do
			aimTurret(turret, value)
		end

	elseif action == "AimDelta" then
		if typeof(value) ~= "Vector2" then
			return
		end

		-- Захист від випадкового гігантського стрибка миші.
		if value.Magnitude > 500 then
			return
		end

		for _, turret in ipairs(turrets) do
			aimTurretDelta(turret, value)
		end

	elseif action == "Fire" then
		for _, turret in ipairs(turrets) do
			fireTurret(player, controlledVehicle, turret)
		end
	end
end)

-- =========================================
-- UPDATE
-- =========================================

RunService.Heartbeat:Connect(function(dt)
	for turret, data in pairs(activeTurrets) do
		if not turret.Parent or not data.Main.Parent then
			activeTurrets[turret] = nil
			continue
		end

		-- Self-heal after arcade vehicle controllers anchor descendants.
		-- This is the actual fix for a turret that receives AimDelta but
		-- physically refuses to rotate.
		keepTurretMovable(turret, data.Main)

		local yawSpeed = math.rad(
			tonumber(turret:GetAttribute("YawSpeed")) or 90
		)

		local pitchSpeed = math.rad(
			tonumber(turret:GetAttribute("PitchSpeed")) or 60
		)

		local maxYawStep = yawSpeed * dt
		local maxPitchStep = pitchSpeed * dt

		local minYawAttribute = turret:GetAttribute("MinYaw")
		local maxYawAttribute = turret:GetAttribute("MaxYaw")

		if minYawAttribute == nil or maxYawAttribute == nil then
			data.CurrentYaw =
				moveAngleTowards(
					data.CurrentYaw,
					data.TargetYaw,
					maxYawStep
				)

			data.CurrentYaw = normalizeAngle(data.CurrentYaw)
		else
			data.CurrentYaw =
				moveTowards(
					data.CurrentYaw,
					data.TargetYaw,
					maxYawStep
				)
		end

		data.CurrentPitch =
			moveTowards(
				data.CurrentPitch,
				data.TargetPitch,
				maxPitchStep
			)

		data.YawMotor.C0 =
			data.BaseYawC0
			* CFrame.Angles(
				0,
				data.CurrentYaw,
				0
			)

		-- У нашій моделі вертикальний вузол крутиться по Z.
		-- Мінус потрібен через локальну орієнтацію Tur_vert_opt.
		data.PitchMotor.C0 =
			data.BasePitchC0
			* CFrame.Angles(
				0,
				0,
				-data.CurrentPitch
			)
	end
end)

-- =========================================
-- PUBLIC
-- =========================================

function TurretController.RegisterTurret(turret)
	return setupTurret(turret)
end

return TurretController
