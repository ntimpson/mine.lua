--[[
  ATM10 Lava Cauldron Collector
  -----------------------------
  Walks a grid of lava cauldrons, fills a bucket from any that have lava,
  then returns home and empties the bucket into the tank behind the dock.
  If fuel is below 1000 at startup or after a collect, it burns lava for fuel
  instead (startup pulls from the tank; mid-run burns the collected bucket).

  SETUP:
  1. Place the turtle at the dock -- this spot becomes home (0,0,0).
  2. Put a bucket-fillable lava/fluid TANK directly BEHIND the turtle.
  3. Put one empty bucket in turtle slot 1.
  4. Face the turtle toward the cauldron field before the first run.
  5. Lay out cauldrons like this (top-down, turtle facing the field):

         [tank]
        [turtle]  <-- home, facing field
     [C][C][C][C] <-- row 1, 1 block in front, side-by-side
         (gap)
     [C][C][C][C] <-- row 2
         (gap)
     [C][C][C][C] <-- row 3

  6. Run: lava
]]--

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------
local STATE_FILE = "lava_state.txt"
local BUCKET_SLOT = 1
local ROW_SPACING = 2 -- cauldron row, empty block, next cauldron row
local FIRST_ROW_Z = 1 -- first cauldron row is 1 block in front of home
local WAIT_BETWEEN_PASSES = 10 -- seconds to wait when a full pass finds no lava
local REFUEL_BELOW = 1000 -- burn lava for fuel when below this

------------------------------------------------------------
-- STATE
------------------------------------------------------------
local pos = {x = 0, y = 0, z = 0}
local facing = 0 -- 0=north(-z) 1=east(+x) 2=south(+z) 3=west(-x)
local DX = {0, 1, 0, -1}
local DZ = {-1, 0, 1, 0}

local function saveState()
  local f = fs.open(STATE_FILE, "w")
  f.write(textutils.serialize({pos = pos, facing = facing}))
  f.close()
end

local function loadState()
  if not fs.exists(STATE_FILE) then return false end
  local f = fs.open(STATE_FILE, "r")
  local data = textutils.unserialize(f.readAll())
  f.close()
  if data then
    pos, facing = data.pos, data.facing
    return true
  end
  return false
end

------------------------------------------------------------
-- MOVEMENT
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

local function forward()
  if turtle.detect() then
    print("Path blocked at (" .. pos.x .. "," .. pos.y .. "," .. pos.z .. ").")
    return false
  end
  if turtle.forward() then
    pos.x = pos.x + DX[facing + 1]
    pos.z = pos.z + DZ[facing + 1]
    saveState()
    return true
  end
  return false
end

local function goTo(x, y, z)
  if pos.y < y then
    while pos.y < y do
      if not turtle.up() then return false end
      pos.y = pos.y + 1
      saveState()
    end
  elseif pos.y > y then
    while pos.y > y do
      if not turtle.down() then return false end
      pos.y = pos.y - 1
      saveState()
    end
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

local function goHome()
  if not goTo(0, 0, 0) then
    print("Could not return home.")
    return false
  end
  faceDir(0)
  return true
end

------------------------------------------------------------
-- BUCKET / FUEL HELPERS
------------------------------------------------------------
local function itemName(slot)
  local item = turtle.getItemDetail(slot or BUCKET_SLOT)
  return item and item.name or nil
end

local function needsFuel()
  local fuel = turtle.getFuelLevel()
  return fuel ~= "unlimited" and fuel < REFUEL_BELOW
end

local function burnLavaBucket()
  turtle.select(BUCKET_SLOT)
  if itemName(BUCKET_SLOT) ~= "minecraft:lava_bucket" then
    print("Slot 1 does not have a lava bucket to burn.")
    return false
  end
  if not turtle.refuel(1) then
    print("Could not burn the lava bucket.")
    return false
  end
  print("Burned lava bucket for fuel. Fuel: " .. tostring(turtle.getFuelLevel()))
  return itemName(BUCKET_SLOT) == "minecraft:bucket"
end

local function ensureEmptyBucket()
  turtle.select(BUCKET_SLOT)
  local name = itemName(BUCKET_SLOT)
  if name == "minecraft:bucket" then return true end
  if name == "minecraft:lava_bucket" then
    if needsFuel() then
      return burnLavaBucket()
    end
    print("Slot 1 already has a lava bucket; emptying into the tank first.")
    return false
  end
  print("Put an empty bucket in turtle slot 1.")
  return false
end

local function isLavaCauldron(data)
  if not data or not data.name then return false end
  local name = data.name:lower()
  if name:find("lava_cauldron", 1, true) then return true end
  if name:find("cauldron", 1, true) and data.state then
    local fluid = tostring(data.state.fluid or data.state.Fluid or ""):lower()
    if fluid:find("lava", 1, true) then return true end
  end
  return false
end

local function emptyBucketIntoTank()
  if not goHome() then return false end
  faceDir(2) -- tank is behind home
  turtle.select(BUCKET_SLOT)

  local name = itemName(BUCKET_SLOT)
  if name == "minecraft:bucket" then
    faceDir(0)
    return true
  end
  if name ~= "minecraft:lava_bucket" then
    print("Slot 1 does not have a lava bucket to empty.")
    faceDir(0)
    return false
  end

  if not turtle.place() then
    print("Could not empty the lava bucket into the tank behind home.")
    faceDir(0)
    return false
  end

  if itemName(BUCKET_SLOT) ~= "minecraft:bucket" then
    print("Tank did not return an empty bucket.")
    faceDir(0)
    return false
  end

  print("Emptied lava into the tank. Fuel: " .. tostring(turtle.getFuelLevel()))
  faceDir(0)
  return true
end

local function fillBucketFromTank()
  if pos.x ~= 0 or pos.y ~= 0 or pos.z ~= 0 then
    if not goHome() then return false end
  end
  if itemName(BUCKET_SLOT) ~= "minecraft:bucket" then
    if not ensureEmptyBucket() then
      faceDir(0)
      return false
    end
  end

  faceDir(2) -- tank is behind home
  turtle.select(BUCKET_SLOT)
  if not turtle.place() then
    print("Could not fill the bucket from the tank behind home.")
    faceDir(0)
    return false
  end

  if itemName(BUCKET_SLOT) ~= "minecraft:lava_bucket" then
    print("Tank did not provide a lava bucket.")
    faceDir(0)
    return false
  end

  faceDir(0)
  return true
end

local function refuelFromTankIfNeeded()
  if not needsFuel() then
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" then
      print("Fuel is unlimited; skipping tank refuel.")
    else
      print("Fuel is " .. fuel .. " (threshold " .. REFUEL_BELOW ..
            "); skipping tank refuel.")
    end
    return true
  end

  print("Fuel is low; pulling lava from the tank behind home...")
  if not goHome() then return false end

  while needsFuel() do
    if not fillBucketFromTank() then
      faceDir(0)
      return turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() > 0
    end
    if not burnLavaBucket() then
      faceDir(0)
      return false
    end
  end

  faceDir(0)
  return true
end

local function handleCollectedLava()
  if needsFuel() then
    print("Fuel is below " .. REFUEL_BELOW .. "; burning this bucket.")
    return burnLavaBucket()
  end
  return emptyBucketIntoTank()
end

local function collectFromCauldronAhead()
  turtle.select(BUCKET_SLOT)
  if itemName(BUCKET_SLOT) ~= "minecraft:bucket" then
    return false
  end

  local ok, data = turtle.inspect()
  if not (ok and isLavaCauldron(data)) then
    return false
  end

  if not turtle.place() then
    print("Failed to fill the bucket from the cauldron ahead.")
    return false
  end

  if itemName(BUCKET_SLOT) ~= "minecraft:lava_bucket" then
    print("Cauldron interaction did not produce a lava bucket.")
    return false
  end

  print("Collected lava at relative (" .. pos.x .. "," .. pos.y .. "," .. pos.z .. ").")
  return true
end

------------------------------------------------------------
-- FIELD SWEEP
------------------------------------------------------------
local function cauldronStandPos(col, row)
  -- Field is in front of home (facing 0 / -z). Stand one block closer to home
  -- than the cauldron, then face forward into it.
  local cauldronZ = -(FIRST_ROW_Z + (row - 1) * ROW_SPACING)
  return col - 1, 0, cauldronZ + 1
end

local function sweepField(cols, rows)
  local collected = 0

  for row = 1, rows do
    for col = 1, cols do
      local fuel = turtle.getFuelLevel()
      if fuel ~= "unlimited" and fuel < 50 then
        print("Fuel is critically low; checking the home tank...")
        if not refuelFromTankIfNeeded() or
           (turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < 50) then
          print("Unable to keep enough fuel. Stopping.")
          goHome()
          return collected, false
        end
      end

      if itemName(BUCKET_SLOT) == "minecraft:lava_bucket" then
        if not handleCollectedLava() then
          return collected, false
        end
      elseif not ensureEmptyBucket() then
        goHome()
        return collected, false
      end

      local x, y, z = cauldronStandPos(col, row)
      print("Checking row " .. row .. " cauldron " .. col ..
            " from (" .. x .. "," .. y .. "," .. z .. ")...")

      if not goTo(x, y, z) then
        print("Could not reach that cauldron stand position.")
        goHome()
        return collected, false
      end

      faceDir(0) -- look into the field / cauldron ahead

      if collectFromCauldronAhead() then
        collected = collected + 1
        if not handleCollectedLava() then
          return collected, false
        end
      end
    end
  end

  if not goHome() then
    return collected, false
  end
  return collected, true
end

------------------------------------------------------------
-- ENTRY POINT
------------------------------------------------------------
local resumed = loadState()
if resumed then
  print("Loaded saved position: (" .. pos.x .. "," .. pos.y .. "," .. pos.z ..
        "), facing " .. facing)
else
  print("No saved position found -- treating current spot as home (0,0,0).")
  saveState()
end

write("How many cauldrons in each row? ")
local cols = tonumber(read())
while not cols or cols < 1 or cols ~= math.floor(cols) do
  write("Please enter a whole number of cauldrons per row: ")
  cols = tonumber(read())
end

write("How many rows? ")
local rows = tonumber(read())
while not rows or rows < 1 or rows ~= math.floor(rows) do
  write("Please enter a whole number of rows: ")
  rows = tonumber(read())
end

print("Field: " .. cols .. " cauldrons/row, " .. rows ..
      " rows, 1 empty block between rows.")
print("Lava goes into the tank behind home.")
print("Lava is burned for fuel only when below " .. REFUEL_BELOW .. ".")

if itemName(BUCKET_SLOT) == "minecraft:lava_bucket" then
  if not handleCollectedLava() then return end
elseif not ensureEmptyBucket() then
  return
end

if not refuelFromTankIfNeeded() then
  print("Unable to start: add lava to the tank behind the turtle.")
  return
end

local fuel = turtle.getFuelLevel()
if fuel ~= "unlimited" and fuel < 50 then
  print("Turtle needs more fuel before starting.")
  return
end

print("Starting cauldron collection loop. Press Ctrl+T to stop.")
while true do
  local collected, ok = sweepField(cols, rows)
  if not ok then
    print("Stopped after collecting " .. collected .. " lava bucket(s).")
    return
  end

  if collected == 0 then
    print("No lava found this pass. Waiting " .. WAIT_BETWEEN_PASSES ..
          "s before checking again...")
    sleep(WAIT_BETWEEN_PASSES)
  else
    print("Pass complete. Collected " .. collected ..
          " lava bucket(s). Scanning again...")
  end
end
