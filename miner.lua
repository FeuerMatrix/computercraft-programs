-- CC Turtle Mining Program by FireMatrix

local LOG_DATA = true
--Checks for easier ways back than just reversing every movement. Makes the turtle more fuel efficient.
local RETURN_PATH_STRAIGHTENING = true
--How many last movement positions away the turtle will consider when finding a better path.
local RETURN_PATH_STRAIGHTENING_MAX_CHECKING_DISTANCE = 20
local VEINMINE_IGNORE_BOUNDARIES = true
-- if true, the turtle gets rid of items not in the list of blocks to mine
local DELETE_UNWANTED_ITEMS = false

local x, y, z = 0,0,0
local xdir, zdir = 1,0

--boundaries of the area to mine
local bound_x, bound_yp, bound_yn, bound_zp, bound_zn = 4, 2, 2, 4, 4

--this is only here so that lua syntax check ignores computer craft specific globals --TODO delete on release
turtle = turtle

--prints current coordinates and face direction in the console
local function logData()
    if not LOG_DATA then
        return
    end
    print(x .. " | " .. y .. " | " .. z .. " || " .. xdir .. " | " .. zdir)
end

--moves the turtle forward
local function forward(length)
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

--TODO
local function check()
    
end

--TODO
local function checkUp()
    
end

--TODO
local function checkDown()
    
end

--moves <length> blocks forward, while checking all open faces for ores
local function mk_corridor_optimine(length)
    for i = 1, length, 1 do
        forward()
        checkUp()
        checkDown()
        left()
        check()
        turnAround()
        check()
        left()
    end
end

--moves the turtle to the position in the yz plane
local function mv_yz(ypos, zpos)
    --TODO
end

--starts the main mining program
local function mine()
    for y_current = -bound_yn, bound_yp, 1 do
        local zDisplacement = (2 * y_current) % 5
        local z_bound_lower_current_y = (math.floor(bound_zn / 5) + 1) * 5 - zDisplacement
        z_bound_lower_current_y = z_bound_lower_current_y > bound_zn and z_bound_lower_current_y - 5 or z_bound_lower_current_y
        
        for z_current = -z_bound_lower_current_y, bound_zp, 5 do
            mv_yz(y_current, z_current)
            --TODO extend a shaft in x direction
        end
    end
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

--makes the turtle return to its starting position, facing backwards
local function returnToStart()
    if not (x == 0) then
        orientTowards(x < 0 and 1 or -1, 0)
        local temp = math.abs(x)
        for i = 1, temp, 1 do
            forward()
        end
    end

    if not (z == 0) then
        orientTowards(0, z < 0 and 1 or -1)
        local temp = math.abs(z)
        for i = 1, temp, 1 do
            forward()
        end
    end

    if y == 0 then
        return
    end
    local temp = math.abs(y)
    if y > 0 then
        for i = 1, temp, 1 do
            down()
        end
    else
        for i = 1, temp, 1 do
            up()
        end
    end
    orientTowards(-1,0)
end

--main program
local function main()
    mine()
    returnToStart()
end

main();