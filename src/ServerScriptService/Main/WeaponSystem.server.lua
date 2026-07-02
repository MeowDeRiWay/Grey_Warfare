local Modules = script.Parent.Parent:WaitForChild("Modules")

local WeaponManager = require(Modules:WaitForChild("WeaponManager"))

WeaponManager.StartRemoteListener()
WeaponManager.StartAutoEquip()
