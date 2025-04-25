local TERM_CODES = require("multicursor-nvim.term-codes")
local feedkeysManager = require("multicursor-nvim.feedkeys-manager")
local tbl = require("multicursor-nvim.tbl")
local util = require("multicursor-nvim.util")

local set_extmark = vim.api.nvim_buf_set_extmark
local del_extmark = vim.api.nvim_buf_del_extmark
local clear_namespace = vim.api.nvim_buf_clear_namespace
local replace_termcodes = vim.api.nvim_replace_termcodes
local get_extmark = vim.api.nvim_buf_get_extmark_by_id

--- @param buffer integer
--- @param startLine integer
--- @param endLine integer
local function get_lines(buffer, startLine, endLine)
    local lines = vim.api.nvim_buf_get_lines(buffer, startLine, endLine, true)
    for i, line in ipairs(lines) do
        if vim.fn.type(line) == vim.v.t_blob then
            lines[i] = vim.fn.string(line)
        end
    end
    return lines
end

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
    -- feedkeysManager.nvim_feedkeys(keys, mode, false)
    feedkeysManager:keepjumpsFeedkeys(keys, mode)
end

--- @param a MarkPos
--- @param b MarkPos
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

--- @param a Cursor
--- @param b Cursor
--- @return boolean
local function compareCursorsPosition(a, b)
    return compareMarkPos(a._pos, b._pos)
end

--- @param a Pos
--- @param b Pos
local function positionsEqual(a, b)
    return a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

--- See :h getcurpos()
--- @alias CursorPos [integer, integer, integer, integer, integer]

--- See :h getpos()
--- @alias MarkPos [integer, integer, integer, integer]

--- 1-indexed line, 1-indexed col, virtualedit offset
--- @alias Pos [integer, integer, integer]

--- 1-indexed line, 1-indexed col
--- @alias SimplePos [integer, integer]

--- @alias CursorQuery {disabledCursors?: boolean, enabledCursors?: boolean}

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
--- @field package _enabled         boolean
--- @field package _state           CursorState
--- @field package _changePos       MarkPos
--- @field package _redoChangePos   MarkPos
--- @field package _origChangePos   MarkPos
--- @field package _undoRegistered  boolean | nil
--- @field package _origPos         CursorPos
--- @field package _origVPos        MarkPos
--- @field package _drift           [integer, integer]
--- @field package _pos             CursorPos
--- @field package _register        table
--- @field package _search          string
--- @field package _visualStart     MarkPos
--- @field package _visualEnd       MarkPos
--- @field package _visualIds       integer[] | nil
--- @field package _vPos            MarkPos
--- @field package _mode            string
--- @field package _posId           integer | nil
--- @field package _changePosId     integer | nil
--- @field package _vPosId          integer | nil
--- @field package _jumps           Pos[]
--- @field package _jumpIdx         integer
local Cursor = {}
Cursor.__index = Cursor

--- @class MultiCursorUndoItem
--- @field data number[]
--- @field enabled boolean

--- @package
--- @class SharedMultiCursorState
--- @field mainCursor Cursor | nil
--- @field signIds? integer[]
--- @field modifiedId integer
--- @field cursors Cursor[]
--- @field oldCursor? Cursor[]
--- @field oldSeqCur? integer
--- @field oldCursors? Cursor[]
--- @field oldJumplist? Pos[]
--- @field oldJumpIdx? integer
--- @field options? table
--- @field nsid integer
--- @field virtualEditBlock? boolean
--- @field cursorline? boolean
--- @field undoItems table<string, MultiCursorUndoItem>
--- @field redoItems table<string, MultiCursorUndoItem>
--- @field currentSeq integer | nil
--- @field changedtick integer | nil
--- @field numLines number
--- @field numDisabledCursors number
--- @field numEnabledCursors number
--- @field leftcol number
--- @field textoffset number
--- @field exclusive boolean
--- @field eol_listchar boolean
--- @field yanked? boolean
--- @field yankedWhileDisabled? boolean
--- @field opts MultiCursorOpts
--- @field mainSignHlExists? boolean
--- @field jumps Pos[]
--- @field jumpIdx integer
--- @field package lastJump? Pos
local state = {
    cursors = {},
    errors = {},
    undoItems = {},
    redoItems = {},
    numDisabledCursors = 0,
    numEnabledCursors = 0,
    id = 1,
    modifiedId = 0,
    nsid = 0,
    numLines = 0,
    leftcol = 0,
    textoffset = 0,
    jumps = {},
    didPushJump = false,
    jumpIdx = 0
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

local hlSearch = nil

local function setHlsearch()
    if hlSearch == nil then
        hlSearch = vim.o.hlsearch
        vim.o.hlsearch = false
        -- vim.cmd.noh()
    end
end

local function unsetHlsearch()
    if hlSearch then
        vim.o.hlsearch = true
        vim.schedule(vim.cmd.noh)
    end
    hlSearch = nil
end


--- @return Cursor
local function createCursor(cursor)
    cursor._id = state.id
    state.id = state.id + 1
    cursor._enabled = true
    cursor._drift = { 0, 0 }
    cursor._jumpIdx = 0
    cursor._jumps = {}
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
local function cursorReset(cursor)
    cursor._origPos = cursor._pos
    cursor._origVPos = cursor._vPos
    cursor._origChangePos = cursor._changePos
    cursor._undoRegistered = false
    cursor._changePos = nil
    cursor._state = CursorState.none
    cursor._drift = { 0, 0 }
end

--- @param cursor Cursor
--- @param target Cursor
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
                    and math.max(cursor._pos[5] or 0, curswantVirtcol)
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
        and (
            cursor._vPos[3] < cursor._pos[3]
            or cursor._vPos[3] == cursor._pos[3]
            and cursor._vPos[4] < cursor._pos[4]
        )
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
            priority = 2000,
            virt_text = ve[3] > #line
                and (vs[3] > #line
                    and {{string.rep(" ", ve[4] - vs[4] + (state.exclusive and 0 or 1)), hl}}
                    or {{string.rep(" ", ve[4] + (state.exclusive and 0 or 1)), hl}}
                ) or nil,
            end_col = ve[3] + (state.exclusive and -1 or 0),
            virt_text_pos = "overlay",
            virt_text_win_col = displayWidth + (vs[3] > #line and vs[4] or 0) - state.leftcol,
            hl_group = hl,
        })
        cursor._visualIds[#cursor._visualIds + 1] = id
    else
        local i = vs[2]
        while i <= ve[2] do
            local row = i - 1
            local line = lines[row - start + 1]
            local col = i == vs[2] and (vs[3] - 1) or 0
            local displayWidth = line and vim.fn.strdisplaywidth(line) or 0
            local endCol = i == ve[2]
                and ve[3] - 1
                or #line
            local endVirtCol = i == ve[2]
                and endCol
                or endCol + ve[4]
            local virt_text = endVirtCol >= #line
                and (col > #line
                    and {{
                        i == ve[2]
                            and string.rep(" ", ve[4] + (endVirtCol == displayWidth + 1 and 1 or 0))
                            or " ",
                        hl
                    }}
                    or {{
                        i == ve[2]
                            and string.rep(" ", ve[4] + (state.exclusive and 0 or 1))
                            or (((#line == 0) or state.eol_listchar) and " " or ""),
                        hl
                    }}
                ) or nil
            local id = set_extmark(0, state.nsid, row, col, {
                strict = false,
                undo_restore = false,
                virt_text = virt_text,
                end_col = endCol + (state.exclusive and 0 or 1),
                priority = 2000,
                virt_text_pos = "overlay",
                virt_text_win_col = displayWidth
                    + (col >= #line and i == vs[2] and vs[4] or 0) - state.leftcol,
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
            virt_text = (#line == 0 or state.eol_listchar) and {{" ", hl}} or nil,
            end_col = #line,
            virt_text_pos = "overlay",
            priority = 2000,
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
    local startCol
    local endCol
    local startVirtCol
    local endVirtCol
    local atEnd = cursor._vPos[3] < cursor._pos[3]
        or cursor._vPos[3] == cursor._pos[3]
        and cursor._vPos[4] < cursor._pos[4]
    if atEnd then
        startCol = cursor._vPos[3]
        endCol = cursor._pos[3]
        startVirtCol = startCol + cursor._vPos[4]
        endVirtCol = endCol + cursor._pos[4]
    else
        startCol = cursor._pos[3]
        endCol = cursor._vPos[3]
        startVirtCol = startCol + cursor._pos[4]
        endVirtCol = endCol + cursor._vPos[4]
    end
    local col = startCol < #lines[1] and startCol or startVirtCol
    local atEndOfLine = cursor._pos[5] == vim.v.maxcol

    local maxCol = 0
    if atEndOfLine and state.virtualEditBlock then
        local i = startLine
        while i <= endLine do
            local line = lines[i - start]
            if line and #line >= maxCol then
                maxCol = #line
            end
            i = i + 1
        end
        maxCol = maxCol + 1
    else
        maxCol = endVirtCol
    end

    local i = startLine
    while i <= endLine do
        local line = lines[i - start]
        if line then
            local displayWidth = vim.fn.strdisplaywidth(line)
            local virt_text
            local lineEndCol = atEndOfLine and #line or endVirtCol
            if state.virtualEditBlock then
                if atEndOfLine then
                    if maxCol > #line then
                        virt_text = {{
                            string.rep(" ", maxCol - #line),
                            hl
                        }}
                    end
                elseif startCol > #line then
                    virt_text = {{
                        string.rep(" ", endVirtCol - startVirtCol + 1),
                        hl
                    }}
                elseif col > #line then
                    virt_text = {{
                        string.rep(" ", endVirtCol - col + 1),
                        hl
                    }}
                elseif endVirtCol >= #line then
                    virt_text = {{
                        string.rep(" ", endVirtCol - #line),
                        hl
                    }}
                end
            end
            local virt_text_win_col = displayWidth
                + (col > #line and (col - #line) - 1 or 0)
                - state.leftcol
            local id = set_extmark(0, state.nsid, i - 1, col - 1, {
                strict = false,
                undo_restore = false,
                end_col = lineEndCol,
                virt_text_pos = "overlay",
                priority = 2000,
                virt_text_win_col = virt_text_win_col,
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

--- @param cursor Cursor
--- @return Cursor[]
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

--- @param cursor Cursor
--- @return Cursor[]
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


local VISUAL_LOOKUP = {
    v = {
        type = "c",
        enterVisualKey = "v",
        enterSelectKey = "",
        draw = cursorDrawVisualChar,
        split = cursorSplitVisualChar,
    },
    V = {
        type = "l",
        enterVisualKey = "V",
        enterSelectKey = "",
        draw = cursorDrawVisualLine,
        split = cursorSplitVisualLine,
    },
    [TERM_CODES.CTRL_V] = {
        type = "b",
        enterVisualKey = TERM_CODES.CTRL_V,
        enterSelectKey = "",
        draw = cursorDrawVisualBlock,
        split = cursorSplitVisualBlock,
    },
    s = {
        type = "c",
        enterVisualKey = "v",
        enterSelectKey = TERM_CODES.CTRL_G,
        draw = cursorDrawVisualChar,
        split = cursorSplitVisualChar,
    },
    S = {
        type = "l",
        enterVisualKey = "V",
        enterSelectKey = TERM_CODES.CTRL_G,
        draw = cursorDrawVisualLine,
        split = cursorSplitVisualLine,
    },
    [TERM_CODES.CTRL_S] = {
        type = "b",
        enterVisualKey = TERM_CODES.CTRL_V,
        enterSelectKey = TERM_CODES.CTRL_G,
        draw = cursorDrawVisualBlock,
        split = cursorSplitVisualBlock,
    },
}

--- @param cursor Cursor
local function cursorDraw(cursor)
    local visualHL
    local cursorHL
    local priority
    if cursor._enabled then
        visualHL = "MultiCursorVisual"
        cursorHL = "MultiCursorCursor"
        priority = 20000
    else
        visualHL = "MultiCursorDisabledVisual"
        cursorHL = "MultiCursorDisabledCursor"
        priority = 10000
    end
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
    local lines = get_lines(0, start, _end + 1)

    cursor._visualIds = {}
    if visualInfo then
        visualInfo.draw(cursor, lines, start, visualHL)
    end

    local row = cursor._pos[2] - 1
    local col = cursor._pos[3] - 1
    local virtCol = col + cursor._pos[4]
    local charLine = lines[cursor._pos[2] - start]
    local virtedit = virtCol >= #charLine

    local virt_text_win_col
    if virtedit then
        local vc = vim.fn.virtcol({ cursor._pos[2], cursor._pos[3] }) + cursor._pos[4] - 1
        virt_text_win_col = vc - state.leftcol
        if virt_text_win_col < 0 then
            return
        end
    end

    local id = set_extmark(0, state.nsid, row, col, {
        strict = false,
        undo_restore = false,
        virt_text_pos = "overlay",
        priority = priority,
        virt_text_win_col = virt_text_win_col,
        hl_group = cursorHL,
        end_col = virtedit and col or col + 1,
        virt_text_hide = true,
        virt_text = virtedit and {{ " ", cursorHL, }} or nil,
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
    cursor._posId = set_extmark(
        0,
        state.nsid,
        cursor._pos[2] - 1,
        cursor._pos[3] - 1,
        { strict = false, undo_restore = true }
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

--- @param cursor Cursor
local function cursorWrite(cursor)
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

--- @param cursor Cursor
local function cursorUpdate(cursor)
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

--- Enables or disables all cursors
--- @param value boolean
function CursorContext:setCursorsEnabled(value)
    local reg = state.yankedWhileDisabled
        and vim.fn.getreginfo("")
    state.yankedWhileDisabled = false
    for _, cursor in ipairs(state.cursors) do
        if cursor ~= state.mainCursor and cursor._enabled ~= value
            and cursor._state ~= CursorState.deleted
        then
            state.numDisabledCursors = state.numDisabledCursors + (value and -1 or 1)
            state.numEnabledCursors = state.numEnabledCursors + (value and 1 or -1)
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
--- @param opts? CursorQuery
--- @return Cursor[]
function CursorContext:getCursors(opts)
    local enabledCursors = default(opts and opts.enabledCursors, true)
    local disabledCursors = default(opts and opts.disabledCursors, false)
    local cursors = tbl.filter(state.cursors, function(cursor)
        return cursor._state ~= CursorState.deleted
            and (cursor._enabled == enabledCursors or (not cursor._enabled) == disabledCursors)
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
--- @param callback fun(cursor: Cursor, i: integer, t: Cursor[])
--- @param opts? CursorQuery
function CursorContext:forEachCursor(callback, opts)
    tbl.forEach(self:getCursors(opts), callback)
end

--- Util method which maps each cursor to a value.
--- @generic T
--- @param callback fun(cursor: Cursor, i: integer, t: Cursor[]): T
--- @param opts? CursorQuery
--- @return T[]
function CursorContext:mapCursors(callback, opts)
    return tbl.map(self:getCursors(opts), callback)
end

--- Util method which returns the last cursor matching the predicate.
--- @param predicate fun(cursor: Cursor, i: integer, t: Cursor[]): any
--- @param opts? CursorQuery
--- @return Cursor | nil
function CursorContext:findLastCursor(predicate, opts)
    return tbl.findLast(self:getCursors(opts), predicate)
end

--- Util method which returns the first cursor matching the predicate.
--- @param predicate fun(cursor: Cursor, i: integer, t: Cursor[]): any
--- @param opts? CursorQuery
--- @return Cursor | nil
function CursorContext:findCursor(predicate, opts)
    return tbl.find(self:getCursors(opts), predicate)
end

--- Returns the closest cursor which appears AFTER pos.
--- A cursor exactly at pos will not be returned.
--- It does not wrap, so if none are found, then nil is returned.
--- If you wish to wrap, use `ctx:nextCursor(...) or ctx:firstCursor(...)`.
--- @param pos SimplePos | Pos
--- @param opts? CursorQuery
--- @return Cursor | nil
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
--- @param pos SimplePos | Pos
--- @param opts? CursorQuery
--- @return Cursor | nil
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
--- @param pos SimplePos | Pos
--- @param direction -1 | 1
--- @param wrap? boolean
--- @param opts? CursorQuery
--- @return Cursor | nil
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
--- @param opts? CursorQuery
--- @return Cursor | nil
function CursorContext:seekBoundaryCursor(direction, opts)
    if direction == -1 then
        return self:firstCursor(opts)
    else
        return self:lastCursor(opts)
    end
end

--- Returns the nearest cursor to pos, and accepts a cursor exactly at pos.
--- @param pos SimplePos | Pos
--- @param opts? CursorQuery
--- @return Cursor | nil
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

--- @param pos SimplePos | Pos
--- @param opts? CursorQuery
--- @return Cursor | nil
function CursorContext:getCursorAtPos(pos, opts)
    return self:findCursor(function(cursor)
        return cursor._pos[2] == pos[1]
            and cursor._pos[3] == pos[2]
            and (not pos[3] or cursor._pos[4] == pos[3])
    end, opts)
end

--- Returns the cursor under the main cursor
--- @return Cursor | nil
function CursorContext:overlappedCursor()
    util.warnOnce(
        "ctx:overlappedCursor",
        "ctx:overlappedCursor() is deprecated. Use ctx:mainCursor():overlappedCursor() instead"
    )
    return self:mainCursor():overlappedCursor()
end

--- Returns the main cursor.
--- @return Cursor
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
--- @param opts? CursorQuery
--- @return Cursor | nil
function CursorContext:firstCursor(opts)
    return self:findCursor(function() return true end, opts)
end

--- Returns the cursor closest to the end of the document.
--- @param opts? CursorQuery
--- @return Cursor | nil
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
                if state.numDisabledCursors == 0 then
                    for _, cursor in ipairs(state.cursors) do
                        if cursor._enabled and cursor._state ~= CursorState.deleted then
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
--- @return Cursor | nil
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

--- @return Pos
function Cursor:getPos()
    cursorCheckUpdate(self)
    return { self._pos[2], self._pos[3], self._pos[4] }
end

--- @param pos SimplePos | Pos
--- @return self
function Cursor:setPos(pos)
    cursorCheckUpdate(self)
    local virtcol = vim.fn.virtcol({ pos[1], pos[2] })
    self._pos = { 0, pos[1], pos[2], pos[3] or 0, virtcol }
    self._state = CursorState.dirty
    cursorSetMarks(self)
    return self
end

--- @param pos SimplePos | Pos
--- @return self
function Cursor:setVisualAnchor(pos)
    cursorCheckUpdate(self)
    local virtcol = vim.fn.virtcol({ pos[1], pos[2] })
    self._vPos = { 0, pos[1], pos[2], pos[3] or 0, virtcol }
    self._state = CursorState.dirty
    cursorSetMarks(self)
    return self
end

--- @return Pos
function Cursor:getVisualAnchor()
    cursorCheckUpdate(self)
    return { self._vPos[2], self._vPos[3], self._vPos[4] }
end

--- @param pos SimplePos | Pos
function Cursor:setRedoChangePos(pos)
    cursorCheckUpdate(self)
    self._redoChangePos = { 0, pos[1], pos[2], 0 }
    cursorSetMarks(self)
end

--- @param pos SimplePos | Pos
function Cursor:setUndoChangePos(pos)
    cursorCheckUpdate(self)
    self._drift = { 0, 0 }
    self._changePos = { 0, pos[1], pos[2], 0 }
    self._origChangePos = self._changePos
    cursorSetMarks(self)
end

--- @param search string
function Cursor:setSearch(search)
    self._search = search
end

function Cursor:getCursorWord()
    cursorCheckUpdate(self)
    cursorWrite(self)
    return vim.fn.expand("<cword>")
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
        _visualStart = cursor._visualStart,
        _visualEnd = cursor._visualEnd,
        _vPos = cursor._vPos,
        _mode = cursor._mode,
        _state = CursorState.new,
    })
end

-- cursors are packed together for undo history like so
-- id1, line1, col1, id2, line2, col2
-- the id is of each cursor is negative if the cursor is disabled

--- @param cursors Cursor[]
--- @return number[]
local function packRedoCursors(cursors)
    local data = {}
    data[1] = state.mainCursor._id
    data[2] = state.mainCursor._redoChangePos[2]
    data[3] = state.mainCursor._redoChangePos[3]
    local i = 4
    for _, cursor in ipairs(cursors) do
        data[i] = cursor._enabled and cursor._id or -cursor._id
        data[i + 1] = cursor._redoChangePos[2]
        data[i + 2] = cursor._redoChangePos[3]
        i = i + 3
    end
    return data
end

--- @param cursors Cursor[]
--- @return number[]
local function packUndoCursors(cursors)
    local data = {}
    data[1] = state.mainCursor._id
    data[2] = state.mainCursor._changePos[2]
    data[3] = state.mainCursor._changePos[3]
    local i = 4
    for _, cursor in ipairs(cursors) do
        if cursor._enabled then
            data[i] = cursor._id
            data[i + 1] = cursor._changePos[2]
            data[i + 2] = cursor._changePos[3]
        else
            data[i] = -cursor._id
            data[i + 1] = cursor._origPos[2]
            data[i + 2] = cursor._origPos[3]
        end
        i = i + 3
    end
    return data
end

--- @param data number[]
local function unpackCursors(data)
    local cursorLookup = {}
    for _, cursor in ipairs(state.cursors) do
        cursorLookup[cursor._id] = cursor
    end
    state.cursors = {}
    local newMainCursor
    state.numDisabledCursors = 0
    state.numEnabledCursors = 0
    state.numLines = vim.fn.line("$")
    for i = 1, #data, 3 do
        if data[i + 1] >= 1 and data[i + 1] <= state.numLines then
            local cursor = cursorLookup[math.abs(data[i])] or cursorCopy(state.mainCursor)
            local col = math.max(1,
                math.min(
                    data[i + 2],
                    #get_lines(0, data[i + 1] - 1, data[i + 1])[1]
                )
            )
            local curswantVirtcol = vim.fn.virtcol({ data[i + 1], data[i + 2] })
            cursor._pos = { 0, data[i + 1], col, 0, curswantVirtcol }
            cursor._mode = "n"
            cursor._vPos = cursor._pos
            cursor._changePos = cursor._pos
            cursor._modifiedId = state.modifiedId
            cursor._enabled = data[i] > 0
            if cursor._enabled then
                state.numEnabledCursors = state.numEnabledCursors + 1
            else
                state.numDisabledCursors = state.numDisabledCursors + 1
            end
            if i == 1 then
                newMainCursor = cursor
            else
                state.cursors[#state.cursors + 1] = cursor
            end
        end
    end
    if newMainCursor then
        state.mainCursor = newMainCursor
    else
        state.mainCursor = CursorContext:nearestCursor(state.mainCursor:getPos())
    end
end

--- Returns a new cursor with the same position, registers,
--- visual selection, and mode as this cursor.
--- @return Cursor
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
        vim.fn.setpos(".", compareMarkPos(self._pos, self._vPos) and self._pos or self._vPos)
        feedkeys('o'
            .. (info.type == "l" and "'" or '`')
            .. ']'
            .. ((info.type == "c" and lines[#lines] == "") and TERM_CODES.BACKSPACE or "")
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
--- @return Pos, Pos
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

function Cursor:disable()
    if self._state ~= CursorState.deleted and self._enabled then
        state.numDisabledCursors = state.numDisabledCursors + 1
        state.numEnabledCursors = state.numEnabledCursors - 1
        self._enabled = false
        self._state = CursorState.dirty
    end
    return self
end

function Cursor:enable()
    if self._state ~= CursorState.deleted and not self._enabled then
        state.numEnabledCursors = state.numEnabledCursors + 1
        state.numDisabledCursors = state.numDisabledCursors - 1
        self._enabled = true
        self._state = CursorState.dirty
    end
    return self
end

--- Calls callback with cursor
--- @param callback fun(cursor: Cursor)
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
--- For example, cursor:feedkeys('dw') will delete a word.
--- By default, keys are not remapped and keycodes are not parsed.
--- @param keys string
--- @param opts? { remap?: boolean, keycodes?: boolean }
function Cursor:feedkeys(keys, opts)
    self:perform(function()
        feedkeys(keys, opts)
    end)
end

--- Sets the visual selection and sets the cursor position to `visualEnd`.
--- @param visualStart SimplePos | Pos
--- @param visualEnd SimplePos | Pos
--- @return self
function Cursor:setVisual(visualStart, visualEnd)
    cursorCheckUpdate(self)
    local atVisualEnd = visualStart[1] > visualEnd[1]
        or visualStart[1] == visualEnd[1]
        and visualStart[2] > visualEnd[2]
    if atVisualEnd then
        self._visualStart = { self._visualEnd[1], visualEnd[1], visualEnd[2], 0 }
        self._visualEnd = { self._visualStart[1], visualStart[1], visualStart[2], 0 }
    else
        self._visualStart = { self._visualStart[1], visualStart[1], visualStart[2], 0 }
        self._visualEnd = { self._visualEnd[1], visualEnd[1], visualEnd[2], 0 }
    end
    if self:hasSelection() then
        local nvs = self._visualStart
        local nve = self._visualEnd
        local virtcolVs = vim.fn.virtcol({ nvs[2], nvs[3] })
        local virtcolVe = vim.fn.virtcol({ nvs[2], nvs[3] })
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
    return self._mode == "v"
        or self._mode == "V"
        or self._mode == TERM_CODES.CTRL_V
end

--- Returns true if cursor is in select char/line/block mode
--- @return boolean
function Cursor:inSelectMode()
    return self._mode == "s"
        or self._mode == "S"
        or self._mode == TERM_CODES.CTRL_S
end

--- When cursors are disabled, only the main cursor can be interacted with.
--- @return boolean
function CursorContext:cursorsEnabled()
    return state.numDisabledCursors == 0
end

--- @return integer
function CursorContext:numCursors()
    return state.numEnabledCursors + state.numDisabledCursors + 1
end

--- @return integer
function CursorContext:numEnabledCursors()
    return state.numEnabledCursors + 1
end

--- @return integer
function CursorContext:numDisabledCursors()
    return state.numDisabledCursors
end

local function cursorContextMergeCursors()
    --- @type Cursor[]
    local newCursors = {}
    local didMerge = false
    state.numDisabledCursors = 0
    state.numEnabledCursors = 0
    for _, cursor in ipairs(state.cursors) do
        cursorCheckUpdate(cursor)
        local exists = false
        if cursor._enabled
            and cursor._pos[2] == state.mainCursor._pos[2]
            and cursor._pos[3] == state.mainCursor._pos[3]
            and cursor._pos[4] == state.mainCursor._pos[4]
        then
            exists = true
        else
            for _, c in ipairs(newCursors) do
                if cursor._enabled == c._enabled
                    and cursor._pos[2] == c._pos[2]
                    and cursor._pos[3] == c._pos[3]
                    and cursor._pos[4] == c._pos[4]
                then
                    exists = true
                    break
                end
            end
        end
        if exists then
            didMerge = true
            cursorErase(cursor)
            cursorClearMarks(cursor)
        else
            if cursor._enabled then
                state.numEnabledCursors = state.numEnabledCursors + 1
            else
                state.numDisabledCursors = state.numDisabledCursors + 1
            end
            newCursors[#newCursors + 1] = cursor
        end
    end
    local origCursors = state.cursors
    state.cursors = newCursors
    return origCursors, didMerge
end

function CursorContext:hasCursors()
    return #state.cursors > 1
        or #state.cursors == 1
        and state.cursors[1] ~= state.mainCursor
end

local function clearCursorContext()
    clear_namespace(0, state.nsid, 0, -1)
    state.signIds = nil
    state.numDisabledCursors = 0
    state.numEnabledCursors = 0
    state.lastJump = nil
    state.jumps = {}
    state.errors = {}
    state.jumpIdx = 0
    state.yankedWhileDisabled = false
    unsetOptions()
    unsetHlsearch()
    state.yanked = false
    if state.yankedBuffer then
        local buffer = state.yankedBuffer
        state.yankedBuffer = nil
        vim.schedule(function()
            vim.fn.setreg(state.origRegister,
                table.concat(buffer, "\n"), "l")
        end)
    end
    state.cursors = {}
    state.mainCursor = nil
    if state.opts.shallowUndo then
        state.undoItems = {}
        state.redoItems = {}
    end
end

function CursorContext:clear()
    if state.mainCursor then
        state.oldCursor = cursorCopy(state.mainCursor)
    end
    state.oldCursors = {table.unpack(state.cursors)}
    state.oldJumpIdx = state.jumpIdx
    state.oldJumplist = state.jumps
    state.oldSeqCur = state.currentSeq
    clearCursorContext()
end

--- @param cursor Cursor
local function cursorApplyDrift(cursor)
    if not cursor._redoChangePos then
        cursor._redoChangePos = cursor._pos
    end
    if cursor._undoRegistered then
        if VISUAL_LOOKUP[cursor._mode]
            and compareMarkPos(cursor._origVPos, cursor._origPos)
        then
            cursor._changePos = cursor._origVPos
        else
            cursor._changePos = cursor._origPos
        end
    elseif not cursor._changePos then
        cursor._changePos = cursor._pos
    else
        cursor._changePos = { table.unpack(cursor._changePos) }
        cursor._changePos[2] = cursor._changePos[2] - cursor._drift[1]
        cursor._changePos[3] = cursor._changePos[3] - cursor._drift[2]
    end
    return cursor
end

local function updateSigns()
    local signsOnLeft = string.match(vim.o.signcolumn, "yes")
        or string.match(vim.o.signcolumn, "auto")
        or vim.o.signcolumn == "number"
        and not vim.o.number
        and not vim.o.relativenumber

    if signsOnLeft == state.signsOnLeft then
        return
    end

    state.signsOnLeft = signsOnLeft
    local leftSpace = signsOnLeft and "" or " "
    local rightSpace = signsOnLeft and " " or ""
    state.alignedSigns = {}

    local function createCursorSign(n)
        if state.signs[n] then
            state.alignedSigns[n] = leftSpace .. state.signs[n] .. rightSpace
        end
    end
    local function createArrowSign(n, offset)
        if state.signs[n] then
            local leftChar = signsOnLeft and "" or state.signs[n]
            local rightChar = signsOnLeft and state.signs[n] or ""
            state.alignedSigns[offset] = rightSpace .. state.signs[n] .. leftSpace
            state.alignedSigns[offset + 1] = leftChar .. (state.signs[1] or " ") .. rightChar
            state.alignedSigns[offset + 2] = leftChar .. (state.signs[2] or " ") .. rightChar
            state.alignedSigns[offset + 3] = leftChar .. (state.signs[3] or " ") .. rightChar
        else
            state.alignedSigns[offset + 1] = state.alignedSigns[1]
            state.alignedSigns[offset + 2] = state.alignedSigns[2]
            state.alignedSigns[offset + 3] = state.alignedSigns[3]
        end
    end
    createCursorSign(1)
    createCursorSign(2)
    createCursorSign(3)
    createArrowSign(4, 4)
    createArrowSign(5, 8)
    createArrowSign(6, 12)
    createArrowSign(7, 16)
end

local function redrawSigns()
    if state.signIds then
        for _, id in ipairs(state.signIds) do
            del_extmark(0, state.nsid, id)
        end
    end
    state.signIds = {}
    local hasDisabledCursor = false
    local cursorAbove = 0
    local cursorBelow = 0
    local signsToAdd = {}
    local ws = vim.fn.line("w0")
    local we = vim.fn.line("w$")
    for _, cursor in ipairs(state.cursors) do
        if not cursor._enabled then
            hasDisabledCursor = true
        end
        local line = cursor._pos[2]
        if line < ws then
            cursorAbove = math.max(cursorAbove, cursor._enabled and 2 or 1)
            line = ws
            signsToAdd[line] = math.max(signsToAdd[line] or 0, 0)
        elseif line > we then
            cursorBelow = math.max(cursorBelow, cursor._enabled and 2 or 1)
            line = we
            signsToAdd[line] = math.max(signsToAdd[line] or 0, 0)
        else
            signsToAdd[line] = math.max(signsToAdd[line] or 0, cursor._enabled and 2 or 1)
        end
    end
    signsToAdd[state.mainCursor._pos[2]] = 2
    for line, level in pairs(signsToAdd) do
        if level == 2 and hasDisabledCursor then
            level = 3
        end
        local signIdx
        if line == ws then
            signIdx = (cursorAbove == 0 and 0 or cursorAbove == 2 and 4 or 12) + level
        elseif line == we then
            signIdx = (cursorBelow == 0 and 0 or cursorBelow == 2 and 8 or 16) + level
        else
            signIdx = level
        end

        local signText = state.alignedSigns[signIdx]

        state.signIds[#state.signIds + 1] =
            set_extmark(0, state.nsid, line - 1, 0, {
                undo_restore = false,
                priority = 20000 + level * 10,
                sign_text = signText,
                sign_hl_group = line == state.mainCursor._pos[2]
                    and "MultiCursorMainSign"
                    or "MultiCursorSign",
            })
    end
end

local function cursorContextRedraw()
    clear_namespace(0, state.nsid, 0, -1)
    state.cursorSignId = nil
    if #state.cursors > 0 then
        for _, cursor in ipairs(state.cursors) do
            cursor._visualIds = nil
            cursor._posId = nil
            cursor._vPosId = nil
            cursor._changePosId = nil
            cursorSetMarks(cursor)
            cursorDraw(cursor)
        end
        redrawSigns()
    end
end

--- @package
--- @param applyToMainCursor boolean
local function cursorContextUpdate(applyToMainCursor)
    local unmergedCursors, didMerge = cursorContextMergeCursors()
    if not state.currentSeq then
        local undoTree = vim.fn.undotree()
        state.currentSeq = undoTree.seq_cur
    elseif vim.b.changedtick ~= state.changedtick then
        local undoTree = vim.fn.undotree()
        if undoTree.seq_cur and state.currentSeq ~= undoTree.seq_cur then
            if didMerge then
                state.mainCursor._changePos = state.mainCursor._origPos
                for _, cursor in ipairs(unmergedCursors) do
                    cursor._changePos = cursor._origPos
                end
            else
                if applyToMainCursor then
                    cursorApplyDrift(state.mainCursor)
                else
                    state.mainCursor._changePos = state.mainCursor._origChangePos
                    if not state.mainCursor._redoChangePos then
                        state.mainCursor._redoChangePos = state.mainCursor._pos
                    end
                end
                for _, cursor in ipairs(unmergedCursors) do
                    cursorApplyDrift(cursor)
                end
            end
            for _, cursor in ipairs(state.cursors) do
                cursor._redoChangePos = cursor._redoChangePos or cursor._pos
            end
            local undoItem = #unmergedCursors > 0
                and packUndoCursors(unmergedCursors)
                or nil
            local redoItem = #state.cursors > 0
                and packRedoCursors(state.cursors)
                or nil
            state.undoItems[undoItemId(state.currentSeq)] = undoItem
            state.redoItems[undoItemId(undoTree.seq_cur)] = redoItem
            state.currentSeq = undoTree.seq_cur
        end
        for _, cursor in ipairs(state.cursors) do
            cursor._changePos = cursor._changePos
                or cursor._origChangePos
        end
        state.mainCursor._changePos = state.mainCursor._changePos
            or state.mainCursor._origChangePos
    end
    state.changedtick = vim.b.changedtick
    if #state.cursors == 0 then
        clearCursorContext()
    else
        setHlsearch()
        redrawSigns()
    end
end

--- @class CursorManager
local CursorManager = {}

--- @param nsid integer
--- @param opts MultiCursorOpts
function CursorManager:setup(nsid, opts)
    state.nsid = nsid
    state.opts = opts or {}

    local DEFAULT_SIGNS = { "┆", "│", "┃", "↑", "↓", "⇡", "⇣" }
    if state.opts.signs == false then
        state.signs = {}
    elseif type(state.opts.signs) == "table" then
        state.signs = {}
        for i = 1, 7 do
            local sign = state.opts.signs[i]
            if sign == nil then
                sign = DEFAULT_SIGNS[i]
            end
            if sign ~= false then
                state.signs[i] = vim.fn.nr2char(
                    vim.fn.strgetchar(vim.fn.trim(sign), 0))
            end
        end
    else
        state.signs = DEFAULT_SIGNS
    end

    vim.api.nvim_create_autocmd("BufEnter", {
        pattern = "*",
        callback = function()
            state.currentSeq = vim.fn.undotree().seq_cur
            state.numLines = vim.fn.line("$")
        end
    })

    vim.api.nvim_create_autocmd("TextYankPost", {
        pattern = "*",
        callback = function()
            if #state.cursors > 0 then
                state.yanked = true
            end
        end
    })
end

function CursorManager:update()
    state.mainCursor = state.mainCursor or createCursor({})
    cursorRead(state.mainCursor)
    cursorContextUpdate(false)
end

function CursorManager:onSafeState()
    local oldLeftCol = state.leftcol
    state.leftcol = vim.fn.winsaveview().leftcol
    if oldLeftCol ~= state.leftcol then
        for _, cursor in ipairs(state.cursors) do
            cursorErase(cursor)
            cursorDraw(cursor)
        end
    end
end

local function updateCursorline()
    if vim.o.cursorline == state.cursorline then
        return
    end
    if state.mainSignHlExists == nil then
        state.mainSignHlExists = vim.fn.hlexists("MultiCursorMainSign") == 1
    end
    if state.mainSignHlExists == true then
        return
    end
    local newHl = vim.api.nvim_get_hl(0, {
        name = "MultiCursorSign",
        link = false
    })
    if vim.o.cursorline
        and vim.o.signcolumn == "number"
        and (vim.o.number or vim.o.relativenumber)
    then
        local hl = vim.api.nvim_get_hl(0, {
            name = "CursorLineNr",
            link = false
        })
        newHl = vim.tbl_deep_extend("keep", newHl, hl)
    else
        local hl = vim.api.nvim_get_hl(0, {
            name = "CursorLineSign",
            link = false
        })
        newHl = vim.tbl_deep_extend("keep", newHl, hl)
    end
    vim.api.nvim_set_hl(0, "MultiCursorMainSign", newHl)
end

--- @param opts ActionOptions
local function tryUndo(opts)
    if not opts.allowUndo then
        return
    end
    if state.currentSeq
        and state.changedtick
        and state.changedtick ~= vim.b.changedtick
    then
        local undoTree = vim.fn.undotree()
        if undoTree.seq_cur == undoTree.seq_last
            and undoTree.seq_cur ~= state.currentSeq
        then
            vim.cmd({ cmd = "undo", bang = true })
            opts.excludeMainCursor = false
            cursorWrite(state.mainCursor)
        end
    elseif opts.excludeMainCursor and opts.ifNotUndo then
        opts.ifNotUndo(state.mainCursor)
    end
end

local function updateVirtualEdit()
    state.virtualEditBlock = false
    for _, key in ipairs(vim.opt.virtualedit:get()) do
        if key == "block" or key == "all" then
            state.virtualEditBlock = true
            break
        end
    end
end

--- @param origCursor Cursor
--- @param winStartLine integer
local function fixWindowScroll(origCursor, winStartLine)
    local newStartLine = vim.fn.line("w0")
    local newEndLine = vim.fn.line("w$")
    local scrollOff = vim.o.scrolloff
    if scrollOff >= math.floor((newEndLine - newStartLine) / 2) then
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

--- @class ActionOptions
--- @field excludeMainCursor? boolean
--- @field fixWindow? boolean
--- @field allowUndo? boolean
--- @field ifNotUndo? function

--- @param callback fun(context: CursorContext)
--- @param opts ActionOptions
function CursorManager:action(callback, opts)
    updateSigns()
    updateCursorline()
    setOptions()
    updateVirtualEdit()
    -- state.leftcol = vim.fn.winsaveview().leftcol
    state.textoffset = vim.fn.getwininfo(vim.fn.win_getid())[1].textoff
    state.exclusive = vim.o.selection == "exclusive"
    state.eol_listchar = vim.opt.listchars:get().eol ~= nil

    tryUndo(opts)
    state.errors = {}

    local jump = vim.fn.getpos("''")
    local didJump = not state.lastJump or not positionsEqual(jump, state.lastJump)
    if didJump then
        state.lastJump = jump
        if opts.allowUndo and not (
            #state.jumps > 0
            and state.mainCursor
            and positionsEqual(state.jumps[state.jumpIdx], state.mainCursor._pos)
        ) then
            state.didPushJump = true
            for _, cursor in ipairs(state.cursors) do
                cursor._jumpIdx = cursor._jumpIdx + 1
                cursor._jumps[cursor._jumpIdx] = cursor._pos
                cursor._jumps[cursor._jumpIdx + 1] = nil
            end
            state.jumpIdx = state.jumpIdx + 1
            state.jumps[state.jumpIdx] = state.mainCursor
                and state.mainCursor._pos or vim.fn.getpos(".")
            state.jumps[state.jumpIdx + 1] = nil
        end
    end

    local origCursor = state.mainCursor or createCursor({})
    state.mainCursor = origCursor
    cursorRead(origCursor)

    cursorSetMarks(origCursor)
    origCursor._enabled = true
    if opts.excludeMainCursor then
        cursorReset(origCursor)
    else
        state.cursors[#state.cursors + 1] = origCursor
    end
    for _, cursor in ipairs(state.cursors) do
        cursorReset(cursor)
    end
    local winStartLine = vim.fn.line("w0")
    local result = callback(CursorContext)

    state.mainCursor = CursorContext:mainCursor()
    if not state.mainCursor:hasSelection() then
        state.mainCursor._mode = "n"
    end
    for _, cursor in ipairs(state.cursors) do
        if cursor._enabled and cursor._state ~= CursorState.deleted then
            cursorCopyMode(cursor, state.mainCursor)
        end
    end
    cursorCheckUpdate(state.mainCursor)
    cursorWrite(state.mainCursor)
    if state.mainCursor == origCursor and opts.fixWindow ~= false then
        fixWindowScroll(origCursor, winStartLine)
    end
    state.mainCursor._state = CursorState.deleted
    state.cursors = tbl.filter(state.cursors, function(cursor)
        cursorUpdate(cursor)
        return cursor._state ~= CursorState.deleted
    end)

    if didJump then
        if opts.allowUndo then
            for _, cursor in ipairs(state.cursors) do
                cursor._jumps[cursor._jumpIdx + 1] = cursor._pos
                cursor._jumps[cursor._jumpIdx + 2] = nil
            end
            state.jumps[state.jumpIdx + 1] = state.mainCursor
                and state.mainCursor._pos or vim.fn.getpos(".")
            state.jumps[state.jumpIdx + 2] = nil
        end
    end

    if state.yanked then
        state.yanked = false
        state.cursors[#state.cursors + 1] = state.mainCursor
        table.sort(state.cursors, compareCursorsPosition)
        local buffer = {}
        for _, cursor in ipairs(state.cursors) do
            for _, line in ipairs(cursor._register.regcontents) do
                buffer[#buffer + 1] = line
            end
        end
        state.yankedBuffer = buffer
        state.cursors = tbl.filter(state.cursors, function(cursor)
            return cursor ~= state.mainCursor
        end)
        if state.numDisabledCursors > 0
            and state.numEnabledCursors == 0
        then
            state.yankedWhileDisabled = true
        end
    end

    cursorContextUpdate(not opts.excludeMainCursor)

    local errors = tbl.uniq(state.errors)
    state.errors = {}
    for _, error in ipairs(errors) do
        util.echoerr(error, false)
    end

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
    local lookup = direction == 1
        and state.redoItems
        or state.undoItems
    local undoItem = lookup[id]
    if not undoItem then
        clearCursorContext()
        return
    end
    if not state.mainCursor then
        state.mainCursor = cursorRead(createCursor({}))
    end
    unpackCursors(undoItem)
    if not state.mainCursor then
        state.mainCursor = cursorRead(createCursor({}))
    end
    cursorContextMergeCursors()
    cursorWrite(state.mainCursor)
    if #state.cursors == 0 then
        clearCursorContext()
    else
        setOptions()
        setHlsearch()
        cursorContextRedraw()
        state.oldCursor = cursorCopy(state.mainCursor)
        state.oldCursors = {table.unpack(state.cursors)}
        state.oldSeqCur = state.currentSeq
    end
end

--- @param direction integer
function CursorManager:navigateJumplist(direction)
    local jumpIdx
    local jump
    local numJumps
    for _, cursor in ipairs(state.cursors) do
        if direction == -1 and state.didPushJump then
            direction = 0
        end

        jumpIdx = cursor._jumpIdx + direction
        jump = nil
        numJumps = #cursor._jumps
        if jumpIdx < 1 then
            jumpIdx = 1
            if cursor._jumpIdx > 1 then
                jump = cursor._jumps[jumpIdx]
            end
        elseif jumpIdx > numJumps then
            jumpIdx = numJumps
            if cursor._jumpIdx < numJumps then
                jump = cursor._jumps[jumpIdx]
            end
        else
            jump = cursor._jumps[jumpIdx]
        end
        cursor._jumpIdx = jumpIdx

        if jump then
            cursorErase(cursor)
            cursorClearMarks(cursor)
            cursor._pos = { jump[1], jump[2], jump[3], jump[4], jump[3] }
            cursorSetMarks(cursor)
            cursorDraw(cursor)
        end
    end
    jumpIdx = state.jumpIdx + direction
    jump = nil
    numJumps = #state.jumps
    local mainJump
    if jumpIdx < 1 then
        jumpIdx = 1
        if state.jumpIdx > 1 then
            mainJump = state.jumps[jumpIdx]
        end
    elseif jumpIdx > numJumps then
        jumpIdx = numJumps
        if state.jumpIdx < numJumps then
            mainJump = state.jumps[jumpIdx]
        end
    else
        mainJump = state.jumps[jumpIdx]
    end
    state.jumpIdx = jumpIdx
    if mainJump then
        local pos = {
            mainJump[1],
            mainJump[2],
            mainJump[3],
            mainJump[4],
            mainJump[3],
        }
        state.mainCursor._pos = pos
        cursorWrite(state.mainCursor)
    end
    state.didPushJump = false
    state.lastJump = vim.fn.getpos("''")
end

function CursorContext:restore()
    if state.oldSeqCur ~= state.currentSeq then
        return
    end
    local oldCursors = state.oldCursors or {}
    local oldCursor = state.oldCursor
    state.jumps = state.oldJumplist or {}
    state.jumpIdx = state.oldJumpIdx or 0
    state.oldCursors = self:getCursors()
    state.oldCursor = self:mainCursor()
    for _, cursor in ipairs(oldCursors) do
        state.cursors[#state.cursors + 1] = cursor
        cursor._state = CursorState.new
        cursorSetMarks(cursor)
    end
    if oldCursor then
        state.mainCursor = oldCursor
        state.mainCursor._state = CursorState.new
        cursorSetMarks(state.mainCursor)
    end
    for _, cursor in ipairs(state.oldCursors) do
        cursor:delete()
    end
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

--- @return integer
function CursorManager:numCursors()
    return CursorContext:numCursors()
end

--- @return integer
function CursorManager:numEnabledCursors()
    return CursorContext:numEnabledCursors()
end

--- @return integer
function CursorManager:numDisabledCursors()
    return CursorContext:numDisabledCursors()
end

return CursorManager
