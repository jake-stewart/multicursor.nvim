-------------------------------------------
-- THIS FILE WAS GENERATED AUTOMATICALLY --
-------------------------------------------
_G.require("tsnvimlib_bundle").__MapSource(debug.getinfo(1).short_src, "multicursor-nvim/typescript/index.ts", {13,2,369,370,371,372,373,373,373,373,377,377,377,373,373,373,381,382,383,384,385,386,386,389,390,391,391,391,394,395,396,397,398,398,401,401,401,405,406,407,407,407,407,412,413,414,416,417,419,420,420,423,424,425,425,428,429,430,430,433,434,435,435,435,435,435,1,2,3,27,27,32,33,34,35,32,38,39,40,41,42,43,43,43,43,43,43,43,43,52,53,54,55,55,55,64,65,66,67,67,67,76,38,79,80,81,83,84,84,84,84,85,85,85,85,85,88,89,89,91,93,94,95,96,96,99,101,101,102,102,103,104,105,108,112,112,114,114,114,114,114,114,112,112,112,112,112,112,112,112,112,112,112,112,112,112,120,102,102,102,123,123,124,124,125,126,127,129,129,129,129,129,129,129,129,129,129,129,129,129,129,137,124,124,124,140,141,142,143,143,144,144,145,146,147,148,148,148,148,148,148,148,153,153,144,144,144,144,158,159,160,161,161,161,161,161,161,161,161,163,164,164,164,164,164,164,164,164,167,167,167,167,167,167,167,177,79,180,181,182,183,180,186,187,187,186,190,191,191,191,191,191,191,191,198,199,200,200,200,200,201,202,202,202,202,190,208,209,210,211,211,213,208,216,217,218,218,220,216,223,224,225,225,225,225,223,228,229,230,231,232,233,233,236,237,238,238,238,238,238,243,244,244,247,247,247,250,228,253,254,255,256,253,262,263,262,266,267,267,267,271,275,276,278,278,278,278,278,278,278,282,283,284,285,285,285,285,285,285,285,285,293,294,294,294,294,294,294,294,294,303,304,305,305,305,309,310,311,317,322,323,324,324,327,327,327,327,330,336,337,338,338,340,341,341,344,346,348,349,266,352,353,354,355,356,357,358,359,359,359,361,361,364,364,352,441,441,449,442,443,444,445,446,450,452,453,452,456,456,456,456,456,457,457,457,457,457,458,458,458,458,458,459,459,459,459,459,460,460,460,460,460,462,462,462,462,463,463,463,463,463,449,466,467,468,469,469,466,473,474,475,473,478,479,479,479,482,483,478,486,487,488,489,490,492,493,494,494,497,498,498,500,501,501,486,505,506,505,509,510,511,511,509,515,516,516,516,519,520,521,522,523,524,524,524,528,529,530,530,533,534,535,535,535,535,535,535,535,536,536,536,515,541,542,542,542,545,546,547,548,549,550,551,541,555,556,558,559,563,564,565,566,568,568,568,568,568,568,568,563,574,575,574,578,579,578,582,583,582,586,587,586,586})
local ____lualib = require("lualib_bundle")
local __TS__Class = ____lualib.__TS__Class
local __TS__ObjectAssign = ____lualib.__TS__ObjectAssign
local __TS__StringAccess = ____lualib.__TS__StringAccess
local __TS__ArrayFind = ____lualib.__TS__ArrayFind
local __TS__ArrayAt = ____lualib.__TS__ArrayAt
local __TS__ArrayFilter = ____lualib.__TS__ArrayFilter
local __TS__ArrayMap = ____lualib.__TS__ArrayMap
local __TS__New = ____lualib.__TS__New
local ____exports = {}
local getCursor, setCursor, setMode, CTRL_V
function getCursor()
    local mode = vim.fn.mode()
    local pos = vim.fn.getcurpos()
    setMode("n")
    return {
        mode = mode,
        register = vim.fn.getreg(""),
        pos = pos,
        visual = {
            vim.fn.getpos("'<"),
            vim.fn.getpos("'>")
        }
    }
end
function setCursor(cursor)
    vim.fn.setreg("", cursor.register)
    vim.fn.setpos("'<", cursor.visual[1])
    vim.fn.setpos("'>", cursor.visual[2])
    vim.fn.setpos(".", cursor.pos)
    setMode(cursor.mode, cursor)
end
function setMode(newMode, cursor)
    local mode = vim.fn.mode()
    if mode == newMode then
        return
    end
    if cursor then
        if newMode == "v" or newMode == "V" or newMode == CTRL_V then
            if mode == "n" then
                if (cursor and cursor.pos[3]) == (cursor and cursor.visual[1][3]) and (cursor and cursor.pos[2]) == (cursor and cursor.visual[1][2]) then
                    vim.cmd.norm({args = {"gvo"}, bang = true})
                else
                    vim.cmd.norm({args = {"gv"}, bang = true})
                end
            end
        elseif newMode == "n" then
            if mode == "v" or mode == "V" or mode == CTRL_V then
                vim.cmd.norm({args = {"v"}, bang = true})
            end
        end
    else
        if newMode == "n" then
            if mode == "v" then
                vim.cmd.norm("v")
            elseif mode == "V" then
                vim.cmd.norm("V")
            elseif mode == CTRL_V then
                vim.cmd.norm(CTRL_V)
            end
        elseif newMode == "v" then
            if mode == "n" then
                vim.cmd.norm("v")
            end
        elseif newMode == "V" then
            if mode == "n" then
                vim.cmd.norm("V")
            end
        elseif newMode == CTRL_V then
            if mode == "n" then
                vim.cmd.norm(CTRL_V)
            end
        end
    end
end
local ESC = vim.api.nvim_replace_termcodes("<esc>", true, true, true)
CTRL_V = vim.api.nvim_replace_termcodes("<c-v>", true, true, true)
local NOT_STRICT = {strict = false}
local CursorManager = __TS__Class()
CursorManager.name = "CursorManager"
function CursorManager.prototype.____constructor(self, nsid)
    self.cursors = {}
    self.undoItems = {}
    self.nsid = nsid
end
function CursorManager.prototype.updateCursorPos(self, cursor, cursorId, visualStartId, visualEndId)
    local newCursor = __TS__ObjectAssign({}, cursor)
    newCursor.visual = {unpack(newCursor.visual)}
    local cursorRow, cursorCol = unpack(vim.api.nvim_buf_get_extmark_by_id(0, self.nsid, cursorId, {}))
    if cursorRow and cursorCol then
        newCursor.pos = {
            cursor.pos[1],
            cursorRow + 1,
            cursorCol + 1,
            cursor.pos[4],
            math.max(cursor.pos[5], cursorCol + 1)
        }
    end
    if visualStartId then
        local visualStartRow, visualStartCol = unpack(vim.api.nvim_buf_get_extmark_by_id(0, self.nsid, visualStartId, {}))
        if visualStartRow and visualStartCol then
            newCursor.visual[1] = {cursor.visual[1][1], visualStartRow + 1, visualStartCol + 1, cursor.visual[1][4]}
        end
    end
    if visualEndId then
        local visualEndRow, visualEndCol = unpack(vim.api.nvim_buf_get_extmark_by_id(0, self.nsid, visualEndId, {}))
        if visualEndRow and visualEndCol then
            newCursor.visual[2] = {cursor.visual[2][1], visualEndRow + 1, visualEndCol + 1, cursor.visual[2][4]}
        end
    end
    return newCursor
end
function CursorManager.prototype.drawCursor(self, cursor)
    local start
    local ____end
    if cursor.mode == "v" or cursor.mode == "V" or cursor.mode == CTRL_V then
        start = math.max(
            math.min(cursor.visual[1][2], cursor.pos[2]) - 1,
            0
        )
        ____end = math.max(
            math.max(cursor.visual[2][2], cursor.pos[2]) - 1,
            start
        )
    else
        start = cursor.pos[2] - 1
        ____end = cursor.pos[2] - 1
    end
    local lines = vim.api.nvim_buf_get_lines(0, start, ____end + 1, true)
    local char
    local charLine = lines[cursor.pos[2] - start]
    if charLine then
        char = __TS__StringAccess(charLine, cursor.pos[3] - 1)
    end
    local visualIds = {}
    if cursor.mode == "v" then
        do
            local i = cursor.visual[1][2]
            while i <= cursor.visual[2][2] do
                local row = i - 1
                local line = lines[row - start + 1]
                local col = i == cursor.visual[1][2] and cursor.visual[1][3] - 1 or 0
                local endCol = i == cursor.visual[2][2] and cursor.visual[2][3] - 1 or (line and #line or 0)
                local ____vim_api_nvim_buf_set_extmark_2 = vim.api.nvim_buf_set_extmark
                local ____self_nsid_1 = self.nsid
                local ____temp_0
                if i == cursor.visual[2][2] then
                    ____temp_0 = nil
                else
                    ____temp_0 = {{" ", "MultiCursorVisual"}}
                end
                local id = ____vim_api_nvim_buf_set_extmark_2(
                    0,
                    ____self_nsid_1,
                    row,
                    col,
                    {
                        strict = false,
                        virt_text = ____temp_0,
                        end_col = endCol + 1,
                        virt_text_pos = "inline",
                        virt_text_win_col = line and #line or 0,
                        hl_group = "MultiCursorVisual"
                    }
                )
                visualIds[#visualIds + 1] = id
                i = i + 1
            end
        end
    elseif cursor.mode == "V" then
        do
            local i = cursor.visual[1][2]
            while i <= cursor.visual[2][2] do
                local row = i - 1
                local line = lines[row - start + 1]
                local endCol = line and #line or 0
                local id = vim.api.nvim_buf_set_extmark(
                    0,
                    self.nsid,
                    row,
                    0,
                    {
                        strict = false,
                        virt_text = {{" ", "MultiCursorVisual"}},
                        end_col = endCol + 1,
                        virt_text_pos = "inline",
                        virt_text_win_col = line and #line or 0,
                        hl_group = "MultiCursorVisual"
                    }
                )
                visualIds[#visualIds + 1] = id
                i = i + 1
            end
        end
    elseif cursor.mode == CTRL_V then
        local range = {cursor.visual[1][3] - 1, cursor.visual[2][3] - 1}
        local startCol = math.min(range[1], range[2])
        local endCol = math.max(range[1], range[2])
        do
            local i = cursor.visual[1][2]
            while i <= cursor.visual[2][2] do
                local row = i - 1
                local line = lines[row - start + 1]
                if line and #line >= startCol then
                    local id = vim.api.nvim_buf_set_extmark(
                        0,
                        self.nsid,
                        row,
                        startCol,
                        {strict = false, end_col = endCol + 1, hl_group = "MultiCursorVisual"}
                    )
                    visualIds[#visualIds + 1] = id
                end
                i = i + 1
            end
        end
    end
    local visualStartId
    local visualEndId
    if cursor.visual[1][2] > 0 and cursor.visual[1][3] > 0 then
        visualStartId = vim.api.nvim_buf_set_extmark(
            0,
            self.nsid,
            cursor.visual[1][2] - 1,
            cursor.visual[1][3] - 1,
            NOT_STRICT
        )
    end
    if cursor.visual[2][2] > 0 and cursor.visual[2][3] > 0 then
        visualEndId = vim.api.nvim_buf_set_extmark(
            0,
            self.nsid,
            cursor.visual[2][2] - 1,
            cursor.visual[2][3] - 1,
            NOT_STRICT
        )
    end
    local cursorId = vim.api.nvim_buf_set_extmark(
        0,
        self.nsid,
        cursor.pos[2] - 1,
        cursor.pos[3] - 1,
        {strict = false, virt_text_pos = "overlay", virt_text = {{char or " ", "MultiCursorCursor"}}}
    )
    return __TS__ObjectAssign({}, cursor, {cursorId = cursorId, visualIds = visualIds, visualStartId = visualStartId, visualEndId = visualEndId})
end
function CursorManager.prototype.clear(self)
    vim.api.nvim_buf_clear_namespace(0, self.nsid, 0, -1)
    self.cursors = {}
    self.undoItems = {}
end
function CursorManager.prototype.addCursor(self, cursor)
    local ____self_cursors_3 = self.cursors
    ____self_cursors_3[#____self_cursors_3 + 1] = self:drawCursor(cursor)
end
function CursorManager.prototype.getCursorAtPosition(self, row, col)
    local extmarks = vim.api.nvim_buf_get_extmarks(
        0,
        self.nsid,
        {row - 1, col - 1},
        {row, col},
        {}
    )
    for ____, extmark in ipairs(extmarks) do
        if extmark[2] == row - 1 and extmark[3] == col - 1 then
            local cursor = __TS__ArrayFind(
                self.cursors,
                function(____, c) return c.cursorId == extmark[1] end
            )
            if cursor then
                return cursor
            end
        end
    end
end
function CursorManager.prototype.popCursor(self)
    local cursor = __TS__ArrayAt(self.cursors, -1)
    if cursor then
        self:deleteCursor(cursor)
    end
    return cursor
end
function CursorManager.prototype.eraseCursor(self, cursor)
    for ____, id in ipairs(cursor.visualIds) do
        vim.api.nvim_buf_del_extmark(0, self.nsid, id)
    end
    vim.api.nvim_buf_del_extmark(0, self.nsid, cursor.cursorId)
end
function CursorManager.prototype.deleteCursor(self, cursor)
    self:eraseCursor(cursor)
    self.cursors = __TS__ArrayFilter(
        self.cursors,
        function(____, c) return c ~= cursor end
    )
end
function CursorManager.prototype.mergeCursors(self, mainCursor)
    local newCursors = {}
    for ____, cursor in ipairs(self.cursors) do
        local exists = false
        if cursor.pos[2] == mainCursor.pos[2] and cursor.pos[3] == mainCursor.pos[3] then
            exists = true
        else
            for ____, c in ipairs(newCursors) do
                if cursor.pos[2] == c.pos[2] and cursor.pos[3] == c.pos[3] then
                    exists = true
                    break
                end
            end
        end
        if exists then
            self:eraseCursor(cursor)
        else
            newCursors[#newCursors + 1] = cursor
        end
    end
    self.cursors = newCursors
end
function CursorManager.prototype.update(self, mainCursor)
    local undoTree = vim.fn.undotree()
    self:mergeCursors(mainCursor)
    self.undoItems[undoTree.seq_cur] = {cursors = self.cursors, cursor = mainCursor}
end
function CursorManager.prototype.hasCursors(self)
    return #self.cursors > 0
end
function CursorManager.prototype.performMacro(self, macro)
    if not self:hasCursors() or #macro == 0 then
        return
    end
    local origCursor = getCursor()
    local origClipboard = vim.o.clipboard
    vim.o.clipboard = ""
    local cursorId = vim.api.nvim_buf_set_extmark(
        0,
        self.nsid,
        origCursor.pos[2] - 1,
        origCursor.pos[3] - 1,
        {strict = false}
    )
    local visualStartId
    local visualEndId
    if origCursor.visual[1][2] > 0 and origCursor.visual[1][3] > 0 then
        visualStartId = vim.api.nvim_buf_set_extmark(
            0,
            self.nsid,
            origCursor.visual[1][2] - 1,
            origCursor.visual[1][3] - 1,
            NOT_STRICT
        )
    end
    if origCursor.visual[2][2] > 0 and origCursor.visual[2][3] > 0 then
        visualEndId = vim.api.nvim_buf_set_extmark(
            0,
            self.nsid,
            origCursor.visual[2][2] - 1,
            origCursor.visual[2][3] - 1,
            NOT_STRICT
        )
    end
    for ____, cursor in ipairs(self.cursors) do
        for ____, id in ipairs(cursor.visualIds) do
            vim.api.nvim_buf_del_extmark(0, self.nsid, id)
        end
    end
    local newCursors = {}
    for ____, cursor in ipairs(self.cursors) do
        cursor = self:updateCursorPos(cursor, cursor.cursorId, cursor.visualStartId, cursor.visualEndId)
        vim.api.nvim_buf_del_extmark(0, self.nsid, cursor.cursorId)
        setCursor(cursor)
        vim.cmd.norm({args = {macro}, bang = false})
        newCursors[#newCursors + 1] = self:drawCursor(getCursor())
    end
    newCursors = __TS__ArrayMap(
        newCursors,
        function(____, c) return self:updateCursorPos(c, c.cursorId, c.visualStartId, c.visualEndId) end
    )
    origCursor = self:updateCursorPos(origCursor, cursorId, visualStartId, visualEndId)
    vim.api.nvim_buf_del_extmark(0, self.nsid, cursorId)
    if visualStartId then
        vim.api.nvim_buf_del_extmark(0, self.nsid, visualStartId)
    end
    if visualEndId then
        vim.api.nvim_buf_del_extmark(0, self.nsid, visualEndId)
    end
    self.cursors = newCursors
    self:update(origCursor)
    vim.o.clipboard = origClipboard
    setCursor(origCursor)
end
function CursorManager.prototype.undo(self)
    local undoTree = vim.fn.undotree()
    local undoItem = self.undoItems[undoTree.seq_cur]
    if undoItem then
        self.cursors = {}
        vim.api.nvim_buf_clear_namespace(0, self.nsid, 0, -1)
        for ____, c in ipairs(undoItem.cursors) do
            local ____self_cursors_4 = self.cursors
            ____self_cursors_4[#____self_cursors_4 + 1] = self:drawCursor(c)
        end
        setCursor(undoItem.cursor)
    else
        self:clear()
    end
end
local InputManager = __TS__Class()
InputManager.name = "InputManager"
function InputManager.prototype.____constructor(self, nsid, cursorManager)
    self.inCmdMode = false
    self.inInsertMode = false
    self.applying = false
    self.expanding = false
    self.macro = ""
    self.cursorManager = cursorManager
    local function au(event, pattern, callback)
        vim.api.nvim_create_autocmd(event, {pattern = pattern, callback = callback})
    end
    au(
        "ModeChanged",
        "*:c",
        function() return self:onCommandLineMode(true) end
    )
    au(
        "ModeChanged",
        "c:*",
        function() return self:onCommandLineMode(false) end
    )
    au(
        "ModeChanged",
        "*:[iR]",
        function() return self:onInsertMode(true) end
    )
    au(
        "ModeChanged",
        "[iR]:*",
        function() return self:onInsertMode(false) end
    )
    au(
        "SafeState",
        "*",
        function() return self:onSafeState() end
    )
    vim.on_key(
        function(key, typed) return self:onKey(key, typed) end,
        nsid
    )
    vim.keymap.set(
        "n",
        "\\",
        function() return self:onPressPrefix() end
    )
end
function InputManager.prototype.onInsertMode(self, enabled)
    self.inInsertMode = enabled
    if not enabled then
        self.macro = self.macro .. vim.fn.getreg(".") .. ESC
    end
end
function InputManager.prototype.onCommandLineMode(self, enabled)
    self.inCmdMode = enabled
    self.macro = ""
end
function InputManager.prototype.onPressPrefix(self)
    if self:isDisabled() then
        return
    end
    self.cursorManager:addCursor(getCursor())
    self.expanding = true
end
function InputManager.prototype.onSafeState(self)
    if not self:isDisabled() then
        self.applying = true
        if self.macro == "u" then
            self.cursorManager:undo()
        elseif self.expanding then
            if self.macro ~= "\\" then
                self.expanding = false
            end
        elseif #self.macro > 0 then
            self.cursorManager:performMacro(self.macro)
        end
        self.macro = ""
        self.applying = false
    end
end
function InputManager.prototype.isDisabled(self)
    return self.inCmdMode or self.applying or self.inInsertMode
end
function InputManager.prototype.onKey(self, key, typed)
    if not self:isDisabled() then
        self.macro = self.macro .. typed
    end
end
function InputManager.prototype.addCursorAtMouse(self)
    if self:isDisabled() then
        return
    end
    local mousePos = vim.fn.getmousepos()
    if mousePos.line == vim.fn.line(".") and mousePos.column == vim.fn.col(".") then
        local cursor = self.cursorManager:popCursor()
        if cursor then
            setCursor(cursor)
            self.cursorManager:update(cursor)
        end
    else
        local existingCursor = self.cursorManager:getCursorAtPosition(mousePos.line, mousePos.column)
        if existingCursor then
            self.cursorManager:deleteCursor(existingCursor)
        else
            local cursor = getCursor()
            self.cursorManager:addCursor(cursor)
            vim.fn.setpos(".", {
                cursor.pos[1],
                mousePos.line,
                mousePos.column,
                0,
                mousePos.column
            })
            self.cursorManager:update(getCursor())
        end
    end
end
function InputManager.prototype.addCursorWithMotion(self, motion)
    if self:isDisabled() then
        return
    end
    self.applying = true
    self.macro = ""
    local origCursor = getCursor()
    vim.cmd.norm(motion)
    self.cursorManager:addCursor(origCursor)
    self.cursorManager:update(getCursor())
    self.applying = false
end
vim.cmd.hi("link", "MultiCursorCursor", "Cursor")
vim.cmd.hi("link", "MultiCursorVisual", "Visual")
local cursorManager
local inputManager
function ____exports.setup(opts)
    local nsid = vim.api.nvim_create_namespace("multicursor")
    cursorManager = __TS__New(CursorManager, nsid)
    inputManager = __TS__New(InputManager, nsid, cursorManager)
    vim.api.nvim_create_autocmd(
        {"WinLeave"},
        {
            pattern = "*",
            callback = function() return cursorManager:clear() end
        }
    )
end
function ____exports.hasCursors()
    return cursorManager:hasCursors()
end
function ____exports.clearCursors()
    cursorManager:clear()
end
function ____exports.addCursorWithMotion(motion)
    inputManager:addCursorWithMotion(motion)
end
function ____exports.addCursorWithMouse()
    inputManager:addCursorAtMouse()
end
return ____exports
