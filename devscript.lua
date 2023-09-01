-- CC Turtle Mining Program by FireMatrix

--whether the mine should be enterable by the player (aka be 2 blocks high)
local PLAYER_ENTERABLE = false
local LOG_DATA = true
--Checks for easier ways back than just reversing every movement. Makes the turtle more fuel efficient.
local RETURN_PATH_STRAIGHTENING = true
--How many last movement positions away the turtle will consider when finding a better path.
local RETURN_PATH_STRAIGHTENING_MAX_CHECKING_DISTANCE = 20

local x, y, z = 0,0,0
local xdir, zdir = 1,0

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

-- mines a corridor of the given <length>
local function mk_corridor_stripmine(length, upwards)
    if upwards and PLAYER_ENTERABLE then
        up()
    elseif PLAYER_ENTERABLE then
        down()
    end
    forward()
    if length > 1 then
        mk_corridor(length-1, not upwards)
    end
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

--starts the main mining program
local function mine()
    mk_corridor_optimine(2)
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
    forward(3)
    left()
    forward(2)
    left()
    forward(10)
    left()
    forward(6)
    right()
    down(1)
    returnToStart()
end

main();