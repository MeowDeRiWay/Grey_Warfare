local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ServerScriptService:WaitForChild("Modules")

local FlagManager = require(Modules:WaitForChild("FlagManager"))
local TerritoryManager = require(Modules:WaitForChild("TerritoryManager"))
local VehicleTerminalManager = require(Modules:WaitForChild("VehicleTerminalManager"))

FlagManager.SetupAllFlags()
FlagManager.StartAutoSetup()

TerritoryManager.SetupAllObjects()
TerritoryManager.StartAutoSetup()
TerritoryManager.StartLoop()

VehicleTerminalManager.SetupAll()
VehicleTerminalManager.StartAutoSetup()

print("[TeamOwnership] Started")