--[[
  ATM10 Mining Dimension Ore Turtle
  ----------------------------------
  - Asks which ore's Y-band to use, the turtle's world Y, and square size
  - Mines a main shaft to the right with branches spaced 3 blocks apart
  - Collects every block it mines (not only the selected band ore)
  - Follows connected ore veins (capped at 128 blocks) then resumes
  - After each square, descends 3 blocks and repeats through the band
  - Returns home after every layer and waits for approval to continue
  - Tracks position via dead-reckoning and auto-returns to refuel/unload

  SETUP (do this before running):
  1. Place the turtle at your dock -- this spot becomes "home" (0,0,0).
  2. Put a chest directly BEHIND the turtle (opposite the tunnel
     direction) and stock it with coal/charcoal. This one chest supplies
     fuel and receives mined ore. The script always leaves at least one
     coal in it for the next run. Put the coal in the chest's first slot
     so the turtle pulls fuel instead of deposited ore.
  3. If you also have an RF/FE charging-station peripheral wired up next
     to the dock (e.g. the "Turtle Charging Station" mod), the script
     finds and uses that automatically.
  4. Manually put a stack of coal/charcoal in inventory slot 1 before the
     first run, so freshly mined ore never lands in the fuel slot.
  5. Face the turtle down the tunnel direction you want it to dig --
     i.e. AWAY from the drop-off chest -- before the first run. Whatever
     direction it's facing the very first time you run "mine" becomes
     both "home" (0,0,0) and the tunnel direction for good.
  6. Run: mine
]]--

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------
local REFUEL_FROM     = "front"   -- shared fuel/drop-off chest behind home
local MIN_FUEL_BUFFER = 50        -- extra fuel kept in reserve on top of the calculated trip home
local REFUEL_BELOW    = 1000      -- skip refueling when at or above this fuel level
local DROP_OFF_HOME   = true      -- dump all mined blocks into the shared chest on every return
local STATE_FILE      = "turtle_state.txt"
local KEEP_SLOTS      = {1}       -- inventory slot(s) reserved for fuel, never touched/tossed
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

local function countChestCoal()
  local chest = peripheral.wrap("front")
  if not chest or type(chest.list) ~= "function" then return nil end

  local total = 0
  for _, item in pairs(chest.list()) do
    if item.name and item.name:lower():find("coal", 1, true) then
      total = total + item.count
    end
  end
  return total
end

local function refuel()
  print("Refueling at home...")
  local charger = findChargingPeripheral()
  turtle.select(1)

  local suck = turtle.suck
  if REFUEL_FROM == "below" then suck = turtle.suckDown
  elseif REFUEL_FROM == "above" then suck = turtle.suckUp end

  if charger then
    print("Found a charging peripheral, waiting for full fuel...")
    local limit = turtle.getFuelLimit()
    while turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < limit do
      sleep(2)
    end
    print("Charged via peripheral.")

    if turtle.getItemCount(1) == 0 then
      local chestCoal = countChestCoal()
      if chestCoal and chestCoal > 1 then
        suck(1)
      else
        print("Warning: no reserve fuel could be kept in slot 1.")
      end
    end
    return
  end

  -- Keep at least one fuel item in slot 1 and burn only additional items.
  local pulled = 0
  local burned = 0
  while turtle.getFuelLevel() ~= "unlimited" and
        turtle.getFuelLevel() < turtle.getFuelLimit() do
    while turtle.getItemCount(1) <= 1 do
      local chestCoal = countChestCoal()
      if chestCoal == nil then
        print("Unable to inspect the shared chest for coal.")
        return
      elseif chestCoal <= 1 then
        print("Keeping the last coal in the shared chest.")
        print("Burned " .. burned .. " fuel item(s). Fuel: " ..
              tostring(turtle.getFuelLevel()))
        return
      end

      if not suck(1) then
        print("Could not pull coal from the shared chest.")
        print("Burned " .. burned .. " fuel item(s). Fuel: " ..
              tostring(turtle.getFuelLevel()))
        return
      end
      pulled = pulled + 1

      if not turtle.refuel(0) then
        turtle.drop()
        print("Put coal in the first slot of the shared chest.")
        return
      end
    end

    if not turtle.refuel(1) then
      print("Slot 1 does not contain valid turtle fuel.")
      return
    end
    burned = burned + 1
  end
  print("Pulled " .. pulled .. " and burned " .. burned ..
        " fuel item(s). Fuel: " .. tostring(turtle.getFuelLevel()))
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
  if fuel ~= "unlimited" and fuel <= distanceHome() + MIN_FUEL_BUFFER then
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
if band then
  if currentWorldY > band[2] then
    firstWorldY = band[2]
  elseif currentWorldY < band[1] then
    firstWorldY = band[1]
  else
    firstWorldY = currentWorldY
  end
  lastWorldY = band[1]
  if firstWorldY < lastWorldY then
    lastWorldY = band[2]
  end
end

local firstRelY = firstWorldY - homeWorldY
local lastRelY = lastWorldY - homeWorldY

local rows = math.floor((size - 1) / TUNNEL_SPACING) + 1
local layers = 1
if band then
  layers = math.floor(math.abs(firstWorldY - lastWorldY) / TUNNEL_SPACING) + 1
end
local startupFuel = turtle.getFuelLevel()

print("Plan: right-running main shaft with " .. rows ..
      " branches/layer, each " .. size .. " blocks long, ~" ..
      layers .. " layer(s).")

if startupFuel ~= "unlimited" and startupFuel < REFUEL_BELOW then
  if distanceHome() ~= 0 then
    print("Not enough fuel for the planned run, and the turtle is away from home.")
    return
  end

  print("Fuel is low; checking the shared chest behind the turtle...")
  faceDir(2)
  refuelIfNeeded()
  faceDir(0)
  startupFuel = turtle.getFuelLevel()

  if startupFuel ~= "unlimited" and startupFuel <= MIN_FUEL_BUFFER then
    print("Unable to start: add more coal to the shared chest.")
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
