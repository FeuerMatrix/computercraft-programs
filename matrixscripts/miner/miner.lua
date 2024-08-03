---@diagnostic disable: duplicate-set-field
-- CC Turtle Mining Program by FeuerMatrix

package.path = package.path .. ";../?.lua"
local ExcavationTree = require "miner.ExcavationTree"
local core = require "core.turtle_core"
local termlib = require "core.term_core"

--[[
whether to excavate the entire vein of found ore
]]
local DO_VEINMINE
--[[
    if false, the turtle makes sure to not break out of boundaries even if ore was found
]]
local MINING_IGNORE_BOUNDARIES
--[[
    if true, the turtle gets rid of items not in the list of blocks to mine
]]
local DELETE_UNWANTED_ITEMS
--[[
    up to which slot (including this) items can be thrown or consumed for making room in the turtle<br>
    Used in an iteration in checkInventoryFull().<br><br>
    <b>Why does this exist?</b><br>
    Slots that have already been checked contain items that are non-combustible and part of the wanted resource filter. Those items will likely never leave these slots until the turtle empties at the starting point.<br>
    The more slots are full with valuable items, the less mining operations the turtle can perform before it is full again. Also, all these slots need to be iterated over, which causes a severe time loss since changing slots is the second worst time performance limiter, first being moving.<br>
    This value effectively forces the turtle to unload everything once approaching that point since only the \<this> first slots are even considered for throwing away.<br>
    Note: This does not mean that the other slots are completely wasted, since they still have items in it that were collected until the last slot became full.<br><br>
    Nevertheless, in the worst case the last 16-\<this> slots might contain only 1 non-relevant item. Therefore, setting this too low will force the turtle into more return trips than may be necessary. Getting closer to 0 on this value will get closer to deactivating the feature of making room altogether.
]]
local MAX_INVENTORY_LOAD_FOR_DELETING = 12
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

--boundaries of the area to mine
local bound_x, bound_yp, bound_yn, bound_zp, bound_zn

--variable used for storing the excavation tree during ore excavation
local excavation_graph

--path to the filter settings file
local filter_path = core.root_path.."/miner/filter.settings"

--path to the standard settings file
local settings_path = core.root_path.."/miner/miner.settings"

--wanted item whitelist<br>
--note: this doesn't accept oredict/tags
local ore_whitelist

local returnToMiningPosition

--overrides to imported functions
do
    local temp = core.fuel_to_return
    --[[
        @Override<br>
        calculates how much fuel is required to return to starting position<br>
        @return the amount of fuel needed to return
    ]]
    function core:fuel_to_return()
        if excavation_graph == nil then
            return temp(self)
        end
        return self:one_norm(excavation_graph:getFirstParent():getCoordinates()) + excavation_graph:currentDepth() - 1
    end
    
    local temp = core.returnToStart
    --[[
        @Override<br>
        makes the turtle return to its starting position, facing backwards
    ]]
    function core:returnToStart()
        if not (excavation_graph == nil) then --if the turtle was currently excavating an ore vein, it should first trace that back
            local temp_node = excavation_graph
            while not (temp_node.x == self.x and temp_node.y == self.y and temp_node.z == self.z) do --excavation graph might have already updated, but movement not yet conducted
                if temp_node.parent == nil then
                    error("critical error in ore excavation data")
                end
                temp_node = temp_node.parent
            end
            while not (temp_node.parent == nil) do
                temp_node = temp_node.parent
                self:mv_xyz(temp_node:getCoordinates())
            end
        end
        temp(self)
    end
    
    local temp = core.refuel
    --[[
        @Override<br>
        refuels the turtle with following logic
        <ol>
        <li>tries to consume fuel from the fuel slot, always leaving 1 item except if the fuel is unstackable.</li>
        <li>if previous failed, search for another slot with fuel and try to swap it onto the fuel slot. Then return to 1. If swap impossible, consume fuel directly from that slot.</li>
        <li>if previous failed, return to start and throw an error to the user</li>
        </ol>
    ]]
    function core:refuel()
        temp(self)
        local fuel_in_slot = turtle.refuel(0)
        for i = 1, 16, 1 do --check other slots for fuel
            if not (i == self.FUEL_SLOT) then
                turtle.select(i)
                if turtle.refuel(0) then
                    if turtle.getItemCount() > 1 and not fuel_in_slot and (turtle.getItemCount(16) == 0 or turtle.getItemCount(self.FUEL_SLOT) == 0) then --if there is more than one fuel item in the selected slot and no more fuel in the fuel slot, makes the found fuel the new fuel in the fuel slot.
                        if not turtle.getItemCount(self.FUEL_SLOT) == 0 then
                            turtle.select(self.FUEL_SLOT)
                            turtle.transferTo(16)
                            turtle.select(i)
                        end
                        turtle.transferTo(self.FUEL_SLOT)
                        self:refuel()
                        return
                    end
                    turtle.refuel() --if the above condition is not fulfilled, the found fuel is simply consumed.
                    turtle.select(self.FUEL_SLOT)
                    return
                end
            end
        end
        self.current_movement_significance = 2
        self:returnToStart()
        self:emptyAll()
        error("Critical fuel level. Terminating Program.")
    end

    --[[
        Checks if the block described in the given data is whitelisted for mining. TODO editable whitelist<br>
        @param data the data of the block to check<br>
        @return true, if the block may be mined; false otherwise
    ]]
    function core:is_whitelisted(data)
        return ore_whitelist[data["name"]]
    end

    --[[
        @Override<br>
        checks if the turtle has a full inventory<br>
        If this is the case, the turtle will empty it. In order to do this, fuel in non-fuel-slots might be consumed.
    ]]
    function core:checkInventoryFull()
        if turtle.getItemCount(16) == 0 or self.current_movement_significance == 2 then
            return
        end
        --try to consume fuel stacks, and if a slot opens up, transfer from slot 16
        --if unwanted item disposal is turned on, also tries that
        for i = 1, 16, 1 do
            if i <= MAX_INVENTORY_LOAD_FOR_DELETING and turtle.getFuelLevel() < self.FUEL_CONSUMPTION_LIMIT and not (i == self.FUEL_SLOT) and not (turtle.getItemCount(i) == 0) then
                turtle.select(i)
                turtle.refuel(64)
            end
            if turtle.getItemCount(i) == 0 then
                turtle.select(16)
                turtle.transferTo(i)
                turtle.select(self.FUEL_SLOT)
                return
            end
            if (DELETE_UNWANTED_ITEMS and i <= MAX_INVENTORY_LOAD_FOR_DELETING) and (not (i == self.FUEL_SLOT)) and (not core:is_whitelisted(turtle.getItemDetail(i))) then
                turtle.drop(64)
                return
            end
        end
        turtle.select(self.FUEL_SLOT)
        local previous_significance = self.current_movement_significance
        self.current_movement_significance = 2
        local return_x, return_y, return_z, return_xdir, return_zdir = self.x,self.y,self.z,self.xdir,self.zdir
        self:returnToStart()
        self:empty()
        self.current_movement_significance = 1
        returnToMiningPosition(return_x, return_y, return_z)
        self:orientTowards(return_xdir,return_zdir)
        self.current_movement_significance = previous_significance
    end
end

--[[
    calculates whether the given point is inside the boundaries defined by the bound_* variables<br>
    @param check_x the x coordinate to check<br>
    @param check_y the y coordinate to check<br>
    @param check_z the z coordinate to check<br>
    @return true, if the given point is out of bounds; false otherwise
]]
local function is_out_of_bounds(check_x, check_y, check_z)
    return check_x < 0 or check_x > bound_x or check_y > bound_yp or check_y < -bound_yn or check_z > bound_zp or check_z < -bound_zn
end

local check
local checkUp
local checkDown

--common code of the check() functions
local function cascade_checks()
    local starting_xdir, starting_zdir = core.xdir, core.zdir
    if excavation_graph == nil or not excavation_graph:contains(core.x + core.xdir, core.y, core.z + core.zdir) then
        check()
    end
    if excavation_graph == nil or not excavation_graph:contains(core.x, core.y - 1, core.z) then
        checkDown()
    end
    if excavation_graph == nil or not excavation_graph:contains(core.x, core.y + 1, core.z) then
        checkUp()
    end
    local new_xdir, new_zdir = core:rotate_left(starting_xdir, starting_zdir)
    if excavation_graph == nil or not excavation_graph:contains(core.x + new_xdir, core.y, core.z + new_zdir) then
        core:orientTowards(new_xdir, new_zdir)
        check()
    end
    new_xdir, new_zdir = core:rotate_right(starting_xdir, starting_zdir)
    if excavation_graph == nil or not excavation_graph:contains(core.x + new_xdir, core.y, core.z + new_zdir) then
        core:orientTowards(new_xdir, new_zdir)
        check()
    end
    new_xdir, new_zdir = core:rotate_around(starting_xdir, starting_zdir)
    if excavation_graph == nil or not excavation_graph:contains(core.x + new_xdir, core.y, core.z + new_zdir) then
        core:orientTowards(new_xdir, new_zdir)
        check()
    end
end

--[[
    checks the block in front and mines it if it's whitelisted<br>
    If ore excavation is turned on, the turtle will check faces connected to the mined block for more whitelisted blocks.
]]
function check()
    local is_block, data = turtle.inspect()
    if (not is_block) or (not core:is_whitelisted(data)) or (not MINING_IGNORE_BOUNDARIES and is_out_of_bounds(core.x + core.xdir, core.y, core.z + core.zdir)) then
        return
    end
    if not DO_VEINMINE then
        core:dig()
        return
    end
    if excavation_graph == nil then
        excavation_graph = ExcavationTree.newInstance(core.x, core.y, core.z)
    end
    local temp = ExcavationTree.newInstance(core.x + core.xdir, core.y, core.z + core.zdir)
    excavation_graph:addChild(temp)
    excavation_graph = temp
    core:forward()
    do
        local temp_xdir, temp_zdir = core:rotate_around(core.xdir, core.zdir)
        cascade_checks()
        core:orientTowards(temp_xdir, temp_zdir)
    end
    core:forward()
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
    if (not is_block) or (not core:is_whitelisted(data)) or (not MINING_IGNORE_BOUNDARIES and is_out_of_bounds(core.x, core.y+1, core.z)) then
        return
    end
    if not DO_VEINMINE then
        core:digUp()
        return
    end
    if excavation_graph == nil then
        excavation_graph = ExcavationTree.newInstance(core.x, core.y, core.z)
    end
    local temp = ExcavationTree.newInstance(core.x, core.y+1, core.z)
    excavation_graph:addChild(temp)
    excavation_graph = temp
    core:up()
    cascade_checks()
    core:down()
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
    if (not is_block) or (not core:is_whitelisted(data)) or (not MINING_IGNORE_BOUNDARIES and is_out_of_bounds(core.x, core.y-1, core.z)) then
        return
    end
    if not DO_VEINMINE then
        core:digDown()
        return
    end
    if excavation_graph == nil then
        excavation_graph = ExcavationTree.newInstance(core.x, core.y, core.z)
    end
    local temp = ExcavationTree.newInstance(core.x, core.y-1, core.z)
    excavation_graph:addChild(temp)
    excavation_graph = temp
    core:down()
    cascade_checks()
    core:up()
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
    local starting_xdir, starting_zdir = core.xdir, core.zdir
    for i = 1, length, 1 do
        core:mv_x(1)
        check()
        checkUp()
        checkDown()
        core:orientTowards(core:rotate_left(starting_xdir, starting_zdir))
        check()
        core:orientTowards(core:rotate_right(starting_xdir, starting_zdir))
        check()
    end
    core:mv_x(-length)
end

--starts the main mining program
local function mine()
    for y_current = -bound_yn, bound_yp, 1 do
        local z_bound_lower_current_y = (math.floor(bound_zn / SHAFT_OFFSET_HORIZONTAL) + 1) * SHAFT_OFFSET_HORIZONTAL - (SHAFT_OFFSET_ON_NEXT_Y * y_current) % SHAFT_OFFSET_HORIZONTAL
        z_bound_lower_current_y = z_bound_lower_current_y > bound_zn and z_bound_lower_current_y - SHAFT_OFFSET_HORIZONTAL or z_bound_lower_current_y
        
        for z_current = -z_bound_lower_current_y, bound_zp, SHAFT_OFFSET_HORIZONTAL do
            core:mv_xyz(0, y_current, z_current)
            core:orientTowards(1,0)
            mk_corridor_optimine(bound_x)
        end
    end
    core:returnToStart()
    core:emptyAll()
end

--recursive helper function for returnToMiningPosition()
local function traceExcavationGraph(return_x, return_y, return_z, node)
    if not (node.parent == nil) then
        traceExcavationGraph(return_x, return_y, return_z, node.parent)
        core:mv_xyz(node:getCoordinates())
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
        core:mv_xyz(0, return_y, return_z) --so that the x movement is executed last (mv_xyz moves x first)
        core:mv_xyz(return_x, 0, 0)
        return
    end
    --if the turtle was excavating an ore vein, it should not break a lot of blocks to get back. Therefore, it first moves to the excavation entry point and then traces the excavation graph to the return coordinates
    local upper_node = excavation_graph:getFirstParent()
    core:mv_xyz(0, upper_node.y, upper_node.z) --so that the x movement is executed last (mv_xyz moves x first)
    core:mv_xyz(upper_node.x, 0, 0)
    local temp_node = excavation_graph
    while not (temp_node.x == return_x and temp_node.y == return_y and temp_node.z == return_z) do --excavation graph might have already updated, but movement not yet conducted
        if temp_node.parent == nil then
            error("critical error in ore excavation data")
        end
        temp_node = temp_node.parent
    end
    traceExcavationGraph(return_x, return_y, return_z, temp_node)
end

--[[
    loads the contents of the ore filter file into the settings<br><br>
    This clears all previously loaded settings.<br>
    If the file doesn't exist or contents are missing, they are replaced by a default.
]]
local function loadOreFilter()
    settings.clear()
    settings.load(filter_path)

    --sets missing or broken parts of the settings to defaults
    if not settings.get("block_whitelist") then
        settings.set("block_whitelist", {
            ["minecraft:coal_ore"] = true,
            ["minecraft:copper_ore"] = true,
            ["minecraft:iron_ore"] = true,
            ["minecraft:redstone_ore"] = true,
            ["minecraft:gold_ore"] = true,
            ["minecraft:lapis_ore"] = true,
            ["minecraft:diamond_ore"] = true,
            ["minecraft:emerald_ore"] = true,
            ["minecraft:deepslate_copper_ore"] = true,
            ["minecraft:deepslate_coal_ore"] = true,
            ["minecraft:deepslate_iron_ore"] = true,
            ["minecraft:deepslate_redstone_ore"] = true,
            ["minecraft:deepslate_gold_ore"] = true,
            ["minecraft:deepslate_lapis_ore"] = true,
            ["minecraft:deepslate_diamond_ore"] = true,
            ["minecraft:deepslate_emerald_ore"] = true,
            ["minecraft:nether_gold_ore"] = true,
            ["minecraft:nether_quartz_ore"] = true,
            ["minecraft:ancient_debris"] = true,
            ["minecraft:coal"] = true,
            ["minecraft:raw_copper"] = true,
            ["minecraft:raw_iron"] = true,
            ["minecraft:redstone"] = true,
            ["minecraft:raw_gold"] = true,
            ["minecraft:lapis_lazuli"] = true,
            ["minecraft:diamond"] = true,
            ["minecraft:emerald"] = true,
            ["minecraft:gold_nugget"] = true,
            ["minecraft:nether_quartz"] = true,
        })
        settings.save(filter_path)
    end
    ore_whitelist = settings.get("block_whitelist")
end

--TODO function that loads all settings at once (but does not allow for saving afterward)

--main program
local function main()
    loadOreFilter()
    settings.clear()
    settings.load(settings_path)
    termlib.options = {
        {name="Miner by FireMatrix", type="label", unselectable=true},
        {name="", type="label", unselectable=true},
        {name="boundaries", type="menu", value={
            {name="Miner by FireMatrix", type="label", unselectable=true},
            {name="", type="label", unselectable=true},
            {name="x", type="var", value={type="int", value=settings.get("x", 5), min=0, desc="How far the Miner should go forward"}},
            {name="y positive", type="var", value={type="int", value=settings.get("yp", 5), min=0, desc="How far the Miner should go up"}},
            {name="y negative", type="var", value={type="int", value=settings.get("yn", 5), min=0, desc="How far the Miner should go down"}},
            {name="z positive", type="var", value={type="int", value=settings.get("zp", 5), min=0, desc="How far the Miner should go left"}},
            {name="z negative", type="var", value={type="int", value=settings.get("zn", 5), min=0, desc="How far the Miner should go right"}}
        }},
        {name="veinmine/excavate", type="var", value={type="bool", value=settings.get("veinmine", true), desc="Whether to excavate whole veins"}},
        {name="veinmine breaks bounds", type="var", value={type="bool", value=settings.get("boundbreak", true), desc="Whether veinmine can ignore boundaries"}},
        {name="delete items", type="var", value={type="bool", value=settings.get("deletion", false), desc="Whether to delete items not in the filter"}},
        {name="fast mode", type="var", value={type="bool", value=settings.get("fast", false), desc="Makes the turtle faster, but might miss veins that are only 1*1*X"}}, --TODO figure out speed diff
    }
    termlib.exitName = "start program"
    termlib:startTerminal()

    --sets global vars according to selected settings
    bound_x = termlib.options[3].value[3].value.value
    bound_yp = termlib.options[3].value[4].value.value
    bound_yn = termlib.options[3].value[5].value.value
    bound_zp = termlib.options[3].value[6].value.value
    bound_zn = termlib.options[3].value[7].value.value
    DO_VEINMINE = termlib.options[4].value.value
    MINING_IGNORE_BOUNDARIES = termlib.options[5].value.value
    DELETE_UNWANTED_ITEMS = termlib.options[6].value.value
    if termlib.options[7].value.value then
        SHAFT_OFFSET_HORIZONTAL = 8
        SHAFT_OFFSET_ON_NEXT_Y = 3
    end

    settings.set("x", bound_x)
    settings.set("yp", bound_yp)
    settings.set("yn", bound_yn)
    settings.set("zp", bound_zp)
    settings.set("zn", bound_zn)
    settings.set("veinmine", DO_VEINMINE)
    settings.set("boundbreak", MINING_IGNORE_BOUNDARIES)
    settings.set("deletion", DELETE_UNWANTED_ITEMS)
    settings.set("fast", termlib.options[7].value.value)
    settings.save(settings_path)
    settings.clear()
    turtle.select(core.FUEL_SLOT)
    mine()
    core:orientTowards(1,0)
end

main();