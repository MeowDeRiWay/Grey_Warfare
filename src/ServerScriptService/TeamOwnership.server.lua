local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ServerScriptService:WaitForChild("Modules")

local FlagManager = require(Modules:WaitForChild("FlagManager"))

FlagManager.SetupAllFlags()
FlagManager.StartAutoSetup()

print("[TeamOwnership] Started")