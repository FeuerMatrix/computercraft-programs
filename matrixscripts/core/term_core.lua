--terminal library by FeuerMatrix
local M = {}

--[[
    Terminal Composition:<br>
    U=up, L=left, R=right, D=down, M=main, B=bottom<br><br>
    UUUUUUUUUUU<br>
    LMMMMMMMMMR<br>
    LMMMMMMMMMR<br>
    LMMMMMMMMMR<br>
    LBBBBBBBBBR<br>
    DDDDDDDDDDD
]]
M.term_xmax, M.term_ymax = term.getSize()
M.border_left = window.create(term.current(), 1, 2, 1, M.term_ymax-1)
M.border_right = window.create(term.current(), M.term_xmax, 2, 1, M.term_ymax-1)
M.border_up = window.create(term.current(), 1, 1, M.term_xmax, 1)
M.border_down = window.create(term.current(), 1, M.term_ymax, M.term_xmax, 1)
M.mainArea = window.create(term.current(), 3, 2, M.term_xmax-4, M.term_ymax-2)
M.bottomArea = window.create(term.current(), 3, M.term_ymax-1, M.term_xmax-4, 1)

--[[
    LABEL: text, not selectable
    MENU: Opens a submenu
    EXIT: closes submenu
]]
M.options = {}
M.exitName = "exit terminal"
M.numkeys = {
    zero=0,
    one=1,
    two=2,
    three=3,
    four=4,
    five=5,
    six=6,
    seven=7,
    eight=8,
    nine=9
}

function M:drawTerminal(text, auxText, selected_line)
    term.clear()
    self.mainArea.clear()
    self.bottomArea.clear()
    self.border_up.setCursorPos(1,1)
    self.border_down.setCursorPos(1,1)
    self.border_up.write("/")
    self.border_down.write("\\")
    for i = 1, self.term_xmax-2, 1 do
        self.border_up.write("^")
        self.border_down.write("_")
    end
    self.border_up.write("\\")
    self.border_down.write("/")
    for i = 1, self.term_ymax-2, 1 do
        self.border_left.setCursorPos(1,i)
        self.border_left.write("|")
        self.border_right.setCursorPos(1,i)
        self.border_right.write("|")
    end

    for index, value in ipairs(text) do
        self.mainArea.setCursorPos(1,index)
        if selected_line == index then
            self.mainArea.setTextColor(colors.white)
        else
            self.mainArea.setTextColor(colors.lime)
        end
        self.mainArea.write(value)
    end
    self.bottomArea.setCursorPos(1,1)
    self.bottomArea.write(auxText)
end

--option: name, valueType, default
function M:displayOptions(options, auxText, selected_line)
    local text = {}
    for i, current_option in ipairs(options) do
        text[i] = current_option["name"] .. (options[i]["type"] == "var" and " | " .. tostring(options[i]["value"]["value"]) or "")
    end

    self:drawTerminal(text, auxText, selected_line)
end

function M:getFirstSelectableIndex(options)
    for i = 1, #options, 1 do
        if options[i]["type"] ~= "label" then
            return i
        end
    end
    return nil
end

function M:driveVarChange(varArgs)
    local exited = false
    local argc = 1
        local options = {{name=varArgs["name"], type="var", value={value=varArgs["value"]["value"]}}}
        if varArgs["value"]["type"] then
            argc = argc + 1
            options[argc] = {name="(type: "..varArgs["value"]["type"]..")", type="label"}
        end
        if varArgs["value"]["desc"] then
            argc = argc + 1
            options[argc] = {name=varArgs["value"]["desc"], type="label"}
        end

    while not exited do
        self:displayOptions(options, "   Enter to Save, Delete to Exit", 1)
        local _, key = os.pullEvent("key")
        key = keys.getName(key);
        (({
            enter = function ()
                exited = true
                varArgs["value"]["value"] = options[1]["value"]["value"]
            end,
            delete = function ()
                exited = true
            end
        })[key] or function ()
            if varArgs["value"]["type"] == "bool" then
                options[1]["value"]["value"] = not options[1]["value"]["value"]
                return
            end
            
            if self.numkeys[key] then
                options[1]["value"]["value"] = options[1]["value"]["value"] * 10 + self.numkeys[key]
                return
            end
            if key == "backspace" then
                options[1]["value"]["value"] = math.floor(options[1]["value"]["value"]/10)
            end
        end)()
    end
end

function M:driveMenu(options)
    local exited = false
    local selected_line = self:getFirstSelectableIndex(options)
    while not exited do
        self:displayOptions(options, "Arrow Keys to Move, Enter to Select", selected_line)
        --look for key presses
        local _, key = os.pullEvent("key")
        key = keys.getName(key);

        (({
            enter = function ()
                (({
                    exit = function ()
                        exited = true
                    end,
                    menu = function ()
                        local nextOptions = options[selected_line]["value"]
                        if nextOptions[#nextOptions]["type"] ~= "exit" then
                            nextOptions[#nextOptions+1] = {name="back", type="exit"}
                        end
                        self:driveMenu(nextOptions)
                    end,
                    var = function ()
                        self:driveVarChange(options[selected_line])
                    end
                })[options[selected_line]["type"]] or function () end)()
            end,
            down = function ()
                for i = selected_line+1, #options, 1 do
                    if options[i]["type"] ~= "label" then
                        selected_line = i
                        return
                    end
                end
            end,
            up = function ()
                for i = selected_line-1, 1, -1 do
                    if options[i]["type"] ~= "label" then
                        selected_line = i
                        return
                    end
                end
            end
        })[key] or function() end)()
    end
end

--the set that options points to will be permutated with changed variable values
function M:startTerminal()
    local options = self.options
    options[#options+1] = {name=self.exitName, type="exit"}

    self:driveMenu(options)
end
return M