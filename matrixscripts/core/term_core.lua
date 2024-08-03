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

--[[
    @param selected_line_relative the index of the currently selected line, relative to the first displayed line. Therefore, this is the actual line index in the main area terminal window and not the selected option index.
]]
function M:drawTerminal(text, auxText, selected_line_relative)
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
    self.border_down.setCursorPos(1,1)--
    self.border_down.write(#text)
    for i = 1, #text, 1 do
        self.mainArea.setCursorPos(1,i)
        if selected_line_relative == i then
            self.mainArea.setTextColor(colors.white)
        else
            self.mainArea.setTextColor(colors.lime)
        end
        self.mainArea.write(text[i])
    end
    self.bottomArea.setCursorPos(1,1)
    self.bottomArea.write(auxText)
end

--option: name, valueType, default
function M:displayOptions(options, auxText, selected_line, firstDisplayedLine)
    local text = {}
    for i = firstDisplayedLine, firstDisplayedLine+9, 1 do
        if not options[i] then
            break
        end
        text[i-firstDisplayedLine+1] = options[i]["name"] .. (options[i]["type"] == "var" and " | " .. tostring(options[i]["value"]["value"]) or "")
    end

    self:drawTerminal(text, auxText, selected_line-firstDisplayedLine+1)
end

function M:getFirstSelectableIndex(options)
    for i = 1, #options, 1 do
        if not options[i]["unselectable"] then
            return i
        end
    end
    return nil
end

function M:driveVarChange(varArgs)
    local exited = false
    local argc = 1
        local options = {{name=varArgs["name"], type="var", value={value=varArgs["value"]["value"], min=varArgs["value"]["min"], max=varArgs["value"]["max"], type=varArgs["value"]["type"]}}}
        if varArgs["value"]["type"] then
            argc = argc + 1
            options[argc] = {name="(type: "..varArgs["value"]["type"]..")", type="label"}
        end
        if varArgs["value"]["desc"] then
            argc = argc + 1
            options[argc] = {name=varArgs["value"]["desc"], type="label"}
        end

    while not exited do
        self:displayOptions(options, "   Enter to Save, Delete to Exit", 1, 1)
        local _, key = os.pullEvent("key")
        key = keys.getName(key);
        (({
            enter = function ()
                exited = true
                varArgs["value"]["value"] = options[1]["value"]["value"]
            end,
            delete = function ()
                exited = true
            end,
            left = function ()
                if options[1]["value"]["type"] == "bool" then
                    options[1]["value"]["value"] = not options[1]["value"]["value"]
                    return
                end
                options[1]["value"]["value"] = options[1]["value"]["value"]-1
            end,
            right = function ()
                if options[1]["value"]["type"] == "bool" then
                    options[1]["value"]["value"] = not options[1]["value"]["value"]
                    return
                end
                options[1]["value"]["value"] = options[1]["value"]["value"]+1
            end,
            up = function ()
                if options[1]["value"]["type"] == "bool" then
                    options[1]["value"]["value"] = not options[1]["value"]["value"]
                    return
                end
                options[1]["value"]["value"] = options[1]["value"]["value"] * -1
            end,
            down = function ()
                if options[1]["value"]["type"] == "bool" then
                    options[1]["value"]["value"] = not options[1]["value"]["value"]
                    return
                end
                options[1]["value"]["value"] = options[1]["value"]["value"] * -1
            end
        })[key] or function ()
            local currentVar = options[1]["value"]
            if varArgs["value"]["type"] == "bool" then
                currentVar["value"] = not currentVar["value"]
                return
            end
            
            if self.numkeys[key] then
                currentVar["value"] = currentVar["value"] * 10 + (currentVar["value"] < 0 and self.numkeys[key] * -1 or self.numkeys[key])
                return
            end
            if key == "backspace" then
                currentVar["value"] = math.modf(currentVar["value"]/10)
            end
        end)()
        
        local currentVar = options[1]["value"]
        if currentVar["max"] ~= nil and currentVar["max"] < currentVar["value"] then
            currentVar["value"] = currentVar["max"]
        elseif currentVar["min"] ~= nil and currentVar["min"] > currentVar["value"] then
            currentVar["value"] = currentVar["min"]
        end
    end
end

function M:driveMenu(options)
    local exited = false
    local firstDisplayedLine = 1
    local selected_line = self:getFirstSelectableIndex(options)
    while not exited do
        self:displayOptions(options, "Press I for more info", selected_line, firstDisplayedLine)
        self.border_up.setCursorPos(1,1)
        self.border_up.write(selected_line .. " " .. firstDisplayedLine .. " " .. tostring(not not options[selected_line]))
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
            i = function ()
                if not options[1]["isInfo"] then
                    self:driveMenu({
                        {name="TermLib by FireMatrix", type="label", unselectable=true, isInfo = true},
                        {name="- navigation -", type="label"},
                        {name="+ menu scrolls up and down to", type="label", unselectable=true},
                        {name="  reveal options!", type="label", unselectable=true},
                        {name="+ navigate: up/down arrow", type="label", unselectable=true},
                        {name="+ select option: enter", type="label", unselectable=true},
                        {name="- quick value change -", type="label"},
                        {name="+ left/right arrow over item:", type="label", unselectable=true},
                        {name="  toggle bools or inc/dec numbers", type="label", unselectable=true},
                        {name="- value menu -", type="label"},
                        {name="+ left/right arrow: toggle bools or", type="label", unselectable=true},
                        {name="  inc/dec numbers", type="label", unselectable=true},
                        {name="+ up/down arrow: toggle bools or", type="label", unselectable=true},
                        {name="  invert sign", type="label", unselectable=true},
                        {name="- -----", type="label"},
                        {name="+ number key: enter digit to the", type="label", unselectable=true},
                        {name="  right", type="label", unselectable=true},
                        {name="+ backspace: remove digit from", type="label", unselectable=true},
                        {name="  right", type="label", unselectable=true},
                        {name="- -----", type="label"},
                        {name="+ enter: save changes and return", type="label", unselectable=true},
                        {name="+ delete: return without saving", type="label", unselectable=true},
                        {name="back", type="exit"}
                    })
                end
            end,
            down = function ()
                for i = selected_line+1, #options, 1 do
                    if not options[i]["unselectable"] then
                        selected_line = i
                        if selected_line > firstDisplayedLine + 8 then
                            if selected_line ~= #options then
                                firstDisplayedLine = selected_line - 8
                                return
                            end
                            firstDisplayedLine = selected_line - 9
                        end
                        return
                    end
                end
                for i = 1, selected_line, 1 do
                    if not options[i]["unselectable"] then
                        selected_line = i
                        if selected_line <= firstDisplayedLine then
                            if selected_line ~= 1 then
                                firstDisplayedLine = selected_line - 1
                                return
                            end
                            firstDisplayedLine = selected_line
                        end
                        return
                    end
                end
            end,
            up = function ()
                for i = selected_line-1, 1, -1 do
                    if not options[i]["unselectable"] then
                        selected_line = i
                        if selected_line <= firstDisplayedLine then
                            if selected_line ~= 1 then
                                firstDisplayedLine = selected_line - 1
                                return
                            end
                            firstDisplayedLine = selected_line
                        end
                        return
                    end
                end
                for i = #options, selected_line, -1 do
                    if not options[i]["unselectable"] then
                        selected_line = i
                        if selected_line > firstDisplayedLine + 8 then
                            if selected_line ~= #options then
                                firstDisplayedLine = selected_line - 8
                                return
                            end
                            firstDisplayedLine = selected_line - 9
                        end
                        return
                    end
                end
            end,
            left = function ()
                if options[selected_line]["type"] == "var" then
                    local currentVar = options[selected_line]["value"]
                    if currentVar["type"] == "bool" then
                        currentVar["value"] = not currentVar["value"]
                        return
                    end
                    currentVar["value"] = currentVar["value"]-1
                    if currentVar["min"] ~= nil and currentVar["min"] > currentVar["value"] then
                        currentVar["value"] = currentVar["min"]
                    end
                end
            end,
            right = function ()
                if options[selected_line]["type"] == "var" then
                    local currentVar = options[selected_line]["value"]
                    if currentVar["type"] == "bool" then
                        currentVar["value"] = not currentVar["value"]
                        return
                    end
                    currentVar["value"] = currentVar["value"]+1
                    if currentVar["max"] ~= nil and currentVar["max"] < currentVar["value"] then
                        currentVar["value"] = currentVar["max"]
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