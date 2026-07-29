--[[
  ATM10 Mining Dimension Ore Turtle
  ----------------------------------
  - Prompts you for what block to mine and how far to tunnel
  - Strip-mines a single tunnel, checking up/down/left/right for the
    target ore and grabbing it, discarding everything else
  - Tracks its own position via dead-reckoning (no GPS needed)
  - Auto-returns to the dock and refuels before it runs out of gas,
    then resumes exactly where it left off

  SETUP (do this before running):
  1. Place the turtle at your dock -- this spot becomes "home" (0,0,0).
  2. Put a chest of coal/charcoal directly BELOW the turtle. This is the
     fallback fuel source. If you also have an RF/FE charging-station
     peripheral wired up next to the dock (e.g. the "Turtle Charging
     Station" mod), the script finds and uses that automatically instead
     and skips the chest entirely.
  3. Put an empty chest directly BEHIND the turtle (opposite the tunnel
     direction) -- this is where it dumps mined ore each time it comes
     home. It turns around to face this chest specifically for drop-off,
     then turns back around to head back out.
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
local REFUEL_FROM     = "below"   -- "front" | "below" | "above" -- where the fuel chest is
local MIN_FUEL_BUFFER = 50        -- extra fuel kept in reserve on top of the calculated trip home
local DROP_OFF_HOME   = true      -- dump ore into the chest behind the dock on every return
local STATE_FILE      = "turtle_state.txt"
local KEEP_SLOTS      = {1}       -- inventory slot(s) reserved for fuel, never touched/tossed

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
    if not turtle.dig() then break end
    sleep(0.4)
  end
end

local function forward()
  digForward()
  if turtle.forward() then
    pos.x = pos.x + DX[facing + 1]
    pos.z = pos.z + DZ[facing + 1]
    saveState()
    return true
  end
  return false
end

local function up()
  while turtle.detectUp() do
    if not turtle.digUp() then break end
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
    if not turtle.digDown() then break end
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
-- HELPERS
------------------------------------------------------------
local function distanceHome()
  return math.abs(pos.x) + math.abs(pos.y) + math.abs(pos.z)
end

local function isTarget(name, target)
  if not name then return false end
  return string.find(name:lower(), target, 1, true) ~= nil
end

-- Void everything that isn't fuel or the target ore
local function cleanInventory(target)
  for slot = 1, 16 do
    local skip = false
    for _, k in ipairs(KEEP_SLOTS) do if slot == k then skip = true end end
    if not skip then
      local item = turtle.getItemDetail(slot)
      if item and not isTarget(item.name, target) then
        turtle.select(slot)
        turtle.dropDown()
      end
    end
  end
  turtle.select(1)
end

-- Check up/down/left/right for the target ore and mine it if found
local function checkSides(target)
  local ok, data = turtle.inspectUp()
  if ok and isTarget(data.name, target) then turtle.digUp() end

  ok, data = turtle.inspectDown()
  if ok and isTarget(data.name, target) then turtle.digDown() end

  turnLeft()
  ok, data = turtle.inspect()
  if ok and isTarget(data.name, target) then turtle.dig() end
  turnRight()

  turnRight()
  ok, data = turtle.inspect()
  if ok and isTarget(data.name, target) then turtle.dig() end
  turnLeft()
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

local function refuel()
  print("Refueling at home...")
  local charger = findChargingPeripheral()
  turtle.select(1)

  local suck = turtle.suck
  if REFUEL_FROM == "below" then suck = turtle.suckDown
  elseif REFUEL_FROM == "above" then suck = turtle.suckUp end

  if charger then
    print("Found a charging peripheral, waiting for full fuel...")
    local target = turtle.getFuelLimit()
    while turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < target do
      sleep(2)
    end
    print("Charged via peripheral.")

    if turtle.getItemCount(1) == 0 and not suck(1) then
      print("Warning: no reserve fuel could be kept in slot 1.")
    end
    return
  end

  -- Keep at least one fuel item in slot 1 and burn only additional items.
  local pulled = 0
  local burned = 0
  while turtle.getFuelLevel() ~= "unlimited" and
        turtle.getFuelLevel() < turtle.getFuelLimit() do
    while turtle.getItemCount(1) <= 1 do
      if not suck(1) then
        print("Fuel chest is empty; keeping the last fuel item in slot 1.")
        print("Burned " .. burned .. " fuel item(s). Fuel: " ..
              tostring(turtle.getFuelLevel()))
        return
      end
      pulled = pulled + 1
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

------------------------------------------------------------
-- NAVIGATE HOME AND BACK OUT AGAIN
------------------------------------------------------------
local function goTo(x, y, z)
  if pos.y < y then while pos.y < y do up() end
  elseif pos.y > y then while pos.y > y do down() end end

  if pos.x < x then faceDir(1); while pos.x < x do forward() end
  elseif pos.x > x then faceDir(3); while pos.x > x do forward() end end

  if pos.z < z then faceDir(2); while pos.z < z do forward() end
  elseif pos.z > z then faceDir(0); while pos.z > z do forward() end end
end

local function goHome(target)
  local outX, outY, outZ, outFacing = pos.x, pos.y, pos.z, facing
  print("Heading home to refuel (" .. distanceHome() .. " blocks)...")
  goTo(0, 0, 0)
  faceDir(0) -- face 0 = the tunnel direction, same way it started

  if DROP_OFF_HOME then
    faceDir(2) -- turn around 180 to face the chest behind the dock
    for slot = 1, 16 do
      local item = turtle.getItemDetail(slot)
      if item and isTarget(item.name, target) then
        turtle.select(slot)
        turtle.drop()
      end
    end
    turtle.select(1)
    faceDir(0) -- turn back to face the tunnel
  end

  refuel()
  print("Heading back out to (" .. outX .. "," .. outY .. "," .. outZ .. ")...")
  goTo(outX, outY, outZ)
  faceDir(outFacing)
end

------------------------------------------------------------
-- MAIN MINING LOOP
------------------------------------------------------------
local function mine(target, length)
  for i = 1, length do
    local costHome = distanceHome() + 1
    local fuel = turtle.getFuelLevel()
    if fuel ~= "unlimited" and fuel <= costHome + MIN_FUEL_BUFFER then
      goHome(target)
    end

    if not forward() then
      print("Blocked and couldn't clear it, stopping at block " .. i)
      break
    end

    checkSides(target)
    cleanInventory(target)

    local free = 0
    for slot = 1, 16 do if turtle.getItemCount(slot) == 0 then free = free + 1 end end
    if free <= 1 then
      print("Inventory nearly full, heading home to drop off.")
      goHome(target)
    end
  end

  goHome(target)
  print("Done. Back at home, fuel: " .. tostring(turtle.getFuelLevel()))
end

------------------------------------------------------------
-- ENTRY POINT
------------------------------------------------------------
local resumed = loadState()
if resumed then
  print("Loaded saved position: (" .. pos.x .. "," .. pos.y .. "," .. pos.z .. "), facing " .. facing)
  print("Distance from home: " .. distanceHome())
else
  print("No saved position found -- treating current spot as home (0,0,0).")
  saveState()
end

local startupFuel = turtle.getFuelLevel()
if startupFuel ~= "unlimited" and startupFuel == 0 then
  print("No fuel available at startup; checking the fuel chest...")
  refuel()

  if turtle.getFuelLevel() == 0 then
    print("Unable to start: add at least two fuel items to the fuel chest.")
    return
  end
end

write("What ore/block do you want to mine? (e.g. gold, diamond, allthemodium) ")
local target = read():lower()

if ORE_BANDS[target] then
  local band = ORE_BANDS[target]
  print(target .. " spawns between Y" .. band[1] .. " and Y" .. band[2] ..
        " in the Mining Dimension. Make sure the turtle is positioned there before continuing.")
end

write("How many blocks forward should it tunnel? ")
local length = tonumber(read())
if not length then
  print("Not a number, defaulting to 64.")
  length = 64
end

print("Starting fuel: " .. tostring(turtle.getFuelLevel()))
mine(target, length)
