local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProjectileManager = require(script.Parent.ProjectileManager)

local WeaponManager = {}

-- VERSION: AIM PITCH CAMERA V4
-- Зброя тримається через Weld, а не WeldConstraint.
-- Ліво/право лишається за тілом, верх/низ приходить від камери через AimPitch.

local DEFAULT_WEAPON_NAME = "Pistol_A"
local EQUIPPED_WEAPON_FOLDER_NAME = "EquippedWeapon"
local REMOTE_NAME = "WeaponActionRequest"

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

	-- Основний шлях для ручної зброї:
	-- ReplicatedStorage/Weapons/Pistol_A
	local direct = weaponsFolder:FindFirstChild(weaponName)
	if direct and direct:IsA("Model") then
		return direct
	end

	-- Запасний шлях на майбутнє, якщо колись захочеш окрему папку модулів.
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

	-- V5:
	-- Після ручного вирівнювання Hold_* камера може крутити не ту вісь.
	-- Тому вісь прицілювання задається атрибутом на зброї:
	-- Aim_pitch_axis = "X" / "-X" / "Y" / "-Y" / "Z" / "-Z"
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

	-- Через PivotTo у моделі може бути власний PivotOffset.
	-- Тому запам'ятовуємо реальне положення Main відносно targetPivotCFrame,
	-- щоб наступні зміни AimPitch не ламали твою ручну підгонку Hold_*.
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
		AimPitch = 0,
		Ammo = 0,
		LastShotTime = 0,
		Reloading = false,
	}
	playerStates[player] = state
	return state
end

function WeaponManager.EquipWeapon(player, weaponName)
	weaponName = weaponName or DEFAULT_WEAPON_NAME

	local character = player.Character
	if not character then
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
	local state = getState(player)
	state.Weapon = weapon
	state.WeaponWeld = nil
	state.MainLocalOffset = nil
	state.Ammo = magazineSize
	state.LastShotTime = 0
	state.Reloading = false

	if not weldWeaponToCharacter(weapon, character, state) then
		warn("[WeaponManager] Failed to weld weapon:", player.Name, weaponName)
		weapon:Destroy()
		return nil
	end

	weapon:SetAttribute("Current_ammo", state.Ammo)
	print("[WeaponManager AIM PITCH V4] Equipped:", player.Name, weaponName, "pitch/yaw/roll:", weapon:GetAttribute("Hold_pitch"), weapon:GetAttribute("Hold_yaw"), weapon:GetAttribute("Hold_roll"))
	return weapon
end

local function reloadWeapon(player)
	local state = getState(player)
	local weapon = state.Weapon
	if not weapon or not weapon.Parent or state.Reloading then
		return
	end

	state.Reloading = true
	local reloadTime = tonumber(weapon:GetAttribute("Reload_time")) or 1.5

	task.delay(reloadTime, function()
		if not player.Parent then return end
		local currentState = getState(player)
		if currentState.Weapon ~= weapon then return end
		if not weapon.Parent then return end

		local magazineSize = tonumber(weapon:GetAttribute("Magazine_size")) or 7
		currentState.Ammo = magazineSize
		currentState.Reloading = false
		weapon:SetAttribute("Current_ammo", currentState.Ammo)
	end)
end

local function fireWeapon(player)
	local state = getState(player)
	local weapon = state.Weapon

	if not weapon or not weapon.Parent then
		weapon = WeaponManager.EquipWeapon(player, DEFAULT_WEAPON_NAME)
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

	if state.Ammo <= 0 then
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

function WeaponManager.StartRemoteListener()
	getWeaponRemote().OnServerEvent:Connect(function(player, action, value)
		if action == "Fire" then
			fireWeapon(player)
		elseif action == "Reload" then
			reloadWeapon(player)
		elseif action == "AimPitch" then
			setAimPitch(player, value)
		end
	end)
end

function WeaponManager.StartAutoEquip()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			WeaponManager.EquipWeapon(player, DEFAULT_WEAPON_NAME)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			task.defer(function()
				WeaponManager.EquipWeapon(player, DEFAULT_WEAPON_NAME)
			end)
		end
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			WeaponManager.EquipWeapon(player, DEFAULT_WEAPON_NAME)
		end)
	end
end

Players.PlayerRemoving:Connect(function(player)
	playerStates[player] = nil
end)

return WeaponManager
