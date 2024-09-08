local TERM_CODES = require("multicursor-nvim.term-codes")
local feedkeysManager = require("multicursor-nvim.feedkeys-manager")
local tbl = require("multicursor-nvim.tbl")

--- @class MultiCursorUndo
--- @field cursors Cursor[]
--- @field mainCursor Cursor

local visualSelectModes = {
    v = { visual = "v", select = "" },
    V = { visual = "V", select = "" },
    [TERM_CODES.CTRL_V] = { visual = TERM_CODES.CTRL_V, select = "" },
    s = { visual = "v", select = TERM_CODES.CTRL_G },
    S = { visual = "V", select = TERM_CODES.CTRL_G },
    [TERM_CODES.CTRL_S] = { visual = TERM_CODES.CTRL_V, select = TERM_CODES.CTRL_G },
}

local function feedkeys(macro, opts)
    local mode = (opts and opts.remap and "" or "n") .. "x"
    feedkeysManager.feedkeys(macro, mode, false)
end

--- @param newMode string
--- @param cursor? Cursor
local function setMode(newMode, cursor)
    local mode = vim.fn.mode()
    if mode == newMode then
        return ""
    end
    local result
    if cursor then
        local info = visualSelectModes[newMode]
        if info then
            if mode == "n" then
                result = cursor._v[2] .. "G"
                    .. cursor._v[3] .. "|"
                    .. info.visual
                    .. cursor._pos[2] .. "G"
                    .. cursor._pos[3] .. "|"
                    .. info.select
            end
        elseif newMode == "n" then
            result = TERM_CODES.ESC
        end
    else
        if newMode == "n" then
            result = TERM_CODES.ESC
        else
            local info = visualSelectModes[newMode]
            if info then
                result = info.visual + info.select
            end
        end
    end
    feedkeys(result)
end

--- @param a Cursor
--- @param b Cursor
--- @return boolean
local function compareCursors(a, b)
    if a._pos[2] == b._pos[2] then
        return a._pos[3] < b._pos[3]
    end
    return a._pos[2] < b._pos[2]
end

--- @param pos [integer, integer]
--- @param a Cursor
--- @param b Cursor
local function closerCursor(pos, a, b)
    local aRowDist = math.abs(a._pos[2] - pos[1])
    local bRowDist = math.abs(b._pos[2] - pos[1])
    if aRowDist < bRowDist then
        return a
    elseif bRowDist < aRowDist then
        return b
    else
        local aColDist = math.abs(a._pos[3] - pos[2])
        local bColDist = math.abs(b._pos[3] - pos[2])
        if aColDist < bColDist then
            return a
        else
            return b
        end
    end
end

--- @enum CursorState
local CursorState = {
    none = 0,
    dirty = 1,
    new = 2,
    deleted = 3,
}

local function echoerr(message)
    message = type(message) == "string"
        and message or vim.inspect(message)
    vim.api.nvim_echo({{message, "Error"}}, false, {})
end

local function ternary(b, t, f)
    if b then
        return t()
    else
        return f()
    end
end

--- @class Cursor
--- @field package _state           CursorState
--- @field package _pos             CursorPos
--- @field package _mainCursor      boolean | nil
--- @field package _register        string
--- @field package _search          string
--- @field package _visual          [ MarkPos, MarkPos ]
--- @field package _v               MarkPos
--- @field package _mode            string
--- @field package _posId           number | nil
--- @field package _vId             number | nil
local Cursor = {}
Cursor.__index = Cursor

--- @return Cursor
local function createCursor(cursor)
    return setmetatable(cursor, Cursor)
end

--- @class CursorContext
--- @field package _mainCursor Cursor | nil
--- @field package _cursors Cursor[]
--- @field package _nsid number
--- @field package _actionOccurred boolean
--- @field package _disabled boolean
local CursorContext = {}
CursorContext.__index = CursorContext

--- @param cursors Cursor[]
--- @param nsid number
--- @param disabled boolean
--- @return CursorContext
local function createCursorContext(cursors, nsid, disabled)
    --- @type CursorContext
    local ctx = {
        _disabled = disabled,
        _actionOccurred = false,
        _cursors = cursors,
        _nsid = nsid,
    }
    return setmetatable(ctx, CursorContext)
end

--- @type CursorContext
local cursorCtx

--- @class CursorManager
--- @field private _cursors Cursor[]
--- @field private _disabled boolean
--- @field private _nsid number
--- @field private _undoItems table<number, MultiCursorUndo>
local CursorManager = {}
CursorManager.__index = CursorManager

--- @return CursorManager
--- @param nsid number
local function createCursorManager(nsid)
    cursorCtx = createCursorContext({}, nsid, false)
    --- @type CursorManager
    local fields = {
        _cursors = {},
        _undoItems = {},
        _nsid = nsid,
        _disabled = false,
    }
    return setmetatable(fields, CursorManager)
end

--- @param cursor Cursor | nil
function CursorContext:setMainCursor(cursor)
    if self._mainCursor then
        self._mainCursor._mainCursor = false
        if self._mainCursor._state ~= CursorState.deleted then
            self._mainCursor._state = CursorState.dirty
        end
    end
    if cursor then
        self._mainCursor = cursor
        cursor._state = CursorState.dirty
    elseif self._mainCursor then
        local exactMatch = tbl.find(self._cursors, function(c)
            return c._state ~= CursorState.deleted
                and self._mainCursor._pos[2] == c._pos[2]
                and self._mainCursor._pos[3] == c._pos[3]
        end)
        if exactMatch then
            self._mainCursor = exactMatch
        else
            self._mainCursor = self:findNextCursor(self._mainCursor:getPos())
        end
    else
        self._mainCursor = tbl.find(self._cursors, function(c)
            return c._state ~= CursorState.deleted
        end)
    end
    if not self._mainCursor then
        self._mainCursor = createCursor({}):read()
        self._cursors[#self._cursors + 1] = self._mainCursor
    end
    self._mainCursor._mainCursor = true
end

--- @param pos [integer, integer]
function CursorContext:getCursorAtPosition(pos)
    for _, cursor in ipairs(self._cursors) do
        if cursor._pos[2] == pos[1] and cursor._pos[3] == pos[2] then
            return cursor
        end
    end
end


--- @return boolean
function CursorContext:areCursorsDisabled()
    return self._disabled
end

--- @param value boolean
function CursorContext:setCursorsDisabled(value)
    if value ~= self._disabled then
        self._disabled = value
        for _, cursor in ipairs(self._cursors) do
            if cursor._state ~= CursorState.deleted then
                cursor._state = CursorState.dirty
            end
        end
    end
end

--- @param callback fun(cursor: Cursor, i: number): boolean | nil
function CursorContext:forEach(callback)
    if self._disabled then
        callback(self._mainCursor, 1)
        return
    end
    table.sort(self._cursors, compareCursors)
    local idx = 1
    for i = 1, #self._cursors do
        local cursor = self._cursors[i]
        if cursor._state ~= CursorState.deleted then
            if self._actionOccurred then
                cursor:updatePos()
            end
            if callback(cursor, idx) then
                break
            end
            idx = idx + 1
        end
    end
    if self._actionOccurred then
        for _, cursor in ipairs(self._cursors) do
            if cursor._state ~= CursorState.deleted then
                cursor:updatePos()
            end
        end
        self._actionOccurred = false
    end
end

--- @generic T
--- @param callback fun(cursor: Cursor, i: number): T
--- @return T[]
function CursorContext:map(callback)
    local results = {}
    self:forEach(function(cursor, i)
        results[#results + 1] = callback(cursor, i)
    end)
    return results
end

--- @param pos [integer, integer]
--- @param direction? -1 | 1
--- @return Cursor
function CursorContext:findNextCursor(pos, direction)
    local cursors = tbl.filter(self._cursors, function(cursor)
        return cursor._state ~= CursorState.deleted
    end)
    if #cursors <= 1 then
        return cursors[1]
    end
    table.sort(cursors, compareCursors)

    local beforeIdx
    local afterIdx

    for i, cursor in ipairs(cursors) do
        if cursor._state ~= CursorState.deleted then
            if cursor._pos[2] > pos[1]
                or cursor._pos[2] == pos[1]
                and cursor._pos[3] >= pos[2]
            then
                if cursor._pos[3] == pos[2] then
                    beforeIdx = i - 1
                    afterIdx = i + 1
                else
                    beforeIdx = i - 1
                    afterIdx = i
                end
                break
            end
        end
    end
    if not afterIdx then
        afterIdx = 1
        beforeIdx = #cursors
    end
    local before = cursors[beforeIdx > 0 and beforeIdx or #cursors]
    local after = cursors[afterIdx <= #cursors and afterIdx or 1]
    return direction == 1 and after
        or direction == -1 and before
        or closerCursor(pos, before, after)
end

--- @param predicate fun(cursor: Cursor, i: integer): any
--- @return Cursor | nil
function CursorContext:find(predicate)
    local result
    self:forEach(function(cursor, i)
        if predicate(cursor, i) then
            result = cursor
            return true
        end
    end)
    return result
end

--- @return Cursor
function CursorContext:getMainCursor()
    if not self._mainCursor then
        self._mainCursor = tbl.find(self._cursors, function(cursor)
            return cursor._state ~= CursorState.deleted
        end)
        if not self._mainCursor then
            self._mainCursor = createCursor({}):read()
        end
    end
    return self._mainCursor
end

--- @return Cursor
function CursorContext:firstCursor()
    local firstCursor
    for _, cursor in ipairs(self._cursors) do
        if cursor._state ~= CursorState.deleted
            and not firstCursor
            or compareCursors(cursor, firstCursor)
        then
            firstCursor = cursor
        end
    end
    return firstCursor
end

--- @return Cursor
function CursorContext:lastCursor()
    local lastCursor
    for i = #self._cursors, 1, -1 do
        local cursor = self._cursors[i]
        if cursor._state ~= CursorState.deleted
            and not lastCursor
            or compareCursors(lastCursor, cursor)
        then
            lastCursor = cursor
        end
    end
    return lastCursor
end

-- see :h getcurpos()
--- @alias CursorPos [number, number, number, number, number]

-- see :h getpos()
--- @alias MarkPos [number, number, number, number]

--- @return number
function Cursor:line()
    return self._pos[2]
end

--- @return number
function Cursor:col()
    return self._pos[3]
end

--- @return string
function Cursor:getLine()
    return vim.api.nvim_buf_get_lines(
        0, self._pos[2], self._pos[2] + 1, true)[1]
end

function Cursor:delete()
    self._state = CursorState.deleted
    if self._mainCursor then
        cursorCtx:setMainCursor(nil)
    end
end

function Cursor:select()
    cursorCtx:setMainCursor(self)
end

function Cursor:atVisualStart()
    return self._pos[2] < self._v[2]
        or self._pos[2] == self._v[2]
        and self._pos[3] <= self._v[3]
end

function Cursor:convertToSingleLines()
    if visualSelectModes[self._mode] then
        if self._mode == "v" or self._mode == "s" then
            local atVisualStart = self:atVisualStart()
            local lines = vim.api.nvim_buf_get_lines(
                0, self._visual[1][2] - 1, self._visual[2][2], false)
            for i = self._visual[1][2], self._visual[2][2] do
                local newCursor = self:clone()
                local startCol = i == self._visual[1][2]
                    and self._visual[1][3]
                    or 1
                local endCol = i == self._visual[2][2]
                    and self._visual[2][3]
                    or #lines[i - self._visual[1][2] + 1]
                newCursor:setVisual(atVisualStart
                    and { i, endCol, i, startCol }
                    or { i, startCol, i, endCol }
                )
                newCursor._mode = "v"
            end
        elseif self._mode == "V" or self._mode == "S" then
            local lines = vim.api.nvim_buf_get_lines(
                0, self._visual[1][2] - 1, self._visual[2][2], false)
            for i = self._visual[1][2], self._visual[2][2] do
                local newCursor = self:clone()
                newCursor:setVisual({
                    i,
                    #lines[i - self._visual[1][2] + 1],
                    i,
                    1,
                })
                newCursor._mode = "v"
            end
        elseif self._mode == TERM_CODES.CTRL_V or self._mode == TERM_CODES.CTRL_S then
            local atVisualStart = self:atVisualStart()
            for i = self._visual[1][2], self._visual[2][2] do
                local newCursor = self:clone()
                newCursor:setVisual(atVisualStart
                    and {i, self._visual[2][3], i, self._visual[1][3]}
                    or {i, self._visual[1][3], i, self._visual[2][3]}
                )
                newCursor._mode = "v"
            end
        end
    else
        return
    end
    self:delete()
end

--- @return boolean | nil
function Cursor:isMainCursor()
    return self._mainCursor
end

--- @return [integer, integer]
function Cursor:getPos()
    return {self._pos[2], self._pos[3]}
end

--- @param pos [integer, integer]
function Cursor:setPos(pos)
    self._pos = { self._pos[0], pos[1], pos[2], 0, pos[2] }
    self:setMarks()
end

--- @return Cursor
function Cursor:clone()
    --- @type Cursor
    local fields = {
        _pos = self._pos,
        _register = self._register,
        _search = self._search,
        _visual = self._visual,
        _v = self._v,
        _mode = self._mode,
        _state = CursorState.new,
    }
    local cursor = createCursor(fields)
    cursor:setMarks()
    cursorCtx._cursors[#cursorCtx._cursors + 1] = cursor
    return cursor
end

--- @return string[]
function Cursor:getVisualLines()
    return vim.fn.getregion(self._v, self._pos, {
        type = visualSelectModes[self._mode].visual,
        exclusive = false
    })
end

--- @return string[]
function Cursor:getFullVisualLines()
    return vim.api.nvim_buf_get_lines(
        0, self._visual[1][2] - 1, self._visual[2][2], true)
end

function Cursor:updatePos()
    local cursorExtmark = vim.api.nvim_buf_get_extmark_by_id(
        0, cursorCtx._nsid, self._posId, {})

    if cursorExtmark and #cursorExtmark > 0 then
        self._pos = {
            self._pos[1],
            cursorExtmark[1] + 1,
            cursorExtmark[2] + 1,
            self._pos[4],
            cursorExtmark[2] + 1 == self._pos[3]
                and math.max(self._pos[5], cursorExtmark[2] + 1)
                or cursorExtmark[2] + 1
        }
    end

    if self._vId then
        local vExtmark = vim.api.nvim_buf_get_extmark_by_id(
                0, cursorCtx._nsid, self._vId, {})
        if vExtmark and #vExtmark > 0 then
            self._v = {
                self._v[1],
                vExtmark[1] + 1,
                vExtmark[2] + 1,
                self._v[4],
            }
            return
        end
    end
    self._v = self._pos
end

--- @return [[number, number], [number, number]]
function Cursor:getVisual()
    if self:inVisualMode() then
        if self:atVisualStart() then
            --- @type any
            return {{self._pos[2], self._pos[3]}, {self._v[2], self._v[3]}}
        else
            --- @type any
            return {{self._v[2], self._v[3]}, {self._pos[2], self._pos[3]}}
        end
    end
    --- @type any
    return {
        {self._visual[1][2], self._visual[1][3]},
        {self._visual[2][2], self._visual[2][3]}
    }
end

--- @return string
function Cursor:mode()
    return self._mode
end

--- @param mode string
function Cursor:setMode(mode)
    self._mode = mode
end

--- @param action string | function
--- @param opts? { remap: boolean }
function Cursor:perform(action, opts)
    cursorCtx._actionOccurred = true
    self._state = CursorState.dirty

    self:write()
    local apply = type(action) == "function" and action or function()
        feedkeys(action, opts)
    end
    local success, err = pcall(apply, self)
    if success then
        self:read()
        self:setMarks()
    else
        echoerr(err)
    end
end

function Cursor:read()
    self._mode = vim.fn.mode()
    self._pos = vim.fn.getcurpos()
    self._v = vim.fn.getpos("v")
    setMode("n")
    self._register = vim.fn.getreg("")
    self._search = vim.fn.getreg("/")
    self._visual = {vim.fn.getpos("'<"), vim.fn.getpos("'>")}
    return self
end

function Cursor:write()
    vim.fn.setreg("", self._register)
    vim.fn.setreg("/", self._search)
    vim.fn.setpos("'<", self._visual[1])
    vim.fn.setpos("'>", self._visual[2])
    vim.fn.setpos(".", self._pos)
    setMode(self._mode, self)
end



--- @param visual [integer, integer, integer, integer]
function Cursor:setVisual(visual)
    local vs = self._visual[1]
    local ve = self._visual[2]
    local startLine, startCol, endLine, endCol = table.unpack(visual)
    local atVisualEnd = startLine > endLine or startLine == endLine and startCol > endCol
    local newVisual = atVisualEnd
        and {
            { ve[1], endLine, endCol, 0 },
            { vs[1], startLine, startCol, 0 },
        }
        or {
            { vs[1], startLine, startCol, 0 },
            { ve[1], endLine, endCol, 0 },
        }
    if self:inVisualMode() then
        local nvs = newVisual[1]
        local nve = newVisual[2]
        if atVisualEnd then
            self._pos = { self._pos[1], nvs[2], nvs[3], nvs[4], nvs[3]  }
            self._v = { self._pos[1], nve[2], nve[3], nve[4], nve[3]  }
        else
            self._v = { self._pos[1], nvs[2], nvs[3], nvs[4], nvs[3]  }
            self._pos = { self._pos[1], nve[2], nve[3], nve[4], nve[3]  }
        end
    end
    self._visual = newVisual
    self._state = CursorState.dirty
    self:setMarks()
end

--- @return boolean
function Cursor:inVisualMode()
    return not not visualSelectModes[self._mode]
end

--- @param lines string[]
--- @param start number
--- @param hl string
function Cursor:drawVisualChar(lines, start, hl)
    local i = self._visual[1][2]
    while i <= self._visual[2][2] do
        local row = i - 1
        local line = lines[row - start + 1]
        local col = i == self._visual[1][2]
            and self._visual[1][3] - 1
            or 0
        local endCol = i == self._visual[2][2]
            and self._visual[2][3] - 1
            or (line and #line or 0)
        local id = vim.api.nvim_buf_set_extmark(0, cursorCtx._nsid, row, col, {
            strict = false,
            undo_restore = false,
            virt_text = ternary(i == self._visual[2][2],
                function() return nil end,
                function() return {{" ", hl}} end
            ),
            end_col = endCol + 1,
            virt_text_pos = "inline",
            virt_text_win_col = line and #line or 0,
            hl_group = hl,
        })
        self._visualIds[#self._visualIds + 1] = id
        i = i + 1
    end
end

--- @param lines string[]
--- @param start number
--- @param hl string
function Cursor:drawVisualLine(lines, start, hl)
    local i = self._visual[1][2]
    while i <= self._visual[2][2] do
        local row = i - 1
        local line = lines[row - start + 1]
        local endCol = ternary(line,
            function() return #line end,
            function() return 0 end
        )
        local id = vim.api.nvim_buf_set_extmark(
            0,
            cursorCtx._nsid,
            row,
            0,
            {
                strict = false,
                undo_restore = false,
                virt_text = {{" ", hl}},
                end_col = endCol + 1,
                virt_text_pos = "inline",
                virt_text_win_col = line and #line or 0,
                hl_group = hl,
            }
        )
        self._visualIds[#self._visualIds + 1] = id
        i = i + 1
    end
end

--- @param lines string[]
--- @param start number
--- @param hl string
function Cursor:drawVisualBlock(lines, start, hl)
    local range = {self._visual[1][3] - 1, self._visual[2][3] - 1}
    local startCol = math.min(range[1], range[2])
    local endCol = math.max(range[1], range[2])
    local i = self._visual[1][2]
    while i <= self._visual[2][2] do
        local row = i - 1
        local line = lines[row - start + 1]
        if line and #line >= startCol then
            local id = vim.api.nvim_buf_set_extmark(
                0,
                cursorCtx._nsid,
                row,
                startCol,
                {
                    strict = false,
                    undo_restore = false,
                    end_col = endCol + 1,
                    hl_group = hl,
                }
            )
            self._visualIds[#self._visualIds + 1] = id
        end
        i = i + 1
    end
end

function Cursor:setMarks()
    local opts = { strict = false, undo_restore = false }
    self:clearMarks()
    if self:inVisualMode() then
        self._vId = vim.api.nvim_buf_set_extmark(
            0,
            cursorCtx._nsid,
            self._v[2] - 1,
            self._v[3] - 1,
            opts
        )
    end
    self._posId = vim.api.nvim_buf_set_extmark(
        0,
        cursorCtx._nsid,
        self._pos[2] - 1,
        self._pos[3] - 1,
        opts
    )
end

function Cursor:draw()
    local visualHL = cursorCtx._disabled
        and "MultiCursorDisabledVisual"
        or "MultiCursorVisual"
    local cursorHL = cursorCtx._disabled
        and "MultiCursorDisabledCursor"
        or "MultiCursorCursor"
    local start
    local _end

    if visualSelectModes[self._mode] then
        start = math.max(math.min(self._visual[1][2], self._pos[2]) - 1, 0)
        _end = math.max(math.max(self._visual[2][2], self._pos[2]) - 1, start)
    else
        start = self._pos[2] - 1
        _end = self._pos[2] - 1
    end
    local lines = vim.api.nvim_buf_get_lines(0, start, _end + 1, true)

    local char = ""
    local charLine = lines[self._pos[2] - start]
    if charLine then
        char = string.sub(charLine, self._pos[3], self._pos[3])
    end
    if #char ~= 1 then
        char = " "
    end

    self._visualIds = {}

    if self._mode == "v" or self._mode == "s" then
        self:drawVisualChar(lines, start, visualHL)
    elseif self._mode == "V" or self._mode == "S" then
        self:drawVisualLine(lines, start, visualHL)
    elseif self._mode == TERM_CODES.CTRL_V or self._mode == TERM_CODES.CTRL_S then
        self:drawVisualBlock(lines, start, visualHL)
    end
    self._visualIds[#self._visualIds + 1] = vim.api.nvim_buf_set_extmark(
        0,
        cursorCtx._nsid,
        self._pos[2] - 1,
        self._pos[3] - 1,
        {
            strict = false,
            undo_restore = false,
            virt_text_pos = "overlay",
            virt_text_hide = true,
            virt_text = {{char, cursorHL}},
        }
    )
end

function Cursor:clearMarks()
    if self._posId then
        vim.api.nvim_buf_del_extmark(0, cursorCtx._nsid, self._posId)
        self._posId = nil
    end
    if self._vId then
        vim.api.nvim_buf_del_extmark(0, cursorCtx._nsid, self._vId)
        self._vId = nil
    end
end

function Cursor:erase()
    if self._visualIds then
        for _, id in ipairs(self._visualIds) do
            vim.api.nvim_buf_del_extmark(0, cursorCtx._nsid, id)
        end
    end
end

function CursorManager:dirty()
    cursorCtx._actionOccurred = true
end

--- @return boolean
function CursorManager:cursorsEnabled()
    return not cursorCtx._disabled
end

function CursorManager:clear()
    vim.api.nvim_buf_clear_namespace(0, cursorCtx._nsid, 0, -1)
    cursorCtx._disabled = false
    self._cursors = {}
    self._undoItems = {}
end

--- @param cursor Cursor
function CursorManager:deleteCursor(cursor)
    cursor:erase()
    cursor:clearMarks()
    self._cursors = tbl.filter(self._cursors, function(c)
        return c ~= cursor
    end)
end

--- @param _end number
--- @param cursor Cursor
function CursorManager:insertCursor(_end, cursor)
    cursor = createCursor(cursor)
    cursor:setMarks()
    cursor:draw()
    table.insert(
        self._cursors, _end == 1 and 1 or #self._cursors + 1,
        cursor
    )
end

--- @param mainCursor Cursor
--- @param mergeMain? boolean
function CursorManager:mergeCursors(mainCursor, mergeMain)
    --- @type Cursor[]
    local newCursors = {}
    for _, cursor in ipairs(self._cursors) do
        local exists = false
        if mergeMain
            and cursor._pos[2] == mainCursor._pos[2]
            and cursor._pos[3] == mainCursor._pos[3]
        then
            exists = true
        else
            for _, c in ipairs(newCursors) do
                if cursor._pos[2] == c._pos[2]
                    and cursor._pos[3] == c._pos[3]
                then
                    exists = true
                    break
                end
            end
        end
        if exists then
            cursor:erase()
            cursor:clearMarks()
        else
            newCursors[#newCursors + 1] = cursor
        end
    end
    self._cursors = newCursors
end

--- @param mainCursor Cursor
--- @param mergeMain? boolean
function CursorManager:update(mainCursor, mergeMain)
    if #self._cursors == 0 then
        self:clear()
    else
        mergeMain = mergeMain == nil and true or mergeMain
        local undoTree = vim.fn.undotree()
        self:mergeCursors(mainCursor, mergeMain)
        self._undoItems[undoTree.seq_cur] = {
            cursors = tbl.map(self._cursors, tbl.shallow_copy),
            mainCursor = tbl.shallow_copy(mainCursor),
        }
    end
end

function CursorManager:hasCursors()
    return #self._cursors > 0
end

function CursorManager:loadUndoItem()
    local undoTree = vim.fn.undotree()
    local undoItem = self._undoItems[undoTree.seq_cur]
    if undoItem then
        self._cursors = tbl.map(undoItem.cursors, function(c)
            return createCursor(tbl.shallow_copy(c))
        end)
        self:redraw()
        createCursor(undoItem.mainCursor):write()
        return true
    end
    return false
end

function CursorManager:undo()
    if not self:loadUndoItem() then
        self:clear()
    end
end

function CursorManager:redo()
    self:loadUndoItem()
end

function CursorManager:redraw()
    vim.api.nvim_buf_clear_namespace(0, cursorCtx._nsid, 0, -1)
    for _, cursor in ipairs(self._cursors) do
        cursor:setMarks()
        cursor:draw()
    end
end

--- @param callback fun(context: CursorContext)
function CursorManager:action(callback)
    local origClipboard = vim.o.clipboard
    vim.o.clipboard = ""
    local origCursor = createCursor({}):read()
    origCursor._mainCursor = true
    origCursor:setMarks()
    self._cursors[#self._cursors + 1] = origCursor
    for _, cursor in ipairs(self._cursors) do
        cursor._state = 0
    end
    cursorCtx._cursors = self._cursors
    cursorCtx._mainCursor = origCursor
    cursorCtx._nsid = self._nsid
    callback(cursorCtx)
    self._cursors = tbl.filter(self._cursors, function(cursor)
        if cursor._state == CursorState.deleted then
            cursor:clearMarks()
            cursor:erase()
            return false
        end
        return true
    end)
    local mainCursor = cursorCtx._mainCursor
    if not mainCursor then
        mainCursor = cursorCtx:findNextCursor(origCursor:getPos())
    end
    if cursorCtx._actionOccurred then
        self._cursors = tbl.filter(self._cursors, function(cursor)
            if cursor == mainCursor then
                cursor:updatePos()
                cursor:erase()
                cursor:clearMarks()
                return false
            else
                cursor:updatePos()
                cursor:erase()
                cursor:draw()
                return true
            end
        end)
    else
        self._cursors = tbl.filter(self._cursors, function(cursor)
            if cursor == mainCursor then
                cursor:erase()
                cursor:clearMarks()
                return false
            else
                if cursor._state == CursorState.new then
                    cursor:draw()
                elseif cursor._state == CursorState.dirty then
                    cursor:erase()
                    cursor:draw()
                end
                return true
            end
        end)
    end
    if not mainCursor then
        mainCursor = createCursor({}):read()
    end

    self:update(mainCursor, not cursorCtx._disabled)
    mainCursor:write()
    cursorCtx._actionOccurred = false
    vim.o.clipboard = origClipboard
end

return createCursorManager
