local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ServerScriptService:WaitForChild("Modules")

local FlagManager = require(Modules:WaitForChild("FlagManager"))
local TerritoryManager = require(Modules:WaitForChild("TerritoryManager"))

FlagManager.SetupAllFlags()
FlagManager.StartAutoSetup()

TerritoryManager.SetupAllObjects()
TerritoryManager.StartAutoSetup()
TerritoryManager.StartLoop()

print("[TeamOwnership] Started")