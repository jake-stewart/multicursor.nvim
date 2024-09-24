local TERM_CODES = require("multicursor-nvim.term-codes")
local feedkeysManager = require("multicursor-nvim.feedkeys-manager")
local tbl = require("multicursor-nvim.tbl")
local util = require("multicursor-nvim.util")

local set_extmark = vim.api.nvim_buf_set_extmark
local del_extmark = vim.api.nvim_buf_del_extmark
local clear_namespace = vim.api.nvim_buf_clear_namespace
local replace_termcodes = vim.api.nvim_replace_termcodes
local get_extmark = vim.api.nvim_buf_get_extmark_by_id
local get_lines = vim.api.nvim_buf_get_lines

--- @param cur integer
local function undoItemId(cur)
    return vim.fn.bufnr() .. ":" .. cur
end

--- @param keys string
--- @param opts? { remap?: boolean, keycodes?: boolean }
local function feedkeys(keys, opts)
    local mode = opts and opts.remap and "x" or "xn"
    if opts and opts.keycodes then
        keys = replace_termcodes(keys, true, true, true)
    end
    feedkeysManager.feedkeys(keys, mode, false)
end

--- @param a Cursor
--- @param b Cursor
--- @return boolean
local function compareCursorsPosition(a, b)
    if a._pos[2] == b._pos[2] then
        if a._pos[3] == b._pos[3] then
            return a._pos[4] < b._pos[4]
        end
        return a._pos[3] < b._pos[3]
    end
    return a._pos[2] < b._pos[2]
end

--- 1-indexed line and column.
--- @alias SimplePos [integer, integer]

--- See :h getcurpos()
--- @alias CursorPos [integer, integer, integer, integer, integer]

--- See :h getpos()
--- @alias MarkPos [integer, integer, integer, integer]

--- @enum CursorState
local CursorState = {
    none = 0,
    dirty = 1,
    new = 2,
    deleted = 3,
}

--- @class Cursor
--- @field package _id              integer
--- @field package _modifiedId      integer
--- @field package _state           CursorState
--- @field package _changePos       MarkPos
--- @field package _origChangePos   MarkPos
--- @field package _drift           [integer, integer]
--- @field package _pos             CursorPos
--- @field package _register        string
--- @field package _search          string
--- @field package _visual          [ MarkPos, MarkPos ]
--- @field package _visualIds       integer[] | nil
--- @field package _vPos            MarkPos
--- @field package _mode            string
--- @field package _posId           integer | nil
--- @field package _vPosId          integer | nil
local Cursor = {}
Cursor.__index = Cursor

--- @class MultiCursorUndoItem
--- @field data number[]
--- @field enabled boolean

--- @package
--- @class SharedMultiCursorState
--- @field mainCursor Cursor | nil
--- @field modifiedId integer
--- @field cursors Cursor[]
--- @field nsid integer
--- @field virtualEditBlock boolean
--- @field undoItems table<string, MultiCursorUndoItem>
--- @field redoItems table<string, MultiCursorUndoItem>
--- @field currentSeq integer | nil
--- @field shallowUndo boolean
--- @field numLines number
--- @field leftcol number
--- @field textoffset number
--- @field enabled boolean
local state = {
    cursors = {},
    undoItems = {},
    redoItems = {},
    clipboard = nil,
    id = 0,
    shallowUndo = false,
    modifiedId = 0,
    enabled = true,
    nsid = 0,
    numLines = 0,
    leftcol = 0,
    textoffset = 0,
}

--- @return Cursor
local function createCursor(cursor)
    cursor._id = state.id
    state.id = state.id + 1
    return setmetatable(cursor, Cursor)
end

local function safeGetExtmark(id)
    local mark = get_extmark(0, state.nsid, id, {})
    if mark and #mark > 0 then
        if mark[1] >= state.numLines then
            -- this is probably a neovim bug
            -- the mark can be outside of the file
            mark[1] = state.numLines - 1
            mark[2] = 0
        end
        return mark
    end
    return nil
end

--- @param cursor Cursor
local function cursorUpdatePos(cursor)
    local oldPos = cursor._pos
    cursor._modifiedId = state.modifiedId

    if cursor._posId then
        local mark = safeGetExtmark(cursor._posId)
        if mark then
            local curswantVirtcol = vim.fn.virtcol({ mark[1] + 1, mark[2] + 1 })
            cursor._pos = {
                cursor._pos[1],
                mark[1] + 1,
                mark[2] + 1,
                cursor._pos[4],
                mark[2] + 1 == cursor._pos[3]
                    and math.max(cursor._pos[5], curswantVirtcol)
                    or curswantVirtcol
            }
            cursor._drift[1] = cursor._drift[1] + (cursor._pos[2] - oldPos[2])
            cursor._drift[2] = cursor._drift[2] + (cursor._pos[3] - oldPos[3])
        else
            cursor._posId = nil
        end
    end

    if cursor._vPosId then
        local mark = safeGetExtmark(cursor._vPosId)
        if mark then
            cursor._vPos = {
                cursor._vPos[1],
                mark[1] + 1,
                mark[2] + 1,
                cursor._vPos[4],
            }
        else
            cursor._vPosId = nil
            cursor._vPos = cursor._pos
        end
    else
        cursor._vPos = cursor._pos
    end
end

--- @param cursor Cursor
local function cursorCheckUpdate(cursor)
    if cursor._modifiedId ~= state.modifiedId then
        cursorUpdatePos(cursor)
    end
end

--- @param cursor Cursor
--- @param lines string[]
--- @param start integer
--- @param hl string
local function cursorDrawVisualChar(cursor, lines, start, hl)
    local vs
    local ve
    if cursor._vPos[2] < cursor._pos[2]
        or cursor._vPos[2] == cursor._pos[2]
        and (cursor._vPos[3] + cursor._vPos[4])
            < (cursor._pos[3] + cursor._pos[4])
    then
        vs = cursor._vPos
        ve = cursor._pos
    else
        vs = cursor._pos
        ve = cursor._vPos
    end
    if vs[2] == ve[2] then
        local line = lines[vs[2] - start]
        local displayWidth = line and vim.fn.strdisplaywidth(line) or 0
        local id = set_extmark(0, state.nsid, vs[2] - 1, vs[3] - 1, {
            strict = false,
            undo_restore = false,
            priority = 200,
            virt_text = ve[3] > #line
                and {{string.rep(" ", ve[4] - vs[4] + 1), hl}}
                or nil,
            end_col = ve[3],
            virt_text_pos = "overlay",
            virt_text_win_col = displayWidth + vs[4] - state.leftcol,
            hl_group = hl,
        })
        cursor._visualIds[#cursor._visualIds + 1] = id
    else
        local i = vs[2]
        while i <= ve[2] do
            local row = i - 1
            local line = lines[row - start + 1]
            local col = i == vs[2] and (vs[3] - 1 + vs[4]) or 0
            local displayWidth = line and vim.fn.strdisplaywidth(line) or 0
            local endCol = i == ve[2]
                and ve[3] - 1
                or #line
            local virt_text = endCol >= #line and {{
                i == ve[2]
                    and string.rep(" ", ve[4] + (ve[3] == displayWidth + 1 and 1 or 0))
                    or " ",
                hl
            }} or nil
            local id = set_extmark(0, state.nsid, row, col, {
                strict = false,
                undo_restore = false,
                virt_text = virt_text,
                end_col = endCol + 1,
                priority = 200,
                virt_text_pos = "overlay",
                virt_text_win_col = displayWidth
                    + (i == vs[2] and vs[4] or 0) - state.leftcol,
                hl_group = hl,
            })
            cursor._visualIds[#cursor._visualIds + 1] = id
            i = i + 1
        end
    end
end

--- @param cursor Cursor
--- @param lines string[]
--- @param start integer
--- @param hl string
local function cursorDrawVisualLine(cursor, lines, start, hl)
    local visualStart, visualEnd = cursor:getVisual()
    local i = visualStart[1]
    while i <= visualEnd[1] do
        local row = i - 1
        local line = lines[row - start + 1]
        local displayWidth = line and vim.fn.strdisplaywidth(line) or 0
        local id = set_extmark(0, state.nsid, row, 0, {
            strict = false,
            undo_restore = false,
            virt_text = {{" ", hl}},
            end_col = #line,
            virt_text_pos = "inline",
            priority = 200,
            virt_text_win_col = displayWidth - state.leftcol,
            hl_group = hl,
        })
        cursor._visualIds[#cursor._visualIds + 1] = id
        i = i + 1
    end
end

--- @param cursor Cursor
--- @param lines string[]
--- @param start integer
--- @param hl string
local function cursorDrawVisualBlock(cursor, lines, start, hl)
    local startLine = math.min(cursor._vPos[2], cursor._pos[2])
    local endLine = math.max(cursor._vPos[2], cursor._pos[2])
    local vc = cursor._vPos[3] + cursor._vPos[4]
    local pc = cursor._pos[3] + cursor._pos[4]
    local startCol = math.min(vc, pc)
    local endCol = math.max(vc, pc)

    local i = startLine
    while i <= endLine do
        local line = lines[i - start]
        if line and #line >= startCol then
            local displayWidth = vim.fn.strdisplaywidth(line)
            local virt_text = endCol >= #line and {{
                string.rep(" ", endCol - #line
                    + (state.virtualEditBlock and 0 or -1)),
                hl
            }} or nil
            local id = set_extmark(0, state.nsid, i - 1, startCol - 1, {
                strict = false,
                undo_restore = false,
                end_col = endCol,
                virt_text_pos = "inline",
                priority = 200,
                virt_text_win_col = displayWidth - state.leftcol,
                virt_text = virt_text,
                hl_group = hl,
            })
            cursor._visualIds[#cursor._visualIds + 1] = id
        end
        i = i + 1
    end
end

--- @param cursor Cursor
--- @return Cursor[]
local function cursorSplitVisualChar(cursor)
    local newCursors = {}
    local atVisualStart = cursor:atVisualStart()
    local visualStart, visualEnd = cursor:getVisual()
    local lines = get_lines(
        0, visualStart[1] - 1, visualEnd[1], false)
    for i = visualStart[1], visualEnd[1] do
        local newCursor = cursor:clone()
        newCursors[#newCursors + 1] = newCursor
        local startCol = i == visualStart[1]
            and visualStart[2]
            or 1
        local endCol = i == visualEnd[1]
            and visualEnd[2]
            or #lines[i - visualStart[1] + 1]
        if atVisualStart then
            newCursor:setVisual({ i, endCol }, { i, startCol })
        else
            newCursor:setVisual({ i, startCol }, { i, endCol })
        end
        newCursor._mode = "v"
    end
    return newCursors
end

--- @param cursor Cursor
--- @return Cursor[]
local function cursorSplitVisualLine(cursor)
    local newCursors = {}
    local visualStart, visualEnd = cursor:getVisual()
    local lines = get_lines(
        0, visualStart[1] - 1, visualEnd[1], false)
    for i = visualStart[1], visualEnd[1] do
        local newCursor = cursor:clone()
        newCursors[#newCursors + 1] = newCursor
        newCursor:setVisual(
            { i, #lines[i - visualStart[1] + 1] },
            { i, 1 }
        )
        newCursor._mode = "v"
    end
    return newCursors
end

--- @param cursor Cursor
--- @return Cursor[]
local function cursorSplitVisualBlock(cursor)
    local newCursors = {}
    local atVisualStart = cursor:atVisualStart()
    local visualStart, visualEnd = cursor:getVisual()
    for i = visualStart[1], visualEnd[1] do
        local newCursor = cursor:clone()
        newCursors[#newCursors + 1] = newCursor
        if atVisualStart then
            newCursor:setVisual(
                { i, visualEnd[2] },
                { i, visualStart[2] }
            )
        else
            newCursor:setVisual(
                { i, visualStart[2] },
                { i, visualEnd[2] }
            )
        end
        newCursor._mode = "v"
    end
    return newCursors
end


local VISUAL_LOOKUP = {
    v = {
        enterVisualKey = "v",
        enterSelectKey = "",
        draw = cursorDrawVisualChar,
        split = cursorSplitVisualChar,
    },
    V = {
        enterVisualKey = "V",
        enterSelectKey = "",
        draw = cursorDrawVisualLine,
        split = cursorSplitVisualLine,
    },
    [TERM_CODES.CTRL_V] = {
        enterVisualKey = TERM_CODES.CTRL_V,
        enterSelectKey = "",
        draw = cursorDrawVisualBlock,
        split = cursorSplitVisualBlock,
    },
    s = {
        enterVisualKey = "v",
        enterSelectKey = TERM_CODES.CTRL_G,
        draw = cursorDrawVisualChar,
        split = cursorSplitVisualChar,
    },
    S = {
        enterVisualKey = "V",
        enterSelectKey = TERM_CODES.CTRL_G,
        draw = cursorDrawVisualLine,
        split = cursorSplitVisualLine,
    },
    [TERM_CODES.CTRL_S] = {
        enterVisualKey = TERM_CODES.CTRL_V,
        enterSelectKey = TERM_CODES.CTRL_G,
        draw = cursorDrawVisualBlock,
        split = cursorSplitVisualBlock,
    },
}

--- @param cursor Cursor
local function cursorDraw(cursor)
    local visualHL = state.enabled
        and "MultiCursorVisual"
        or "MultiCursorDisabledVisual"
    local cursorHL = state.enabled
        and "MultiCursorCursor"
        or "MultiCursorDisabledCursor"
    local start
    local _end

    local visualInfo = VISUAL_LOOKUP[cursor._mode]
    if visualInfo then
        local visualStart, visualEnd = cursor:getVisual()
        start = math.max(visualStart[1] - 1, 0)
        _end = math.max(visualEnd[1] - 1, start)
    else
        start = cursor._pos[2] - 1
        _end = cursor._pos[2] - 1
    end
    local lines = get_lines(0, start, _end + 1, true)

    cursor._visualIds = {}
    if visualInfo then
        visualInfo.draw(cursor, lines, start, visualHL)
    end

    local row = cursor._pos[2] - 1
    local col = cursor._pos[3] + cursor._pos[4] - 1

    local charLine = lines[cursor._pos[2] - start]
    local displayWidth = vim.fn.strdisplaywidth(charLine)

    local virt_text_win_col
    if col > #charLine then
        virt_text_win_col = displayWidth + col - #charLine - state.leftcol
        if virt_text_win_col - state.textoffset < 0 then
            virt_text_win_col = nil
        end
    end

    local id = set_extmark(0, state.nsid, row, col, {
        strict = false,
        undo_restore = false,
        virt_text_pos = "overlay",
        priority = 1000,
        virt_text_win_col = virt_text_win_col,
        hl_group = cursorHL,
        end_col = col + 1,
        virt_text_hide = true,
        virt_text = col >= #charLine and {{ " ", cursorHL, }} or nil,
    })
    cursor._visualIds[#cursor._visualIds + 1] = id
end

--- @param cursor Cursor
local function cursorClearMarks(cursor)
    if cursor._posId then
        del_extmark(0, state.nsid, cursor._posId)
        cursor._posId = nil
    end
    if cursor._vPosId then
        del_extmark(0, state.nsid, cursor._vPosId)
        cursor._vPosId = nil
    end
end

--- @param cursor Cursor
local function cursorSetMarks(cursor)
    cursorClearMarks(cursor)
    local opts = { strict = false, undo_restore = false }
    if cursor:inVisualMode() then
        cursor._vPosId = set_extmark(
            0,
            state.nsid,
            cursor._vPos[2] - 1,
            cursor._vPos[3] - 1,
            opts
        )
    end
    cursor._posId = set_extmark(
        0,
        state.nsid,
        cursor._pos[2] - 1,
        cursor._pos[3] - 1,
        opts
    )
end

--- @param cursor Cursor
local function cursorErase(cursor)
    if cursor._visualIds then
        for _, id in ipairs(cursor._visualIds) do
            del_extmark(0, state.nsid, id)
        end
        cursor._visualIds = nil
    end
end

--- @param cursor Cursor
local function cursorRead(cursor)
    cursor._mode = vim.fn.mode()
    cursor._pos = vim.fn.getcurpos()
    cursor._vPos = vim.fn.getpos("v")
    cursor._changePos = vim.fn.getpos("'[")
    cursor._modifiedId = state.modifiedId
    cursor._register = vim.fn.getreginfo("")
    cursor._search = vim.fn.getreg("/")
    if vim.fn.mode() == "n" or not cursor._visual then
        cursor._visual = {
            vim.fn.getpos("'<"),
            vim.fn.getpos("'>"),
        }
    end
    return cursor
end

--- @param cursor Cursor
local function cursorWrite(cursor)
    vim.fn.setreg("", cursor._register)
    vim.fn.setreg("/", cursor._search)
    vim.fn.setpos("'<", cursor._visual[1])
    vim.fn.setpos("'>", cursor._visual[2])
    local mode = vim.fn.mode()
    local visualInfo = VISUAL_LOOKUP[cursor._mode]
    if visualInfo then
        feedkeys((mode == "n" and "" or TERM_CODES.ESC) .. visualInfo.enterVisualKey)
        vim.fn.setpos(".", cursor._vPos)
        feedkeys("o")
        vim.fn.setpos(".", cursor._pos)
        if #visualInfo.enterSelectKey > 0 then
            feedkeys(visualInfo.enterSelectKey)
        end
    elseif cursor._mode == "n" then
        if mode ~= "n" then
            feedkeys(TERM_CODES.ESC)
        end
        vim.fn.setpos(".", cursor._pos)
    else
        error("unexpected mode:" .. mode)
    end
end

--- @class CursorContext
local CursorContext = {}

--- @param cursor Cursor | nil
local function cursorContextSetMainCursor(cursor)
    if state.mainCursor then
        if state.mainCursor._state ~= CursorState.deleted then
            state.mainCursor._state = CursorState.dirty
        end
    end
    state.mainCursor = cursor
end

--- When cursors are disabled, only the main cursor can be interacted with.
--- @param value boolean
function CursorContext:setCursorsEnabled(value)
    if value ~= state.enabled then
        state.enabled = value
        for _, cursor in ipairs(state.cursors) do
            if cursor._state ~= CursorState.deleted then
                cursor._state = CursorState.dirty
            end
        end
    end
end

--- Returns a list of cursors, sorted by their position.
--- @return Cursor[]
function CursorContext:getCursors()
    local cursors = tbl.filter(state.cursors, function(cursor)
        return cursor._state ~= CursorState.deleted
    end)
    table.sort(cursors, compareCursorsPosition)
    return cursors
end

--- Clones and returns the main cursor
--- @return Cursor
function CursorContext:addCursor()
    return self:mainCursor():clone()
end

--- Util which executes callback for each cursor, sorted by their position.
--- @param callback fun(cursor: Cursor, i: integer, t: Cursor[]): boolean | nil
function CursorContext:forEachCursor(callback)
    tbl.forEach(self:getCursors(), callback)
end

--- Util method which maps each cursor to a value.
--- @generic T
--- @param callback fun(cursor: Cursor, i: integer, t: Cursor[]): T
--- @return T[]
function CursorContext:mapCursors(callback)
    return tbl.map(self:getCursors(), callback)
end

--- Util method which returns the first cursor matching the predicate.
--- @param predicate fun(cursor: Cursor, i: integer, t: Cursor[]): any
--- @return Cursor | nil
function CursorContext:findCursor(predicate)
    return tbl.find(self:getCursors(), predicate)
end

--- Returns the closest cursor which appears AFTER pos.
--- A cursor exactly at pos will not be returned.
--- It does not wrap, so if none are found, then nil is returned.
--- If you wish to wrap, use `ctx:nextCursor(...) or ctx:firstCursor(...)`.
--- @param pos SimplePos
--- @param offset? integer
--- @return Cursor | nil
function CursorContext:nextCursor(pos, offset)
    offset = offset or 0
    local nextCursor = nil
    for _, cursor in ipairs(state.cursors) do
        if cursor._state ~= CursorState.deleted then
            cursorCheckUpdate(cursor)
            if cursor._pos[2] > pos[1]
                or cursor._pos[2] == pos[1]
                and (cursor._pos[3] + cursor._pos[4]) > (pos[2] + offset)
            then
                if not nextCursor
                    or compareCursorsPosition(cursor, nextCursor)
                then
                    nextCursor = cursor
                end
            end
        end
    end
    return nextCursor
end

--- Returns the closest cursor which appears BEFORE pos.
--- A cursor exactly at pos will not be returned.
--- It does not wrap, so if none are found, then nil is returned.
--- If you wish to wrap, use `ctx:prevCursor(...) or ctx:lastCursor(...)`.
--- @param pos SimplePos
--- @param offset? integer
--- @return Cursor | nil
function CursorContext:prevCursor(pos, offset)
    offset = offset or 0
    local prevCursor = nil
    for _, cursor in ipairs(state.cursors) do
        if cursor._state ~= CursorState.deleted then
            cursorCheckUpdate(cursor)
            if cursor._pos[2] < pos[1]
                or cursor._pos[2] == pos[1]
                and (cursor._pos[3] + cursor._pos[4]) < (pos[2] + offset)
            then
                if not prevCursor
                    or compareCursorsPosition(prevCursor, cursor)
                then
                    prevCursor = cursor
                end
            end
        end
    end
    return prevCursor
end

--- Returns the nearest cursor to pos, and accepts a cursor exactly at pos.
--- It is guarenteed to find a cursor.
--- @param pos SimplePos
--- @param offset? integer
--- @return Cursor
function CursorContext:nearestCursor(pos, offset)
    offset = offset or 0
    local nearestCursor = nil
    local nearestColDist = 0
    local nearestRowDist = 0
    for _, cursor in ipairs(state.cursors) do
        if cursor._state ~= CursorState.deleted then
            cursorCheckUpdate(cursor)
            local rowDist = math.abs(cursor._pos[2] - pos[1])
            local colDist = math.abs(
                (cursor._pos[3] + cursor._pos[4]) - (pos[2] + offset))
            if not nearestCursor
                or rowDist < nearestRowDist
                or rowDist == nearestRowDist
                and colDist < nearestColDist
            then
                nearestCursor = cursor
                nearestColDist = colDist
                nearestRowDist = rowDist
            end
        end
    end
    return nearestCursor or self:mainCursor()
end

--- @param pos SimplePos
--- @param offset? number
--- @return Cursor | nil
function CursorContext:getCursorAtPos(pos, offset)
    for _, cursor in ipairs(state.cursors) do
        if cursor._state ~= CursorState.deleted
            and cursor._pos[2] == pos[1]
            and cursor._pos[3] == pos[2]
            and (not offset or cursor._pos[4] == offset)
        then
            return cursor
        end
    end
end

--- Returns the cursor under the main cursor
--- @return Cursor | nil
function CursorContext:overlappedCursor()
    local mainCursor = self:mainCursor()
    local overlappedCursor = self:getCursorAtPos(mainCursor:getPos())
    if overlappedCursor ~= mainCursor then
        return overlappedCursor
    end
end

--- Returns the main cursor (the real one).
--- @return Cursor
function CursorContext:mainCursor()
    if not state.mainCursor then
        state.mainCursor = tbl.find(state.cursors, function(cursor)
            return cursor._state ~= CursorState.deleted
        end)
        if not state.mainCursor then
            state.mainCursor = cursorRead(createCursor({}))
        end
        state.cursors[#state.cursors + 1] = state.mainCursor
    end
    return state.mainCursor
end

--- Returns the cursor closest to the start of the document.
--- Guarenteed to find a cursor.
--- @return Cursor
function CursorContext:firstCursor()
    local firstCursor
    for _, cursor in ipairs(state.cursors) do
        if cursor._state ~= CursorState.deleted then
            cursorCheckUpdate(cursor)
            if not firstCursor
                or compareCursorsPosition(cursor, firstCursor)
            then
                firstCursor = cursor
            end
        end
    end
    return firstCursor
end

--- Returns the cursor closest to the end of the document.
--- Guarenteed to find a cursor.
--- @return Cursor
function CursorContext:lastCursor()
    local lastCursor
    for i = #state.cursors, 1, -1 do
        local cursor = state.cursors[i]
        if cursor._state ~= CursorState.deleted then
            cursorCheckUpdate(cursor)
            if not lastCursor
                or compareCursorsPosition(lastCursor, cursor)
            then
                lastCursor = cursor
            end
        end
    end
    return lastCursor
end

--- Returns this cursors current line number, 1 indexed.
--- @return integer
function Cursor:line()
    cursorCheckUpdate(self)
    return self._pos[2]
end

--- Returns this cursors current column number, 1 indexed.
--- @return integer
function Cursor:col()
    cursorCheckUpdate(self)
    return self._pos[3]
end

--- Returns the full line text of where this cursor is located.
--- @return string
function Cursor:getLine()
    cursorCheckUpdate(self)
    return get_lines(
        0, self._pos[2] - 1, self._pos[2], true)[1]
end

--- Deletes this cursor.
--- If this is the main cursor then the closest cursor to it.
--- is set as the new main cursor.
--- If this is the last remaining cursor, a new cursor is created
--- at its position.
function Cursor:delete()
    self._state = CursorState.deleted
    if self == state.mainCursor then
        cursorContextSetMainCursor(
            CursorContext:nearestCursor(self:getPos()))
    end
end

--- Sets this cursor as the main cursor (the real one).
--- @return self
function Cursor:select()
    cursorContextSetMainCursor(self)
    return self
end

--- Returns whether this cursor is the main cursor (the real one).
--- @return boolean
function Cursor:isMainCursor()
    return self == state.mainCursor
end

--- A cursor can either be at the start or end of a visual selection.
--- For example, if you select lines 10-20, your cursor can either be
--- on line 10 (start) or 20 (end). this method returns true when at
--- the start.
--- @return boolean
function Cursor:atVisualStart()
    return self._pos[2] < self._vPos[2]
        or self._pos[2] == self._vPos[2]
        and self._pos[3] <= self._vPos[3]
end

--- For each line of the cursor's visual selection, a new cursor is
--- created, visually selecting only the single line.
--- This method deletes the original cursor.
--- @return Cursor[]
function Cursor:splitVisualLines()
    cursorCheckUpdate(self)
    local visualInfo = VISUAL_LOOKUP[self._mode]
    if visualInfo then
        local newCursors = visualInfo.split(self)
        self:delete()
        return newCursors
    end
    return {}
end

--- @return SimplePos, integer
function Cursor:getPos()
    cursorCheckUpdate(self)
    return {self._pos[2], self._pos[3]}, self._pos[4]
end

--- @param pos SimplePos
--- @param offset? number
--- @return self
function Cursor:setPos(pos, offset)
    cursorCheckUpdate(self)
    self._pos = { self._pos[0], pos[1], pos[2], offset or 0, pos[2] }
    cursorSetMarks(self)
    return self
end

--- @param pos SimplePos
--- @param offset? integer
--- @return self
function Cursor:setVisualAnchor(pos, offset)
    cursorCheckUpdate(self)
    self._vPos = { 0, pos[1], pos[2], offset or 0, pos[2] }
    cursorSetMarks(self)
    return self
end

--- @param cursor Cursor
local function cursorCopy(cursor)
    return createCursor({
        _id = state.id,
        _modifiedId = state.modifiedId,
        _drift = cursor._drift,
        _changePos = cursor._changePos,
        _pos = cursor._pos,
        _register = cursor._register,
        _search = cursor._search,
        _visual = cursor._visual,
        _vPos = cursor._vPos,
        _mode = cursor._mode,
        _state = CursorState.new,
    })
end

--- @param cursors Cursor[]
--- @param mainCursor Cursor
--- @return number[]
local function packCursors(mainCursor, cursors)
    local data = {}
    data[1] = mainCursor._id
    data[2] = mainCursor._changePos[2]
    data[3] = mainCursor._changePos[3]
    local i = 4
    for _, cursor in ipairs(cursors) do
        data[i] = cursor._id
        data[i + 1] = cursor._changePos[2]
        data[i + 2] = cursor._changePos[3]
        i = i + 3
    end
    return data
end

--- @param data number[]
--- @param mainCursor Cursor
--- @param cursors Cursor[]
--- @return Cursor, Cursor[]
local function unpackCursors(data, mainCursor, cursors)
    local cursorLookup = { [mainCursor._id] = mainCursor }
    for _, cursor in ipairs(cursors) do
        cursorLookup[cursor._id] = cursor
    end
    local newCursors = {}
    local newMainCursor
    for i = 1, #data, 3 do
        local cursor = cursorLookup[data[i]] or cursorCopy(mainCursor)
        local col = math.min(data[i + 2], #get_lines(0, data[i + 1] - 1, data[i + 1], true)[1])
        cursor._pos = { 0, data[i + 1], col, 0, col }
        cursor._vPos = cursor._pos
        cursor._changePos = cursor._pos
        cursor._modifiedId = state.modifiedId
        if i == 1 then
            newMainCursor = cursor
        else
            newCursors[#newCursors + 1] = cursor
        end
    end
    return newMainCursor, newCursors
end

--- Returns a new cursor with the same position, registers,
--- visual selection, and mode as this cursor.
--- @return Cursor
function Cursor:clone()
    cursorCheckUpdate(self)
    local cursor = cursorCopy(self)
    cursorSetMarks(cursor)
    state.cursors[#state.cursors + 1] = cursor
    return cursor
end

--- Returns only the text contained in each line of the visual selection.
--- @return string[]
function Cursor:getVisualLines()
    cursorCheckUpdate(self)
    local vPos = self._vPos
    if vPos[3] == 0 then
        vPos = { table.unpack(vPos) }
        vPos[3] = 1
    end
    return vim.fn.getregion(vPos, self._pos, {
        type = VISUAL_LOOKUP[self._mode].visual,
        exclusive = false
    })
end

--- Returns the full line for each line of the visual selection.
--- @return string[]
function Cursor:getFullVisualLines()
    cursorCheckUpdate(self)
    local visualStart, visualEnd = self:getVisual()
    return get_lines(
        0, visualStart[1] - 1, visualEnd[1], true)
end

--- Returns start and end positions of visual selection start position
--- is before or equal to end position.
--- @return SimplePos, SimplePos
function Cursor:getVisual()
    cursorCheckUpdate(self)
    if self:inVisualMode() then
        if self:atVisualStart() then
            return
                {self._pos[2], self._pos[3]},
                {self._vPos[2], self._vPos[3]}
        else
            return
                {self._vPos[2], self._vPos[3]},
                {self._pos[2], self._pos[3]}
        end
    end
    return
        {self._visual[1][2], self._visual[1][3]},
        {self._visual[2][2], self._visual[2][3]}
end

--- Returns this cursor's current mode.
--- It should only ever be in normal, visual, or select modes.
--- @return string: "n" | "v" | "V" | <c-v> | "s" | "S" | <c-s>
function Cursor:mode()
    return self._mode
end

--- Sets this cursor's mode.
--- It should only ever be in normal, visual, or select modes.
--- @param mode string: "n" | "v" | "V" | <c-v> | "s" | "S" | <c-s>
--- @return self
function Cursor:setMode(mode)
    self._state = CursorState.dirty
    self._mode = mode
    return self
end

--- Makes the cursor perform a command/commands.
--- For example, cursor:feedkeys('dw') will delete a word.
--- By default, keys are not remapped and keycodes are not parsed.
--- @param keys string
--- @param opts? { remap?: boolean, keycodes?: boolean }
function Cursor:feedkeys(keys, opts)
    cursorCheckUpdate(self)
    state.modifiedId = state.modifiedId + 1
    self._modifiedId = state.modifiedId
    self._state = CursorState.dirty
    cursorWrite(self)
    local success, err = pcall(feedkeys, keys, opts)
    state.numLines = vim.fn.line("$")
    if success then
        cursorRead(self)
        cursorSetMarks(self)
    else
        util.echoerr(err)
    end
end

--- Sets the visual selection and sets the cursor position to `visualEnd`.
--- @param visualStart SimplePos
--- @param visualEnd SimplePos
--- @return self
function Cursor:setVisual(visualStart, visualEnd)
    cursorCheckUpdate(self)
    local atVisualEnd = visualStart[1] > visualEnd[1]
        or visualStart[1] == visualEnd[1]
        and visualStart[2] > visualEnd[2]
    self._visual = atVisualEnd
        and {
            { self._visual[2][1], visualEnd[1], visualEnd[2], 0 },
            { self._visual[1][1], visualStart[1], visualStart[2], 0 },
        }
        or {
            { self._visual[1][1], visualStart[1], visualStart[2], 0 },
            { self._visual[2][1], visualEnd[1], visualEnd[2], 0 },
        }
    if self:inVisualMode() then
        local nvs = self._visual[1]
        local nve = self._visual[2]
        if atVisualEnd then
            self._pos = { self._pos[1], nvs[2], nvs[3], nvs[4], nvs[3]  }
            self._vPos = { self._pos[1], nve[2], nve[3], nve[4], nve[3]  }
        else
            self._vPos = { self._pos[1], nvs[2], nvs[3], nvs[4], nvs[3]  }
            self._pos = { self._pos[1], nve[2], nve[3], nve[4], nve[3]  }
        end
    end
    self._state = CursorState.dirty
    cursorSetMarks(self)
    return self
end

--- Returns true if in visual or select mode.
--- @return boolean
function Cursor:inVisualMode()
    return not not VISUAL_LOOKUP[self._mode]
end

--- When cursors are disabled, only the main cursor can be interacted with.
--- @return boolean
function CursorContext:cursorsEnabled()
    return state.enabled
end

--- @param mainCursor Cursor
local function cursorContextMergeCursors(mainCursor)
    --- @type Cursor[]
    local newCursors = {}
    for _, cursor in ipairs(state.cursors) do
        cursorCheckUpdate(cursor)
        local exists = false
        if state.enabled
            and cursor._pos[2] == mainCursor._pos[2]
            and cursor._pos[3] == mainCursor._pos[3]
            and cursor._pos[4] == mainCursor._pos[4]
        then
            exists = true
        else
            for _, c in ipairs(newCursors) do
                if cursor._pos[2] == c._pos[2]
                    and cursor._pos[3] == c._pos[3]
                    and cursor._pos[4] == c._pos[4]
                then
                    exists = true
                    break
                end
            end
        end
        if exists then
            cursorErase(cursor)
            cursorClearMarks(cursor)
        else
            newCursors[#newCursors + 1] = cursor
        end
    end
    state.cursors = newCursors
end

function CursorContext:hasCursors()
    return #state.cursors > 0
        or #state.cursors == 1
        and state.cursors[1] ~= state.mainCursor
end

function CursorContext:clear()
    clear_namespace(0, state.nsid, 0, -1)
    if state.clipboard then
        vim.o.clipboard = state.clipboard
        state.clipboard = nil
    end
    state.enabled = true
    state.cursors = {}
    if state.shallowUndo then
        state.undoItems = {}
        state.redoItems = {}
    end
end

--- @param cursor Cursor
local function cursorApplyDrift(cursor)
    if not cursor._changePos then
        cursor._changePos = cursor._pos
    else
        cursor._changePos = { table.unpack(cursor._changePos) }
        cursor._changePos[2] = cursor._changePos[2] - cursor._drift[1]
        cursor._changePos[3] = cursor._changePos[3] - cursor._drift[2]
    end
    return cursor
end

--- @package
--- @param mainCursor Cursor
--- @param applyToMainCursor boolean
local function cursorContextUpdate(mainCursor, applyToMainCursor)
    state.mainCursor = mainCursor
    cursorContextMergeCursors(mainCursor)
    if not state.currentSeq then
        local undoTree = vim.fn.undotree()
        state.currentSeq = undoTree.seq_cur
    else
        local undoTree = vim.fn.undotree()
        if undoTree.seq_cur and state.currentSeq ~= undoTree.seq_cur then
            mainCursor._changePos = mainCursor._origChangePos
            if applyToMainCursor then
                cursorApplyDrift(mainCursor)
            end
            for _, cursor in ipairs(state.cursors) do
                cursorApplyDrift(cursor)
            end
            local undoItem = #state.cursors > 0 and {
                data = packCursors(mainCursor, state.cursors),
                enabled = state.enabled
            } or nil
            state.undoItems[undoItemId(state.currentSeq)] = undoItem
            state.redoItems[undoItemId(undoTree.seq_cur)] = undoItem
            state.currentSeq = undoTree.seq_cur
        end
        for _, cursor in ipairs(state.cursors) do
            cursor._changePos = cursor._changePos
                or cursor._origChangePos
        end
        state.mainCursor._changePos = state.mainCursor._changePos
            or state.mainCursor._origChangePos
    end
    if #state.cursors == 0 then
        CursorContext:clear()
    end
end

local function cursorContextRedraw()
    clear_namespace(0, state.nsid, 0, -1)
    for _, cursor in ipairs(state.cursors) do
        cursorSetMarks(cursor)
        cursorDraw(cursor)
    end
end

--- @class CursorManager
local CursorManager = {}

--- @param nsid integer
--- @param shallowUndo boolean
function CursorManager:setup(nsid, shallowUndo)
    state.nsid = nsid
    state.shallowUndo = shallowUndo
    vim.api.nvim_create_autocmd("BufEnter", {
        pattern = "*",
        callback = function()
            state.currentSeq = vim.fn.undotree().seq_cur
            state.numLines = vim.fn.line("$")
        end
    })
end

function CursorManager:update()
    state.mainCursor = state.mainCursor or createCursor({})
    cursorRead(state.mainCursor)
    local oldLeftCol = state.leftcol
    state.leftcol = vim.fn.winsaveview().leftcol
    if oldLeftCol > 0 or state.leftcol > 0 then
        for _, cursor in ipairs(state.cursors) do
            cursorErase(cursor)
            cursorDraw(cursor)
        end
    end
    cursorContextUpdate(state.mainCursor, false)
end

--- @param callback fun(context: CursorContext)
--- @param applyToMainCursor boolean
function CursorManager:action(callback, applyToMainCursor)
    if state.clipboard == nil then
        state.clipboard = vim.o.clipboard
        vim.o.clipboard = ""
    end
    state.leftcol = vim.fn.winsaveview().leftcol
    state.textoffset = vim.fn.getwininfo(vim.fn.win_getid())[1].textoff
    state.virtualEditBlock = false
    for _, key in ipairs(vim.opt.virtualedit:get()) do
        if key == "block" or key == "all" then
            state.virtualEditBlock = true
            break
        end
    end
    local origRegName = vim.v.register
    local origCursor = state.mainCursor or createCursor({})
    state.mainCursor = origCursor
    cursorRead(state.mainCursor)
    local winStartLine = vim.fn.line("w0")
    cursorSetMarks(state.mainCursor)
    if applyToMainCursor then
        state.cursors[#state.cursors + 1] = origCursor
    else
        origCursor._origChangePos = origCursor._changePos
        origCursor._changePos = nil
        origCursor._state = CursorState.none
        origCursor._drift = { 0, 0 }
    end
    for _, cursor in ipairs(state.cursors) do
        cursor._origChangePos = cursor._changePos
        cursor._changePos = nil
        cursor._state = CursorState.none
        cursor._drift = { 0, 0 }
    end
    local result = callback(CursorContext)

    state.mainCursor = CursorContext:mainCursor()
    if not state.mainCursor:inVisualMode() then
        state.mainCursor._mode = "n"
    end
    cursorCheckUpdate(state.mainCursor)
    cursorErase(state.mainCursor)
    cursorClearMarks(state.mainCursor)
    cursorWrite(state.mainCursor)
    if state.mainCursor == origCursor then
        local newStartLine = vim.fn.line("w0")
        local newEndLine = vim.fn.line("w$")
        local rowDelta = math.max(
            newStartLine - origCursor._pos[2],
            math.min(
                newEndLine - origCursor._pos[2],
                newStartLine - winStartLine - origCursor._drift[1]
            )
        )
        if rowDelta < 0 then
            feedkeys(math.abs(rowDelta) .. TERM_CODES.CTRL_E)
        elseif rowDelta > 0 then
            feedkeys(rowDelta .. TERM_CODES.CTRL_Y)
        end
        -- i would also update leftcol here, but vim.fn.winsaveview()
        -- is returning outdated values. probably a neovim bug
    end
    if state.enabled then
        for _, cursor in ipairs(state.cursors) do
            cursor._mode = state.mainCursor._mode
        end
    end
    state.mainCursor._state = CursorState.deleted
    for _, cursor in ipairs(state.cursors) do
        if cursor._state == CursorState.deleted then
            cursorErase(cursor)
            cursorClearMarks(cursor)
        elseif cursor._state == CursorState.new then
            cursorCheckUpdate(cursor)
            cursorDraw(cursor)
        elseif cursor._state == CursorState.dirty then
            cursorCheckUpdate(cursor)
            cursorErase(cursor)
            cursorDraw(cursor)
        end
    end
    state.cursors = tbl.filter(state.cursors, function(cursor)
        return cursor._state ~= CursorState.deleted
    end)
    cursorContextUpdate(state.mainCursor, applyToMainCursor)
    vim.fn.setreg(origRegName, state.mainCursor._register)
    return result
end

--- @param direction -1 | 1
function CursorManager:loadUndoItem(direction)
    local undoTree = vim.fn.undotree()
    local id = undoItemId(undoTree.seq_cur)
    if state.currentSeq == undoTree.seq_cur then
        return
    end
    state.currentSeq = undoTree.seq_cur
    local lookup = direction == 1 and state.redoItems or state.undoItems
    local undoItem = lookup[id];
    if not undoItem then
        CursorContext:clear()
        return
    end
    state.enabled = undoItem.enabled
    state.mainCursor, state.cursors = unpackCursors(
        undoItem.data, state.mainCursor, state.cursors)
    cursorContextMergeCursors(state.mainCursor)
    if #state.cursors == 0 then
        CursorContext:clear()
    else
        cursorContextRedraw()
    end
    cursorWrite(state.mainCursor)
end

function CursorManager:dirty()
    state.modifiedId = state.modifiedId + 1
    state.numLines = vim.fn.line("$")
end

function CursorManager:cursorsEnabled()
    return CursorContext:cursorsEnabled()
end

function CursorManager:hasCursors()
    return CursorContext:hasCursors()
end

function CursorManager:clear()
    CursorContext:clear()
end

return CursorManager
