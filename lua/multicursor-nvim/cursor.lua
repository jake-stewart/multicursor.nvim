local TERM_CODES = require("multicursor-nvim.term-codes")
local tbl = require("multicursor-nvim.tbl")
local util = require("multicursor-nvim.util")
local apply_langmap = require("multicursor-nvim.langmap")

local set_extmark = vim.api.nvim_buf_set_extmark
local del_extmark = vim.api.nvim_buf_del_extmark
local replace_termcodes = vim.api.nvim_replace_termcodes
local get_extmark = vim.api.nvim_buf_get_extmark_by_id

--- @type mc.State
local state

--- @param buffer integer
--- @param startLine integer
--- @param endLine integer
--- @return string[]
local function get_lines(buffer, startLine, endLine)
    local lines = vim.api.nvim_buf_get_lines(buffer, startLine, endLine, true)
    for i, line in ipairs(lines) do
        if vim.fn.type(line) == vim.v.t_blob then
            lines[i] = vim.fn.string(line)
        end
    end
    return lines
end

--- @param mode string
--- @return boolean
local function isVisualMode(mode)
    return mode == "v"
        or mode == "V"
        or mode == TERM_CODES.CTRL_V
end

--- @param mode string
--- @return boolean
local function isSelectMode(mode)
    return mode == "s"
        or mode == "S"
        or mode == TERM_CODES.CTRL_S
end

--- @param keys string
--- @param opts? { remap?: boolean, keycodes?: boolean, silent?: boolean }
local function feedkeys(keys, opts)
    local mode = opts and opts.remap and "x" or "xn"
    if opts and opts.keycodes then
        keys = replace_termcodes(keys, true, true, true)
    end
    keys = apply_langmap(keys)
    keys = vim.fn.substitute(keys, "'", "'..\"'\"..'", "g")
    local cmd = (opts and opts.silent and "silent " or "")
        .. "keepjumps call feedkeys('" .. keys .. "', '" .. mode .. "')"
    if state.native then
        vim.fn.inputsave()
        local success, err = pcall(vim.cmd, cmd)
        vim.fn.inputrestore()
        if not success then
            error(err, 0)
        end
    else
        vim.cmd(cmd)
    end
end

--- @param a mc.MarkPos
--- @param b mc.MarkPos
--- @return boolean
local function compareMarkPos(a, b)
    if a[2] == b[2] then
        if a[3] == b[3] then
            return a[4] < b[4]
        end
        return a[3] < b[3]
    end
    return a[2] < b[2]
end

--- @param a mc.Cursor
--- @param b mc.Cursor
--- @return boolean
local function compareCursorsPosition(a, b)
    return compareMarkPos(a._pos, b._pos)
end

--- See :h getcurpos()
--- @alias mc.CursorPos [integer, integer, integer, integer, integer]

--- See :h getpos()
--- @alias mc.MarkPos [integer, integer, integer, integer]

--- 1-indexed line, 1-indexed col, virtualedit offset
--- @alias mc.Pos [integer, integer, integer]

--- 1-indexed line, 1-indexed col
--- @alias mc.SimplePos [integer, integer]

--- @class mc.CursorQuery
--- @field enabledCursors? boolean (default true)
--- @field disabledCursors? boolean (default false)

--- @enum mc.CursorState
local CursorState = {
    none = 0,
    dirty = 1,
    new = 2,
    deleted = 3,
}

--- @class mc.Cursor
--- @field package _id              integer
--- @field package _modifiedId      integer
--- @field package _enabled         boolean
--- @field package _state           mc.CursorState
--- @field package _changePos       mc.MarkPos
--- @field package _redoChangePos   mc.MarkPos
--- @field package _origChangePos   mc.MarkPos
--- @field package _undoRegistered  boolean | nil
--- @field package _origPos         mc.CursorPos
--- @field package _origVPos        mc.MarkPos
--- @field package _origRegister    table | nil
--- @field package _drift           [integer, integer]
--- @field package _pos             mc.CursorPos
--- @field package _register        table
--- @field package _search          string
--- @field package _visualStart     mc.MarkPos
--- @field package _visualEnd       mc.MarkPos
--- @field package _vPos            mc.MarkPos
--- @field package _mode            string
--- @field package _posId           integer | nil
--- @field package _changePosId     integer | nil
--- @field package _vPosId          integer | nil
local Cursor = {}
Cursor.__index = Cursor

--- @package
--- @class mc.State
--- @field native? boolean
--- @field mainCursor mc.Cursor | nil
--- @field modifiedId integer
--- @field cursors mc.Cursor[]
--- @field options? table
--- @field nsid integer
--- @field numLines number
--- @field numDisabledCursors number
--- @field numEnabledCursors number
--- @field exclusive boolean
--- @field opts mc.MultiCursorOpts
state = {
    cursors = {},
    errors = {},
    numDisabledCursors = 0,
    numEnabledCursors = 0,
    id = 1,
    modifiedId = 0,
    nsid = 0,
    numLines = 0,
}

local OPTIONS_OVERRIDE = {
    timeout = false,
    clipboard = ""
}

local function setOptions()
    if not state.options then
        state.origRegister = vim.v.register
        state.options = {}
        for key, value in pairs(OPTIONS_OVERRIDE) do
            state.options[key] = vim.o[key]
            vim.o[key] = value
        end
    end
end

local function unsetOptions()
    if state.options then
        for key, value in pairs(state.options) do
            vim.o[key] = value
        end
        state.options = nil
    end
end

--- @type boolean?
local saved_hlSearch = nil

local function setHlsearch()
    if not state.opts.hlsearch then
        if saved_hlSearch == nil then
            saved_hlSearch = vim.o.hlsearch
            vim.o.hlsearch = false
        end
    end
end

local function unsetHlsearch()
    if not state.opts.hlsearch then
        if saved_hlSearch then
            vim.o.hlsearch = true
            vim.schedule(vim.cmd.noh)
        end
        saved_hlSearch = nil
    end
end

--- @param cursor table
--- @param newId? boolean = true
--- @return mc.Cursor
local function createCursor(cursor, newId)
    if newId ~= false then
        cursor._id = state.id
        state.id = state.id + 1
    end
    cursor._enabled = true
    cursor._drift = { 0, 0 }
    if not state.native then
        cursor._jumpIdx = 0
        cursor._jumps = {}
    end
    return setmetatable(cursor, Cursor)
end

--- @param id integer Extmark ID
--- @return vim.api.keyset.get_extmark_item_by_id|nil
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

--- @param cursor mc.Cursor
local function cursorReset(cursor)
    cursor._origPos = cursor._pos
    cursor._origVPos = cursor._vPos
    cursor._origChangePos = cursor._changePos
    if state.native then
        cursor._origRegister = cursor._register
    end
    cursor._undoRegistered = false
    cursor._changePos = nil
    cursor._state = CursorState.none
    cursor._drift = { 0, 0 }
end

--- @param cursor mc.Cursor
--- @param target mc.Cursor
local function cursorCopyMode(cursor, target)
    if cursor._mode == target._mode then
        return
    end
    if target._mode == "n" and cursor:hasSelection() then
        if not cursor:atVisualStart() then
            cursor:feedkeys("o" .. TERM_CODES.ESC)
        else
            cursor:feedkeys(TERM_CODES.ESC)
        end
    end
    cursor._mode = target._mode
end

--- @param cursor mc.Cursor
local function cursorUpdatePos(cursor)
    local oldPos = cursor._pos
    cursor._modifiedId = state.modifiedId

    if cursor._posId then
        local mark = safeGetExtmark(cursor._posId)
        if mark then
            local curswantVirtcol = vim.fn.virtcol(
                { mark[1] + 1, mark[2] + 1 })
            cursor._pos = {
                cursor._pos[1],
                mark[1] + 1,
                mark[2] + 1,
                cursor._pos[4],
                mark[2] + 1 == cursor._pos[3]
                    and cursor._pos[5]
                    or curswantVirtcol
            }
            cursor._drift[1] = cursor._drift[1] + (cursor._pos[2] - oldPos[2])
            cursor._drift[2] = cursor._drift[2] + (cursor._pos[3] - oldPos[3])
        else
            cursor._posId = nil
        end
    end

    if cursor._changePosId then
        local mark = safeGetExtmark(cursor._changePosId)
        if mark then
            cursor._redoChangePos = {
                0,
                mark[1] + 1,
                mark[2] + 1,
                0,
            }
        else
            cursor._changePosId = nil
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

--- @param cursor mc.Cursor
local function cursorCheckUpdate(cursor)
    if cursor._modifiedId ~= state.modifiedId then
        cursorUpdatePos(cursor)
    end
end

--- @param cursor mc.Cursor
--- @return mc.Cursor[]
local function cursorSplitVisualChar(cursor)
    local newCursors = {}
    local atVisualStart = cursor:atVisualStart()
    local visualStart, visualEnd = cursor:getVisual()
    local lines = get_lines(0, visualStart[1] - 1, visualEnd[1])
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

--- @param cursor mc.Cursor
--- @return mc.Cursor[]
local function cursorSplitVisualLine(cursor)
    local newCursors = {}
    local visualStart, visualEnd = cursor:getVisual()
    local lines = get_lines(0, visualStart[1] - 1, visualEnd[1])
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

--- @param cursor mc.Cursor
--- @return mc.Cursor[]
local function cursorSplitVisualBlock(cursor)
    local newCursors = {}
    local atVisualStart = cursor:atVisualStart()
    local visualStart, visualEnd = cursor:getVisual()
    local atEndOfLine = cursor._pos[5] == vim.v.maxcol
    for i = visualStart[1], visualEnd[1] do
        local newCursor = cursor:clone()
        newCursors[#newCursors + 1] = newCursor
        local visualEndCol = atEndOfLine
            and #get_lines(0, i - 1, i)[1]
            or visualEnd[2]
        if atVisualStart then
            newCursor:setVisual(
                { i, visualEndCol },
                { i, visualStart[2] }
            )
        else
            newCursor:setVisual(
                { i, visualStart[2] },
                { i, visualEndCol }
            )
        end
        newCursor._mode = "v"
    end
    return newCursors
end

--- @alias mc._CursorSplitFunc fun(cursor: mc.Cursor): mc.Cursor[]

--- @class mc._VisualInfo
--- @field type string
--- @field enterVisualKey string
--- @field enterSelectKey string
--- @field split mc._CursorSplitFunc
local VISUAL_LOOKUP = {
    v = {
        type = "c",
        enterVisualKey = "v",
        enterSelectKey = "",
        split = cursorSplitVisualChar,
    },
    V = {
        type = "l",
        enterVisualKey = "V",
        enterSelectKey = "",
        split = cursorSplitVisualLine,
    },
    [TERM_CODES.CTRL_V] = {
        type = "b",
        enterVisualKey = TERM_CODES.CTRL_V,
        enterSelectKey = "",
        split = cursorSplitVisualBlock,
    },
    s = {
        type = "c",
        enterVisualKey = "v",
        enterSelectKey = TERM_CODES.CTRL_G,
        split = cursorSplitVisualChar,
    },
    S = {
        type = "l",
        enterVisualKey = "V",
        enterSelectKey = TERM_CODES.CTRL_G,
        split = cursorSplitVisualLine,
    },
    [TERM_CODES.CTRL_S] = {
        type = "b",
        enterVisualKey = TERM_CODES.CTRL_V,
        enterSelectKey = TERM_CODES.CTRL_G,
        split = cursorSplitVisualBlock,
    },
}

--- @param cursor mc.Cursor
local function cursorClearMarks(cursor)
    if cursor._posId then
        del_extmark(0, state.nsid, cursor._posId)
        cursor._posId = nil
    end
    if cursor._vPosId then
        del_extmark(0, state.nsid, cursor._vPosId)
        cursor._vPosId = nil
    end
    if cursor._changePosId then
        del_extmark(0, state.nsid, cursor._changePosId)
        cursor._changePosId = nil
    end
end

--- @param cursor mc.Cursor
local function cursorSetMarks(cursor)
    cursorClearMarks(cursor)
    local opts = { strict = false, undo_restore = false }
    if cursor:hasSelection() then
        cursor._vPosId = set_extmark(
            0,
            state.nsid,
            cursor._vPos[2] - 1,
            cursor._vPos[3] - 1,
            opts
        )
    end
    if cursor._redoChangePos and cursor._redoChangePos[2] > 0 then
        cursor._changePosId = set_extmark(
            0,
            state.nsid,
            cursor._redoChangePos[2] - 1,
            cursor._redoChangePos[3] - 1,
            opts
        )
    end
    local posOpts = opts
    if not state.native then
        posOpts = { strict = false, undo_restore = true }
    end
    cursor._posId = set_extmark(
        0,
        state.nsid,
        cursor._pos[2] - 1,
        cursor._pos[3] - 1,
        posOpts
    )
end

--- @param cursor mc.Cursor
--- @return mc.Cursor
local function cursorRead(cursor)
    cursor._mode = vim.fn.mode()
    cursor._pos = vim.fn.getcurpos()
    cursor._vPos = vim.fn.getpos("v")
    cursor._changePos = vim.fn.getpos("'[")
    cursor._redoChangePos = cursor._changePos
    cursor._modifiedId = state.modifiedId
    cursor._register = vim.fn.getreginfo("")
    cursor._search = vim.fn.getreg("/")
    if cursor._mode == "n" or not cursor._visualStart then
        cursor._visualStart = vim.fn.getpos("'<")
        cursor._visualEnd = vim.fn.getpos("'>")
    end
    return cursor
end

--- @param cursor mc.Cursor
local function cursorWrite(cursor)
    cursor._register.points_to = nil
    vim.fn.setreg("", cursor._register)
    vim.fn.setreg("/", cursor._search)
    local mode = vim.fn.mode()
    if mode ~= "n" then
        feedkeys(TERM_CODES.ESC)
    end
    vim.fn.setpos("'<", cursor._visualStart)
    vim.fn.setpos("'>", cursor._visualEnd)
    local visualInfo = VISUAL_LOOKUP[cursor._mode]
    if visualInfo then
        feedkeys(visualInfo.enterVisualKey)
        vim.fn.setpos(".", cursor._vPos)
        feedkeys("o")
        vim.fn.setpos(".", cursor._pos)
        local buffer = {}
        if cursor._pos[5] == vim.v.maxcol then
            buffer[#buffer + 1] = "$"
        end
        if #visualInfo.enterSelectKey > 0 then
            buffer[#buffer + 1] = visualInfo.enterSelectKey
        end
        if #buffer > 0 then
            feedkeys(table.concat(buffer))
        end
    elseif cursor._mode == "n" then
        if mode ~= "n" then
            feedkeys(TERM_CODES.ESC)
        end
        vim.fn.setpos(".", cursor._pos)
    else
        error("unexpected mode:" .. mode)
    end
    if not cursor._changePos then
        if cursor:atVisualStart() then
            cursor._changePos = cursor._pos
        else
            cursor._changePos = cursor._vPos
        end
        vim.fn.setpos("'[", cursor._changePos)
    end
end

--- @class mc.CursorContext
--- @field clear fun(self: mc.CursorContext) Removes all cursors.
--- @field restore fun(self: mc.CursorContext) Restores the last cleared cursors.
local CursorContext = {}

--- @param cursor mc.Cursor | nil
local function cursorContextSetMainCursor(cursor)
    if not state.native and state.mainCursor
        and state.mainCursor._state ~= CursorState.deleted
    then
        state.mainCursor._state = CursorState.dirty
    end
    state.mainCursor = cursor
end

--- Enables or disables all cursors
--- @param value boolean
function CursorContext:setCursorsEnabled(value)
    local buf = vim.api.nvim_get_current_buf()
    local reg = state.yankedWhileDisabled[buf]
        and vim.fn.getreginfo("")
    state.yankedWhileDisabled[buf] = nil
    for _, cursor in ipairs(state.cursors) do
        if cursor ~= state.mainCursor and cursor._enabled ~= value
            and cursor._state ~= CursorState.deleted
        then
            state.numDisabledCursors =
                state.numDisabledCursors + (value and -1 or 1)
            state.numEnabledCursors =
                state.numEnabledCursors + (value and 1 or -1)
            cursor._register = reg or cursor._register
            cursor._enabled = value
            cursor._state = CursorState.dirty
        end
    end
end

--- @generic T
--- @param value T | nil
--- @param defaultIfNil T
--- @return T
local function default(value, defaultIfNil)
    if value == nil then
        return defaultIfNil
    else
        return value
    end
end

--- Returns a list of cursors, sorted by their position.
--- @param opts? mc.CursorQuery
--- @return mc.Cursor[]
function CursorContext:getCursors(opts)
    local enabledCursors = default(opts and opts.enabledCursors, true)
    local disabledCursors = default(opts and opts.disabledCursors, false)
    local cursors = tbl.filter(state.cursors, function(cursor)
        return cursor._state ~= CursorState.deleted
            and (cursor._enabled == enabledCursors
                or (not cursor._enabled) == disabledCursors)
    end)
    table.sort(cursors, compareCursorsPosition)
    return cursors
end

--- Clones and returns the main cursor
--- @return mc.Cursor
function CursorContext:addCursor()
    return self:mainCursor():clone()
end

--- Util method which executes a callback for each cursor,
--- sorted by their position.
--- @param callback fun(cursor: mc.Cursor, i: integer, t: mc.Cursor[])
--- @param opts? mc.CursorQuery
function CursorContext:forEachCursor(callback, opts)
    tbl.forEach(self:getCursors(opts), callback)
end

--- Util method which maps each cursor to a value, sorted by their position.
--- @generic T
--- @param callback fun(cursor: mc.Cursor, i: integer, t: mc.Cursor[]): T
--- @param opts? mc.CursorQuery
--- @return T[]
function CursorContext:mapCursors(callback, opts)
    return tbl.map(self:getCursors(opts), callback)
end

--- Util method which returns the last cursor matching the predicate.
--- @param predicate fun(cursor: mc.Cursor, i: integer, t: mc.Cursor[]): any
--- @param opts? mc.CursorQuery
--- @return mc.Cursor | nil
function CursorContext:findLastCursor(predicate, opts)
    return tbl.findLast(self:getCursors(opts), predicate)
end

--- Util method which returns the first cursor matching the predicate.
--- @param predicate fun(cursor: mc.Cursor, i: integer, t: mc.Cursor[]): any
--- @param opts? mc.CursorQuery
--- @return mc.Cursor | nil
function CursorContext:findCursor(predicate, opts)
    return tbl.find(self:getCursors(opts), predicate)
end

--- Returns the closest cursor which appears AFTER pos.
--- A cursor exactly at pos will not be returned.
--- It does not wrap, so if none are found, then nil is returned.
--- If you wish to wrap, use `ctx:nextCursor(...) or ctx:firstCursor(...)`.
--- @param pos mc.SimplePos | mc.Pos
--- @param opts? mc.CursorQuery
--- @return mc.Cursor | nil
function CursorContext:nextCursor(pos, opts)
    local offset = pos[3] or 0
    return self:findCursor(function(cursor)
        cursorCheckUpdate(cursor)
        if cursor._pos[2] > pos[1]
            or cursor._pos[2] == pos[1]
            and (cursor._pos[3] + cursor._pos[4]) > (pos[2] + offset)
        then
            return cursor
        end
    end, opts)
end

--- Returns the closest cursor which appears BEFORE pos.
--- A cursor exactly at pos will not be returned.
--- It does not wrap, so if none are found, then nil is returned.
--- If you wish to wrap, use `ctx:prevCursor(...) or ctx:lastCursor(...)`.
--- @param pos mc.SimplePos | mc.Pos
--- @param opts? mc.CursorQuery
--- @return mc.Cursor | nil
function CursorContext:prevCursor(pos, opts)
    local offset = pos[3] or 0
    return self:findLastCursor(function(cursor)
        cursorCheckUpdate(cursor)
        if cursor._pos[2] < pos[1]
            or cursor._pos[2] == pos[1]
            and (cursor._pos[3] + cursor._pos[4]) < (pos[2] + offset)
        then
            return cursor
        end
    end, opts)
end

--- Returns the closest cursor in the specified direction
--- @param pos mc.SimplePos | mc.Pos
--- @param direction -1 | 1
--- @param wrap? boolean
--- @param opts? mc.CursorQuery
--- @return mc.Cursor | nil
function CursorContext:seekCursor(pos, direction, wrap, opts)
    local cursor
    if direction == -1 then
        cursor = self:prevCursor(pos, opts)
        if not cursor and wrap then
            cursor = self:lastCursor(opts)
        end
    else
        cursor = self:nextCursor(pos, opts)
        if not cursor and wrap then
            cursor = self:firstCursor(opts)
        end
    end
    return cursor
end

--- Returns the first/last cursor in the specified direction
--- @param direction -1 | 1
--- @param opts? mc.CursorQuery
--- @return mc.Cursor | nil
function CursorContext:seekBoundaryCursor(direction, opts)
    if direction == -1 then
        return self:firstCursor(opts)
    else
        return self:lastCursor(opts)
    end
end

--- Returns the nearest cursor to pos, and accepts a cursor exactly at pos.
--- @param pos mc.SimplePos | mc.Pos
--- @param opts? mc.CursorQuery
--- @return mc.Cursor | nil
function CursorContext:nearestCursor(pos, opts)
    local offset = pos[3] or 0
    local nearestCursor = nil
    local nearestColDist = 0
    local nearestRowDist = 0
    CursorContext:forEachCursor(function(cursor)
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
    end, opts)
    return nearestCursor
end

--- Returns the exact cursor at pos.
--- @param pos mc.SimplePos | mc.Pos
--- @param opts? mc.CursorQuery
--- @return mc.Cursor | nil
function CursorContext:getCursorAtPos(pos, opts)
    return self:findCursor(function(cursor)
        return cursor._pos[2] == pos[1]
            and cursor._pos[3] == pos[2]
            and (not pos[3] or cursor._pos[4] == pos[3])
    end, opts)
end

--- Returns the cursor under the main cursor
--- @return mc.Cursor | nil
function CursorContext:overlappedCursor()
    util.warnOnce(
        "ctx:overlappedCursor",
        "ctx:overlappedCursor() is deprecated. "
            .. "Use ctx:mainCursor():overlappedCursor() instead"
    )
    return self:mainCursor():overlappedCursor()
end

--- Returns the main cursor.
--- @return mc.Cursor
function CursorContext:mainCursor()
    if not state.mainCursor then
        state.mainCursor = tbl.find(state.cursors, function(cursor)
            return cursor._state ~= CursorState.deleted and cursor._enabled
        end)
        if not state.mainCursor then
            state.mainCursor = cursorRead(createCursor({}))
            state.cursors[#state.cursors + 1] = state.mainCursor
        end
        state.mainCursor:enable()
    end
    return state.mainCursor
end

--- Returns the cursor closest to the start of the document.
--- @param opts? mc.CursorQuery
--- @return mc.Cursor | nil
function CursorContext:firstCursor(opts)
    return self:findCursor(function() return true end, opts)
end

--- Returns the cursor closest to the end of the document.
--- @param opts? mc.CursorQuery
--- @return mc.Cursor | nil
function CursorContext:lastCursor(opts)
    return self:findLastCursor(function() return true end, opts)
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
    return get_lines(0, self._pos[2] - 1, self._pos[2])[1]
end

--- Deletes this cursor.
--- If this is the main cursor then the closest cursor to it.
--- is set as the new main cursor.
--- If this is the last remaining cursor, a new cursor is created
--- at its position.
function Cursor:delete()
    if self._state ~= CursorState.deleted then
        cursorCheckUpdate(self)
        if self ~= state.mainCursor then
            if self._enabled then
                state.numEnabledCursors = state.numEnabledCursors - 1
            else
                state.numDisabledCursors = state.numDisabledCursors - 1
                if not state.native and state.numDisabledCursors == 0 then
                    for _, cursor in ipairs(state.cursors) do
                        if cursor._enabled
                            and cursor._state ~= CursorState.deleted
                        then
                            cursor._state = CursorState.dirty
                        end
                    end
                end
            end
        end
        self._state = CursorState.deleted
        if self == state.mainCursor then
            state.mainCursor = nil
            local newMainCursor = CursorContext:nearestCursor(self:getPos())
                or CursorContext:mainCursor()
            newMainCursor:enable()
            cursorContextSetMainCursor(newMainCursor)
        end
    end
end

--- Returns the disabled cursor underneath this one, if it exists
--- @return mc.Cursor | nil
function Cursor:overlappedCursor()
    if not self._enabled then
        return nil
    end
    return CursorContext:findCursor(function(cursor)
        return not cursor._enabled
            and cursor._pos[2] == self._pos[2]
            and cursor._pos[3] == self._pos[3]
            and cursor._pos[4] == self._pos[4]
    end, { enabledCursors = false, disabledCursors = true })
end

--- Sets this cursor as the main cursor.
--- @return self
function Cursor:select()
    cursorContextSetMainCursor(self)
    return self
end

--- Returns whether this cursor is the main cursor.
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
--- @return mc.Cursor[]
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

--- Returns the position of a cursor.
--- @return mc.Pos
function Cursor:getPos()
    cursorCheckUpdate(self)
    return { self._pos[2], self._pos[3], self._pos[4] }
end

--- Sets the position of the cursor.
--- @param pos mc.SimplePos | mc.Pos
--- @return self
function Cursor:setPos(pos)
    cursorCheckUpdate(self)
    local virtcol = vim.fn.virtcol({ pos[1], pos[2] })
    self._pos = { 0, pos[1], pos[2], pos[3] or 0, virtcol }
    self._state = CursorState.dirty
    cursorSetMarks(self)
    return self
end

--- Sets the position of the visual anchor.
--- Equivalent of `setpos()` on `'v'` for a cursor.
--- @param pos mc.SimplePos | mc.Pos
--- @return self
function Cursor:setVisualAnchor(pos)
    cursorCheckUpdate(self)
    local virtcol = vim.fn.virtcol({ pos[1], pos[2] })
    self._vPos = { 0, pos[1], pos[2], pos[3] or 0, virtcol }
    self._state = CursorState.dirty
    cursorSetMarks(self)
    return self
end

--- Returns the position of cursor's visual anchor same as `getpos('v')`.
--- @return mc.Pos
function Cursor:getVisualAnchor()
    cursorCheckUpdate(self)
    return { self._vPos[2], self._vPos[3], self._vPos[4] }
end

--- Sets the position of the redo position marker.
--- @param pos mc.SimplePos | mc.Pos
function Cursor:setRedoChangePos(pos)
    cursorCheckUpdate(self)
    self._redoChangePos = { 0, pos[1], pos[2], 0 }
    cursorSetMarks(self)
end

--- Sets the position of the undo position marker.
--- @param pos mc.SimplePos | mc.Pos
function Cursor:setUndoChangePos(pos)
    cursorCheckUpdate(self)
    self._drift = { 0, 0 }
    self._changePos = { 0, pos[1], pos[2], 0 }
    self._origChangePos = self._changePos
    cursorSetMarks(self)
end

--- Set the search register of this cursor.
--- @param search string
function Cursor:setSearch(search)
    self._search = search
end

--- Return the <cword> for this cursor.
--- @return string
function Cursor:getCursorWord()
    cursorCheckUpdate(self)
    cursorWrite(self)
    return vim.fn.expand("<cword>")
end

--- @param cursor mc.Cursor
--- @param newId? boolean = true
--- @return mc.Cursor
local function cursorCopy(cursor, newId)
    local copy = createCursor({
        _id = cursor._id,
        _modifiedId = state.modifiedId,
        _drift = cursor._drift,
        _changePos = cursor._changePos,
        _pos = cursor._pos,
        _register = cursor._register,
        _search = cursor._search,
        _visualStart = cursor._visualStart,
        _visualEnd = cursor._visualEnd,
        _vPos = cursor._vPos,
        _mode = cursor._mode,
        _state = CursorState.new,
    }, newId)
    if state.native then
        copy._origRegister = cursor._register
    end
    return copy
end

--- Returns a new cursor with the same position, registers,
--- visual selection, and mode as this cursor.
--- @return mc.Cursor
function Cursor:clone()
    cursorCheckUpdate(self)
    local cursor = cursorCopy(self)
    if cursor._enabled then
        state.numEnabledCursors = state.numEnabledCursors + 1
    else
        state.numDisabledCursors = state.numDisabledCursors + 1
    end
    cursorSetMarks(cursor)
    state.cursors[#state.cursors + 1] = cursor
    return cursor
end

--- Returns only the text contained in each line of the visual selection.
--- @return string[]
function Cursor:getVisualLines()
    cursorCheckUpdate(self)
    local info = VISUAL_LOOKUP[self._mode]
    if not info then
        return {}
    end
    if info.type == "l" then
        return get_lines(
            0,
            math.min(self._pos[2], self._vPos[2]) - 1,
            math.max(self._pos[2], self._vPos[2])
        )
    end
    local pos = self._pos
    local vPos = self._vPos
    if vPos[3] == 0 then
        vPos = { table.unpack(vPos) }
        vPos[3] = 1
    end
    if pos[3] == 0 then
        pos = { table.unpack(pos) }
        pos[3] = 1
    end
    local lines = vim.fn.getregion(vPos, pos, {
        type = info.enterVisualKey,
        exclusive = state.exclusive
    })
    if info.type == "c" then
        if state.exclusive then
            local vs, ve = self:getVisual()
            if vs[1] < ve[1] and ve[2] == 1 then
                table.insert(lines, "")
            end
        else
            local lastPos = compareMarkPos(pos, vPos) and vPos or pos
            local lastCol = vim.fn.col({lastPos[2], "$"})
            if lastCol == lastPos[3] then
                table.insert(lines, "")
            end
        end
    end
    return lines
end

--- Registers this cursor so that its original position is restored upon undo.
--- @return self
function Cursor:registerUndo()
    self._undoRegistered = true
    return self
end

--- Replace only the text contained in each line of the visual selection.
--- If lines is longer than the visual selection, new lines are created
--- @param lines string[]
--- @return self
function Cursor:setVisualLines(lines)
    self:perform(function()
        local info = VISUAL_LOOKUP[self._mode]
        if not info then
            return
        end
        self:registerUndo()
        local vs, ve = self:getVisual()
        if info.type == "b" then
            local numSelectedLines = ve[1] - vs[1] + 1
            if numSelectedLines > #lines then
                for _ = #lines + 1, numSelectedLines do
                    table.insert(lines, string.rep(" ", #lines[1]))
                end
            elseif numSelectedLines < #lines then
                lines = tbl.slice(lines, 1, numSelectedLines)
            end
        end
        local reg = vim.fn.getreginfo("z")
        vim.fn.setreg("z", table.concat(lines, "\n"), info.type)
        feedkeys('"zP' .. info.enterVisualKey)
        vim.fn.setpos(".", compareMarkPos(self._pos, self._vPos)
            and self._pos or self._vPos)
        feedkeys('o'
            .. (info.type == "l" and "'" or '`')
            .. ']'
            .. ((info.type == "c" and lines[#lines] == "")
                and TERM_CODES.BACKSPACE or "")
            .. info.enterSelectKey
        )
        vim.fn.setreg("z", reg)
    end)
    return self
end

--- Replace text contained in the line of the cursor.
--- @param line string
--- @return self
function Cursor:setLine(line)
    self:perform(function()
        self:registerUndo()
        vim.api.nvim_buf_set_lines(
            0, self:line() - 1, self:line(), true, {line})
    end)
    return self
end

--- Returns the full line for each line of the visual selection.
--- @return string[]
function Cursor:getFullVisualLines()
    cursorCheckUpdate(self)
    local visualStart, visualEnd = self:getVisual()
    return get_lines(0, visualStart[1] - 1, visualEnd[1])
end

--- Returns start and end positions of visual selection start position
--- is before or equal to end position.
--- @return mc.Pos, mc.Pos
function Cursor:getVisual()
    cursorCheckUpdate(self)
    if self:hasSelection() then
        if self:atVisualStart() then
            return
                {self._pos[2], self._pos[3], self._pos[4] },
                {self._vPos[2], self._vPos[3], self._vPos[4] }
        else
            return
                {self._vPos[2], self._vPos[3], self._vPos[4] },
                {self._pos[2], self._pos[3], self._pos[4] }
        end
    end
    return
        {self._visualStart[2], self._visualStart[3], 0},
        {self._visualEnd[2], self._visualEnd[3], 0}
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
    if self._state ~= CursorState.deleted then
        self._state = CursorState.dirty
    end
    self._mode = mode
    return self
end

--- Disable the cursor.
--- @return self
function Cursor:disable()
    if self._state ~= CursorState.deleted and self._enabled then
        state.numDisabledCursors = state.numDisabledCursors + 1
        state.numEnabledCursors = state.numEnabledCursors - 1
        self._enabled = false
        self._state = CursorState.dirty
    end
    return self
end

--- Enable the cursor.
--- @return self
function Cursor:enable()
    if self._state ~= CursorState.deleted and not self._enabled then
        state.numEnabledCursors = state.numEnabledCursors + 1
        state.numDisabledCursors = state.numDisabledCursors - 1
        self._enabled = true
        self._state = CursorState.dirty
    end
    return self
end

--- Activates this cursor by setting its registers, visual selection, mode,
--- position, etc. Then, it calls the provided callback where you can perform
--- some lower level operations. Once the callback is finished, the new cursor
--- state is read and the previously selected cursor is restored.
--- @param callback fun(cursor: mc.Cursor)
function Cursor:perform(callback)
    cursorCheckUpdate(self)
    state.modifiedId = state.modifiedId + 1
    self._modifiedId = state.modifiedId
    self._state = CursorState.dirty
    cursorWrite(self)
    local success = pcall(callback, self)
    state.numLines = vim.fn.line("$")
    if success then
        cursorRead(self)
        cursorSetMarks(self)
    else
        state.errors[#state.errors + 1] = vim.v.errmsg
    end
end

--- Makes the cursor perform a command/commands.
---
--- For example, `cursor:feedkeys('dw')` will delete a word.
--- By default, keys are not remapped and keycodes are not parsed.
---
--- @param keys string
--- @param opts? { remap?: boolean, keycodes?: boolean, silent?: boolean }
function Cursor:feedkeys(keys, opts)
    self:perform(function()
        feedkeys(keys, opts)
    end)
end

--- Sets the visual selection and sets the cursor position to `visualEnd`.
--- @param visualStart mc.SimplePos | mc.Pos
--- @param visualEnd mc.SimplePos | mc.Pos
--- @return self
function Cursor:setVisual(visualStart, visualEnd)
    cursorCheckUpdate(self)
    local vs = self._visualStart
    local ve = self._visualEnd
    local atVisualEnd = visualStart[1] > visualEnd[1]
        or visualStart[1] == visualEnd[1]
        and visualStart[2] > visualEnd[2]
    if atVisualEnd then
        self._visualStart = { ve[1], visualEnd[1], visualEnd[2], 0 }
        self._visualEnd = { vs[1], visualStart[1], visualStart[2], 0 }
    else
        self._visualStart = { vs[1], visualStart[1], visualStart[2], 0 }
        self._visualEnd = { ve[1], visualEnd[1], visualEnd[2], 0 }
    end
    if self:hasSelection() then
        local nvs = self._visualStart
        local nve = self._visualEnd
        local virtcolVs = vim.fn.virtcol({ nvs[2], nvs[3] })
        local virtcolVe = vim.fn.virtcol({ nve[2], nve[3] })
        if atVisualEnd then
            self._pos = { self._pos[1], nvs[2], nvs[3], nvs[4], virtcolVs  }
            self._vPos = { self._pos[1], nve[2], nve[3], nve[4], virtcolVe  }
        else
            self._vPos = { self._pos[1], nvs[2], nvs[3], nvs[4], virtcolVs  }
            self._pos = { self._pos[1], nve[2], nve[3], nve[4], virtcolVe  }
        end
    end
    self._state = CursorState.dirty
    cursorSetMarks(self)
    return self
end

--- Returns true if in visual or select mode.
--- @return boolean
function Cursor:hasSelection()
    return not not VISUAL_LOOKUP[self._mode]
end

--- Returns true if cursor is in visual char/line/block mode
--- @return boolean
function Cursor:inVisualMode()
    return isVisualMode(self._mode)
end

--- Returns true if cursor is in select char/line/block mode
--- @return boolean
function Cursor:inSelectMode()
    return isSelectMode(self._mode)
end

--- When cursors are disabled, only the main cursor can be interacted with.
--- @return boolean
function CursorContext:cursorsEnabled()
    return state.numDisabledCursors == 0
end

--- Returns the total number of cursors.
--- There is always at least one cursor (the main cursor).
--- @return integer
function CursorContext:numCursors()
    return state.numEnabledCursors + state.numDisabledCursors + 1
end

--- Returns number of enabled cursors.
--- There is always at least one enabled cursor (the main cursor).
--- @return integer
function CursorContext:numEnabledCursors()
    return state.numEnabledCursors + 1
end

--- Returns the number of disabled cursors.
--- @return integer
function CursorContext:numDisabledCursors()
    return state.numDisabledCursors
end

--- Returns whether there are virtual cursors.
--- @return boolean
function CursorContext:hasCursors()
    return #state.cursors > 1
        or #state.cursors == 1
        and state.cursors[1] ~= state.mainCursor
end

--- @param origCursor mc.Cursor
--- @param winStartLine integer
local function fixWindowScroll(origCursor, winStartLine)
    local newStartLine = vim.fn.line("w0")
    local newEndLine = vim.fn.line("w$")
    local scrollOff = vim.o.scrolloff
    local height = newEndLine - newStartLine
    if origCursor._pos[2] < winStartLine + scrollOff
        or origCursor._pos[2] > winStartLine + height - scrollOff
    then
        -- scrolling is expected and welcome when
        -- cursor has moved outside of original view
    elseif scrollOff >= math.floor(height / 2) then
        -- dont go scrolling since cursor is guarenteed
        -- to be in the middle of the screen due to scrolloff
    elseif origCursor._pos[2] <= newEndLine - scrollOff then
        local rowDelta = math.max(
            newStartLine - origCursor._pos[2] + scrollOff,
            math.min(
                newEndLine - origCursor._pos[2] - scrollOff,
                newStartLine - winStartLine - origCursor._drift[1]
            )
        )
        if rowDelta < 0 then
            local absDelta = math.abs(rowDelta)
            feedkeys(absDelta .. TERM_CODES.CTRL_E)
        elseif rowDelta > 0 then
            local absDelta = rowDelta
            feedkeys(absDelta .. TERM_CODES.CTRL_Y)
        end
    end
    -- i would also update leftcol here, but vim.fn.winsaveview()
    -- is returning outdated values. probably a neovim bug
end

return {
    state = state,
    CursorContext = CursorContext,
    CursorState = CursorState,
    VISUAL_LOOKUP = VISUAL_LOOKUP,
    feedkeys = feedkeys,
    get_lines = get_lines,
    isVisualMode = isVisualMode,
    isSelectMode = isSelectMode,
    compareMarkPos = compareMarkPos,
    compareCursorsPosition = compareCursorsPosition,
    setOptions = setOptions,
    unsetOptions = unsetOptions,
    setHlsearch = setHlsearch,
    unsetHlsearch = unsetHlsearch,
    createCursor = createCursor,
    cursorReset = cursorReset,
    cursorCopyMode = cursorCopyMode,
    cursorCheckUpdate = cursorCheckUpdate,
    cursorClearMarks = cursorClearMarks,
    cursorSetMarks = cursorSetMarks,
    cursorRead = cursorRead,
    cursorWrite = cursorWrite,
    cursorCopy = cursorCopy,
    fixWindowScroll = fixWindowScroll,
}
