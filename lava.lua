--[[
  ATM10 Lava Cauldron Collector
  -----------------------------
  Walks a grid of lava cauldrons, fills a bucket from any that have lava,
  then returns home and empties the bucket into the tank behind the dock.
  If fuel is below 1000 at startup or after a collect, it burns lava for fuel
  instead (startup pulls from the tank; mid-run burns the collected bucket).

  When leaving a row for the tank (or another row), it walks to the end of the
  row, uses the empty column past the last cauldron, then reverses that path.

  SETUP:
  1. Place the turtle at the dock -- this spot becomes home (0,0,0).
  2. Put a bucket-fillable lava/fluid TANK directly BEHIND the turtle.
  3. Put one empty bucket in turtle slot 1.
  4. Face the turtle toward the cauldron field before the first run.
  5. First cauldron is kitty-corner front-RIGHT of the turtle.
     Row 2 is two blocks forward from home. Keep ONE empty column past
     the last cauldron as the return lane:

              [tank]
             [turtle]     <-- home, facing field
          [C][C][C][C] [ ] <-- row 1 (first C is front-right) + return lane
              (gap)
          [C][C][C][C] [ ] <-- row 2 (two forwards from home) + return lane
              (gap)
          [C][C][C][C] [ ] <-- row 3 + return lane

  6. Run: lava
]]--

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------
local STATE_FILE = "lava_state.txt"
local BUCKET_SLOT = 1
local ROW_SPACING = 2 -- stand lines at z = 0, -2, -4, ...
local FIRST_COL_X = 1 -- first cauldron stand is one block to the right of home
local WAIT_BETWEEN_PASSES = 10 -- seconds to wait when a full pass finds no lava
local REFUEL_BELOW = 1000 -- burn lava for fuel when below this
local fieldCols = 1 -- set at startup; last cauldron x = fieldCols

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

-- Last cauldron is at x = fieldCols; return lane is the next column.
local function returnLaneX()
  return fieldCols + 1
end

-- Home via the empty return lane past the last cauldron (ground only).
local function goHome()
  if pos.x == 0 and pos.y == 0 and pos.z == 0 then
    faceDir(0)
    return true
  end

  local laneX = returnLaneX()
  local rowZ = pos.z

  print("Pathing home via return lane x=" .. laneX .. "...")

  if not goTo(laneX, 0, rowZ) then
    print("Could not reach the return lane at the end of the row.")
    print("Leave column x=" .. laneX .. " empty past the last cauldron.")
    return false
  end
  if not goTo(laneX, 0, 0) then
    print("Could not follow the return lane back to the dock line.")
    return false
  end
  if not goTo(0, 0, 0) then
    print("Could not return home.")
    return false
  end

  faceDir(0)
  return true
end

-- Same-row moves stay direct. Row changes reverse the home path on the ground.
local function goToField(x, y, z)
  if pos.x == x and pos.y == y and pos.z == z then
    return true
  end

  if pos.z == z and pos.y == y then
    return goTo(x, y, z)
  end

  local laneX = returnLaneX()

  print("Pathing out via return lane x=" .. laneX .. "...")

  if not goTo(laneX, 0, 0) then return false end
  if not goTo(laneX, 0, z) then
    print("Could not follow the return lane out.")
    print("Leave column x=" .. laneX .. " empty past the last cauldron.")
    return false
  end
  return goTo(x, y, z)
end

------------------------------------------------------------
-- BUCKET / FUEL HELPERS
------------------------------------------------------------
local function itemName(slot)
  local item = turtle.getItemDetail(slot or BUCKET_SLOT)
  return item and item.name or nil
end

local function isEmptyBucketName(name)
  if not name then return false end
  local n = name:lower()
  if n == "minecraft:bucket" then return true end
  -- Empty bucket, but not a filled *lava_bucket* / water_bucket / etc.
  if n:find("bucket", 1, true) and not n:find("lava", 1, true)
     and not n:find("water", 1, true) and not n:find("milk", 1, true)
     and not n:find("powder", 1, true) then
    return true
  end
  return false
end

local function isLavaBucketName(name)
  if not name then return false end
  local n = name:lower()
  return n:find("lava", 1, true) ~= nil and n:find("bucket", 1, true) ~= nil
end

local function findSlot(predicate)
  for slot = 1, 16 do
    local name = itemName(slot)
    if name and predicate(name) then return slot end
  end
  return nil
end

local function moveSlotToBucketSlot(slot)
  if slot == BUCKET_SLOT then
    turtle.select(BUCKET_SLOT)
    return true
  end
  turtle.select(slot)
  if not turtle.transferTo(BUCKET_SLOT) then
    return false
  end
  turtle.select(BUCKET_SLOT)
  return true
end

local function ensureLavaBucketInSlot1()
  if isLavaBucketName(itemName(BUCKET_SLOT)) then
    turtle.select(BUCKET_SLOT)
    return true
  end
  local slot = findSlot(isLavaBucketName)
  if not slot then return false end
  print("Moved lava bucket from slot " .. slot .. " to slot " .. BUCKET_SLOT .. ".")
  return moveSlotToBucketSlot(slot) and isLavaBucketName(itemName(BUCKET_SLOT))
end

local function ensureEmptyBucketInSlot1()
  if isEmptyBucketName(itemName(BUCKET_SLOT)) then
    turtle.select(BUCKET_SLOT)
    return true
  end
  local slot = findSlot(isEmptyBucketName)
  if not slot then return false end
  -- Clear a non-bucket item out of slot 1 if needed.
  if itemName(BUCKET_SLOT) then
    local free = nil
    for s = 2, 16 do
      if turtle.getItemCount(s) == 0 then free = s break end
    end
    if not free then return false end
    turtle.select(BUCKET_SLOT)
    if not turtle.transferTo(free) then return false end
  end
  print("Moved empty bucket from slot " .. slot .. " to slot " .. BUCKET_SLOT .. ".")
  return moveSlotToBucketSlot(slot) and isEmptyBucketName(itemName(BUCKET_SLOT))
end

local function needsFuel()
  local fuel = turtle.getFuelLevel()
  return fuel ~= "unlimited" and fuel < REFUEL_BELOW
end

local function burnLavaBucket()
  if not ensureLavaBucketInSlot1() then
    print("No lava bucket in inventory to burn.")
    return false
  end
  turtle.select(BUCKET_SLOT)
  if not turtle.refuel(1) then
    print("Could not burn the lava bucket.")
    return false
  end
  print("Burned lava bucket for fuel. Fuel: " .. tostring(turtle.getFuelLevel()))
  return ensureEmptyBucketInSlot1()
end

local function ensureEmptyBucket()
  if ensureEmptyBucketInSlot1() then return true end
  if ensureLavaBucketInSlot1() then
    if needsFuel() then
      return burnLavaBucket()
    end
    print("Carrying a lava bucket; emptying into the tank first.")
    return false
  end
  print("Put an empty bucket in the turtle (preferably slot 1).")
  return false
end

local function isLavaCauldron(data)
  if not data or not data.name then return false end
  local name = data.name:lower()
  -- Java: minecraft:lava_cauldron. Ignore plain minecraft:cauldron.
  if name:find("lava_cauldron", 1, true) then return true end
  if name:find("lava", 1, true) and name:find("cauldron", 1, true) then
    return true
  end
  return false
end

local function emptyBucketIntoTank()
  if not goHome() then return false end
  faceDir(2) -- tank is behind home

  -- Already holding only an empty bucket -- nothing to deposit.
  if isEmptyBucketName(itemName(BUCKET_SLOT)) and not findSlot(isLavaBucketName) then
    faceDir(0)
    return true
  end
  if not ensureLavaBucketInSlot1() then
    print("No lava bucket in inventory to empty.")
    faceDir(0)
    return false
  end

  turtle.select(BUCKET_SLOT)
  if not turtle.place() then
    print("Could not empty the lava bucket into the tank behind home.")
    faceDir(0)
    return false
  end

  if not ensureEmptyBucketInSlot1() then
    print("Tank did not return an empty bucket to inventory.")
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
  if not ensureEmptyBucket() then
    faceDir(0)
    return false
  end

  faceDir(2) -- tank is behind home
  turtle.select(BUCKET_SLOT)
  if not turtle.place() then
    print("Could not fill the bucket from the tank behind home.")
    faceDir(0)
    return false
  end

  if not ensureLavaBucketInSlot1() then
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

-- Don't trust saved facing alone after long trips home; find a cauldron by inspect.
local function faceAdjacentCauldron()
  for _ = 1, 4 do
    local ok, data = turtle.inspect()
    if ok and data.name and data.name:lower():find("cauldron", 1, true) then
      return true, data
    end
    turnRight()
  end
  return false, nil
end

local function collectFromCauldronAhead(row, col)
  if not ensureEmptyBucketInSlot1() then
    print("Row " .. row .. " col " .. col ..
          ": no empty bucket available; cannot check.")
    return false
  end

  local found, data = faceAdjacentCauldron()
  if not found then
    print("Row " .. row .. " col " .. col ..
          ": no cauldron adjacent at (" .. pos.x .. "," .. pos.y .. "," ..
          pos.z .. "). Check stand position / pathing.")
    return false
  end

  if not isLavaCauldron(data) then
    print("Row " .. row .. " col " .. col ..
          ": skipped (" .. data.name .. "), cauldron has no lava.")
    return false
  end

  turtle.select(BUCKET_SLOT)
  local before = itemName(BUCKET_SLOT)
  if not turtle.place() then
    print("Row " .. row .. " col " .. col ..
          ": lava cauldron seen but bucket fill failed.")
    return false
  end
  sleep(0.2)

  if not ensureLavaBucketInSlot1() then
    print("Row " .. row .. " col " .. col ..
          ": bucket did not fill. Before=" .. tostring(before) ..
          " after=" .. tostring(itemName(BUCKET_SLOT)) .. ".")
    return false
  end

  print("Row " .. row .. " col " .. col ..
        ": collected lava at (" .. pos.x .. "," .. pos.y .. "," .. pos.z .. ").")
  return true
end

------------------------------------------------------------
-- FIELD SWEEP
------------------------------------------------------------
local function cauldronStandPos(col, row)
  -- First stand is kitty-corner front-right of home: (1,0,0), facing the
  -- cauldron one block ahead. Row 2 stand line is two blocks forward (z=-2).
  local x = FIRST_COL_X + (col - 1) -- cols map to x = 1 .. fieldCols
  local z = -((row - 1) * ROW_SPACING) -- 0, -2, -4, ...
  return x, 0, z
end

local function sweepField(cols, rows)
  local collected = 0
  local checked = 0

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
      print("Moving to row " .. row .. " col " .. col ..
            " stand (" .. x .. "," .. y .. "," .. z .. ")...")

      if not goToField(x, y, z) then
        print("Could not reach row " .. row .. " col " .. col .. ".")
        goHome()
        return collected, false
      end

      -- Must stand on the planned tile and face the field before inspecting.
      if pos.x ~= x or pos.y ~= y or pos.z ~= z then
        print("Position desync at row " .. row .. " col " .. col ..
              ": expected (" .. x .. "," .. y .. "," .. z ..
              ") but tracked (" .. pos.x .. "," .. pos.y .. "," .. pos.z .. ").")
        goHome()
        return collected, false
      end

      checked = checked + 1

      if collectFromCauldronAhead(row, col) then
        collected = collected + 1
        if not handleCollectedLava() then
          return collected, false
        end
      end
    end
  end

  print("Pass checked " .. checked .. "/" .. (cols * rows) ..
        " cauldrons, collected " .. collected .. ".")

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
  write("Is the turtle at the dock facing the field? (y/n) ")
  local atDock = read():lower()
  if atDock == "y" or atDock == "yes" or atDock == "" then
    pos = {x = 0, y = 0, z = 0}
    facing = 0
    saveState()
    print("Recalibrated home to (0,0,0), facing the field.")
  else
    print("Keeping the saved position. Pathing may be wrong if the turtle was moved.")
  end
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

fieldCols = cols

print("Field: " .. cols .. " cauldrons/row, " .. rows ..
      " rows, 1 empty block between rows.")
print("Cauldron stands at x=1.." .. cols ..
      ", return lane at x=" .. (cols + 1) .. " (keep empty).")
print("Row 1 at z=0, row 2 at z=-2 (two steps forward from home).")
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
