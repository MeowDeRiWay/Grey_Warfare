local Workspace = game:GetService("Workspace")

local VehicleDamageManager = {}

local ACTIVE_VEHICLES_FOLDER_NAME = "ActiveVehicles"
local DEFAULT_BASE_RADIUS = 10
local DEFAULT_COLLISION_SAFE_SPEED = 5
local DEFAULT_COLLISION_DAMAGE_MULTIPLIER = 1
local DEFAULT_MAG_CARGO_COST = 1

local registeredVehicles = {}
local explodingVehicles = {}
local started = false

local function getMain(model)
	if not model then
		return nil
	end

	local main = model:FindFirstChild("Main", true)
	if main and main:IsA("BasePart") then
		return main
	end

	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getMountedModulesFolder(vehicle)
	local folder = vehicle and vehicle:FindFirstChild("MountedModules")
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function getCargoAmount(vehicle)
	local mounted = getMountedModulesFolder(vehicle)
	local foundCargoModule = false
	local cargo = 0

	if mounted then
		for _, item in ipairs(mounted:GetDescendants()) do
			if item:IsA("Model") and item:GetAttribute("ModuleRole") == "Cargo" then
				foundCargoModule = true
				cargo += tonumber(item:GetAttribute("Current_cargo")) or 0
			end
		end
	end

	-- VehicleModuleManager may mirror cargo values onto the vehicle itself.
	-- If a real Cargo module exists, use the module values only so cargo is not counted twice.
	if foundCargoModule then
		return math.max(0, cargo)
	end

	return math.max(0, tonumber(vehicle:GetAttribute("Current_cargo")) or 0)
end

local function getAmmoValue(vehicle)
	local mounted = getMountedModulesFolder(vehicle)
	if not mounted then
		return 0
	end

	local total = 0

	for _, module in ipairs(mounted:GetDescendants()) do
		if module:IsA("Model") then
			local magazines = tonumber(module:GetAttribute("Current_magazines"))
			if magazines and magazines > 0 then
				local price = tonumber(module:GetAttribute("Magazine_cargo_price"))
					or tonumber(module:GetAttribute("Cargo_per_mag"))
					or DEFAULT_MAG_CARGO_COST

				if price < 0 then
					price = 0
				end

				total += magazines * price
			end

			-- Physical rocket ammunition is stored as real models inside
			-- Ammo_module* sockets. LoadedAmmo is the source of truth.
			if module:GetAttribute("LoadedAmmo") == true then
				local rocketCost =
					tonumber(module:GetAttribute("Cargo_cost")) or 0

				if rocketCost > 0 then
					total += rocketCost
				end
			end
		end
	end

	return total
end

local function findDamageTarget(instance)
	local current = instance

	while current and current ~= Workspace do
		if current:GetAttribute("Current_health") ~= nil
			or current:GetAttribute("Health") ~= nil
		then
			return current
		end

		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function damageHumanoidIfPresent(target, damage, newHealth)
	if not target or not target:IsA("Model") then
		return
	end

	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if newHealth ~= nil then
		humanoid.Health = math.clamp(newHealth, 0, humanoid.MaxHealth)
	else
		humanoid:TakeDamage(damage)
	end
end

function VehicleDamageManager.ApplyDamage(target, damage)
	damage = tonumber(damage) or 0
	if not target or damage <= 0 then
		return 0
	end

	local currentHealth = target:GetAttribute("Current_health")
	if currentHealth ~= nil then
		currentHealth = tonumber(currentHealth) or 0
		local newHealth = math.max(0, currentHealth - damage)
		target:SetAttribute("Current_health", newHealth)
		damageHumanoidIfPresent(target, damage, newHealth)
		return currentHealth - newHealth
	end

	local health = target:GetAttribute("Health")
	if health ~= nil then
		health = tonumber(health) or 0
		local newHealth = math.max(0, health - damage)
		target:SetAttribute("Health", newHealth)
		damageHumanoidIfPresent(target, damage, newHealth)
		return health - newHealth
	end

	local humanoid = target:IsA("Model") and target:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local before = humanoid.Health
		humanoid:TakeDamage(damage)
		return math.max(0, before - humanoid.Health)
	end

	return 0
end

local function getExplosionStats(vehicle)
	local ammoValue = getAmmoValue(vehicle) -- A * B, summed across ammo modules
	local cargo = getCargoAmount(vehicle) -- C and G in the requested formulas
	local baseRadius = tonumber(vehicle:GetAttribute("Explosion_base_radius")) or DEFAULT_BASE_RADIUS
	baseRadius = math.max(DEFAULT_BASE_RADIUS, baseRadius)

	local damage = ammoValue + cargo / 10
	local radius = baseRadius + cargo / 10

	return damage, radius, ammoValue, cargo
end

local function ejectOccupants(vehicle)
	for _, item in ipairs(vehicle:GetDescendants()) do
		if item:IsA("Seat") or item:IsA("VehicleSeat") then
			local humanoid = item.Occupant
			if humanoid then
				humanoid.Sit = false
			end
		end
	end
end

local function applyExplosionAreaDamage(vehicle, position, damage, radius)
	if damage <= 0 or radius <= 0 then
		return
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { vehicle }
	params.MaxParts = 0

	local parts = Workspace:GetPartBoundsInRadius(position, radius, params)
	local damagedTargets = {}

	for _, part in ipairs(parts) do
		local target = findDamageTarget(part)
		if target and target ~= vehicle and not damagedTargets[target] then
			damagedTargets[target] = true
			-- For now the requested formula is the actual damage inside the radius.
			-- No distance falloff is added unless we decide to add it later.
			VehicleDamageManager.ApplyDamage(target, damage)
		end
	end
end

function VehicleDamageManager.ExplodeVehicle(vehicle)
	if not vehicle or not vehicle.Parent or explodingVehicles[vehicle] then
		return
	end

	explodingVehicles[vehicle] = true
	vehicle:SetAttribute("Destroyed", true)

	local main = getMain(vehicle)
	local position = main and main.Position or vehicle:GetPivot().Position
	local damage, radius, ammoValue, cargo = getExplosionStats(vehicle)

	print(
		"[VehicleDamageManager] EXPLODE:", vehicle.Name,
		"Damage:", damage,
		"Radius:", radius,
		"AmmoValue:", ammoValue,
		"Cargo:", cargo
	)

	ejectOccupants(vehicle)
	applyExplosionAreaDamage(vehicle, position, damage, radius)

	local visual = Instance.new("Explosion")
	visual.Position = position
	visual.BlastRadius = radius
	visual.BlastPressure = 0
	visual.DestroyJointRadiusPercent = 0
	visual.Parent = Workspace

	registeredVehicles[vehicle] = nil

	task.defer(function()
		if vehicle and vehicle.Parent then
			vehicle:Destroy()
		end
		explodingVehicles[vehicle] = nil
	end)
end

local function checkVehicleDeath(vehicle)
	if not vehicle or not vehicle.Parent or explodingVehicles[vehicle] then
		return
	end

	local currentHealth = vehicle:GetAttribute("Current_health")
	if currentHealth == nil then
		currentHealth = vehicle:GetAttribute("Health")
	end

	if currentHealth ~= nil and (tonumber(currentHealth) or 0) <= 0 then
		VehicleDamageManager.ExplodeVehicle(vehicle)
	end
end

function VehicleDamageManager.RegisterVehicle(vehicle)
	if not vehicle or not vehicle:IsA("Model") or registeredVehicles[vehicle] then
		return
	end

	registeredVehicles[vehicle] = true

	local maxHealth = tonumber(vehicle:GetAttribute("Max_health"))
	if maxHealth and vehicle:GetAttribute("Current_health") == nil then
		vehicle:SetAttribute("Current_health", maxHealth)
	end

	vehicle:GetAttributeChangedSignal("Current_health"):Connect(function()
		checkVehicleDeath(vehicle)
	end)

	vehicle:GetAttributeChangedSignal("Health"):Connect(function()
		checkVehicleDeath(vehicle)
	end)

	vehicle.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			registeredVehicles[vehicle] = nil
			explodingVehicles[vehicle] = nil
		end
	end)

	checkVehicleDeath(vehicle)
end

function VehicleDamageManager.ApplyCollisionDamage(vehicle, impactSpeed)
	impactSpeed = math.abs(tonumber(impactSpeed) or 0)
	if impactSpeed <= 0 or not vehicle or not vehicle.Parent then
		return 0
	end

	local safeSpeed = tonumber(vehicle:GetAttribute("Collision_safe_speed")) or DEFAULT_COLLISION_SAFE_SPEED
	local multiplier = tonumber(vehicle:GetAttribute("Collision_damage_multiplier")) or DEFAULT_COLLISION_DAMAGE_MULTIPLIER

	local damage = math.max(0, impactSpeed - safeSpeed) * math.max(0, multiplier)
	if damage <= 0 then
		return 0
	end

	VehicleDamageManager.RegisterVehicle(vehicle)
	local applied = VehicleDamageManager.ApplyDamage(vehicle, damage)

	print(
		"[VehicleDamageManager] COLLISION:", vehicle.Name,
		"Speed:", impactSpeed,
		"Damage:", damage,
		"Applied:", applied
	)

	return applied
end

local hookedFolders = {}

local function hookActiveVehiclesFolder(folder)
	if not folder or not folder:IsA("Folder") or hookedFolders[folder] then
		return
	end

	hookedFolders[folder] = true

	for _, vehicle in ipairs(folder:GetChildren()) do
		if vehicle:IsA("Model") then
			VehicleDamageManager.RegisterVehicle(vehicle)
		end
	end

	folder.ChildAdded:Connect(function(vehicle)
		if vehicle:IsA("Model") then
			task.defer(function()
				VehicleDamageManager.RegisterVehicle(vehicle)
			end)
		end
	end)
end

function VehicleDamageManager.Start()
	if started then
		return
	end
	started = true

	-- IMPORTANT: never yield here. VehicleDamageManager is required while the
	-- server is still booting, before VehicleSpawner may create ActiveVehicles.
	-- Waiting here blocks the entire require chain (flags/terminals/spawner too).
	local existing = Workspace:FindFirstChild(ACTIVE_VEHICLES_FOLDER_NAME)
	if existing then
		hookActiveVehiclesFolder(existing)
	end

	Workspace.ChildAdded:Connect(function(child)
		if child.Name == ACTIVE_VEHICLES_FOLDER_NAME and child:IsA("Folder") then
			hookActiveVehiclesFolder(child)
		end
	end)
end

return VehicleDamageManager
