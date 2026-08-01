--[[
  ATM10 Mining Dimension Ore Turtle
  ----------------------------------
  - Asks which top-down layer to start on, the ore Y-band, world Y, and square size
  - Mines a main shaft to the right with branches spaced 3 blocks apart
  - Collects every block it mines (not only the selected band ore)
  - Follows connected ore veins (capped at 128 blocks) then resumes
  - After each square, descends 3 blocks and repeats through the band
  - Returns home after every layer and waits for approval to continue
  - Tracks position via dead-reckoning and auto-returns to refuel/unload

  SETUP (do this before running):
  1. Place the turtle at your dock -- this spot becomes "home" (0,0,0).
  2. Put a chest directly BEHIND the turtle (opposite the tunnel
     direction). This chest receives mined ore. Put one empty bucket in
     CHEST SLOT 1 so dumped blocks cannot take over the bucket slot.
  3. Put a bucket-fillable lava tank directly LEFT of the turtle while
     it faces the tunnel. Keep this tank supplied with lava.
  4. If you also have an RF/FE charging-station peripheral wired up next
     to the dock (e.g. the "Turtle Charging Station" mod), the script
     finds and uses that automatically.
  5. Face the turtle down the tunnel direction you want it to dig --
     i.e. AWAY from the drop-off chest -- before the first run. Whatever
     direction it's facing the very first time you run "mine" becomes
     both "home" (0,0,0) and the tunnel direction for good.
  6. Run: mine
]]--

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------
local MIN_FUEL_BUFFER = 200       -- extra fuel kept in reserve on top of the calculated trip home
local REFUEL_BELOW    = 1000      -- skip refueling when at or above this fuel level
local REFUEL_TARGET   = 5000      -- stop consuming fuel after reaching this level
local DROP_OFF_HOME   = true      -- dump all mined blocks into the shared chest on every return
local STATE_FILE      = "turtle_state.txt"
local KEEP_SLOTS      = {1}       -- slot 1 holds the reusable lava bucket
local TUNNEL_SPACING  = 3         -- blocks between parallel tunnels / between layers
local VEIN_CAP        = 128       -- max blocks to follow in a single connected vein

-- ATM10 Mining Dimension ore Y-bands (from AllTheMods' own ore distribution chart)
local ORE_BANDS = {
  gold         = {65, 155},
  diamond      = {93, 174},
  iron         = {65, 247},
  coal         = {65, 247},
  copper       = {65, 247},
  redstone     = {65, 205},
  lapis        = {65, 146},
  emerald      = {65, 247},
  allthemodium = {65, 128},
  ancient_debris = {1, 64},
  debris       = {1, 64},
  uranium      = {-62, 157},
  platinum     = {-62, 34},
  silver       = {-62, 34},
  osmium       = {-62, 64},
  nickel       = {-62, 64},
  nickle       = {-62, 64}, -- pack's ore table spells it "Nickle Ore"
  tin          = {-62, 181},
  zinc         = {-62, 128},
  lead         = {-62, 34},
  prosperity   = {65, 249},
}

-- ATM progression ores are player-only in ATM10. Detect and preserve them.
local PROTECTED_ORES = {
  ["allthemodium:allthemodium_ore"] = true,
  ["allthemodium:vibranium_ore"] = true,
  ["allthemodium:unobtainium_ore"] = true,
}

local BAND_ALIASES = {
  ["ancient debris"] = "ancient_debris",
  ["ancientdebris"] = "ancient_debris",
  ["netherite"] = "ancient_debris",
  ["prosperity shard"] = "prosperity",
  ["prosperity_shard"] = "prosperity",
  ["prosperity ore"] = "prosperity",
}

------------------------------------------------------------
-- STATE (dead-reckoning position, saved to disk so a reboot
-- or unload doesn't lose track of home)
------------------------------------------------------------
local pos    = {x = 0, y = 0, z = 0}
local facing = 0 -- 0=north(-z) 1=east(+x) 2=south(+z) 3=west(-x)
local DX = {0, 1, 0, -1}
local DZ = {-1, 0, 1, 0}

local function saveState()
  local f = fs.open(STATE_FILE, "w")
  f.write(textutils.serialize({pos = pos, facing = facing}))
  f.close()
end

local function loadState()
  if fs.exists(STATE_FILE) then
    local f = fs.open(STATE_FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()
    if data then
      pos, facing = data.pos, data.facing
      return true
    end
  end
  return false
end

local function isProtectedOreName(name)
  if not name then return false end
  local n = name:lower()
  if PROTECTED_ORES[n] then return true end
  if not n:find("allthemodium:", 1, true) then return false end
  return n:find("allthemodium_ore", 1, true) ~= nil or
         n:find("vibranium_ore", 1, true) ~= nil or
         n:find("unobtainium_ore", 1, true) ~= nil
end

local function warnProtectedOre(data, direction)
  print("Protected ATM ore found " .. direction .. " at relative (" ..
        pos.x .. "," .. pos.y .. "," .. pos.z .. ").")
  print("Leaving " .. data.name .. " intact for manual mining.")
end

------------------------------------------------------------
-- LOW-LEVEL MOVEMENT (wraps turtle.* and updates pos/facing)
------------------------------------------------------------
local function turnLeft()
  turtle.turnLeft()
  facing = (facing + 3) % 4
  saveState()
end

local function turnRight()
  turtle.turnRight()
  facing = (facing + 1) % 4
  saveState()
end

local function faceDir(target)
  while facing ~= target do turnRight() end
end

local function digForward()
  while turtle.detect() do
    local ok, data = turtle.inspect()
    if ok and isProtectedOreName(data.name) then
      warnProtectedOre(data, "ahead")
      return false
    end
    if not turtle.dig() then return false end
    sleep(0.4)
  end
  return true
end

local function forward()
  if not digForward() then return false end
  if turtle.forward() then
    pos.x = pos.x + DX[facing + 1]
    pos.z = pos.z + DZ[facing + 1]
    saveState()
    return true
  end
  return false
end

local function back()
  if turtle.back() then
    pos.x = pos.x - DX[facing + 1]
    pos.z = pos.z - DZ[facing + 1]
    saveState()
    return true
  end

  -- Fallback if something is blocking the rear
  faceDir((facing + 2) % 4)
  local ok = forward()
  faceDir((facing + 2) % 4)
  return ok
end

local function up()
  while turtle.detectUp() do
    local ok, data = turtle.inspectUp()
    if ok and isProtectedOreName(data.name) then
      warnProtectedOre(data, "above")
      return false
    end
    if not turtle.digUp() then return false end
    sleep(0.4)
  end
  if turtle.up() then
    pos.y = pos.y + 1
    saveState()
    return true
  end
  return false
end

local function down()
  while turtle.detectDown() do
    local ok, data = turtle.inspectDown()
    if ok and isProtectedOreName(data.name) then
      warnProtectedOre(data, "below")
      return false
    end
    if not turtle.digDown() then return false end
    sleep(0.4)
  end
  if turtle.down() then
    pos.y = pos.y - 1
    saveState()
    return true
  end
  return false
end

------------------------------------------------------------
-- VALUABLE / SPOIL DETECTION
------------------------------------------------------------
local function isKeepSlot(slot)
  for _, k in ipairs(KEEP_SLOTS) do
    if slot == k then return true end
  end
  return false
end

local function hasOreTag(tags)
  if not tags then return false end
  for tag, _ in pairs(tags) do
    local t = tostring(tag):lower()
    if t == "c:ores" or t == "forge:ores" or t == "c:ore" or t == "forge:ore" then
      return true
    end
    if t:find("ores/", 1, true) or t:find("/ores", 1, true) then
      return true
    end
    if t:match("ores$") or t:match(":ore$") then
      return true
    end
  end
  return false
end

local function isValuableBlock(data)
  if not data or not data.name then return false end
  local name = data.name:lower()

  if isProtectedOreName(name) then return false end
  if name:find("ancient_debris", 1, true) then return true end
  if hasOreTag(data.tags) then return true end
  if name:find("_ore", 1, true) or name:find(":ore_", 1, true) then return true end
  if name:match("ore$") then return true end
  return false
end

local function freeSlots()
  local free = 0
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then free = free + 1 end
  end
  return free
end

------------------------------------------------------------
-- REFUELING
------------------------------------------------------------
local function findChargingPeripheral()
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name)
    if t and (t:find("charg") or t:find("energ")) then
      return peripheral.wrap(name)
    end
  end
  return nil
end

local function isBucket(item)
  return item and
         (item.name == "minecraft:bucket" or item.name == "minecraft:lava_bucket")
end

local function ensureLavaBucket()
  faceDir(2) -- shared chest is behind the turtle's home direction

  local slotOne = turtle.getItemDetail(1)
  if not isBucket(slotOne) then
    if slotOne then
      turtle.select(1)
      if not turtle.drop() then
        print("Could not clear turtle slot 1 into the shared chest.")
        return false
      end
    end

    -- Reuse a bucket already carried in another inventory slot.
    for slot = 2, 16 do
      local item = turtle.getItemDetail(slot)
      if isBucket(item) then
        turtle.select(slot)
        if turtle.transferTo(1, 1) then
          return true
        end
      end
    end

    local chest = peripheral.wrap("front")
    if not chest or type(chest.list) ~= "function" then
      print("Unable to inspect the shared chest behind the turtle.")
      return false
    end

    local chestBucket = chest.list()[1]
    if not isBucket(chestBucket) then
      print("Put an empty bucket in slot 1 of the shared chest.")
      return false
    end

    turtle.select(1)
    if not turtle.suck(1) or not isBucket(turtle.getItemDetail(1)) then
      print("Could not pull the bucket from chest slot 1.")
      return false
    end
  end

  return true
end

local function refuelFromLavaTank(target)
  if pos.x ~= 0 or pos.y ~= 0 or pos.z ~= 0 then
    return false
  end
  if not ensureLavaBucket() then
    faceDir(0)
    return false
  end

  target = target or turtle.getFuelLimit()
  faceDir(3) -- lava tank is left of the turtle's home direction
  turtle.select(1)
  local burned = 0

  while turtle.getFuelLevel() ~= "unlimited" and
        turtle.getFuelLevel() < target do
    local item = turtle.getItemDetail(1)
    if item and item.name == "minecraft:bucket" then
      if not turtle.place() then
        print("The lava tank is empty or could not fill the bucket.")
        break
      end
      item = turtle.getItemDetail(1)
    end

    if not item or item.name ~= "minecraft:lava_bucket" or
       not turtle.refuel(1) then
      print("The tank did not provide a usable lava bucket.")
      break
    end
    burned = burned + 1
  end

  local fuel = turtle.getFuelLevel()
  print("Burned " .. burned .. " lava bucket(s). Fuel: " .. tostring(fuel))
  faceDir(0)
  turtle.select(1)
  return fuel == "unlimited" or fuel >= target
end

local function refuel()
  print("Refueling from the lava tank at home...")
  local target = math.min(REFUEL_TARGET, turtle.getFuelLimit())
  if refuelFromLavaTank(target) then return end

  local charger = findChargingPeripheral()
  if charger then
    print("Found a charging peripheral, waiting for " .. target .. " fuel...")
    while turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < target do
      sleep(2)
    end
    print("Charged via peripheral.")
  end
end

local function refuelIfNeeded()
  local fuel = turtle.getFuelLevel()
  if fuel == "unlimited" then
    print("Fuel is unlimited; skipping refuel.")
    return
  end
  if fuel >= REFUEL_BELOW then
    print("Fuel is " .. fuel .. " (threshold " .. REFUEL_BELOW ..
          "); skipping refuel.")
    return
  end
  refuel()
end

local function refuelFromInventory(target)
  local selectedSlot = turtle.getSelectedSlot()
  local burned = 0

  for slot = 1, 16 do
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" or fuel >= target then break end

    turtle.select(slot)
    if turtle.getItemCount(slot) > 0 and turtle.refuel(0) then
      while turtle.getItemCount(slot) > 0 do
        fuel = turtle.getFuelLevel()
        if fuel == "unlimited" or fuel >= target then break end
        if not turtle.refuel(1) then break end
        burned = burned + 1
      end
    end
  end

  turtle.select(selectedSlot)
  local fuel = turtle.getFuelLevel()
  if burned > 0 then
    print("Burned " .. burned .. " carried fuel item(s). Fuel: " ..
          tostring(fuel))
  end
  return fuel == "unlimited" or fuel >= target
end

------------------------------------------------------------
-- NAVIGATE HOME AND BACK OUT AGAIN
------------------------------------------------------------
local function distanceHome()
  return math.abs(pos.x) + math.abs(pos.y) + math.abs(pos.z)
end

local function goTo(x, y, z)
  if pos.y < y then
    while pos.y < y do if not up() then return false end end
  elseif pos.y > y then
    while pos.y > y do if not down() then return false end end
  end

  if pos.x < x then
    faceDir(1)
    while pos.x < x do if not forward() then return false end end
  elseif pos.x > x then
    faceDir(3)
    while pos.x > x do if not forward() then return false end end
  end

  if pos.z < z then
    faceDir(2)
    while pos.z < z do if not forward() then return false end end
  elseif pos.z > z then
    faceDir(0)
    while pos.z > z do if not forward() then return false end end
  end

  return true
end

-- Active branch route: branch -> main shaft -> layer origin -> home.
local routeActive = false
local routeLayerY = 0
local routeBranchX = 0

local function followRouteHome()
  if routeActive then
    if not goTo(routeBranchX, routeLayerY, 0) then return false end
    if not goTo(0, routeLayerY, 0) then return false end
  end
  return goTo(0, 0, 0)
end

local function returnAlongRoute(x, y, z)
  if routeActive then
    if not goTo(0, routeLayerY, 0) then return false end
    if not goTo(routeBranchX, routeLayerY, 0) then return false end
  end
  return goTo(x, y, z)
end

local function goHome(stayHome)
  local outX, outY, outZ, outFacing = pos.x, pos.y, pos.z, facing
  print("Heading home to unload/refuel (" .. distanceHome() .. " blocks)...")
  if not followRouteHome() then
    print("Could not reach home; mining stopped.")
    return false
  end
  faceDir(0) -- face 0 = the tunnel direction, same way it started
  faceDir(2) -- turn around 180 to face the shared chest

  local unloadOk = true
  if DROP_OFF_HOME then
    -- Park the bucket first so it reserves chest slot 1 while ore is dumped.
    local bucketParked = false
    local bucket = turtle.getItemDetail(1)
    if isBucket(bucket) then
      turtle.select(1)
      bucketParked = turtle.drop(1)
      if not bucketParked then unloadOk = false end
    end

    for slot = 1, 16 do
      if not isKeepSlot(slot) then
        local item = turtle.getItemDetail(slot)
        if item then
          turtle.select(slot)
          if not turtle.drop() then unloadOk = false end
        end
      end
    end

    turtle.select(1)
    if bucketParked and
       (not turtle.suck(1) or not isBucket(turtle.getItemDetail(1))) then
      print("Could not retrieve the bucket from chest slot 1.")
      unloadOk = false
    end
  end

  if not unloadOk then
    print("The shared chest is full; mining stopped at home.")
    faceDir(0)
    return false
  end

  refuelIfNeeded()
  faceDir(0) -- turn back to face the tunnel
  if stayHome then return true end

  print("Heading back out to (" .. outX .. "," .. outY .. "," .. outZ .. ")...")
  if not returnAlongRoute(outX, outY, outZ) then
    print("Could not return to the mining position.")
    return false
  end
  faceDir(outFacing)
  return true
end

local function ensureFuel()
  local fuel = turtle.getFuelLevel()
  local requiredFuel = distanceHome() + MIN_FUEL_BUFFER + 1
  if fuel ~= "unlimited" and fuel < requiredFuel then
    print("Fuel is low in the mine; checking carried items for fuel...")
    if refuelFromInventory(requiredFuel) then
      return
    end
    print("Carried fuel is not enough; returning home.")
    if not goHome() then error("Mining stopped safely.", 0) end
  end
end

local function ensureInventory()
  if freeSlots() <= 1 then
    print("Inventory nearly full, heading home to drop off.")
    if not goHome() then error("Mining stopped safely.", 0) end
  end
end

------------------------------------------------------------
-- VEIN MINING (capped DFS with backtracking)
------------------------------------------------------------
local veinCount = 0
local visited = {}

local function posKey(x, y, z)
  return x .. "," .. y .. "," .. z
end

local function scanVein()
  local exploreVein

  local function tryHorizontal()
    if veinCount >= VEIN_CAP then return end
    ensureFuel()
    ensureInventory()

    local ok, data = turtle.inspect()
    if not (ok and isValuableBlock(data)) then return end

    local nx = pos.x + DX[facing + 1]
    local nz = pos.z + DZ[facing + 1]
    local key = posKey(nx, pos.y, nz)
    if visited[key] then return end
    visited[key] = true

    digForward()
    if not forward() then return end
    veinCount = veinCount + 1
    exploreVein()
    back()
  end

  local function tryUp()
    if veinCount >= VEIN_CAP then return end
    ensureFuel()
    ensureInventory()

    local ok, data = turtle.inspectUp()
    if not (ok and isValuableBlock(data)) then return end

    local key = posKey(pos.x, pos.y + 1, pos.z)
    if visited[key] then return end
    visited[key] = true

    while turtle.detectUp() do
      if not turtle.digUp() then break end
      sleep(0.4)
    end
    if not up() then return end
    veinCount = veinCount + 1
    exploreVein()
    down()
  end

  local function tryDown()
    if veinCount >= VEIN_CAP then return end
    ensureFuel()
    ensureInventory()

    local ok, data = turtle.inspectDown()
    if not (ok and isValuableBlock(data)) then return end

    local key = posKey(pos.x, pos.y - 1, pos.z)
    if visited[key] then return end
    visited[key] = true

    while turtle.detectDown() do
      if not turtle.digDown() then break end
      sleep(0.4)
    end
    if not down() then return end
    veinCount = veinCount + 1
    exploreVein()
    up()
  end

  exploreVein = function()
    local startFacing = facing
    tryUp()
    tryDown()

    for _ = 1, 4 do
      tryHorizontal()
      turnRight()
    end
    faceDir(startFacing)
  end

  exploreVein()
end

local function checkAndMineVeins()
  local returnX, returnY, returnZ, returnFacing = pos.x, pos.y, pos.z, facing
  veinCount = 0
  visited = {}
  visited[posKey(pos.x, pos.y, pos.z)] = true

  scanVein()

  if pos.x ~= returnX or pos.y ~= returnY or pos.z ~= returnZ then
    goTo(returnX, returnY, returnZ)
  end
  faceDir(returnFacing)

  if veinCount >= VEIN_CAP then
    print("Vein cap (" .. VEIN_CAP .. ") reached; resuming tunnel.")
  elseif veinCount > 0 then
    print("Mined " .. veinCount .. " connected ore block(s).")
  end
end

------------------------------------------------------------
-- SQUARE STRIP MINING (right-running shaft with branches)
------------------------------------------------------------
local function mineSquare(size, layerY)
  if not goTo(0, layerY, 0) then
    print("Could not reach the layer origin.")
    return false
  end

  routeActive = true
  routeLayerY = layerY
  routeBranchX = 0
  faceDir(1) -- main shaft runs right from home

  for branchX = 0, size - 1, TUNNEL_SPACING do
    -- Extend/traverse the main shaft to the next branch.
    faceDir(1)
    while pos.x < branchX do
      routeBranchX = pos.x
      ensureFuel()
      ensureInventory()

      if not forward() then
        print("Main shaft blocked before branch x=" .. branchX ..
              ". Clear the protected/unbreakable block and rerun.")
        return false
      end
      routeBranchX = pos.x
      checkAndMineVeins()
    end

    routeBranchX = branchX
    print("Layer Y-rel " .. layerY .. ": mining branch x=" .. branchX)
    faceDir(0) -- branches run forward, away from the chest

    local branchLength = 0
    for i = 1, size do
      ensureFuel()
      ensureInventory()

      if not forward() then
        print("Branch x=" .. branchX .. " blocked at step " .. i ..
              "; returning to the main shaft.")
        break
      end
      branchLength = branchLength + 1
      checkAndMineVeins()
    end

    -- Return through the cleared branch, preserving the shortest home route.
    faceDir(2)
    for _ = 1, branchLength do
      ensureFuel()
      ensureInventory()
      if not forward() then
        print("Could not return along branch x=" .. branchX .. ".")
        return false
      end
    end
    faceDir(1)
  end

  if not goTo(0, layerY, 0) then
    print("Could not return along the main shaft to the layer origin.")
    return false
  end
  routeBranchX = 0
  faceDir(0)
  return true
end

local function mineBand(size, firstRelY, lastRelY)
  local layerY = firstRelY
  local step = -TUNNEL_SPACING

  if lastRelY > firstRelY then
    step = TUNNEL_SPACING
  end

  while true do
    print("Mining " .. size .. "x" .. size .. " square at relative Y" .. layerY)

    if not mineSquare(size, layerY) then
      print("Stopping early due to navigation failure.")
      local reachedHome = goHome(true)
      routeActive = false
      if reachedHome then
        print("Stopped safely at home.")
      else
        print("Mining stopped before the turtle could return home.")
      end
      return
    end

    -- Every completed layer ends at home for unloading, refueling, and review.
    local reachedHome = goHome(true)
    routeActive = false
    if not reachedHome then
      print("Mining stopped before the turtle could return home.")
      return
    end

    if layerY == lastRelY then
      print("Done. Back at home, fuel: " .. tostring(turtle.getFuelLevel()))
      return
    end

    local nextY = layerY + step
    if step < 0 and nextY < lastRelY then
      nextY = lastRelY
    elseif step > 0 and nextY > lastRelY then
      nextY = lastRelY
    end

    if nextY == layerY then
      print("Done. Back at home, fuel: " .. tostring(turtle.getFuelLevel()))
      return
    end

    print("Layer complete. Turtle is unloaded and refueled at home.")
    write("Press Enter for the next layer, or type q to stop: ")
    local answer = read():lower()
    if answer == "q" or answer == "quit" or answer == "stop" then
      print("Stopped at home. Run mine again when ready.")
      return
    end

    layerY = nextY
  end
end

------------------------------------------------------------
-- ENTRY POINT
------------------------------------------------------------
local resumed = loadState()
if resumed then
  print("Loaded saved position: (" .. pos.x .. "," .. pos.y .. "," .. pos.z ..
        "), facing " .. facing)
  print("Distance from home: " .. distanceHome())
else
  print("No saved position found -- treating current spot as home (0,0,0).")
  saveState()
end

if distanceHome() == 0 then
  print("Checking the lava tank before starting...")
  refuelFromLavaTank()
else
  print("Turtle is away from home; skipping the startup lava-tank check.")
end

write("Which layer from the top should mining start at? (1 = top) ")
local startLayer = tonumber(read())
while not startLayer or startLayer < 1 or startLayer ~= math.floor(startLayer) do
  write("Please enter a whole-number layer (1 = top): ")
  startLayer = tonumber(read())
end

write("Which ore's Y-band? (e.g. coal, diamond, ancient debris) ")
local bandOre = read():lower()
bandOre = bandOre:match("^%s*(.-)%s*$")
bandOre = BAND_ALIASES[bandOre] or bandOre

local band = ORE_BANDS[bandOre]
if band then
  print(bandOre .. " spawns between Y" .. band[1] .. " and Y" .. band[2] ..
        " in the Mining Dimension.")
  print("The turtle will keep EVERY block and vein-mine all ores in that range.")
else
  print("No Y range is configured for " .. bandOre ..
        "; it will mine a single square at the current Y.")
end

if bandOre == "allthemodium" then
  print("Note: turtles cannot harvest Allthemodium ore in ATM10.")
  print("It will leave those blocks intact for you to mine manually.")
elseif bandOre == "vibranium" or bandOre == "unobtainium" then
  print("That ATM metal does not spawn in the Mining Dimension and is player-only.")
end

write("What is the turtle's current world Y level? ")
local currentWorldY = tonumber(read())
while not currentWorldY do
  write("Please enter a number for the current Y level: ")
  currentWorldY = tonumber(read())
end

write("Square size (side length in blocks)? ")
local size = tonumber(read())
if not size or size < 1 then
  print("Not a valid size, defaulting to 16.")
  size = 16
end
size = math.floor(size)

-- Convert absolute world Y into home-relative Y.
local homeWorldY = currentWorldY - pos.y

local firstWorldY = currentWorldY
local lastWorldY = currentWorldY
local layers = 1
if band then
  local topWorldY = band[2]
  local bottomWorldY = band[1]
  layers = math.ceil((topWorldY - bottomWorldY) / TUNNEL_SPACING) + 1

  if startLayer > layers then
    print("That band has only " .. layers .. " layers; starting at layer " ..
          layers .. " instead.")
    startLayer = layers
  end

  firstWorldY = math.max(
    topWorldY - ((startLayer - 1) * TUNNEL_SPACING),
    bottomWorldY
  )
  lastWorldY = bottomWorldY
elseif startLayer ~= 1 then
  print("No Y-band is configured, so only layer 1 is available.")
  startLayer = 1
end

local firstRelY = firstWorldY - homeWorldY
local lastRelY = lastWorldY - homeWorldY

local rows = math.floor((size - 1) / TUNNEL_SPACING) + 1
local remainingLayers = layers - startLayer + 1
local startupFuel = turtle.getFuelLevel()

print("Plan: right-running main shaft with " .. rows ..
      " branches/layer, each " .. size .. " blocks long, ~" ..
      remainingLayers .. " layer(s), starting at top-down layer " ..
      startLayer .. " of " .. layers .. " (world Y" .. firstWorldY .. ").")

if startupFuel ~= "unlimited" and startupFuel < REFUEL_BELOW then
  if distanceHome() ~= 0 then
    print("Not enough fuel for the planned run, and the turtle is away from home.")
    return
  end

  print("Fuel is low; checking the lava tank left of the turtle...")
  refuelIfNeeded()
  faceDir(0)
  startupFuel = turtle.getFuelLevel()

  if startupFuel ~= "unlimited" and startupFuel <= MIN_FUEL_BUFFER then
    print("Unable to start: add more lava to the tank left of the turtle.")
    return
  end
end

if firstWorldY ~= currentWorldY then
  print("Moving from world Y" .. currentWorldY .. " to Y" .. firstWorldY ..
        " for the " .. bandOre .. " band...")
  if not goTo(pos.x, firstRelY, pos.z) then
    print("Unable to reach the starting Y level.")
    return
  end
elseif band then
  print("Current Y" .. currentWorldY .. " is already in the target range.")
end

print("Starting fuel: " .. tostring(turtle.getFuelLevel()))
mineBand(size, firstRelY, lastRelY)
