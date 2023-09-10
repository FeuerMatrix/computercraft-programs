-- CC Turtle Mining Program by FeuerMatrix

local DEBUG_MODE = false

--[[
whether to excavate the entire vein of found ore TODO WIP deactivation
]]
local DO_VEINMINE = true
--[[
    if false, the turtle makes sure to not break out of boundaries TODO WIP
]]
local VEINMINE_IGNORE_BOUNDARIES = true
--[[
    if true, the turtle gets rid of items not in the list of blocks to mine TODO WIP
]]
local DELETE_UNWANTED_ITEMS = true
--[[
    up to which slot (including this) items can be thrown or consumed for making room in the turtle<br>
    Used in an iteration in checkInventoryFull().<br><br>
    <b>Why does this exist?</b><br>
    Slots that have already been checked contain items that are non-combustible and part of the wanted resource filter. Those items will likely never leave these slots until the turtle empties at the starting point.<br>
    The more slots are full with valuable items, the less mining operations the turtle can perform before it is full again. Also, all these slots need to be iterated over, which causes a severe time loss since changing slots is the second worst time performance limiter, first being moving.<br>
    This value effectively forces the turtle to unload everything if only the \<this> first slots are even considered for throwing away.<br>
    Note: This does not mean that the other slots are completely wasted, since they still have items in it that were collected until the last slot became full.<br><br>
    Nevertheless, in the worst case the last 16-\<this> slots might contain only 1 non-relevant item. Therefore, setting this too low will force the turtle into more return trips than may be necessary. Getting closer to 0 on this value will get closer to deactivating the feature altogether.
]]
local MAX_INVENTORY_LOAD_FOR_DELETING = 12
--[[
    the slot that fuel is held in<br>
    For good performance this should be 1. Other values untested.
]]
local FUEL_SLOT = 1
--[[
    the upper limit for fuel to carry at one time<br>
    This is not a hard limit, some actions may still go above this if they have a reason to do so. Putting this too high means that the turtle will swallow the entire load of mined coal.
]]
local FUEL_CONSUMPTION_LIMIT = 20000
--[[
    how much blocks to the next shaft on the same y-level<br>
    (5/2) -> minimal mining to check EVERY block<br>
    (8/3) -> assumes that most ore veins will extend in more than one direction. ~50% faster, but might miss some ore veins with only 1 or 2 blocks
]]
local SHAFT_OFFSET_HORIZONTAL = 5
--[[
    by how much horizontal shafts on neighbouring y-levels are offset to each other in z-direction
]]
local SHAFT_OFFSET_ON_NEXT_Y = 2

--[[
    do I really need to explain these<br>
    The coordinates of the turtle. These aren't actual minecraft coordinates: the coordinate system has the turtle starting point as (0,0,0) and the turtle starts facing positive x
]]
local x, y, z = 0,0,0
--[[
    the direction the turtle is facing.<br>
    1 if facing the direction, -1 if facing opposite, 0 if orthogonal to the corresponding axis
]]
local xdir, zdir = 1,0

--boundaries of the area to mine
local bound_x, bound_yp, bound_yn, bound_zp, bound_zn = 4, 1, 1, 2, 2

--basic implementation of a tree structure.<br>
--Note that this is a special implementation for the vein excavation and does not necessarily behave exactly as a normal tree would.
local tree
tree = {
    --[[
        instanciates an object of the tree type<br>
        @param node_x x coordinate of the node<br>
        @param node_y y coordinate of the node<br>
        @param node_z z coordinate of the node
    ]]
    newInstance = function(node_x, node_y, node_z)
        return {
            --x coordinate of the node
            x = node_x,
            --y coordinate of the node
            y = node_y,
            --z coordinate of the node
            z = node_z,
            --[[
                queries the coordinates of the tree
                <ol>
                    <li>@return x coordinate</li>
                    <li>@return y coordinate</li>
                    <li>@return z coordinate</li>
                </ol>
            ]]
            getCoordinates = function (self)
                return self.x, self.y, self.z
            end,
            --children of this node
            children = {},
            --[[
                parent node of this node<br>
                only gets set here so that it is clear the parameter is used (since it starts at nil)
            ]]
            parent = nil,
            --[[
                adds the given tree as a child<br>
                @param new_tree the node to make the new child
            ]]
            addChild = function (self, new_tree)
                new_tree.parent = self
                self.children[#self.children+1] = new_tree
            end,
            --[[
                checks whether this node is a leaf (has children)<br>
                 @return true, if this node is a leaf; false otherwise
            ]]
            isLeaf = function (self)
                return #self.children == 0
            end,
            --[[
                checks if this node or a child contains a point with the given coordinates<br>
                @param search_x x coordinate of point to search for<br>
                @param search_y y coordinate of point to search for<br>
                @param search_z z coordinate of point to search for<br>
                @return true, if the point was found; false otherwise
            ]]
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
            --[[
                checks how many nodes there are above this one<br>
                @return the amount of nodes above this one in the tree
            ]]
            currentDepth = function (self)
                local temp = self
                local counter = 0
                while not (temp.parent == nil) do
                    counter = counter + 1
                    temp = temp.parent
                end
                return counter
            end,
            --[[
                queries the top node of the tree<br>
                @return the top node
            ]]
            getFirstParent = function (self)
                local current_knot = self
                while not (current_knot.parent == nil) do
                    current_knot = current_knot.parent
                end
                return current_knot
            end,
            --allows for object.class.newInstance()
            class = tree
        }
    end
}

--variable used for storing the excavation tree during ore excavation
local excavation_graph


--[[
    Significance of the movement that is currently executed. Determines how to react to problems like hitting bedrock, full inventory and low fuel.
    <ul>
    <li>0 <=> Low significance, e.g. following ore veines. Bedrock is just ignored and the movement is cancelled. Logistical problems immediately pause the action.</li>
    <li>1 <=> Normal significance, e.g. mining a branch. Logistical problems are treated like for low significance, but changes to the planned movement will be made when hitting bedrock.</li>
    <li>2 <=> Critical Movement. Logistical problems are ignored. Hitting bedrock results in the entire program yielding.</li>
    </ul>
]]
local current_movement_significance = 1

local returnToMiningPosition
local returnToStart
local checkInventoryFull

--this is only here so that lua syntax check ignores computer craft specific globals TODO delete on release
turtle = turtle
textutils = textutils

--prints current coordinates and face direction in the console
local function logData()
    if not DEBUG_MODE then
        return
    end
    print(x .. " | " .. y .. " | " .. z .. " || " .. xdir .. " | " .. zdir)
end

--[[
    empties the inventory of the turtle in a container in front of it<br>
    The fuel in the fuel slot is left alone.
]]
local function empty()
    for i = 1, 16, 1 do
        if not (i == FUEL_SLOT) and not (turtle.getItemCount(i) == 0) then
            turtle.select(i)
            turtle.drop()
        end
    end
    turtle.select(FUEL_SLOT)
end

--empties the complete inventory into a container in front
local function emptyAll()
    empty()
    if turtle.getItemCount(FUEL_SLOT) == 0 then
        return
    end
    turtle.select(FUEL_SLOT)
    turtle.drop()
end

--[[
    Returns the 1-norm of the current coordinate vector (also known as Manhattan distance)<br>
    @return Manhattan distance of current coordinate to (0,0,0)
]]
local function one_norm(in1, in2, in3)
    return math.abs(in1) + math.abs(in2) + math.abs(in3)
end

--[[
    calculates how much fuel is required to return to starting position<br>
    @return the amount of fuel needed to return
]]
local function fuel_to_return()
    if excavation_graph == nil then
        return one_norm(x,y,z)
    end
    return one_norm(excavation_graph:getFirstParent():getCoordinates()) + excavation_graph:currentDepth() - 1
end

--[[
    refuels the turtle with following logic
    <ol>
    <li>tries to consume fuel from the fuel slot, always leaving 1 item except if the fuel is unstackable.</li>
    <li>if previous failed, search for another slot with fuel and try to swap it onto the fuel slot. Then return to 1. If swap impossible, consume fuel directly from that slot.</li>
    <li>if previous failed, return to start and throw an error to the user</li>
    </ol>
]]
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

--[[
    checks if the current fuel level is high enough to make it back even after one more movement<br>
    If not enough fuel is supplied, enters refueling.<br>
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

--wrapper function for turtle.dig() that does necessary checks
local function dig()
    checkInventoryFull()
    turtle.dig()
end

--wrapper function for turtle.digUp() that does necessary checks
local function digUp()
    checkInventoryFull()
    turtle.digUp()
end

--wrapper function for turtle.digDown() that does necessary checks
local function digDown()
    checkInventoryFull()
    turtle.digDown()
end

--[[
    Moves the turtle forward by the given length.<br>
    @param <b>length</b> The amount of blocks to move. Defaults to 1.
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

--[[
    Moves the turtle upward by the given length.<br>
    @param <b>length</b> The amount of blocks to move. Defaults to 1.
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

--[[
    Moves the turtle down by the given length.<br>
    @param <b>length</b> The amount of blocks to move. Defaults to 1.
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

--[[
    rotates the given directions to the right<br>
     @param old_xdir the x axis direction before the rotation<br>
     @param old_zdir the z axis direction before the rotation<br>
     <ol>
        <li>@return the new x axis direction</li>
        <li>@return the new z axis direction</li>
    </ol>
]]
local function rotate_right(old_xdir, old_zdir)
    return -old_zdir, old_xdir
end

--[[
    rotates the given directions to the left<br>
     @param old_xdir the x axis direction before the rotation<br>
     @param old_zdir the z axis direction before the rotation<br>
     <ol>
        <li>@return the new x axis direction</li>
        <li>@return the new z axis direction</li>
    </ol>
]]
local function rotate_left(old_xdir, old_zdir)
    return old_zdir, -old_xdir
end

--[[
    rotates the given directions around<br>
     @param old_xdir the x axis direction before the rotation<br>
     @param old_zdir the z axis direction before the rotation<br>
     <ol>
        <li>@return the new x axis direction</li>
        <li>@return the new z axis direction</li>
    </ol>
]]
local function rotate_around(old_xdir, old_zdir)
    return -old_xdir, -old_zdir
end

--[[
    Turns the turtle right.
]]
local function right()
    turtle.turnRight()
    xdir, zdir = rotate_right(xdir, zdir)
    logData()
end

--[[
    Turns the turtle left.
]]
local function left()
    turtle.turnLeft()
    xdir, zdir = rotate_left(xdir, zdir)
    logData()
end

--[[
    Turns the turtle around.
]]
local function turnAround()
    turtle.turnRight()
    turtle.turnRight()
    xdir, zdir = rotate_around(xdir, zdir)
    logData()
end


--[[
    Turns the turtle so that it faces the given direction.<br>
    @param xOr where to face on the x-axis (valid are -1, 0, 1)<br>
    @param zOr where to face on the y-axis (valid are -1, 0, 1)
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

--[[
    Checks if the block described in the given data is whitelisted for mining. TODO editable whitelist<br>
    @param data the data of the block to check<br>
    @return true, if the block may be mined; false otherwise
]]
local function is_whitelisted(data)
    if data["tags"] ~= nil and data["tags"]["forge:ores"] then
        return true
    end
    return false
end

--[[
    moves the turtle by the given amount in x direction<br>
    @param x_translation the amount of blocks to move - negative numbers are accepted<br>
    @implNote might permuate the turtle rotation
]]
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

--[[
    moves the turtle by the given amount in y direction<br>
    @param y_translation the amount of blocks to move - negative numbers are accepted
]]
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

--[[
    moves the turtle by the given amount in z direction<br>
    @param z_translation the amount of blocks to move - negative numbers are accepted<br>
    @implNote might permuate the turtle rotation
]]
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

--[[
    moves the turtle to the given location<br>
    Movements are carried out in the order x->y->z<br><br>
    @param xpos x coordinate of the point to move to<br>
    @param ypos y coordinate of the point to move to<br>
    @param zpos z coordinate of the point to move to<br>
    @implNote might permuate the turtle rotation
]]
local function mv_xyz(xpos, ypos, zpos)
    mv_x(xpos - x)
    mv_z(zpos - z)
    mv_y(ypos - y)
end

--[[
    checks if the turtle has a full inventory<br>
    If this is the case, the turtle will empty it. In order to do this, fuel in non-fuel-slots might be consumed.
]]
function checkInventoryFull()
    if turtle.getItemCount(16) == 0 or current_movement_significance == 2 then
        return
    end
    --try to consume fuel stacks, and if a slot opens up, transfer from slot 16
    --if unwanted item disposal is turned on, also tries that
    for i = 1, 16, 1 do
        if i <= MAX_INVENTORY_LOAD_FOR_DELETING and turtle.getFuelLevel() < FUEL_CONSUMPTION_LIMIT and not (i == FUEL_SLOT) and not (turtle.getItemCount(i) == 0) then
            turtle.select(i)
            turtle.refuel(64)
        end
        if turtle.getItemCount(i) == 0 then
            turtle.select(16)
            turtle.transferTo(i)
            turtle.select(FUEL_SLOT)
            return
        end
        if (DELETE_UNWANTED_ITEMS and i <= MAX_INVENTORY_LOAD_FOR_DELETING) and (not (i == FUEL_SLOT)) and (not is_whitelisted(turtle.getItemDetail(i, true))) then
            turtle.drop(64)
            return
        end
    end
    turtle.select(FUEL_SLOT)
    local previous_significance = current_movement_significance
    current_movement_significance = 2
    local return_x, return_y, return_z, return_xdir, return_zdir = x,y,z,xdir,zdir
    returnToStart()
    empty()
    current_movement_significance = 1
    returnToMiningPosition(return_x, return_y, return_z)
    orientTowards(return_xdir,return_zdir)
    current_movement_significance = previous_significance
end

local check
local checkUp
local checkDown

--common code of the check() functions
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

--[[
    checks the block in front and mines it if it's whitelisted<br>
    If ore excavation is turned on, the turtle will check faces connected to the mined block for more whitelisted blocks.
]]
function check()
    local is_block, data = turtle.inspect()
    if (not is_block) or (not is_whitelisted(data)) then
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
    if excavation_graph == nil then --should never happen in correct implementation
        error("critical error in ore excavation data")
    end
    if excavation_graph.parent == nil then
        excavation_graph = nil
        return
    end
end

--[[
    checks the block below and mines it if it's whitelisted<br>
    If ore excavation is turned on, the turtle will check faces connected to the mined block for more whitelisted blocks.
]]
function checkUp()
    local is_block, data = turtle.inspectUp()
    if (not is_block) or (not is_whitelisted(data)) then
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
    if excavation_graph == nil then --should never happen in correct implementation
        error("critical error in ore excavation data")
    end
    if excavation_graph.parent == nil then
        excavation_graph = nil
        return
    end
end

--[[
    checks the block above and mines it if it's whitelisted<br>
    If ore excavation is turned on, the turtle will check faces connected to the mined block for more whitelisted blocks.
]]
function checkDown()
    local is_block, data = turtle.inspectDown()
    if (not is_block) or (not is_whitelisted(data)) then
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
    if excavation_graph == nil then --should never happen in correct implementation
        error("critical error in ore excavation data")
    end
    if excavation_graph.parent == nil then
        excavation_graph = nil
        return
    end
end

--[[
    moves given amount of blocks forward, while checking all open faces for ores<br>
    Afterwards, goes back to the starting point.<br>
    @param length amount of blocks to move<br>
    @implNote might permuate the turtle rotation
]]
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

--recursive helper function for returnToMiningPosition()
local function traceExcavationGraph(return_x, return_y, return_z, node)
    if not (node.parent == nil) then
        traceExcavationGraph(return_x, return_y, return_z, node.parent)
        mv_xyz(node:getCoordinates())
    end
end

--[[
    moves the turtle to the given position, tracing back the path including respecting the ore excavation path<br>
    @param return_x the x coordinate to return to<br>
    @param return_y the y coordinate to return to<br>
    @param return_z the z coordinate to return to
]]
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
    turtle.select(FUEL_SLOT)
    mine()
end

main();