--terminal library by FeuerMatrix
local M = {}

M.term_xmax, M.term_ymax = term.getSize()
M.border_left = window.create(term.current(), 1, 2, 1, M.term_ymax-1)
M.border_right = window.create(term.current(), M.term_xmax, 2, 1, M.term_ymax-1)
M.border_up = window.create(term.current(), 1, 1, M.term_xmax, 1)
M.border_down = window.create(term.current(), 1, M.term_ymax, M.term_xmax, 1)
M.mainArea = window.create(term.current(), 3, 2, M.term_xmax-2, M.term_ymax-1)
M.mainAreaText = {}

function M:drawTerminal()
    term.clear()
    self.border_up.write("/")
    self.border_down.write("\\")
    for i = 1, self.term_xmax-2, 1 do
        self.border_up.write("^")
        self.border_down.write("_")
    end
    self.border_up.write("\\")
    self.border_down.write("/")
    for i = 1, self.term_ymax-2, 1 do
        self.border_left.setCursorPos(1, i)
        self.border_left.write("|")
        self.border_right.setCursorPos(1, i)
        self.border_right.write("|")
    end

    for index, value in ipairs(self.mainAreaText) do
        self.mainArea.setCursorPos(1,index)
        self.mainArea.write(value)
    end
end

function M:displayOptions()
    

    self:drawTerminal()
end
return M