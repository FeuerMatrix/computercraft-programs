-- CC Turtle Mining Program by FeuerMatrix

local LOG_DATA = false
--Checks for easier ways back than just reversing every movement. Makes the turtle more fuel efficient.
local RETURN_PATH_STRAIGHTENING = true
--How many last movement positions away the turtle will consider when finding a better path.
local RETURN_PATH_STRAIGHTENING_MAX_CHECKING_DISTANCE = 20
local DO_VEINMINE = true
local VEINMINE_IGNORE_BOUNDARIES = true
--if true, the turtle gets rid of items not in the list of blocks to mine
local DELETE_UNWANTED_ITEMS = false
local FUEL_SLOT = 1
--the upper limit for fuel to carry at one time. This is not a hard limit, some actions may still go above this if they have a reason to do so. Putting this too high means that the turtle will swallow the entire load of mined coal.
local FUEL_CONSUMPTION_LIMIT = 20000
--(5/2) -> minimal mining to check EVERY block | (8/3) -> assumes that most ore veins will extend in more than one direction. ~50% faster, but might miss some ore veins with only 1 or 2 blocks
--how much blocks to the next shaft on the same y-level
local SHAFT_OFFSET_HORIZONTAL = 5
--by how much horizontal shafts on neighbouring y-levels are offset to each other in z-direction
local SHAFT_OFFSET_ON_NEXT_Y = 2

local x, y, z = 0,0,0
local xdir, zdir = 1,0

--boundaries of the area to mine
local bound_x, bound_yp, bound_yn, bound_zp, bound_zn = 4, 1, 1, 2, 2

--basic implementation of a tree structure. Note that this is a special implementation for the vein excavation and does not necessarily behave exactly as a normal tree would.
local tree
tree = {
    newInstance = function(node_x, node_y, node_z)
        return {
            x = node_x,
            y = node_y,
            z = node_z,
            getCoordinates = function (self)
                return self.x, self.y, self.z
            end,
            children = {},
            addChild = function (self, new_tree)
                new_tree.parent = self
                self.children[#self.children+1] = new_tree
            end,
            isLeaf = function (self)
                return #self.children == 0
            end,
            contains = function (self, search_x, search_y, search_z)
                if self.x == search_x and self.y == search_y and self.z == search_z then
                    return true
                end
                for i = 1, #self.children, 1 do
                    if self.children[i]:contains(search_x, search_y, search_z) then
                        return true
                    end
                end
                return false
            end,
            currentDepth = function (self)
                local temp = self
                local counter = 0
                while not (temp.parent == nil) do
                    counter = counter + 1
                    temp = temp.parent
                end
                return counter
            end,
            getFirstParent = function (self)
                local current_knot = self
                while not (current_knot.parent == nil) do
                    current_knot = current_knot.parent
                end
                return current_knot
            end,
            class = tree --allows for object.class.newInstance()
        }
    end
}

local excavation_graph

--[[-
    Significance of the movement that is currently executed. Determines how to react to problems like hitting bedrock, full inventory and low fuel.

    0 <=> Low significance, e.g. following ore veines. Bedrock is just ignored and the movement is cancelled. Logistical problems immediately pause the action.
    1 <=> Normal significance, e.g. mining a branch. Logistical problems are treated like for low significance, but changes to the planned movement will be made when hitting bedrock.
    2 <=> Critical Movement. Logistical problems are ignored. Hitting bedrock results in the entire program yielding.
]]
local current_movement_significance = 1

local returnToMiningPosition
local returnToStart
local checkInventoryFull

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

local function empty()
    for i = 1, 16, 1 do
        if not (i == FUEL_SLOT) then
            turtle.select(i)
            turtle.drop()
        end
    end
    turtle.select(FUEL_SLOT)
end

local function emptyAll()
    empty()
    turtle.select(FUEL_SLOT)
    turtle.drop()
end

--[[-
    Returns the 1-norm of the current coordinate vector (also known as Manhattan distance)
    @return Manhattan distance of current coordinate to (0,0,0)
]]
local function one_norm(in1, in2, in3)
    return math.abs(in1) + math.abs(in2) + math.abs(in3)
end

local function fuel_to_return()
    if excavation_graph == nil then
        return one_norm(x,y,z)
    end
    return one_norm(excavation_graph:getFirstParent():getCoordinates()) + excavation_graph:currentDepth() - 1
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
    if turtle.getItemSpace() == 0 and turtle.getItemCount() == 1 then --if the fuel item is not stackable, the turtle will not keep a single fuel item around (since that would just waste the slot)
        if turtle.refuel(1) then
            return
        end
    end
    local fuel_in_slot = turtle.refuel(0)
    for i = 1, 16, 1 do --check other slots for fuel
        if not (i == FUEL_SLOT) then
            turtle.select(i)
            if turtle.refuel(0) then
                if turtle.getItemCount() > 1 and not fuel_in_slot and (turtle.getItemCount(16) == 0 or turtle.getItemCount(FUEL_SLOT) == 0) then --if there is more than one fuel item in the selected slot and no more fuel in the fuel slot, makes the found fuel the new fuel in the fuel slot.
                    if not turtle.getItemCount(FUEL_SLOT) == 0 then
                        turtle.select(FUEL_SLOT)
                        turtle.transferTo(16)
                        turtle.select(i) 
                    end
                    turtle.transferTo(FUEL_SLOT)
                    refuel()
                    return
                end
                turtle.refuel() --if the above condition is not fulfilled, the found fuel is simply consumed.
                turtle.select(FUEL_SLOT)
                return
            end
        end
    end
    current_movement_significance = 2
    returnToStart()
    emptyAll()
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
    if fuel > 1 + fuel_to_return() then
        return
    end
    refuel()
end

local function dig()
    checkInventoryFull()
    turtle.dig()
end

local function digUp()
    checkInventoryFull()
    turtle.digUp()
end

local function digDown()
    checkInventoryFull()
    turtle.digDown()
end

--[[-
    Moves the turtle forward by the given length.
    @param #int length The amount of blocks to move. Defaults to 1.
]]
local function forward(length)
    checkFuelStatus()
    if not length then
        length = 1
    end

    for i = 1, length, 1 do
        while not turtle.forward() do
            turtle.attack()
            dig()
        end
        x = x + xdir
        z = z + zdir
        logData()
    end
end

--[[-
    Moves the turtle upward by the given length.
    @param #int length The amount of blocks to move. Defaults to 1.
]]
local function up(length)
    checkFuelStatus()
    if not length then
        length = 1
    end

    for i = 1, length, 1 do
        while not turtle.up() do
            turtle.attackUp()
            digUp()
        end
        y = y + 1
        logData()
    end
end

--[[-
    Moves the turtle down by the given length.
    @param #int length The amount of blocks to move. Defaults to 1.
]]
local function down(length)
    checkFuelStatus()
    if not length then
        length = 1
    end

    for i = 1, length, 1 do
        while not turtle.down() do
        turtle.attackDown()
        digDown()
    end
    y = y - 1
    logData()
    end
end

local function rotate_right(old_xdir, old_zdir)
    return -old_zdir, old_xdir
end

local function rotate_left(old_xdir, old_zdir)
    return old_zdir, -old_xdir
end

local function rotate_around(old_xdir, old_zdir)
    return -old_xdir, -old_zdir
end

--[[-
    Turns the turtle right.
]]
local function right()
    turtle.turnRight()
    xdir, zdir = rotate_right(xdir, zdir)
    logData()
end

--[[-
    Turns the turtle left.
]]
local function left()
    turtle.turnLeft()
    xdir, zdir = rotate_left(xdir, zdir)
    logData()
end

--[[-
    Turns the turtle around.
]]
local function turnAround()
    turtle.turnRight()
    turtle.turnRight()
    xdir, zdir = rotate_around(xdir, zdir)
    logData()
end


--[[-
    Turns the turtle so that it faces the given direction.
    @param #int xOr Where to face on the x-axis (valid are -1, 0, 1)
    @param #int yOr Where to face on the y-axis (valid are -1, 0, 1)
]]
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

--Moves the turtle to the specified position. This may change rotation
local function mv_xyz(xpos, ypos, zpos)
    mv_x(xpos - x)
    mv_z(zpos - z)
    mv_y(ypos - y)
end

function checkInventoryFull()
    if turtle.getItemCount(16) == 0 or current_movement_significance == 2 then
        return
    end
    
    --try to consume fuel stacks first, and if a slot opens up, transfer from slot 16
    if turtle.getFuelLevel() < FUEL_CONSUMPTION_LIMIT then
        for i = 1, 16, 1 do
            if not (i == FUEL_SLOT) and not (turtle.getItemCount(i) == 0) then
                turtle.select(i)
                turtle.refuel(64)
            end
            if turtle.getItemCount(i) == 0 then
                turtle.select(16)
                turtle.transferTo(i)
                turtle.select(FUEL_SLOT)
                return
            end
        end
    end
    turtle.select(FUEL_SLOT)
    local previous_significance = current_movement_significance
    current_movement_significance = 2
    local return_x, return_y, return_z, return_xdir, return_zdir = x,y,z,xdir,zdir
    returnToStart()
    empty()
    returnToMiningPosition(return_x, return_y, return_z)
    orientTowards(return_xdir,return_zdir)
    current_movement_significance = previous_significance
end

local check
local checkUp
local checkDown

local function cascade_checks()
    local starting_xdir, starting_zdir = xdir, zdir
    if excavation_graph == nil or not excavation_graph:contains(x + xdir, y, z + zdir) then
        check()
    end
    if excavation_graph == nil or not excavation_graph:contains(x, y - 1, z) then
        checkDown()
    end
    if excavation_graph == nil or not excavation_graph:contains(x, y + 1, z) then
        checkUp()
    end
    local new_xdir, new_zdir = rotate_left(starting_xdir, starting_zdir)
    if excavation_graph == nil or not excavation_graph:contains(x + new_xdir, y, z + new_zdir) then
        orientTowards(new_xdir, new_zdir)
        check()
    end
    new_xdir, new_zdir = rotate_right(starting_xdir, starting_zdir)
    if excavation_graph == nil or not excavation_graph:contains(x + new_xdir, y, z + new_zdir) then
        orientTowards(new_xdir, new_zdir)
        check()
    end
    local new_xdir, new_zdir = rotate_around(starting_xdir, starting_zdir)
    if excavation_graph == nil or not excavation_graph:contains(x + new_xdir, y, z + new_zdir) then
        orientTowards(new_xdir, new_zdir)
        check()
    end
end

function check()
    local is_block, data = turtle.inspect()
    if (not is_block) or (not is_block_whitelisted(data)) then
        return
    end
    if excavation_graph == nil then
        excavation_graph = tree.newInstance(x, y, z)
    end
    local temp = tree.newInstance(x + xdir, y, z + zdir)
    excavation_graph:addChild(temp)
    excavation_graph = temp
    forward()
    cascade_checks()
    forward()
    excavation_graph = excavation_graph.parent
    if excavation_graph.parent == nil then
        excavation_graph = nil
        return
    end
end

function checkUp()
    local is_block, data = turtle.inspectUp()
    if (not is_block) or (not is_block_whitelisted(data)) then
        return
    end
    if excavation_graph == nil then
        excavation_graph = tree.newInstance(x, y+1, z)
    end
    local temp = tree.newInstance(x, z)
    excavation_graph:addChild(temp)
    excavation_graph = temp
    up()
    cascade_checks()
    down()
    excavation_graph = excavation_graph.parent
    if excavation_graph.parent == nil then
        excavation_graph = nil
        return
    end
end

function checkDown()
    local is_block, data = turtle.inspectDown()
    if (not is_block) or (not is_block_whitelisted(data)) then
        return
    end
    if excavation_graph == nil then
        excavation_graph = tree.newInstance(x, y-1, z)
    end
    local temp = tree.newInstance(x + xdir, z + zdir)
    excavation_graph:addChild(temp)
    excavation_graph = temp
    down()
    cascade_checks()
    up()
    excavation_graph = excavation_graph.parent
    if excavation_graph.parent == nil then
        excavation_graph = nil
        return
    end
end

--moves <length> blocks forward, while checking all open faces for ores
local function mk_corridor_optimine(length)
    local starting_xdir, starting_zdir = xdir, zdir
    for i = 1, length, 1 do
        mv_x(1)
        check()
        checkUp()
        checkDown()
        orientTowards(rotate_left(starting_xdir, starting_zdir))
        check()
        orientTowards(rotate_right(starting_xdir, starting_zdir))
        check()
    end
    mv_x(-length)
end

--starts the main mining program
local function mine()
    for y_current = -bound_yn, bound_yp, 1 do
        local z_bound_lower_current_y = (math.floor(bound_zn / SHAFT_OFFSET_HORIZONTAL) + 1) * SHAFT_OFFSET_HORIZONTAL - (SHAFT_OFFSET_ON_NEXT_Y * y_current) % SHAFT_OFFSET_HORIZONTAL
        z_bound_lower_current_y = z_bound_lower_current_y > bound_zn and z_bound_lower_current_y - SHAFT_OFFSET_HORIZONTAL or z_bound_lower_current_y
        
        for z_current = -z_bound_lower_current_y, bound_zp, SHAFT_OFFSET_HORIZONTAL do
            mv_xyz(0, y_current, z_current)
            orientTowards(1,0)
            mk_corridor_optimine(bound_x)
        end
    end
    returnToStart()
    emptyAll()
end

--helper function for returnToMiningPosition()
local function traceExcavationGraph(return_x, return_y, return_z, node)
    if not (node.parent == nil) then
        traceExcavationGraph(return_x, return_y, return_z, node.parent)
        mv_xyz(node:getCoordinates())
    end
end

function returnToMiningPosition(return_x, return_y, return_z)
    if excavation_graph == nil then
        mv_xyz(0, return_y, return_z) --so that the x movement is executed last (mv_xyz moves x first)
        mv_xyz(return_x, 0, 0)
        return
    end
    --if the turtle was excavating an ore vein, it should not break a lot of blocks to get back. Therefore, it first moves to the excavation entry point and then traces the excavation graph to the return coordinates
    local upper_node = excavation_graph:getFirstParent()
    mv_xyz(0, upper_node.y, upper_node.z) --so that the x movement is executed last (mv_xyz moves x first)
    mv_xyz(upper_node.x, 0, 0)
    local temp_node = excavation_graph
    while not (temp_node.x == return_x and temp_node.y == return_y and temp_node.z == return_z) do --excavation graph might have already updated, but movement not yet conducted
        if temp_node.parent == nil then
            error("critical error in ore excavation data")
        end
        temp_node = temp_node.parent
    end
    traceExcavationGraph(return_x, return_y, return_z, temp_node)
end

--makes the turtle return to its starting position, facing backwards
function returnToStart()
    if not (excavation_graph == nil) then --if the turtle was currently excavating an ore vein, it should first trace that back
        local temp_node = excavation_graph
        while not (temp_node.x == x and temp_node.y == y and temp_node.z == z) do --excavation graph might have already updated, but movement not yet conducted
            if temp_node.parent == nil then
                error("critical error in ore excavation data")
            end
            temp_node = temp_node.parent
        end
        while not (temp_node.parent == nil) do
            temp_node = temp_node.parent
            mv_xyz(temp_node:getCoordinates())
        end
    end
    mv_xyz(0,0,0)

    orientTowards(-1,0)
end

--main program
local function main()
    mine()
end

main();