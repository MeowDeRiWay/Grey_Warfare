local Workspace = game:GetService("Workspace")

local VehicleExitManager = {}
local exiting = setmetatable({}, {__mode = "k"})

local function getVehicle(seat)
 local folder = Workspace:FindFirstChild("ActiveVehicles")
 local current = seat
 while current and current ~= Workspace do
  if current:IsA("Model") and current.Parent == folder then return current end
  current = current.Parent
 end
 return nil
end

local function isVehiclePart(part)
 local current = part.Parent
 while current and current ~= Workspace do
  if current:IsA("Model") and current:GetAttribute("OwnerUserId") ~= nil then return true end
  current = current.Parent
 end
 return false
end

local function findExitPosition(vehicle, seat, character, root)
 local main = vehicle:FindFirstChild("Main") or vehicle.PrimaryPart or seat
 local forward = Vector3.new(main.CFrame.LookVector.X, 0, main.CFrame.LookVector.Z)
 if forward.Magnitude < 0.001 then forward = Vector3.new(0, 0, -1) end
 local frame = CFrame.lookAt(main.Position, main.Position + forward.Unit)
 local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
 for _, part in ipairs(vehicle:GetDescendants()) do
  -- Invisible interaction zones do not enlarge the vehicle footprint.
  if part:IsA("BasePart") and (part == main or part.Transparency < 1) then
   for _, x in ipairs({-0.5, 0.5}) do
    for _, y in ipairs({-0.5, 0.5}) do
     for _, z in ipairs({-0.5, 0.5}) do
      local world = part.CFrame:PointToWorldSpace(Vector3.new(x * part.Size.X, y * part.Size.Y, z * part.Size.Z))
      local pos = frame:PointToObjectSpace(world)
      minX, maxX = math.min(minX, pos.X), math.max(maxX, pos.X)
      minZ, maxZ = math.min(minZ, pos.Z), math.max(maxZ, pos.Z)
     end
    end
   end
  end
 end
 local charFrame, charSize = character:GetBoundingBox()
 local radius = math.max(0.35, math.max(charSize.X, charSize.Z) / 2)
 local height = math.max(0.5, charSize.Y)
 local rootToBottom = math.max(root.Size.Y / 2, root.Position.Y - (charFrame.Position.Y - charSize.Y / 2))
 local margin = math.max(0.2, tonumber(vehicle:GetAttribute("Exit_margin")) or 0.5)
 local groundSearch = math.max(1, tonumber(vehicle:GetAttribute("Exit_ground_search")) or 30)
 local ray = RaycastParams.new()
 ray.FilterType = Enum.RaycastFilterType.Exclude
 ray.FilterDescendantsInstances = {vehicle, character}
 ray.IgnoreWater = true
 ray.RespectCanCollide = true
 local overlap = OverlapParams.new()
 overlap.FilterType = Enum.RaycastFilterType.Exclude
 overlap.FilterDescendantsInstances = {vehicle, character}
 overlap.MaxParts = 0
 local centerX, centerZ = (minX + maxX) / 2, (minZ + maxZ) / 2
 for ring = 1, 3 do
  local gap = radius + margin + (ring - 1) * (radius * 2 + margin)
  local candidates = {
   Vector3.new(maxX + gap, 0, centerZ), Vector3.new(minX - gap, 0, centerZ),
   Vector3.new(centerX, 0, maxZ + gap), Vector3.new(centerX, 0, minZ - gap),
   Vector3.new(maxX + gap, 0, maxZ + gap), Vector3.new(minX - gap, 0, maxZ + gap),
   Vector3.new(maxX + gap, 0, minZ - gap), Vector3.new(minX - gap, 0, minZ - gap),
  }
  for _, offset in ipairs(candidates) do
   local world = frame:PointToWorldSpace(offset)
   local start = Vector3.new(world.X, seat.Position.Y + height + 2, world.Z)
   local hit = Workspace:Raycast(start, Vector3.new(0, -(groundSearch + height + 2), 0), ray)
   -- Airborne vehicles release the player beside the vehicle at seat height.
   local bottomY = hit and hit.Position.Y + 0.15 or seat.Position.Y - rootToBottom
   local position = Vector3.new(world.X, bottomY + rootToBottom, world.Z)
   local bodyCenter = Vector3.new(world.X, bottomY + height / 2, world.Z)
   local clear = not hit or hit.Normal.Y >= 0.5
   if clear then
    for _, part in ipairs(Workspace:GetPartBoundsInBox(CFrame.new(bodyCenter), Vector3.new(radius * 2, height, radius * 2), overlap)) do
     if part:IsA("BasePart") and (part.CanCollide or (part.Transparency < 1 and isVehiclePart(part))) then
      clear = false
      break
     end
    end
   end
   -- Terrain ceilings are not returned by the part overlap query.
   if clear and Workspace:Raycast(Vector3.new(world.X, bottomY + 0.05, world.Z), Vector3.new(0, height, 0), ray) then
    clear = false
   end
   if clear then return position end
  end
 end
 return nil
end

function VehicleExitManager.IsExiting(humanoid)
 return exiting[humanoid] == true
end

function VehicleExitManager.PlaceOutside(vehicle, seat, humanoid)
 if exiting[humanoid] or not humanoid or humanoid.Health <= 0 then return false end
 local character = humanoid.Parent
 local root = character and character:FindFirstChild("HumanoidRootPart")
 if not root or not vehicle.Parent or not seat.Parent or vehicle:GetAttribute("Destroyed") == true then return false end
 local position = findExitPosition(vehicle, seat, character, root)
 if not position then return false end
 exiting[humanoid] = true
 humanoid.Sit = false
 task.defer(function()
  -- SeatWeld must be detached before teleporting: otherwise the chassis may be dragged too.
  for _, weld in ipairs(seat:GetChildren()) do
   if weld.Name == "SeatWeld" and weld:IsA("Weld") then
    local a, b = weld.Part0, weld.Part1
    if (a and a:IsDescendantOf(character)) or (b and b:IsDescendantOf(character)) then weld:Destroy() end
   end
  end
  for _ = 1, 12 do
   if humanoid.SeatPart ~= seat then break end
   task.wait()
  end
  if character.Parent and root.Parent and humanoid.Health > 0 and not humanoid.SeatPart then
   if vehicle.Parent and seat.Parent then
    position = findExitPosition(vehicle, seat, character, root) or position
   end
   local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
   if look.Magnitude < 0.001 then look = Vector3.new(0, 0, -1) end
   local targetRoot = CFrame.lookAt(position, position + look.Unit)
   character:PivotTo(targetRoot * root.CFrame:Inverse() * character:GetPivot())
   root.AssemblyLinearVelocity = Vector3.zero
   root.AssemblyAngularVelocity = Vector3.zero
  end
  exiting[humanoid] = nil
 end)
 return true
end

function VehicleExitManager.TryExit(player)
 local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
 local seat = humanoid and humanoid.SeatPart
 local vehicle = seat and getVehicle(seat)
 if not vehicle then return false end
 return VehicleExitManager.PlaceOutside(vehicle, seat, humanoid)
end

return VehicleExitManager
