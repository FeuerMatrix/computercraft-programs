-- CC Turtle Mining Program by FeuerMatrix

local LOG_DATA = false
--Checks for easier ways back than just reversing every movement. Makes the turtle more fuel efficient.
local RETURN_PATH_STRAIGHTENING = true
--How many last movement positions away the turtle will consider when finding a better path.
local RETURN_PATH_STRAIGHTENING_MAX_CHECKING_DISTANCE = 20
local VEINMINE_IGNORE_BOUNDARIES = true
--if true, the turtle gets rid of items not in the list of blocks to mine
local DELETE_UNWANTED_ITEMS = false
local INFINITE_FUEL = false
local FUEL_SLOT = 1
--(5/2) -> minimal mining to check EVERY block | (8/3) -> assumes that most ore veins will extend in more than one direction. ~50% faster, but might miss some ore veins with only 1 or 2 blocks
--how much blocks to the next shaft on the same y-level
local SHAFT_OFFSET_HORIZONTAL = 5
--by how much horizontal shafts on neighbouring y-levels are offset to each other in z-direction
local SHAFT_OFFSET_ON_NEXT_Y = 2

local x, y, z = 0,0,0
local xdir, zdir = 1,0

--boundaries of the area to mine
local bound_x, bound_yp, bound_yn, bound_zp, bound_zn = 5, 2, 2, 5, 5

--[[-
    Significance of the movement that is currently executed. Determines how to react to problems like hitting bedrock, full inventory and low fuel.

    0 <=> Low significance, e.g. following ore veines. Bedrock is just ignored and the movement is cancelled. Logistical problems immediately pause the action.
    1 <=> Normal significance, e.g. mining a branch. Logistical problems are treated like for low significance, but changes to the planned movement will be made when hitting bedrock.
    2 <=> Critical Movement. Logistical problems are ignored. Hitting bedrock results in the entire program yielding.
]]
local current_movement_significance = 1

local returnToStart

--this is only here so that lua syntax check ignores computer craft specific globals --TODO delete on release
turtle = turtle
textutils = textutils

--prints current coordinates and face direction in the console
local function logData()
    if not LOG_DATA then
        return
    end
    print(x .. " | " .. y .. " | " .. z .. " || " .. xdir .. " | " .. zdir)
end

--[[-
    Returns the 1-norm of the current coordinate vector (also known as Manhattan distance)
    @return Manhattan distance of current coordinate to (0,0,0)
]]
local function coordinate_1_norm()
    return math.abs(x) + math.abs(y) + math.abs(z)
end

local function refuel()
    if not (turtle.getSelectedSlot() == FUEL_SLOT) then
        turtle.select(FUEL_SLOT)
    end
    if turtle.getItemCount() > 1 then
        if turtle.refuel(turtle.getItemCount() - 1) then
            return
        end
    end
    for i = 1, 16, 1 do --check other slots for fuel
        if not (i == FUEL_SLOT) then
            turtle.select(i)
            if turtle.refuel(64) then
                return
            end
        end
    end
    current_movement_significance = 2
    returnToStart()
    error("Critical fuel level. Terminating Program.")
end

--[[-
    Checks if the current fuel level is high enough to make it back even after one more movement. If not enough fuel is supplied, enters refueling.
]]
local function checkFuelStatus()
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" or current_movement_significance == 2 then
        return
    end
    if fuel > 1 + coordinate_1_norm() then
        return
    end
    refuel()
end

--moves the turtle forward
local function forward(length)
    checkFuelStatus()
    if not length then
        length = 1
    end

    for i = 1, length, 1 do
        while not turtle.forward() do
            turtle.attack()
            turtle.dig()
        end
        x = x + xdir
        z = z + zdir
        logData()
    end
end

--moves the turtle upward
local function up(length)
    checkFuelStatus()
    if not length then
        length = 1
    end

    for i = 1, length, 1 do
        while not turtle.up() do
            turtle.attackUp()
            turtle.digUp()
        end
        y = y + 1
        logData()
    end
end

--moves the turtle down
local function down(length)
    checkFuelStatus()
    if not length then
        length = 1
    end

    for i = 1, length, 1 do
        while not turtle.down() do
        turtle.attackDown()
        turtle.digDown()
    end
    y = y - 1
    logData()
    end
end

--turns the turtle right
local function right()
    turtle.turnRight()
    local xtemp = xdir
    xdir = -zdir
    zdir = xtemp
    logData()
end

--turns the turtle left
local function left()
    turtle.turnLeft()
    local xtemp = xdir
    xdir = zdir
    zdir = -xtemp
    logData()
end

--turns the turtle around
local function turnAround()
    turtle.turnRight()
    turtle.turnRight()
    xdir = -xdir
    zdir = -zdir
end

--orients the turtle in the given x/z-directions
local function orientTowards(xOr, zOr)
    if xdir == xOr and zdir == zOr then
        return
    end
    if xdir == zOr and -zdir == xOr  then
        right()
        return
    end
    left()
    if not (xdir == xOr and zdir == zOr) then
        left()
    end
end

--[[-
    Checks if the block described in the given data is whitelisted for mining. TODO editable whitelist
    @param #table data The data of the block to check
    @return #boolean
]]
local function is_block_whitelisted(data)
    if data["tags"]["forge:ores"] then
        return true
    end
    return false
end

local function mv_x(x_translation)
    if x_translation == 0 then
        return
    end

    orientTowards(x_translation > 0 and 1 or -1, 0)
    local temp = math.abs(x_translation)
    for i = 1, temp, 1 do
        forward()
    end
end

local function mv_y(y_translation)
    if y_translation == 0 then
        return
    end

    local temp = math.abs(y_translation)
    if y_translation < 0 then
        for i = 1, temp, 1 do
            down()
        end
        return
    end

    for i = 1, temp, 1 do
        up()
    end
end

local function mv_z(z_translation)
    if z_translation == 0 then
        return
    end

    orientTowards(0, z_translation > 0 and 1 or -1)
    local temp = math.abs(z_translation)
    for i = 1, temp, 1 do
        forward()
    end
end

--moves the turtle to the position in the yz plane
local function mv_yz(ypos, zpos)
   mv_z(zpos - z)
   mv_y(ypos - y)
end

local function check()
    local is_block, data = turtle.inspect()
    if (not is_block) or (not is_block_whitelisted(data)) then
        return
    end
    turtle.dig()
end

local function checkUp()
    local is_block, data = turtle.inspectUp()
    if (not is_block) or (not is_block_whitelisted(data)) then
        return
    end
    turtle.digUp()
end

local function checkDown()
    local is_block, data = turtle.inspectDown()
    if (not is_block) or (not is_block_whitelisted(data)) then
        return
    end
    turtle.digDown()
end

--moves <length> blocks forward, while checking all open faces for ores
local function mk_corridor_optimine(length)
    for i = 1, length, 1 do
        forward()
        check()
        checkUp()
        checkDown()
        left()
        check()
        turnAround()
        check()
        if i < length then
            left()
        end
    end
end

--starts the main mining program
local function mine()
    for y_current = -bound_yn, bound_yp, 1 do
        local z_bound_lower_current_y = (math.floor(bound_zn / SHAFT_OFFSET_HORIZONTAL) + 1) * SHAFT_OFFSET_HORIZONTAL - (SHAFT_OFFSET_ON_NEXT_Y * y_current) % SHAFT_OFFSET_HORIZONTAL
        z_bound_lower_current_y = z_bound_lower_current_y > bound_zn and z_bound_lower_current_y - SHAFT_OFFSET_HORIZONTAL or z_bound_lower_current_y
        
        for z_current = -z_bound_lower_current_y, bound_zp, SHAFT_OFFSET_HORIZONTAL do
            mv_yz(y_current, z_current)
            orientTowards(1,0)
            mk_corridor_optimine(bound_x)
            mv_x(-bound_x)
        end
    end
end

--makes the turtle return to its starting position, facing backwards
function returnToStart()
    mv_yz(0,0)

    mv_x(-x)
    
    orientTowards(-1,0)
end

--main program
local function main()
    mine()
    returnToStart()
end

main();