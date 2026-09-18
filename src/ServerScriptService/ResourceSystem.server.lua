local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ServerScriptService:WaitForChild("Modules")
local ResourceManager = require(Modules:WaitForChild("ResourceManager"))

ResourceManager.Start()

print("[ResourceSystem] Started")
