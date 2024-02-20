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
--TODO doc
--[[
    LABEL: text, not selectable
    MENU: Opens a submenu
    EXIT: closes submenu
]]
M.options = {}
M.exitName = "exit terminal"
M.auxText = "Arrow Keys to Move, Enter to Select"
--TODO doc
M.selected_line = 0

function M:drawTerminal(text)
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
        if self.selected_line == index then
            self.mainArea.setTextColor(colors.white)
        else
            self.mainArea.setTextColor(colors.lime)
        end
        self.mainArea.write(value)
    end
    self.bottomArea.setCursorPos(1,1)
    self.bottomArea.write(self.auxText)
end

--option: name, valueType, default
function M:displayOptions(options)
    local text = {}
    for i, current_option in ipairs(options) do
        text[i] = current_option["name"]
    end

    self:drawTerminal(text)
end

function M:selectFirstEntry(options)
    for i = 1, #options, 1 do
        if options[i]["type"] ~= "label" then
            self.selected_line = i
            break
        end
    end
end

function M:driveMenu(options)
    local exited = false
    self:selectFirstEntry(options)
    while not exited do
        self:displayOptions(options)
        --look for key presses
        local _, key = os.pullEvent("key")
        key = keys.getName(key);

        ({
            enter = function ()
                ({
                    exit = function ()
                        exited = true
                    end,
                    menu = function ()
                        local nextOptions = options[self.selected_line]["value"]
                        if nextOptions[#nextOptions]["type"] ~= "exit" then
                            nextOptions[#nextOptions+1] = {name="back", type="exit"}
                        end
                        self:driveMenu(nextOptions)
                    end
                })[options[self.selected_line]["type"]]()
                self:selectFirstEntry(options)
            end,
            down = function ()
                for i = self.selected_line+1, #options, 1 do
                    if options[i]["type"] ~= "label" then
                        self.selected_line = i
                        return
                    end
                end
            end,
            up = function ()
                for i = self.selected_line-1, 1, -1 do
                    if options[i]["type"] ~= "label" then
                        self.selected_line = i
                        return
                    end
                end
            end,
            __index = function ()
                
            end
        })[key]()
    end
end

function M:startTerminal()
    local options = self.options
    options[#options+1] = {name=self.exitName, type="exit"}

    self:driveMenu(options)
end
return M