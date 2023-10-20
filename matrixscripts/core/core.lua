--turtle programs core by FeuerMatrix
local M = {}

DEBUG_MODE = false

--[[
    the slot that fuel is held in<br>
    For good performance this should be 1
]]
M.FUEL_SLOT = 1
--[[
    the upper limit for fuel to carry at one time<br>
    This is not a hard limit, some actions may still go above this if they have a reason to do so. Putting this too high means that the turtle will swallow the entire load of mined coal.
]]
M.FUEL_CONSUMPTION_LIMIT = 20000

--[[
    do I really need to explain these<br>
    The coordinates of the turtle. These aren't actual minecraft coordinates: the coordinate system has the turtle starting point as (0,0,0) and the turtle starts facing positive x
]]
M.x, M.y, M.z = 0,0,0
--[[
    the direction the turtle is facing.<br>
    1 if facing the direction, -1 if facing opposite, 0 if orthogonal to the corresponding axis
]]
M.xdir, M.zdir = 1,0

--[[
    Significance of the movement that is currently executed. Determines how to react to problems like hitting bedrock, full inventory and low fuel.
    <ul>
    <li>0 <=> Low significance, e.g. following ore veines. Bedrock is just ignored and the movement is cancelled. Logistical problems immediately pause the action.</li>
    <li>1 <=> Normal significance, e.g. mining a branch. Logistical problems are treated like for low significance, but changes to the planned movement will be made when hitting bedrock.</li>
    <li>2 <=> Critical Movement. Logistical problems are ignored. Hitting bedrock results in the entire program yielding.</li>
    </ul>
]]
M.current_movement_significance = 1

--path to the root folder of this program bundle (only works if core is run from INSIDE this program bundle)
M.root_path = string.match(shell.getRunningProgram(), ".-matrixscripts")

--[[
    empty method<br>
    can be overridden by scripts using this library and is then used in other functions in this library
]]
function M:checkInventoryFull()
    --pre-definition of function so that it can be called while technically undefined
end

--[[
    Returns the 1-norm of the current coordinate vector (also known as Manhattan distance)<br>
    @return Manhattan distance of current coordinate to (0,0,0)
]]
function M:one_norm(in1, in2, in3)
    return math.abs(in1) + math.abs(in2) + math.abs(in3)
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
function M:rotate_right(old_xdir, old_zdir)
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
function M:rotate_left(old_xdir, old_zdir)
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
function M:rotate_around(old_xdir, old_zdir)
    return -old_xdir, -old_zdir
end

--[[
    Turns the turtle right.
]]
function M:right()
    turtle.turnRight()
    self.xdir, self.zdir = self:rotate_right(self.xdir, self.zdir)
    self:logData()
end

--[[
    Turns the turtle left.
]]
function M:left()
    turtle.turnLeft()
    self.xdir, self.zdir = self:rotate_left(self.xdir, self.zdir)
    self:logData()
end

--[[
    Turns the turtle around.
]]
function M:turnAround()
    turtle.turnRight()
    turtle.turnRight()
    self.xdir, self.zdir = self:rotate_around(self.xdir, self.zdir)
    self:logData()
end

--[[
    Turns the turtle so that it faces the given direction.<br>
    @param xOr where to face on the x-axis (valid are -1, 0, 1)<br>
    @param zOr where to face on the y-axis (valid are -1, 0, 1)
]]
function M:orientTowards(xOr, zOr)
    if self.xdir == xOr and self.zdir == zOr then
        return
    end
    if self.xdir == zOr and -self.zdir == xOr  then
        self:right()
        return
    end
    self:left()
    if not (self.xdir == xOr and self.zdir == zOr) then
        self:left()
    end
end

--prints current coordinates and face direction in the console
function M:logData()
    if not DEBUG_MODE then
        return
    end
    print(self.x .. " | " .. self.y .. " | " .. self.z .. " || " .. self.xdir .. " | " .. self.zdir)
end

--[[
    tries to refuel the turtle from the fuel slot<br>
    @return true, if the turtle was refueled; false otherwise
]]
function M:refuel()
    if not (turtle.getSelectedSlot() == self.FUEL_SLOT) then
        turtle.select(self.FUEL_SLOT)
    end
    if turtle.getItemCount() > 1 then
        if turtle.refuel(turtle.getItemCount() - 1) then
            return true
        end
    end
    if turtle.getItemSpace() == 0 and turtle.getItemCount() == 1 then --if the fuel item is not stackable, the turtle will not keep a single fuel item around (since that would just waste the slot)
        if turtle.refuel(1) then
            return true
        end
    end
    return false
end

--[[
    checks if the current fuel level is high enough to make it back even after one more movement<br>
    If not enough fuel is supplied, enters refueling.<br>
]]
function M:checkFuelStatus()
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" or self.current_movement_significance == 2 then
        return
    end
    if fuel > (1 + self:fuel_to_return()) then
        return
    end
    self:refuel()
end

--wrapper function for turtle.dig() that does necessary checks
function M:dig()
    self:checkInventoryFull()
    local _, error_msg = turtle.dig()
    if error_msg == "Cannot break unbreakable block" then
        if self.current_movement_significance ~= 2 then
            self:returnToStart()
            self:emptyAll()
        end
        error("Hit unbreakable block (like bedrock)")
    end
end

--wrapper function for turtle.digUp() that does necessary checks
function M:digUp()
    self:checkInventoryFull()
    local _, error_msg = turtle.digUp()
    if error_msg == "Cannot break unbreakable block" then
        if self.current_movement_significance ~= 2 then
            self:returnToStart()
            self:emptyAll()
        end
        error("Hit unbreakable block (like bedrock)")
    end
end

--wrapper function for turtle.digDown() that does necessary checks
function M:digDown()
    self:checkInventoryFull()
    local _, error_msg = turtle.digDown()
    if error_msg == "Cannot break unbreakable block" then
        if self.current_movement_significance ~= 2 then
            self:returnToStart()
            self:emptyAll()
        end
        error("Hit unbreakable block (like bedrock)")
    end
end

--[[
    Moves the turtle forward by the given length.<br>
    @param <b>length</b> The amount of blocks to move. Defaults to 1.
]]
function M:forward(length)
    self:checkFuelStatus()
    if not length then
        length = 1
    end

    for i = 1, length, 1 do
        while not turtle.forward() do
            turtle.attack()
            self:dig()
        end
        self.x = self.x + self.xdir
        self.z = self.z + self.zdir
        self:logData()
    end
end

--[[
    Moves the turtle upward by the given length.<br>
    @param <b>length</b> The amount of blocks to move. Defaults to 1.
]]
function M:up(length)
    self:checkFuelStatus()
    if not length then
        length = 1
    end

    for i = 1, length, 1 do
        while not turtle.up() do
            turtle.attackUp()
            self:digUp()
        end
        self.y = self.y + 1
        self:logData()
    end
end

--[[
    Moves the turtle down by the given length.<br>
    @param <b>length</b> The amount of blocks to move. Defaults to 1.
]]
function M:down(length)
    self:checkFuelStatus()
    if not length then
        length = 1
    end

    for i = 1, length, 1 do
        while not turtle.down() do
        turtle.attackDown()
        self:digDown()
    end
    self.y = self.y - 1
    self:logData()
    end
end

--[[
    empties the inventory of the turtle in a container in front of it<br>
    The fuel in the fuel slot is left alone.
]]
function M:empty()
    for i = 1, 16, 1 do
        if not (i == self.FUEL_SLOT) and not (turtle.getItemCount(i) == 0) then
            turtle.select(i)
            turtle.drop()
        end
    end
    turtle.select(self.FUEL_SLOT)
end

--empties the complete inventory into a container in front
function M:emptyAll()
    self:empty()
    if turtle.getItemCount(self.FUEL_SLOT) == 0 then
        return
    end
    turtle.select(self.FUEL_SLOT)
    turtle.drop()
end

--[[
    calculates how much fuel is required to return to starting position<br>
    @return the amount of fuel needed to return
]]
function M:fuel_to_return()
    return self:one_norm(self.x,self.y,self.z)
end

--[[
    moves the turtle by the given amount in x direction<br>
    @param x_translation the amount of blocks to move - negative numbers are accepted<br>
    @implNote might permuate the turtle rotation
]]
function M:mv_x(x_translation)
    if x_translation == 0 then
        return
    end

    self:orientTowards(x_translation > 0 and 1 or -1, 0)
    local temp = math.abs(x_translation)
    for i = 1, temp, 1 do
        self:forward()
    end
end

--[[
    moves the turtle by the given amount in y direction<br>
    @param y_translation the amount of blocks to move - negative numbers are accepted
]]
function M:mv_y(y_translation)
    if y_translation == 0 then
        return
    end

    local temp = math.abs(y_translation)
    if y_translation < 0 then
        for i = 1, temp, 1 do
            self:down()
        end
        return
    end

    for i = 1, temp, 1 do
        self:up()
    end
end

--[[
    moves the turtle by the given amount in z direction<br>
    @param z_translation the amount of blocks to move - negative numbers are accepted<br>
    @implNote might permuate the turtle rotation
]]
function M:mv_z(z_translation)
    if z_translation == 0 then
        return
    end

    self:orientTowards(0, z_translation > 0 and 1 or -1)
    local temp = math.abs(z_translation)
    for i = 1, temp, 1 do
        self:forward()
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
function M:mv_xyz(xpos, ypos, zpos)
    self:mv_x(xpos - self.x)
    self:mv_z(zpos - self.z)
    self:mv_y(ypos - self.y)
end

--makes the turtle return to its starting position, facing backwards
function M:returnToStart()
    self:mv_xyz(0,0,0)

    self:orientTowards(-1,0)
end

return M