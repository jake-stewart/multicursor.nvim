local cursor = require("multicursor-nvim.cursor")
local TERM_CODES = require("multicursor-nvim.term-codes")
local tbl = require("multicursor-nvim.tbl")
local util = require("multicursor-nvim.util")

--- @package
--- @class mc.State
--- @field signIds? integer[]
--- @field stateHistory table<integer, mc.StateHistoryItem>
--- @field virtualEditBlock? boolean
--- @field cursorline? boolean
--- @field visual? boolean
--- @field undoItems table<string, mc.MultiCursorUndoItem>
--- @field redoItems table<string, mc.MultiCursorUndoItem>
--- @field currentSeq integer | nil
--- @field changedtick integer | nil
--- @field leftcol number
--- @field textoffset number
--- @field eol_listchar boolean
--- @field yanked? boolean
--- @field yankedWhileDisabled table<integer, boolean>
--- @field mainSignHlExists? boolean
--- @field jumps mc.Pos[]
--- @field jumpIdx integer
--- @field signsOnLeft? boolean
--- @field renderSigns? boolean
--- @field package lastJump? mc.Pos
local state = cursor.state
local CursorContext = cursor.CursorContext
local CursorState = cursor.CursorState
local VISUAL_LOOKUP = cursor.VISUAL_LOOKUP
local get_lines = cursor.get_lines
local isVisualMode = cursor.isVisualMode
local isSelectMode = cursor.isSelectMode
local compareMarkPos = cursor.compareMarkPos
local compareCursorsPosition = cursor.compareCursorsPosition
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
local cursorCopy = cursor.cursorCopy
local fixWindowScroll = cursor.fixWindowScroll

local set_extmark = vim.api.nvim_buf_set_extmark
local del_extmark = vim.api.nvim_buf_del_extmark
local clear_namespace = vim.api.nvim_buf_clear_namespace

--- @param cur integer Undo sequence ID
--- @return string
local function undoItemId(cur)
    return vim.fn.bufnr() .. ":" .. cur
end

local function historyItemId()
    return vim.fn.win_getid() .. ":" .. vim.fn.bufnr()
end

--- @param a mc.Pos
--- @param b mc.Pos
local function positionsEqual(a, b)
    return a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

--- @class mc.Cursor
--- @field package _visualIds integer[] | nil
--- @field package _jumps mc.Pos[]
--- @field package _jumpIdx integer

--- @class mc.MultiCursorUndoItem
--- @field data number[]
--- @field enabled boolean

--- @package
--- @class mc.StateHistoryItem
--- @field cursor? mc.Cursor
--- @field cursors mc.Cursor[]
--- @field seqCur integer
--- @field jumplist mc.Pos[]
--- @field jumpIdx integer

--- @class mc._VisualRenderPart
--- @field priority? integer
--- @field line integer
--- @field col integer
--- @field endCol integer
--- @field lineLength integer
--- @field lineWidth integer

--- @param hl string
--- @param part mc._VisualRenderPart
local function renderVisualPart(hl, part)
    local shift = part.lineWidth
            + (part.col > part.lineLength
                and (part.col - part.lineLength - 1) or 0) - state.leftcol
    return set_extmark(0, state.nsid, part.line - 1, part.col - 1, {
        strict = false,
        undo_restore = false,
        priority = part.priority or 2000,
        virt_text = part.endCol > part.lineLength
            and (part.col > part.lineLength
                and {{
                    string.rep(" ", part.endCol - part.col + 1
                        + math.min(0, shift)),
                    hl,
                }}
                or {{
                    string.rep(" ", part.endCol - part.lineLength
                        + math.min(0, shift)),
                    hl,
                }}
            ) or nil,
        end_col = part.endCol,
        virt_text_pos = "overlay",
        virt_text_win_col = math.max(0, shift),
        hl_group = hl,
    })
end

--- @param cursor mc.Cursor
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
    --- @type mc._VisualRenderPart[]
    local parts = {}
    for lnum = vs[2], ve[2] do
        local idx = lnum - start;
        table.insert(parts, {
            line = lnum,
            col = 1,
            endCol = #lines[idx] + (state.eol_listchar and 1 or 0),
            lineLength = #lines[idx],
            lineWidth = vim.fn.strdisplaywidth(lines[idx])
        } --[[ as mc._VisualRenderPart ]])
    end
    if vs[2] == ve[2] then
        parts[1].col = vs[3] + (vs[3] > #lines[vs[2] - start] and vs[4] or 0)
        parts[1].endCol = ve[3] + (ve[3] > #lines[ve[2] - start] and ve[4] or 0)
    else
        parts[1].col = vs[3] + (vs[3] > #lines[vs[2] - start] and vs[4] - 1 or 0)
        if vs[3] > #lines[vs[2] - start] then
            parts[1].col = parts[1].col + 1
            parts[1].endCol = parts[1].col
        end
        parts[#parts].endCol = ve[3]
            + (ve[3] > #lines[ve[2] - start] and ve[4] or 0)
    end
    for _, part in ipairs(parts) do
        table.insert(cursor._visualIds, renderVisualPart(hl, part))
    end
end

--- @param cursor mc.Cursor
--- @param lines string[]
--- @param start integer
--- @param hl string
local function cursorDrawVisualLine(cursor, lines, start, hl)
    local visualStart, visualEnd = cursor:getVisual()
    for i = visualStart[1], visualEnd[1] do
        local idx = i - start
        table.insert(cursor._visualIds, renderVisualPart(hl, {
            line = i,
            col = 1,
            endCol = #lines[idx] + (state.eol_listchar and 1 or 0),
            lineLength = #lines[idx],
            lineWidth = vim.fn.strdisplaywidth(lines[idx])
        }))
    end
end

--- @param cursor mc.Cursor
--- @param lines string[]
--- @param start integer
--- @param hl string
local function cursorDrawVisualBlock(cursor, lines, start, hl)
    local minLine = math.min(cursor._pos[2], cursor._vPos[2])
    local maxLine = math.max(cursor._pos[2], cursor._vPos[2])
    local virtCols = {
        vim.fn.virtcol({ cursor._pos[2], cursor._pos[3] }) + cursor._pos[4],
        vim.fn.virtcol({ cursor._vPos[2], cursor._vPos[3] }) + cursor._vPos[4]
    }
    local minVirtCol = math.min(virtCols[1], virtCols[2])
    local maxVirtCol = minVirtCol == virtCols[1]
        and virtCols[2] or virtCols[1]

    --- @type mc._VisualRenderPart[]
    local parts = {}

    for lnum = minLine, maxLine do
        local idx = lnum - start;
        local displayWidth = vim.fn.strdisplaywidth(lines[idx])
        if state.virtualEditBlock then
            table.insert(parts, {
                line = lnum,
                col = displayWidth > minVirtCol
                    and vim.fn.virtcol2col(0, lnum, minVirtCol)
                    or #lines[idx] + minVirtCol - displayWidth,
                endCol = displayWidth >= maxVirtCol
                    and vim.fn.virtcol2col(0, lnum, maxVirtCol)
                    or #lines[idx] + maxVirtCol - displayWidth,
                lineLength = #lines[idx],
                lineWidth = displayWidth
            } --[[ @as mc._VisualRenderPart ]])
        elseif cursor._pos[5] == vim.v.maxcol then
            table.insert(parts, {
                line = lnum,
                col = 1,
                endCol = #lines[idx] + (state.eol_listchar and 1 or 0),
                lineLength = #lines[idx],
                lineWidth = displayWidth
            } --[[ @as mc._VisualRenderPart ]])
        elseif displayWidth >= minVirtCol then
            table.insert(parts, {
                line = lnum,
                col = displayWidth >= minVirtCol
                    and vim.fn.virtcol2col(0, lnum, minVirtCol)
                    or #lines[idx] + (state.eol_listchar and 1 or 0),
                endCol = displayWidth >= maxVirtCol
                    and vim.fn.virtcol2col(0, lnum, maxVirtCol)
                    or #lines[idx] + (state.eol_listchar and 1 or 0),
                lineLength = #lines[idx],
                lineWidth = displayWidth
            } --[[ @as mc._VisualRenderPart ]])
        end
    end
    for _, part in ipairs(parts) do
        table.insert(cursor._visualIds, renderVisualPart(hl, part))
    end
end

--- @alias mc._CursorDrawFunc fun(
---     cursor: mc.Cursor,
---     lines: string[],
---     start: integer,
---     hl: string)

--- @class mc._VisualInfo
--- @field draw mc._CursorDrawFunc

VISUAL_LOOKUP.v.draw = cursorDrawVisualChar
VISUAL_LOOKUP.V.draw = cursorDrawVisualLine
VISUAL_LOOKUP[TERM_CODES.CTRL_V].draw = cursorDrawVisualBlock
VISUAL_LOOKUP.s.draw = cursorDrawVisualChar
VISUAL_LOOKUP.S.draw = cursorDrawVisualLine
VISUAL_LOOKUP[TERM_CODES.CTRL_S].draw = cursorDrawVisualBlock

--- @param cursor mc.Cursor
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
    local outOfBounds = virtCol >= #charLine

    local id = renderVisualPart(cursorHL, {
        priority = priority,
        col = outOfBounds and (virtCol + 1) or (col + 1),
        line = row + 1,
        endCol = outOfBounds and (virtCol + 1) or (col + 1),
        lineLength = #charLine,
        lineWidth = vim.fn.strdisplaywidth(charLine),
    })

    cursor._visualIds[#cursor._visualIds + 1] = id
end

--- @param cursor mc.Cursor
local function cursorErase(cursor)
    if cursor._visualIds then
        for _, id in ipairs(cursor._visualIds) do
            del_extmark(0, state.nsid, id)
        end
        cursor._visualIds = nil
    end
end

--- @param cursor mc.Cursor
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

-- cursors are packed together for undo history like so
-- id1, line1, col1, id2, line2, col2
-- the id is of each cursor is negative if the cursor is disabled

--- @param cursors mc.Cursor[]
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

--- @param cursors mc.Cursor[]
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
    if #state.cursors > 0 then
        for _, cursor in ipairs(state.cursors) do
            cursorLookup[cursor._id] = cursor
        end
    else
        local item = state.stateHistory[historyItemId()]
        if item then
            for _, cursor in ipairs(item.cursors) do
                cursorLookup[cursor._id] = cursor
            end
        end
    end
    state.cursors = {}
    local newMainCursor
    state.numDisabledCursors = 0
    state.numEnabledCursors = 0
    state.numLines = vim.fn.line("$")
    for i = 1, #data, 3 do
        if data[i + 1] >= 1 and data[i + 1] <= state.numLines then
            local cursor = cursorLookup[math.abs(data[i])]
                or cursorCopy(state.mainCursor)
            local col = math.max(1,
                math.min(
                    data[i + 2],
                    #get_lines(0, data[i + 1] - 1, data[i + 1])[1]
                )
            )
            local curswantVirtcol = vim.fn.virtcol(
                { data[i + 1], data[i + 2] })
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
        state.mainCursor = CursorContext:nearestCursor(
            state.mainCursor:getPos())
    end
end

--- @return mc.Cursor[], boolean
local function cursorContextMergeCursors()
    --- @type mc.Cursor[]
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

local function clearCursorContext()
    clear_namespace(0, state.nsid, 0, -1)
    state.signIds = nil
    state.numDisabledCursors = 0
    state.numEnabledCursors = 0
    state.lastJump = nil
    state.jumps = {}
    state.errors = {}
    state.jumpIdx = 0
    state.yankedWhileDisabled = {}
    state.yankedWhileActive = false
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

--- Removes all cursors.
local function cursorContextClear()
    if #state.cursors > 0 then
        state.stateHistory[historyItemId()] = {
            cursor = state.mainCursor
                and cursorCopy(state.mainCursor, false) or nil,
            cursors = tbl.map(state.cursors,
                function(c) return cursorCopy(c, false) end),
            seqCur = state.currentSeq,
            jumpIdx = state.jumpIdx,
            jumplist = state.jumps
        }
    end
    clearCursorContext()
end

--- @param self mc.CursorContext
local function cursorContextRestore(self)
    if self:hasCursors() then
        return
    end
    local id = historyItemId()
    local item = state.stateHistory[id]
    if not item or item.seqCur ~= state.currentSeq then
        return
    end
    if state.mainCursor then
        state.mainCursor:delete()
        state.mainCursor = nil
    end
    for _, cursor in ipairs(state.cursors) do
        cursor:delete()
    end
    state.jumps = item.jumplist
    state.jumpIdx = item.jumpIdx
    for _, cursor in ipairs(item.cursors) do
        state.cursors[#state.cursors + 1] = cursor
        cursor._state = CursorState.new
        cursorSetMarks(cursor)
    end
    if item.cursor then
        state.mainCursor = cursorCopy(item.cursor, false)
        state.mainCursor._state = CursorState.new
        cursorSetMarks(state.mainCursor)
    end
end

--- @param cursor mc.Cursor
--- @return mc.Cursor
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
    local sc = vim.o.signcolumn

    state.renderSigns =
        sc ~= "no" and sc ~= "number"
        or sc == "number"
            and (vim.o.number or vim.o.relativenumber)

    if not state.renderSigns then
        return
    end

    local signsOnLeft = string.match(sc, "yes")
        or string.match(sc, "auto")
        or sc == "number"
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
            state.alignedSigns[offset] =
                rightSpace .. state.signs[n] .. leftSpace
            state.alignedSigns[offset + 1] =
                leftChar .. (state.signs[1] or " ") .. rightChar
            state.alignedSigns[offset + 2] =
                leftChar .. (state.signs[2] or " ") .. rightChar
            state.alignedSigns[offset + 3] =
                leftChar .. (state.signs[3] or " ") .. rightChar
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
        state.signIds = nil
    end
    if not state.renderSigns then
        return
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
            signsToAdd[line] = math.max(signsToAdd[line] or 0,
                cursor._enabled and 2 or 1)
        end
    end
    signsToAdd[state.mainCursor._pos[2]] = 2
    for line, level in pairs(signsToAdd) do
        if level == 2 and hasDisabledCursor then
            level = 3
        end
        local signIdx
        if line == ws then
            signIdx = (cursorAbove == 0 and 0
                or cursorAbove == 2 and 4 or 12) + level
        elseif line == we then
            signIdx = (cursorBelow == 0 and 0
                or cursorBelow == 2 and 8 or 16) + level
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
                    state.mainCursor._changePos =
                        state.mainCursor._origChangePos
                    if not state.mainCursor._redoChangePos then
                        state.mainCursor._redoChangePos =
                            state.mainCursor._pos
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

--- @class mc.CursorManager
local CursorManager = {}

--- @param nsid integer
--- @param opts mc.MultiCursorOpts
function CursorManager:setup(nsid, opts)
    state.native = false
    state.nsid = nsid
    state.opts = opts or {}
    CursorContext.clear = cursorContextClear
    CursorContext.restore = cursorContextRestore
    state.stateHistory = {}
    state.undoItems = {}
    state.redoItems = {}
    state.leftcol = 0
    state.textoffset = 0
    state.jumps = {}
    state.didPushJump = false
    state.jumpIdx = 0
    state.yankedWhileDisabled = {}

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
            else
                state.stateHistory = {}
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
    if state.mainSignHlExists == nil then
        state.mainSignHlExists = vim.fn.hlexists("MultiCursorMainSign") == 1
    end
    if state.mainSignHlExists == true then
        return
    end
    local cursorline = vim.o.cursorline
    local mode = vim.fn.mode()
    local visual = isVisualMode(mode) or isSelectMode(mode)
    if cursorline == state.cursorline and state.visual == visual then
        return
    end
    state.cursorline = cursorline
    state.visual = visual
    local newHl = vim.api.nvim_get_hl(0, {
        name = "MultiCursorSign",
        link = false
    })
    if visual or not cursorline then
        -- don't show cursorline
    elseif vim.o.signcolumn == "number"
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

    --- hl is actually compatible
    --- @diagnostic disable-next-line: param-type-mismatch
    vim.api.nvim_set_hl(0, "MultiCursorMainSign", newHl)
end

--- @param opts mc.ActionOptions
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
    state.virtualEdit = false
    for _, key in ipairs(vim.opt.virtualedit:get()) do
        if key == "block" then
            state.virtualEditBlock = true
        end
        if key == "all" then
            state.virtualEditBlock = true
            state.virtualEdit = true
            break
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
    updateSigns()
    updateCursorline()
    setOptions()
    updateVirtualEdit()
    state.tabstop = vim.o.tabstop
    state.listChars = vim.o.list
    -- state.leftcol = vim.fn.winsaveview().leftcol
    state.textoffset = vim.fn.getwininfo(vim.fn.win_getid())[1].textoff
    state.exclusive = vim.o.selection == "exclusive"
    state.eol_listchar = vim.opt.listchars:get().eol ~= nil

    tryUndo(opts)
    state.errors = {}

    local jump = vim.fn.getpos("''")
    local didJump = not state.lastJump
        or not positionsEqual(jump, state.lastJump)
    if didJump then
        state.lastJump = jump
        if opts.allowUndo and not (
            #state.jumps > 0
            and state.mainCursor
            and positionsEqual(state.jumps[state.jumpIdx],
                state.mainCursor._pos)
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
        state.yankedWhileActive = true
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
            state.yankedWhileDisabled[vim.api.nvim_get_current_buf()] = true
        end
    elseif not state.yankedWhileActive then
        --- @type mc.StateHistoryItem
        local item = state.stateHistory[historyItemId()]
        if item then
            local oldCursors = tbl.shallow_copy(item.cursors)
            local newCursors = tbl.shallow_copy(state.cursors)
            newCursors[#newCursors + 1] = state.mainCursor
            oldCursors[#oldCursors + 1] = item.cursor
            table.sort(newCursors, compareCursorsPosition)
            table.sort(oldCursors, compareCursorsPosition)
            for i, oldCursor in ipairs(oldCursors) do
                local newCursor = newCursors[i]
                if not newCursor then
                    break
                end
                newCursor._register = oldCursor._register
            end
            state.mainCursor._register.points_to = nil
            vim.fn.setreg("", state.mainCursor._register)
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
        state.stateHistory[historyItemId()] = {
            cursor = state.mainCursor
                and cursorCopy(state.mainCursor, false) or nil,
            cursors = tbl.map(state.cursors,
                function (c) return cursorCopy(c, false) end),
            seqCur = state.currentSeq,
            jumpIdx = state.jumpIdx,
            jumplist = state.jumps
        }
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

function CursorManager:dirty()
    state.modifiedId = state.modifiedId + 1
    state.numLines = vim.fn.line("$")
end

--- Returns whether all cursors are enabled.
--- @return boolean
function CursorManager:cursorsEnabled()
    return CursorContext:cursorsEnabled()
end

--- Returns whether there are virtual cursors.
--- @return boolean
function CursorManager:hasCursors()
    return CursorContext:hasCursors()
end

--- Removes all cursors.
function CursorManager:clear()
    CursorContext:clear()
end

--- Returns the total number of cursors.
--- There is always at least one cursor (the main cursor).
--- @return integer
function CursorManager:numCursors()
    return CursorContext:numCursors()
end

--- Returns number of enabled cursors.
--- There is always at least one enabled cursor (the main cursor).
--- @return integer
function CursorManager:numEnabledCursors()
    return CursorContext:numEnabledCursors()
end

--- Returns the number of disabled cursors.
--- @return integer
function CursorManager:numDisabledCursors()
    return CursorContext:numDisabledCursors()
end

return CursorManager
