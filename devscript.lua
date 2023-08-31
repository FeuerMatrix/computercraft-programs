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

local function logData()
    if not LOG_DATA then
        return
    end
    print(x .. " | " .. y .. " | " .. z .. " || " .. xdir .. " | " .. zdir)
end

local function forward()
    while not turtle.forward() do
        turtle.attack()
        turtle.dig()
    end
    x = x + xdir
    z = z + zdir
    logData()
end

local function up()
    while not turtle.up() do
        turtle.attackUp()
        turtle.digUp()
    end
    y = y + 1
    logData()
end

local function down()
    while not turtle.down() do
        turtle.attackDown()
        turtle.digDown()
    end
    y = y - 1
    logData()
end

local function right()
    turtle.turnRight()
    local xtemp = xdir
    xdir = -zdir
    zdir = xtemp
    logData()
end

local function left()
    turtle.turnLeft()
    local xtemp = xdir
    xdir = zdir
    zdir = -xtemp
    logData()
end

local function turnAround()
    turtle.turnRight()
    turtle.turnRight()
    xdir = -xdir
    zdir = -zdir
end

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

local function check()
    
end

local function checkUp()
    
end

local function checkDown()
    
end

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

local function mine()
    mk_corridor_optimine(2)
end

local function returnToStart()
    if zdir == -1 then
        left()
    elseif not (xdir == -1) and (right() or not (xdir == -1))  then
        right()
    end
    for i = 1, x, 1 do
        
    end
end

local function main()
    
    returnToStart()
end

main();