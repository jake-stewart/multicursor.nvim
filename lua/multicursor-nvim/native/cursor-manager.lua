local cursor = require("multicursor-nvim.cursor")
local TERM_CODES = require("multicursor-nvim.term-codes")
local tbl = require("multicursor-nvim.tbl")
local util = require("multicursor-nvim.util")

--- @package
--- @class mc.State
--- @field performing boolean
--- @field bufs table<integer, mc.BufState>
--- @field clearSnapshot? mc.Cursor[]
--- @field yankedWhileDisabled table<integer, boolean>
--- @field afterExport? { operatorfunc?: string, mainPos?: mc.CursorPos }
local state = cursor.state

local CursorContext = cursor.CursorContext
local CursorState = cursor.CursorState
local VISUAL_LOOKUP = cursor.VISUAL_LOOKUP
local feedkeys = cursor.feedkeys
local get_lines = cursor.get_lines
local setOptions = cursor.setOptions
local unsetOptions = cursor.unsetOptions
local setHlsearch = cursor.setHlsearch
local unsetHlsearch = cursor.unsetHlsearch
local createCursor = cursor.createCursor
local cursorReset = cursor.cursorReset
local cursorCopyMode = cursor.cursorCopyMode
local cursorCheckUpdate = cursor.cursorCheckUpdate
local cursorClearMarks = cursor.cursorClearMarks
local cursorSetMarks = cursor.cursorSetMarks
local cursorRead = cursor.cursorRead
local cursorWrite = cursor.cursorWrite
local fixWindowScroll = cursor.fixWindowScroll

local set_extmark = vim.api.nvim_buf_set_extmark
local del_extmark = vim.api.nvim_buf_del_extmark
local get_extmarks = vim.api.nvim_buf_get_extmarks
local clear_namespace = vim.api.nvim_buf_clear_namespace
local get_extmark = vim.api.nvim_buf_get_extmark_by_id

local NATIVE_NS = vim.api.nvim_create_namespace("nvim.multicursor")
local NATIVE_VISUAL_NS = vim.api.nvim_create_namespace("nvim.multicursor.visual")
local NATIVE_CURSOR_NS = vim.api.nvim_create_namespace("nvim.multicursor.cursor")
local DISABLED_NS = vim.api.nvim_create_namespace("multicursor-nvim.disabled")
local DISABLED_ANCHOR_NS = vim.api.nvim_create_namespace("multicursor-nvim.disabled.anchor")
local LAST_NS = vim.api.nvim_create_namespace("multicursor-nvim.last")

--- @class mc.Cursor
--- @field package _nativeId        integer | nil
--- @field package _anchorId        integer | nil

--- Everything about a buffer's cursors that its extmarks cannot hold.
--- The cursors themselves are stored, keyed by the extmark that tracks
--- them, so they come back whole on the next import.
--- @class mc.BufState
--- @field enabled table<integer, mc.Cursor>
--- @field disabled table<integer, mc.Cursor>
--- @field main? mc.Cursor
--- @field last? table<integer, mc.Cursor>

--- @param buf integer
--- @return mc.BufState
local function bufState(buf)
    local bufs = state.bufs[buf]
    if not bufs then
        bufs = { enabled = {}, disabled = {} }
        state.bufs[buf] = bufs
    end
    return bufs
end

--- @param buf integer
--- @param cursor mc.Cursor
local function cursorDeleteNative(buf, cursor)
    if cursor._nativeId then
        pcall(del_extmark, buf, NATIVE_NS, cursor._nativeId)
        cursor._nativeId = nil
    end
end

--- @param a mc.Cursor
--- @param b mc.Cursor
--- @return boolean
local function cursorsOverlap(a, b)
    return a._pos[2] == b._pos[2]
        and a._pos[3] == b._pos[3]
        and a._pos[4] == b._pos[4]
end

--- @param buf integer
local function cursorContextMergeCursors(buf)
    --- @type mc.Cursor[]
    local newCursors = {}
    state.numDisabledCursors = 0
    state.numEnabledCursors = 0
    for _, cursor in ipairs(state.cursors) do
        cursorCheckUpdate(cursor)
        local exists = false
        if cursor._enabled and cursorsOverlap(cursor, state.mainCursor) then
            exists = true
        else
            for _, c in ipairs(newCursors) do
                if cursor._enabled == c._enabled
                    and cursorsOverlap(cursor, c)
                then
                    exists = true
                    break
                end
            end
        end
        if exists then
            cursorDeleteNative(buf, cursor)
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
    state.cursors = newCursors
end

--- @param buf integer
--- @return boolean
local function bufHasCursors(buf)
    return #get_extmarks(buf, NATIVE_NS, 0, -1, { limit = 1 }) > 0
        or #get_extmarks(buf, DISABLED_NS, 0, -1, { limit = 1 }) > 0
end

--- @param buf integer
--- @param cursors? mc.Cursor[]
local function clearBuffer(buf, cursors)
    local bufs = bufState(buf)
    local last = {}
    clear_namespace(buf, LAST_NS, 0, -1)
    if cursors then
        for _, cursor in ipairs(cursors) do
            local id = set_extmark(buf, LAST_NS,
                cursor._pos[2] - 1, cursor._pos[3] - 1, { strict = false })
            last[id] = cursor
        end
    else
        for _, mark in ipairs(get_extmarks(buf, NATIVE_NS, 0, -1, {})) do
            local id = set_extmark(
                buf, LAST_NS, mark[2], mark[3], { strict = false })
            last[id] = bufs.enabled[mark[1]] or createCursor({ _mode = "n" })
        end
        for _, mark in ipairs(get_extmarks(buf, DISABLED_NS, 0, -1, {})) do
            local saved = bufs.disabled[mark[1]]
            if saved then
                local id = set_extmark(
                    buf, LAST_NS, mark[2], mark[3], { strict = false })
                last[id] = saved
            end
        end
    end
    bufs.enabled = {}
    bufs.disabled = {}
    bufs.main = nil
    bufs.last = next(last) and last or nil
    state.yankedWhileDisabled[buf] = nil
    clear_namespace(buf, DISABLED_NS, 0, -1)
    clear_namespace(buf, DISABLED_ANCHOR_NS, 0, -1)
    clear_namespace(buf, NATIVE_NS, 0, -1)
end

--- Removes all cursors.
local function cursorContextClear()
    if state.performing then
        local snapshot = {}
        for _, cursor in ipairs(state.cursors) do
            if cursor ~= state.mainCursor
                and cursor._state ~= CursorState.deleted
            then
                cursor:delete()
                snapshot[#snapshot + 1] = cursor
            end
        end
        state.clearSnapshot = snapshot
    else
        clearBuffer(vim.api.nvim_get_current_buf())
    end
end

--- @param self mc.CursorContext
local function cursorContextRestore(self)
    if self:hasCursors() then
        return
    end
    local buf = vim.api.nvim_get_current_buf()
    local mainCursor = self:mainCursor()
    local bufs = bufState(buf)
    local last = bufs.last or {}
    for _, mark in ipairs(get_extmarks(buf, LAST_NS, 0, -1, {})) do
        local saved = last[mark[1]]
        local cursor = mainCursor:clone()
        cursor._mode = "n"
        cursor:setPos({ mark[2] + 1, mark[3] + 1 })
        if saved then
            cursor._register = saved._register
            cursor._search = saved._search
            if not saved._enabled then
                cursor:disable()
            end
        end
    end
    clear_namespace(buf, LAST_NS, 0, -1)
    bufs.last = nil
end

--- @param mark vim.api.keyset.get_extmark_item
--- @return mc.CursorPos
local function markToPos(mark)
    local line = mark[2] + 1
    local col = mark[3] + 1
    return { 0, line, col, 0, vim.fn.virtcol({ line, col }) }
end

--- @param cursor mc.Cursor
--- @param mainCursor mc.Cursor
--- @param ranges vim.api.keyset.get_extmark_item[]
--- @param ends vim.api.keyset.get_extmark_item[]
local function importVisual(cursor, mainCursor, ranges, ends)
    local line, col = cursor._pos[2], cursor._pos[3]
    for i, range in ipairs(ranges) do
        local details = range[4]
        local startLine, startCol = range[2] + 1, range[3] + 1
        local endLine, endCol = details.end_row + 1, details.end_col
        if (line > startLine or line == startLine and col >= startCol)
            and (line < endLine or line == endLine and col <= endCol + 1)
        then
            local other
            local mark = ends[i]
            if mark then
                other = { mark[2] + 1, mark[3] + 1 }
            end
            if not other then
                if line == startLine and col == startCol then
                    other = { endLine, math.max(endCol, 1) }
                else
                    other = { startLine, startCol }
                end
            end
            cursor._vPos = { 0, line, col, 0 }
            cursor._pos = {
                0, other[1], other[2], 0, vim.fn.virtcol(other),
            }
            cursor._mode = mainCursor._mode
            if mainCursor._pos[5] == vim.v.maxcol then
                cursor._pos[5] = vim.v.maxcol
            end
            return
        end
    end
end

--- Reuses the cursor the previous action stored under this mark, so
--- everything an extmark cannot hold survives. Cursors native created
--- on its own have nothing stored and inherit the main cursor's state.
--- @param saved? mc.Cursor
--- @param mainCursor mc.Cursor
--- @param pos mc.CursorPos
--- @return mc.Cursor
local function adoptCursor(saved, mainCursor, pos)
    local cursor = saved or createCursor({ _mode = "n" })
    cursor._pos = pos
    cursor._vPos = pos
    cursor._register = cursor._register or mainCursor._register
    cursor._search = cursor._search or mainCursor._search
    cursor._visualStart = cursor._visualStart or mainCursor._visualStart
    cursor._visualEnd = cursor._visualEnd or mainCursor._visualEnd
    cursor._modifiedId = state.modifiedId
    cursor._state = CursorState.none
    cursor._enabled = true
    return cursor
end

--- @param buf integer
--- @param mainCursor mc.Cursor
local function importCursors(buf, mainCursor)
    local bufs = bufState(buf)
    local ranges, ends
    if mainCursor:hasSelection() then
        ranges = get_extmarks(buf, NATIVE_VISUAL_NS, 0, -1, { details = true })
        ends = get_extmarks(buf, NATIVE_CURSOR_NS, 0, -1, {})
    end
    for _, mark in ipairs(get_extmarks(buf, NATIVE_NS, 0, -1, {})) do
        local cursor =
            adoptCursor(bufs.enabled[mark[1]], mainCursor, markToPos(mark))
        cursor._nativeId = mark[1]
        cursor._anchorId = nil
        cursor._mode = "n"
        if ranges then
            importVisual(cursor, mainCursor, ranges, ends)
        end
        cursorSetMarks(cursor)
        state.numEnabledCursors = state.numEnabledCursors + 1
        state.cursors[#state.cursors + 1] = cursor
    end
    for _, mark in ipairs(get_extmarks(buf, DISABLED_NS, 0, -1, {})) do
        local saved = bufs.disabled[mark[1]]
        local pos = markToPos(mark)
        if saved and saved._pos[5] == vim.v.maxcol then
            pos[5] = vim.v.maxcol
        end
        local cursor = adoptCursor(saved, mainCursor, pos)
        cursor._nativeId = nil
        if cursor._anchorId then
            local anchor =
                get_extmark(buf, DISABLED_ANCHOR_NS, cursor._anchorId, {})
            if #anchor > 0 then
                cursor._vPos = { 0, anchor[1] + 1, anchor[2] + 1, 0 }
            end
        end
        if not VISUAL_LOOKUP[cursor._mode] then
            cursor._mode = "n"
        end
        cursor._enabled = false
        cursorSetMarks(cursor)
        state.numDisabledCursors = state.numDisabledCursors + 1
        state.cursors[#state.cursors + 1] = cursor
    end
end

--- @param buf integer
--- @param line integer
--- @param col integer
--- @return vim.api.keyset.set_extmark
local function disabledMarkOpts(buf, line, col)
    local text = get_lines(buf, line - 1, line)[1]
    if col <= #text then
        local char = vim.fn.strcharpart(text:sub(col), 0, 1)
        return {
            end_col = col - 1 + #char,
            hl_group = "MultiCursorDisabledCursor",
            priority = 20000,
            strict = false,
        }
    end
    return {
        virt_text = { { " ", "MultiCursorDisabledCursor" } },
        virt_text_pos = "overlay",
        strict = false,
    }
end

--- @param buf integer
--- @param cursor mc.Cursor
--- @param line integer
--- @param col integer
--- @param coladd integer
local function cursorSetNative(buf, cursor, line, col, coladd)
    local row = line - 1
    local lineLength = #get_lines(buf, row, line)[1]
    col = math.max(1, math.min(col, lineLength + 1))
    if cursor._nativeId
        and #get_extmark(buf, NATIVE_NS, cursor._nativeId, {}) > 0
    then
        set_extmark(buf, NATIVE_NS, row, col - 1, {
            id = cursor._nativeId,
            end_row = row,
            end_col = math.min(col, lineLength),
            right_gravity = true,
            end_right_gravity = false,
            ui_watched = true,
            strict = false,
        })
    else
        local ok, id = pcall(vim.api.nvim_mcursor, buf, coladd ~= 0
            and { line, col - 1, coladd }
            or { line, col - 1 })
        cursor._nativeId = ok and id
            or vim.api.nvim_mcursor(buf, { line, col - 1 })
    end
end

--- @param a table | nil
--- @param b table | nil
--- @return boolean
local function registersDiffer(a, b)
    if a == b then
        return false
    end
    if not a or not b then
        return true
    end
    return a.regtype ~= b.regtype
        or not vim.deep_equal(a.regcontents, b.regcontents)
end

--- @param buf integer
--- @param mainCursor mc.Cursor
--- @return boolean
local function exportCursors(buf, mainCursor)
    local enabled = {}
    local disabled = {}
    local selecting = mainCursor:hasSelection()
    local needMirror = selecting
    clear_namespace(buf, DISABLED_NS, 0, -1)
    clear_namespace(buf, DISABLED_ANCHOR_NS, 0, -1)
    for _, cursor in ipairs(state.cursors) do
        cursorCheckUpdate(cursor)
        if not cursor._enabled then
            cursorDeleteNative(buf, cursor)
            local id = set_extmark(
                buf,
                DISABLED_NS,
                cursor._pos[2] - 1,
                cursor._pos[3] - 1,
                disabledMarkOpts(buf, cursor._pos[2], cursor._pos[3])
            )
            cursor._anchorId = cursor:hasSelection() and set_extmark(
                buf,
                DISABLED_ANCHOR_NS,
                cursor._vPos[2] - 1,
                cursor._vPos[3] - 1,
                { strict = false }
            ) or nil
            disabled[id] = cursor
        else
            if registersDiffer(cursor._origRegister, cursor._register)
                or registersDiffer(cursor._register, mainCursor._register)
            then
                needMirror = true
            end
            local pos = selecting and cursor._vPos or cursor._pos
            cursorSetNative(buf, cursor, pos[2], pos[3], pos[4])
            enabled[cursor._nativeId] = cursor
        end
        cursorClearMarks(cursor)
    end
    local bufs = bufState(buf)
    bufs.enabled = enabled
    bufs.disabled = disabled
    bufs.main = mainCursor
    return needMirror
end

--- @class mc.CursorManager
local CursorManager = {}

function CursorManager._mirror()
    pcall(function()
        local buf = vim.api.nvim_get_current_buf()
        local pos = vim.api.nvim_win_get_cursor(0)
        local marks = get_extmarks(
            buf, NATIVE_NS, { pos[1] - 1, pos[2] }, { pos[1] - 1, pos[2] }, {})
        local bufs = bufState(buf)
        local saved = marks[1] and bufs.enabled[marks[1][1]] or bufs.main
        local register = saved and saved._register or vim.fn.getreginfo('"')
        register.points_to = nil
        vim.fn.setreg('"', register)
        if saved and saved:hasSelection() then
            local info = VISUAL_LOOKUP[saved._mode]
            vim.fn.setpos(".", saved._vPos)
            vim.cmd("normal! " .. info.enterVisualKey)
            vim.fn.setpos(".", saved._pos)
            if #info.enterSelectKey > 0 then
                vim.cmd("normal! " .. info.enterSelectKey)
            end
        end
    end)
end

--- @param nsid integer
--- @param opts mc.MultiCursorOpts
function CursorManager:setup(nsid, opts)
    state.native = true
    state.nsid = nsid
    state.opts = opts or {}
    state.performing = false
    state.bufs = {}
    state.yankedWhileDisabled = {}
    CursorContext.clear = cursorContextClear
    CursorContext.restore = cursorContextRestore

    vim.api.nvim_create_autocmd("TextYankPost", {
        pattern = "*",
        callback = function()
            if state.performing then
                return
            end
            local buf = vim.api.nvim_get_current_buf()
            if vim.api.nvim__mcursor_cascading() then
                local startPos = vim.fn.getpos("'[")
                local endPos = vim.fn.getpos("']")
                local endCol = math.min(
                    endPos[3], vim.fn.col({ endPos[2], "$" }))
                local marks = get_extmarks(
                    buf,
                    NATIVE_NS,
                    { startPos[2] - 1, startPos[3] - 1 },
                    { endPos[2] - 1, endCol },
                    {}
                )
                if #marks == 0 then
                    local pos = vim.api.nvim_win_get_cursor(0)
                    marks = get_extmarks(
                        buf,
                        NATIVE_NS,
                        { pos[1] - 1, pos[2] },
                        { pos[1] - 1, pos[2] },
                        {}
                    )
                end
                local enabled = bufState(buf).enabled
                local event = vim.v.event
                for _, mark in ipairs(marks) do
                    local saved = enabled[mark[1]]
                    if not saved then
                        saved = createCursor({ _mode = "n" })
                        enabled[mark[1]] = saved
                    end
                    saved._register = {
                        regcontents = event.regcontents,
                        regtype = event.regtype,
                    }
                end
            elseif #get_extmarks(buf, DISABLED_NS, 0, -1, { limit = 1 }) > 0
                and #get_extmarks(buf, NATIVE_NS, 0, -1, { limit = 1 }) == 0
            then
                state.yankedWhileDisabled[buf] = true
            end
        end
    })

    vim.api.nvim_create_autocmd("BufWipeout", {
        pattern = "*",
        callback = function(args)
            local buf = args.buf
            state.bufs[buf] = nil
            state.yankedWhileDisabled[buf] = nil
        end
    })
end

function CursorManager:onSafeState()
    local buf = vim.api.nvim_get_current_buf()
    if bufHasCursors(buf) then
        setHlsearch()
    else
        unsetHlsearch()
    end
    local afterExport = state.afterExport
    if afterExport then
        local mode = vim.fn.mode()
        if not VISUAL_LOOKUP[mode] and mode ~= "c" then
            state.afterExport = nil
            if afterExport.operatorfunc then
                vim.o.operatorfunc = afterExport.operatorfunc
            end
            if afterExport.mainPos then
                local now = vim.fn.getcurpos()
                if now[2] == afterExport.mainPos[2]
                    and now[3] == afterExport.mainPos[3]
                    and now[5] ~= afterExport.mainPos[5]
                then
                    vim.fn.setpos(".", afterExport.mainPos)
                end
            end
        end
    end
end

--- @class mc.ActionOptions
--- @field excludeMainCursor? boolean
--- @field fixWindow? boolean
--- @field allowUndo? boolean
--- @field ifNotUndo? fun(cursor: mc.Cursor)

--- @generic T
--- @param callback fun(context: mc.CursorContext): T?
--- @param opts mc.ActionOptions
--- @return T?
function CursorManager:action(callback, opts)
    local buf = vim.api.nvim_get_current_buf()
    setOptions()
    state.exclusive = vim.o.selection == "exclusive"
    state.errors = {}
    state.cursors = {}
    state.numEnabledCursors = 0
    state.numDisabledCursors = 0
    state.numLines = vim.fn.line("$")
    state.modifiedId = state.modifiedId + 1
    state.performing = true
    state.clearSnapshot = nil
    vim.o.undolevels = vim.o.undolevels

    local origCursor = createCursor({})
    state.mainCursor = origCursor
    cursorRead(origCursor)
    cursorSetMarks(origCursor)
    if not opts.excludeMainCursor then
        state.cursors[#state.cursors + 1] = origCursor
    end
    importCursors(buf, origCursor)
    for _, cursor in ipairs(state.cursors) do
        cursorReset(cursor)
    end
    if opts.excludeMainCursor then
        cursorReset(origCursor)
    end
    local winStartLine = vim.fn.line("w0")
    local success, result = pcall(callback, CursorContext)

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
    state.mainCursor._state = CursorState.deleted
    state.cursors = tbl.filter(state.cursors, function(cursor)
        if cursor._state == CursorState.deleted then
            cursorDeleteNative(buf, cursor)
            cursorClearMarks(cursor)
            return false
        end
        return true
    end)
    cursorContextMergeCursors(buf)

    local typed = {}
    if vim.fn.mode() ~= "n" then
        feedkeys(TERM_CODES.ESC)
    end
    if state.clearSnapshot or #state.cursors == 0 then
        for _, cursor in ipairs(state.cursors) do
            cursorClearMarks(cursor)
        end
        clearBuffer(buf, state.clearSnapshot)
        state.clearSnapshot = nil
        cursorWrite(state.mainCursor)
    else
        local needMirror = exportCursors(buf, state.mainCursor)
        if state.numEnabledCursors > 0 then
            vim.cmd("silent! normal! 1q=")
        end
        local afterExport = state.afterExport or {}
        if needMirror and state.numEnabledCursors > 0 then
            afterExport.operatorfunc = afterExport.operatorfunc
                or vim.o.operatorfunc
            vim.o.operatorfunc =
                "v:lua.require'multicursor-nvim.native.cursor-manager'._mirror"
            typed[#typed + 1] = "g@l"
        end
        if state.mainCursor:hasSelection() and state.numEnabledCursors > 0 then
            vim.fn.setpos("'<", state.mainCursor._visualStart)
            vim.fn.setpos("'>", state.mainCursor._visualEnd)
            vim.fn.setpos(".", state.mainCursor._vPos)
        else
            cursorWrite(state.mainCursor)
            afterExport.mainPos = vim.fn.getcurpos()
        end
        if next(afterExport) then
            state.afterExport = afterExport
        end
    end
    if state.mainCursor == origCursor and opts.fixWindow ~= false then
        fixWindowScroll(origCursor, winStartLine)
    end
    cursorClearMarks(state.mainCursor)
    if #typed > 0 then
        vim.api.nvim_feedkeys(table.concat(typed), "tn", false)
    end

    state.performing = false
    state.cursors = {}
    state.mainCursor = nil
    unsetOptions()

    local errors = tbl.uniq(state.errors)
    state.errors = {}
    for _, error in ipairs(errors) do
        util.echoerr(error, false)
    end
    if not success then
        error(result, 0)
    end
    return result
end

--- @param direction integer
function CursorManager:navigateJumplist(direction)
    local key = direction < 0 and TERM_CODES.CTRL_O or TERM_CODES.CTRL_I
    local count = math.abs(direction)
    self:action(function(ctx)
        ctx:mainCursor():perform(function()
            vim.api.nvim_feedkeys(count .. key, "nx", false)
        end)
    end, {})
end

--- Returns whether all cursors are enabled.
--- @return boolean
function CursorManager:cursorsEnabled()
    if state.performing then
        return CursorContext:cursorsEnabled()
    end
    local buf = vim.api.nvim_get_current_buf()
    return #get_extmarks(buf, DISABLED_NS, 0, -1, { limit = 1 }) == 0
end

--- Returns whether there are virtual cursors.
--- @return boolean
function CursorManager:hasCursors()
    if state.performing then
        return CursorContext:hasCursors()
    end
    return bufHasCursors(vim.api.nvim_get_current_buf())
end

--- Removes all cursors.
function CursorManager:clear()
    CursorContext:clear()
end

--- Returns the total number of cursors.
--- There is always at least one cursor (the main cursor).
--- @return integer
function CursorManager:numCursors()
    return self:numEnabledCursors() + self:numDisabledCursors()
end

--- Returns number of enabled cursors.
--- There is always at least one enabled cursor (the main cursor).
--- @return integer
function CursorManager:numEnabledCursors()
    if state.performing then
        return CursorContext:numEnabledCursors()
    end
    local buf = vim.api.nvim_get_current_buf()
    return #get_extmarks(buf, NATIVE_NS, 0, -1, {}) + 1
end

--- Returns the number of disabled cursors.
--- @return integer
function CursorManager:numDisabledCursors()
    if state.performing then
        return CursorContext:numDisabledCursors()
    end
    local buf = vim.api.nvim_get_current_buf()
    return #get_extmarks(buf, DISABLED_NS, 0, -1, {})
end

return CursorManager
