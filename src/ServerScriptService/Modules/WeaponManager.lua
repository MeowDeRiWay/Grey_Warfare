local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProjectileManager = require(script.Parent.ProjectileManager)

local WeaponManager = {}

-- VERSION: MAGS + HOLSTER V6
-- Додано:
-- 1) магазини Reg/Utra на моделі персонажа;
-- 2) reload витрачає магазин тільки якщо в активному магазині витрачена хоча б 1 куля;
-- 3) X ховає/дістає зброю;
-- 4) зброя автоматично ховається в Driver_seat / Pass_seat;
-- 5) AimPitch з камери збережений.

local DEFAULT_WEAPON_NAME = "Pistol_A"
local EQUIPPED_WEAPON_FOLDER_NAME = "EquippedWeapon"
local REMOTE_NAME = "WeaponActionRequest"

local DEFAULT_REG_MAG_MAX = 10
local DEFAULT_UTRA_MAG_MAX = 5

local playerStates = {}

local function getRemotesFolder()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	return folder
end

local function getWeaponRemote()
	local remotes = getRemotesFolder()
	local remote = remotes:FindFirstChild(REMOTE_NAME)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_NAME
		remote.Parent = remotes
	end
	return remote
end

local function findWeaponTemplate(weaponName)
	local weaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")
	if not weaponsFolder then
		warn("[WeaponManager] ReplicatedStorage.Weapons not found")
		return nil
	end

	local direct = weaponsFolder:FindFirstChild(weaponName)
	if direct and direct:IsA("Model") then
		return direct
	end

	local modulesFolder = weaponsFolder:FindFirstChild("WModules")
	if modulesFolder then
		local fromModules = modulesFolder:FindFirstChild(weaponName)
		if fromModules and fromModules:IsA("Model") then
			return fromModules
		end
	end

	warn("[WeaponManager] Weapon template not found:", weaponName)
	return nil
end

local function getCharacterRoot(character)
	return character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("UpperTorso")
		or character:FindFirstChildWhichIsA("BasePart")
end

local function getMain(model)
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	local main = model:FindFirstChild("Main", true)
	if main and main:IsA("BasePart") then
		return main
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getBarrel(model)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") and item:GetAttribute("Barrel") == true then
			return item
		end
	end

	local barrel = model:FindFirstChild("Barrel", true)
	if barrel and barrel:IsA("BasePart") then
		return barrel
	end

	return nil
end

local function axisToLocalVector(axis)
	axis = tostring(axis or "X")

	if axis == "X" then return Vector3.xAxis end
	if axis == "-X" then return -Vector3.xAxis end
	if axis == "Y" then return Vector3.yAxis end
	if axis == "-Y" then return -Vector3.yAxis end
	if axis == "Z" then return Vector3.zAxis end
	if axis == "-Z" then return -Vector3.zAxis end

	return Vector3.xAxis
end

local function getBarrelDirection(weapon, barrel)
	local axis = barrel:GetAttribute("Barrel_axis") or weapon:GetAttribute("Barrel_axis") or "X"
	return barrel.CFrame:VectorToWorldSpace(axisToLocalVector(axis)).Unit
end

local function prepareWeaponParts(weapon)
	for _, item in ipairs(weapon:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = false
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.Massless = true
		end
	end
end

local function getNumberAttr(object, name, default)
	local value = object:GetAttribute(name)
	if value == nil then
		return default
	end
	return tonumber(value) or default
end

local function getBoolAttr(object, name, default)
	local value = object:GetAttribute(name)
	if value == nil then
		return default
	end
	return value == true
end

local function ensureCharacterStats(character)
	if not character then
		return
	end

	local maxHealth = tonumber(character:GetAttribute("Max_health")) or DEFAULT_REG_MAG_MAX * 10
	if character:GetAttribute("Max_health") == nil then
		character:SetAttribute("Max_health", maxHealth)
	end
	if character:GetAttribute("Current_health") == nil then
		character:SetAttribute("Current_health", maxHealth)
	end

	local regMax = tonumber(character:GetAttribute("Reg_mag_max")) or DEFAULT_REG_MAG_MAX
	if character:GetAttribute("Reg_mag_max") == nil then
		character:SetAttribute("Reg_mag_max", regMax)
	end
	if character:GetAttribute("Reg_mag_current") == nil then
		character:SetAttribute("Reg_mag_current", regMax)
	end

	local utraMax = tonumber(character:GetAttribute("Utra_mag_max")) or DEFAULT_UTRA_MAG_MAX
	if character:GetAttribute("Utra_mag_max") == nil then
		character:SetAttribute("Utra_mag_max", utraMax)
	end
	if character:GetAttribute("Utra_mag_current") == nil then
		character:SetAttribute("Utra_mag_current", utraMax)
	end
end

local function getMagazineAttrNames(weapon)
	local weaponType = tostring(weapon:GetAttribute("WeaponType") or "Regular")
	local weaponCal = tostring(weapon:GetAttribute("WeaponCal") or "")

	local lowerType = string.lower(weaponType)
	local lowerCal = string.lower(weaponCal)

	if lowerType == "utra" or lowerType == "heavy" or lowerCal:find("utra") or lowerCal:find("heavy") then
		return "Utra_mag_current", "Utra_mag_max"
	end

	return "Reg_mag_current", "Reg_mag_max"
end

local function buildHoldCFrame(weapon, aimPitch)
	aimPitch = tonumber(aimPitch) or 0

	local offsetX = getNumberAttr(weapon, "Hold_offset_x", 0)
	local offsetY = getNumberAttr(weapon, "Hold_offset_y", 0.05)
	local offsetZ = getNumberAttr(weapon, "Hold_offset_z", -1.15)

	local holdPitch = math.rad(getNumberAttr(weapon, "Hold_pitch", 0))
	local holdYaw = math.rad(getNumberAttr(weapon, "Hold_yaw", -90))
	local holdRoll = math.rad(getNumberAttr(weapon, "Hold_roll", 0))

	local aimScale = getNumberAttr(weapon, "Aim_pitch_scale", 1)
	local aimOffset = math.rad(getNumberAttr(weapon, "Aim_pitch_offset", 0))
	local finalAimPitch = aimPitch * aimScale + aimOffset

	if getBoolAttr(weapon, "Aim_pitch_invert", false) then
		finalAimPitch = -finalAimPitch
	end

	local holdCFrame = CFrame.new(offsetX, offsetY, offsetZ)
		* CFrame.Angles(0, holdYaw, 0)
		* CFrame.Angles(holdPitch, 0, 0)
		* CFrame.Angles(0, 0, holdRoll)

	local aimAxis = tostring(weapon:GetAttribute("Aim_pitch_axis") or "Z")

	if aimAxis == "X" then
		return holdCFrame * CFrame.Angles(finalAimPitch, 0, 0)
	elseif aimAxis == "-X" then
		return holdCFrame * CFrame.Angles(-finalAimPitch, 0, 0)
	elseif aimAxis == "Y" then
		return holdCFrame * CFrame.Angles(0, finalAimPitch, 0)
	elseif aimAxis == "-Y" then
		return holdCFrame * CFrame.Angles(0, -finalAimPitch, 0)
	elseif aimAxis == "-Z" then
		return holdCFrame * CFrame.Angles(0, 0, -finalAimPitch)
	end

	return holdCFrame * CFrame.Angles(0, 0, finalAimPitch)
end

local function applyWeaponAim(state)
	if not state then
		return
	end

	local weapon = state.Weapon
	local weld = state.WeaponWeld
	local mainLocalOffset = state.MainLocalOffset
	local aimPitch = state.AimPitch or 0

	if not weapon or not weapon.Parent or not weld or not weld.Parent or not mainLocalOffset then
		return
	end

	weld.C0 = buildHoldCFrame(weapon, aimPitch) * mainLocalOffset
end

local function weldWeaponToCharacter(weapon, character, state)
	local root = getCharacterRoot(character)
	local main = getMain(weapon)
	if not root or not main then
		return false
	end

	weapon.PrimaryPart = main

	local aimPitch = 0
	if state then
		aimPitch = state.AimPitch or 0
	end

	local holdCFrame = buildHoldCFrame(weapon, aimPitch)
	local targetPivotCFrame = root.CFrame * holdCFrame

	weapon:PivotTo(targetPivotCFrame)

	local mainLocalOffset = targetPivotCFrame:ToObjectSpace(main.CFrame)

	local weld = Instance.new("Weld")
	weld.Name = "WeaponRootWeld"
	weld.Part0 = root
	weld.Part1 = main
	weld.C0 = holdCFrame * mainLocalOffset
	weld.C1 = CFrame.identity
	weld.Parent = main

	if state then
		state.WeaponWeld = weld
		state.MainLocalOffset = mainLocalOffset
	end

	return true
end

local function getState(player)
	local state = playerStates[player]
	if state then
		return state
	end

	state = {
		Weapon = nil,
		WeaponWeld = nil,
		MainLocalOffset = nil,
		WeaponName = DEFAULT_WEAPON_NAME,
		AimPitch = 0,
		Ammo = nil,
		LastShotTime = 0,
		Reloading = false,
		HiddenByPlayer = false,
		HiddenBySeat = false,
	}
	playerStates[player] = state
	return state
end

local function destroyEquippedWeapon(state)
	if state.Weapon and state.Weapon.Parent then
		state.Weapon:Destroy()
	end
	state.Weapon = nil
	state.WeaponWeld = nil
	state.MainLocalOffset = nil
end

local function shouldHideWeapon(state)
	return state.HiddenByPlayer == true or state.HiddenBySeat == true
end

function WeaponManager.EquipWeapon(player, weaponName)
	weaponName = weaponName or DEFAULT_WEAPON_NAME

	local character = player.Character
	if not character then
		return nil
	end

	ensureCharacterStats(character)

	local state = getState(player)
	state.WeaponName = weaponName

	if shouldHideWeapon(state) then
		destroyEquippedWeapon(state)
		return nil
	end

	local template = findWeaponTemplate(weaponName)
	if not template then
		return nil
	end

	local oldFolder = character:FindFirstChild(EQUIPPED_WEAPON_FOLDER_NAME)
	if oldFolder then
		oldFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = EQUIPPED_WEAPON_FOLDER_NAME
	folder.Parent = character

	local weapon = template:Clone()
	weapon.Name = weaponName
	weapon.Parent = folder

	prepareWeaponParts(weapon)

	local magazineSize = tonumber(weapon:GetAttribute("Magazine_size")) or 7
	if state.Ammo == nil then
		state.Ammo = magazineSize
	else
		state.Ammo = math.clamp(tonumber(state.Ammo) or magazineSize, 0, magazineSize)
	end

	state.Weapon = weapon
	state.WeaponWeld = nil
	state.MainLocalOffset = nil
	state.LastShotTime = 0
	state.Reloading = false

	if not weldWeaponToCharacter(weapon, character, state) then
		warn("[WeaponManager] Failed to weld weapon:", player.Name, weaponName)
		weapon:Destroy()
		return nil
	end

	weapon:SetAttribute("Current_ammo", state.Ammo)
	print("[WeaponManager MAGS V6] Equipped:", player.Name, weaponName)
	return weapon
end

local function refreshEquippedWeapon(player)
	local state = getState(player)

	if shouldHideWeapon(state) then
		destroyEquippedWeapon(state)
	else
		if not state.Weapon or not state.Weapon.Parent then
			WeaponManager.EquipWeapon(player, state.WeaponName or DEFAULT_WEAPON_NAME)
		end
	end
end

local function reloadWeapon(player)
	local state = getState(player)
	local weapon = state.Weapon

	if shouldHideWeapon(state) or not weapon or not weapon.Parent or state.Reloading then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	ensureCharacterStats(character)

	local magazineSize = tonumber(weapon:GetAttribute("Magazine_size")) or 7

	-- Повний магазин не перезаряджаємо і магазин запасу не витрачаємо.
	if state.Ammo >= magazineSize then
		return
	end

	local currentMagAttr = getMagazineAttrNames(weapon)
	local reserveMags = tonumber(character:GetAttribute(currentMagAttr)) or 0
	if reserveMags <= 0 then
		return
	end

	state.Reloading = true
	local reloadTime = tonumber(weapon:GetAttribute("Reload_time")) or 1.5

	task.delay(reloadTime, function()
		if not player.Parent then return end
		local currentState = getState(player)
		if currentState.Weapon ~= weapon then return end
		if not weapon.Parent then return end
		if shouldHideWeapon(currentState) then return end

		local currentCharacter = player.Character
		if not currentCharacter then return end

		local magAttr = getMagazineAttrNames(weapon)
		local currentReserve = tonumber(currentCharacter:GetAttribute(magAttr)) or 0
		if currentReserve <= 0 then
			currentState.Reloading = false
			return
		end

		currentCharacter:SetAttribute(magAttr, currentReserve - 1)
		currentState.Ammo = magazineSize
		currentState.Reloading = false
		weapon:SetAttribute("Current_ammo", currentState.Ammo)
	end)
end

local function fireWeapon(player)
	local state = getState(player)
	local weapon = state.Weapon

	if shouldHideWeapon(state) then
		return
	end

	if not weapon or not weapon.Parent then
		weapon = WeaponManager.EquipWeapon(player, state.WeaponName or DEFAULT_WEAPON_NAME)
		if not weapon then
			return
		end
	end

	if state.Reloading then
		return
	end

	local now = os.clock()
	local fireRate = tonumber(weapon:GetAttribute("Fire_rate")) or 0.35
	if now - state.LastShotTime < fireRate then
		return
	end

	if (state.Ammo or 0) <= 0 then
		reloadWeapon(player)
		return
	end

	local barrel = getBarrel(weapon)
	if not barrel then
		warn("[WeaponManager] Barrel not found:", weapon.Name)
		return
	end

	state.LastShotTime = now
	state.Ammo -= 1
	weapon:SetAttribute("Current_ammo", state.Ammo)

	local direction = getBarrelDirection(weapon, barrel)
	local origin = barrel.Position + direction * 0.25

	ProjectileManager.FireBullet({
		Owner = player,
		Weapon = weapon,
		Origin = origin,
		Direction = direction,
		Speed = tonumber(weapon:GetAttribute("Projectile_speed")) or 180,
		Gravity = tonumber(weapon:GetAttribute("Projectile_gravity")) or 60,
		Damage = tonumber(weapon:GetAttribute("Damage")) or 20,
		Size = tonumber(weapon:GetAttribute("Projectile_size")) or 0.15,
	})
end

local function setAimPitch(player, aimPitch)
	local state = getState(player)
	if type(aimPitch) ~= "number" then
		return
	end

	state.AimPitch = aimPitch
	applyWeaponAim(state)
end

local function setSeatHidden(player, hidden)
	local state = getState(player)
	state.HiddenBySeat = hidden == true
	refreshEquippedWeapon(player)
end

local function togglePlayerHidden(player)
	local state = getState(player)
	state.HiddenByPlayer = not state.HiddenByPlayer
	refreshEquippedWeapon(player)
end

local function isWeaponHidingSeat(seat)
	if not seat or not seat:IsA("Seat") and not seat:IsA("VehicleSeat") then
		return false
	end

	if seat.Name == "Driver_seat" or seat.Name == "Pass_seat" then
		return true
	end

	if seat:GetAttribute("HideWeapon") == true then
		return true
	end

	return false
end

local function hookCharacter(player, character)
	ensureCharacterStats(character)

	local state = getState(player)
	state.WeaponName = DEFAULT_WEAPON_NAME
	state.Ammo = nil
	state.Reloading = false
	state.HiddenBySeat = false

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Seated:Connect(function(active, seat)
			setSeatHidden(player, active == true and isWeaponHidingSeat(seat))
		end)
	end

	task.wait(0.5)
	refreshEquippedWeapon(player)
end

function WeaponManager.StartRemoteListener()
	getWeaponRemote().OnServerEvent:Connect(function(player, action, value)
		if action == "Fire" then
			fireWeapon(player)
		elseif action == "Reload" then
			reloadWeapon(player)
		elseif action == "AimPitch" then
			setAimPitch(player, value)
		elseif action == "ToggleWeapon" then
			togglePlayerHidden(player)
		end
	end)
end

function WeaponManager.StartAutoEquip()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			task.defer(function()
				hookCharacter(player, player.Character)
			end)
		end

		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
	end
end

Players.PlayerRemoving:Connect(function(player)
	playerStates[player] = nil
end)

return WeaponManager
