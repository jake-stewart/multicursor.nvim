local mc = require("multicursor-nvim.core")
local tbl = require("multicursor-nvim.tbl")
local util = require("multicursor-nvim.util")
local TERM_CODES = require("multicursor-nvim.term-codes")

local setOpfunc = vim.fn[vim.api.nvim_exec([[
  func s:setOpfunc(val)
    let &opfunc = a:val
  endfunc
  echon get(function('s:setOpfunc'), 'name')
]], true)]


-- All of the default actions like match, select, transpose
-- are implemented using the same api provided to users.
--
-- This file should be a good reference if you want to
-- implement your own complex logic.
--
-- If you feel like something is missing from the api then
-- please open an issue.

local examples = {}

function examples.splitCursors(pattern)
    mc.action(function(ctx)
        pattern = pattern or vim.fn.input("Split: ")
        if not pattern or pattern == "" then
            return
        end
        --- @type Cursor[]
        local newCursors = {}
        ctx:forEachCursor(function(cursor)
            for _, newCursor in ipairs(cursor:splitVisualLines()) do
                newCursors[#newCursors + 1] = newCursor
            end
        end)
        --- @param cursor Cursor
        local function pushCursor(cursor, startCol, endCol)
            local newCursor = cursor:clone()
            local pos = cursor:getPos()
            local vs = cursor:getVisual()
            local col = vs[2]
            newCursor:setVisual(
                { pos[1], col + startCol },
                { pos[1], col + endCol }
            )
        end
        for _, cursor in ipairs(newCursors) do
            local selection = cursor:getVisualLines()
            local matches = util.matchlist(selection, pattern, {
                userConfig = true,
            })
            local nextIdx = 0
            for _, match in ipairs(matches) do
                if match.byteidx ~= nextIdx then
                    pushCursor(cursor, nextIdx, match.byteidx - 1)
                end
                nextIdx = match.byteidx + #match.text
            end
            if nextIdx < #selection[1] then
                pushCursor(cursor, nextIdx, #selection[1] - 1)
            end
            cursor:delete()
        end
    end)
end

function examples.matchCursors(pattern)
    mc.action(function(ctx)
        pattern = pattern or vim.fn.input("Match: ")
        if not pattern or pattern == "" then
            return
        end
        --- @type Cursor[]
        local newCursors = {}
        ctx:forEachCursor(function(cursor)
            if cursor:hasSelection() then
                newCursors = tbl.concat(
                    newCursors, cursor:splitVisualLines())
            else
                newCursors[#newCursors + 1] = cursor
                cursor:setMode("v")
            end
        end)
        for _, cursor in ipairs(newCursors) do
            local selection = cursor:getVisualLines()
            local matches = util.matchlist(selection, pattern, {
                userConfig = true,
            })
            local vs = cursor:getVisual()
            for _, match in ipairs(matches) do
                if #match.text > 0 then
                    local newCursor = cursor:clone()
                    newCursor:setVisual(
                        { vs[1], vs[2] + match.byteidx + #match.text - 1 },
                        { vs[1], vs[2] + match.byteidx }
                    )
                    newCursor:setMode("n")
                end
            end
            cursor:delete()
        end
    end)
end

--- @param direction -1 | 1
function examples.transposeCursors(direction)
    mc.action(function(ctx)
        ctx:forEachCursor(function(cursor)
            cursor:splitVisualLines()
        end)
        local cursors = ctx:getCursors()
        local values = tbl.map(cursors, function(cursor)
            return cursor:getVisualLines()[1]
        end)
        for i, cursor in ipairs(cursors) do
            local idx = ((i - direction - 1) % #values) + 1
            cursor:feedkeys('"_c' .. values[idx] .. TERM_CODES.ESC .. "v`<o")
        end
        ctx:seekCursor(ctx:mainCursor():getPos(), direction, true):select()
    end)
end

--- @param direction -1 | 1
--- @param wrap? boolean
function examples.swapCursors(direction, wrap)
    mc.action(function(ctx)
        local mainCursor = ctx:mainCursor()
        local otherCursor = ctx:seekCursor(
            mainCursor:getPos(), direction, wrap)
        if otherCursor and otherCursor ~= mainCursor then
            local mainLines = mainCursor:getVisualLines()
            local otherLines = otherCursor:getVisualLines()
            mainCursor:setVisualLines(otherLines)
            otherCursor:setVisualLines(mainLines)
            otherCursor:select()
        end
    end)
end

function examples.alignCursors()
    mc.action(function(ctx)
        local startLine = ctx:firstCursor():line()
        local endLine = ctx:lastCursor():line()

        local lines = vim.api.nvim_buf_get_lines(
            0, startLine - 1, endLine, false)

        local rows = {}
        local prevLine = nil
        ctx:forEachCursor(function(cursor)
            local col = #lines[cursor:line() - startLine + 1] > 0
                and cursor:col()
                or 0
            -- if col == 0 then
            --     cursor:delete()
            --     return
            -- end
            local row
            if prevLine == cursor:line() then
                row = rows[#rows]
            else
                row = {}
                rows[#rows + 1] = row
                prevLine = cursor:line()
            end
            row[#row + 1] = col
        end)

        local numColumns = tbl.reduce(rows,
            function(n, row) return math.max(n, #row) end, 0)

        for i = 1, numColumns do
            local maxCol = tbl.reduce(rows,
                function (n, row) return math.max(n, row[i] or 0) end, 0)
            for _, row in ipairs(rows) do
                row[i] = maxCol - row[i]
                for j = i + 1, numColumns do
                    row[j] = (row[j] or 0) + row[i]
                end
            end
        end

        prevLine = nil
        local rowIdx = 0
        local colIdx = 0
        ctx:forEachCursor(function(cursor)
            if prevLine ~= cursor:line() then
                prevLine = cursor:line()
                rowIdx = rowIdx + 1
                colIdx = 0
            end
            colIdx = colIdx + 1
            local row = rows[rowIdx]
            local distance = row[colIdx]
            if distance > 0 then
                cursor:feedkeys(distance .. "i <esc>l", { keycodes = true })
            else
                cursor:feedkeys("i<esc>l", { keycodes = true })
            end
            cursor:setRedoChangePos(cursor:getPos())
        end)
    end)
end

--- @param ctx CursorContext
--- @param motion? string | fun(cursor: Cursor)
local function addCursor(ctx, motion, opts)
    opts = opts or {}
    if opts.remap == nil then
        opts.remap = true
    end
    if motion then
        local mainCursor = ctx:mainCursor()
        if opts.addCursor then
            mainCursor:clone()
        end
        local vs, ve = mainCursor:getVisual()
        local oldMode = mainCursor:mode()
        local atVisStart = mainCursor:atVisualStart()
        if type(motion) == "string" then
            mainCursor:feedkeys(motion, opts)
        else
            motion(mainCursor)
        end
        local newPos = mainCursor:getPos()
        local rowDiff = newPos[1] - vs[1]
        local colDiff = mainCursor:mode() == "n"
            and newPos[2] - vs[2]
            or atVisStart
                and vs[2] - newPos[2]
                or newPos[2] - ve[2]
        mainCursor:setMode(oldMode)
        local startRow = vs[1] + rowDiff
        local startCol = vs[2] + colDiff
        local endRow = ve[1] + rowDiff
        local endCol = ve[2] + colDiff
        if oldMode == "V" or oldMode == "S" then
            startCol = vs[2]
            endCol = ve[2]
        end
        if atVisStart then
            mainCursor:setVisual(
                { endRow, endCol },
                { startRow, startCol }
            )
        else
            mainCursor:setVisual(
                { startRow, startCol },
                { endRow, endCol }
            )
        end
    else
        ctx:forEachCursor(function(cursor)
            if cursor:isMainCursor() then
                cursor:clone():disable()
                cursor:setMode("n")
            else
                cursor:disable()
            end
        end)
    end
end

--- @param motion? string | fun(cursor: Cursor)
--- @param opts? { remap?: boolean }
function examples.addCursor(motion, opts)
    mc.action(function(ctx)
        addCursor(ctx, motion, {
            addCursor = true,
            remap = opts and opts.remap,
        })
    end)
end

--- @param motion string | fun(cursor: Cursor)
--- @param opts? { remap?: boolean }
function examples.skipCursor(motion, opts)
    mc.action(function(ctx)
        addCursor(ctx, motion, {
            addCursor = false,
            remap = opts and opts.remap,
        })
    end)
end

--- @return SimplePos
local function getMousePos()
    local mousePos = vim.fn.getmousepos()
    return {
        mousePos.line,
        mousePos.column,
        vim.o.virtualedit == "all"
            --- @diagnostic disable
            and mousePos.coladd
            or nil
    }
end

local mouseDragAdd = true
local mouseDragPos = nil

function examples.handleMouse()
    mc.action(function(ctx)
        mouseDragPos = getMousePos()
        local existingCursor = ctx:getCursorAtPos(mouseDragPos)
        if existingCursor then
            if ctx:numCursors() == 1 then
                mouseDragAdd = true
            else
                existingCursor:delete()
                mouseDragAdd = false
            end
        else
            mouseDragAdd = true
            local mainCursor = ctx:mainCursor()
                mainCursor:clone()
            mainCursor:setPos(mouseDragPos)
                :setVisualAnchor(mouseDragPos)
        end
    end)
end

function examples.handleMouseDrag()
    if mouseDragPos == nil then
        mouseDragPos = getMousePos()
        mouseDragAdd = true
    end
    mc.action(function(ctx)
        local pos = getMousePos()
        pos[2] = mouseDragPos[2]
        local endRow = pos[1]
        if endRow == 0 then
            return
        end
        local direction = mouseDragPos[1] < endRow and 1 or -1
        for i = mouseDragPos[1], endRow, direction do
            pos[1] = i
            local existingCursor = ctx:getCursorAtPos(pos)
            if mouseDragAdd then
                if existingCursor then
                    existingCursor:select()
                else
                    if pos[2] < vim.fn.col({pos[1], "$"}) then
                        local mainCursor = ctx:mainCursor()
                            mainCursor:clone()
                        mainCursor:setPos(pos):setVisualAnchor(pos)
                    end
                end
            else
                local existingCursor = ctx:getCursorAtPos(pos)
                if existingCursor then
                    existingCursor:delete()
                end
            end
        end
    end)
end

function examples.handleMouseRelease()
    mouseDragAdd = true
    mouseDragPos = nil
end

function examples.restoreCursors()
    mc.action(function(ctx)
        ctx:restore()
    end)
end

function examples.disableCursors()
    mc.action(function(ctx)
        local mainCursor = ctx:mainCursor()
        mainCursor:clone()
        ctx:setCursorsEnabled(false)
        mainCursor:setMode("n")
    end)
end

function examples.enableCursors()
    mc.action(function(ctx)
        local cursors = ctx:getCursors()
        ctx:setCursorsEnabled(true)
        for _, cursor in ipairs(cursors) do
            cursor:delete()
        end
    end)
end

function examples.toggleCursor()
    mc.action(function(ctx)
        ctx:setCursorsEnabled(false)
        local mainCursor = ctx:mainCursor()
        local cursor = mainCursor:overlappedCursor()
        if cursor then
            cursor:delete()
        else
            local newCursor = mainCursor:clone()
            mainCursor:disable()
            newCursor:setMode("n"):select()
        end
    end)
end

function examples.duplicateCursors()
    mc.action(function(ctx)
        ctx:forEachCursor(function(cursor)
            cursor:clone():disable()
            cursor:setMode("n")
        end)
    end)
end

function examples.visualToCursors()
    mc.action(function(ctx)
        ctx:forEachCursor(function(cursor)
            cursor:splitVisualLines()
        end)
        ctx:forEachCursor(function(cursor)
            cursor:feedkeys(TERM_CODES.ESC)
        end)
    end)
end

function examples.insertVisual()
    local mode = vim.fn.mode()
    mc.action(function(ctx)
        ctx:forEachCursor(function(cursor)
            cursor:splitVisualLines()
        end)
        ctx:forEachCursor(function(cursor)
            cursor:feedkeys(
                (cursor:atVisualStart() and "" or "o")
                    .. "<esc>"
                    .. (mode == TERM_CODES.CTRL_V and "" or "^"),
                { keycodes = true }
            )
        end)
    end)
    mc.feedkeys(mode == TERM_CODES.CTRL_V and "i" or "I")
end

function examples.appendVisual()
    local mode = vim.fn.mode()
    mc.action(function(ctx)
        ctx:forEachCursor(function(cursor)
            cursor:splitVisualLines()
        end)
        ctx:forEachCursor(function(cursor)
            cursor:feedkeys(
                (cursor:atVisualStart() and "o" or "")
                    .. "<esc>"
                    .. (mode == TERM_CODES.CTRL_V and "" or "$"),
                { keycodes = true }
            )
        end)
    end)
    mc.feedkeys(mode == TERM_CODES.CTRL_V and "a" or "A")
end

--- @param direction -1 | 1
local function selectBoundaryCursor(direction)
    mc.action(function(ctx)
        if ctx:numEnabledCursors() > 1 then
            ctx:seekBoundaryCursor(direction):select()
        else
            local mainCursor = ctx:mainCursor()
            local cursor = ctx:seekBoundaryCursor(direction, {
                disabledCursors = true,
                enabledCursors = false,
            })
            if cursor then
                cursor:select()
                mainCursor:delete()
                cursor:clone():disable()
            end
        end
    end)
end

function examples.firstCursor()
    selectBoundaryCursor(-1)
end

function examples.lastCursor()
    selectBoundaryCursor(1)
end

--- @param direction -1 | 1
--- @param wrap? boolean
local function selectRelativeCursor(direction, wrap)
    if wrap == nil then
        wrap = true
    end
    mc.action(function(ctx)
        local mainCursor = ctx:mainCursor()
        if ctx:numEnabledCursors() > 1 then
            local cursor = ctx:seekCursor(mainCursor:getPos(), direction, wrap)
            if cursor then
                cursor:select()
            end
        else
            local opts = { disabledCursors = true }
            local cursor = ctx:seekCursor(mainCursor:getPos(), direction, wrap, opts)
            if cursor then
                cursor:select()
                mainCursor:delete()
                cursor:clone():disable()
            end
        end
    end)
end

--- @param wrap? boolean default true
function examples.nextCursor(wrap)
    selectRelativeCursor(1, wrap)
end

--- @param wrap? boolean default true
function examples.prevCursor(wrap)
    selectRelativeCursor(-1, wrap)
end

function examples.deleteCursor()
    mc.action(function(ctx)
        ctx:mainCursor():delete()
    end)
end

function examples.deleteOverlappedCursor()
    mc.action(function(ctx)
        ctx:forEachCursor(function(cursor)
            local overlapped = cursor:overlappedCursor()
            if overlapped then
                overlapped:delete()
            end
        end)
    end)
end

local function escapeRegex(regex)
    regex = vim.fn.substitute(regex, "\\", "\\\\\\\\", "g")
    regex = vim.fn.substitute(regex, "/", "\\\\/", "g")
    regex = vim.fn.substitute(regex, "\n", "\\\\n", "g")
    return regex
end

local function isKeyword(s)
    return vim.fn.match(s, '\\v^\\k+$') >= 0
end

--- @param direction? -1 | 1
--- @param add boolean
local function matchAddCursor(direction, add)
    mc.action(function(ctx)
        local mainCursor = ctx:mainCursor()
        local cursorChar
        local cursorWord
        local searchWord
        if not mainCursor:hasSelection() then
            local c = mainCursor:col()
            cursorChar = string.sub(mainCursor:getLine(), c, c)
            cursorWord = mainCursor:getCursorWord()
            if cursorChar ~= ""
                and isKeyword(cursorChar)
                and string.find(cursorWord, cursorChar, 1, true)
            then
                searchWord = true
                mainCursor:feedkeys('"_yiw')
            end
        end
        addCursor(ctx, function(cursor)
            local regex
            local hasSelection = cursor:hasSelection()
            if hasSelection then
                regex = "\\C\\V" .. escapeRegex(table.concat(cursor:getVisualLines(), "\n"))
                if cursor:mode() == "V" or cursor:mode() == "S" then
                    cursor:feedkeys(cursor:atVisualStart() and "0" or "o0")
                elseif not cursor:atVisualStart() then
                    cursor:feedkeys("o")
                end
            else
                if cursorChar == "" then
                    regex = "\\v^$"
                elseif searchWord then
                    regex = "\\v<\\C\\V" .. escapeRegex(cursorWord) .. "\\v>"
                else
                    regex = "\\C\\V" .. escapeRegex(cursorChar)
                end
            end
            cursor:perform(function()
                vim.fn.search(regex, (direction == -1 and "b" or ""))
            end)
            if hasSelection then
                cursor:feedkeys(TERM_CODES.ESC)
            end
        end, { addCursor = add })
    end)
end

--- @param direction? -1 | 1
function examples.matchAddCursor(direction)
    matchAddCursor(direction, true)
end

--- @param direction? -1 | 1
function examples.matchSkipCursor(direction)
    matchAddCursor(direction, false)
end

function examples.matchAllAddCursors()
    mc.action(function(ctx)
        local mainCursor = ctx:mainCursor()
        local regex
        local hasSelection = mainCursor:hasSelection()
        if hasSelection then
            regex = "\\C\\V" .. escapeRegex(table.concat(mainCursor:getVisualLines(), "\n"))
        else
            local word = mainCursor:getCursorWord()
            regex = "\\v<\\C\\V" .. escapeRegex(word) .. "\\v>"
        end

        local startPos = mainCursor:getPos()
        local firstMatchPos = nil

        while true do
            addCursor(ctx, function(cursor)
                cursor:perform(function()
                    vim.fn.search(regex)
                end)
                if hasSelection then
                    cursor:feedkeys(TERM_CODES.ESC)
                end
            end, { addCursor = firstMatchPos ~= nil })
            local newPos = mainCursor:getPos()
            if not firstMatchPos then
                firstMatchPos = newPos
            elseif firstMatchPos[1] == newPos[1]
                and firstMatchPos[2] == newPos[2]
            then
                break
            end
        end
        mainCursor:setPos(startPos)
        mainCursor:delete()
    end)
end

--- @param direction? -1 | 1
--- @param add boolean
local function lineAddCursor(direction, add)
    mc.action(function(ctx)
        local mainCursor = ctx:mainCursor()
        local line, _, offset = table.unpack(mainCursor:getPos())
        if offset > 0 then
            addCursor(ctx, direction == -1 and "k" or "j", {
                addCursor = add,
                remap = false,
            })
            return
        end
        local virtCol = vim.fn.virtcol(".")
        local lastLine = vim.fn.line("$")
        local found = false
        while true do
            line = line + direction
            if line < 1 or line > lastLine then
                break
            end
            local maxCol = vim.fn.virtcol({ line, "$" })
            if virtCol == 1 or maxCol > virtCol then
                found = true
                break
            end
        end
        if not found then
            return
        end
        addCursor(ctx, function(cursor)
            cursor:setPos({
                line,
                vim.fn.virtcol2col(0, line, virtCol),
                offset,
            })
        end, { addCursor = add })
    end)
end

--- @param direction? -1 | 1
function examples.lineAddCursor(direction)
    lineAddCursor(direction, true)
end

--- @param direction? -1 | 1
function examples.lineSkipCursor(direction)
    lineAddCursor(direction, false)
end

function examples.addCursorOperator()
    local mode = vim.fn.mode()
    local curPos = vim.fn.getpos(".")
    local fromVisual = mode == "v"
        or mode == "V"
        or mode == TERM_CODES.CTRL_V
        or mode == "s"
        or mode == "S"
        or mode == TERM_CODES.CTRL_S
    local atVisualStart
    if fromVisual then
        local vPos = vim.fn.getpos("v")
        atVisualStart = curPos[2] < vPos[2]
            or curPos[2] == vPos[2]
            and (curPos[3] < vPos[3]
                or curPos[3] == vPos[3]
                and curPos[4] < vPos[4])
    end
    setOpfunc(function()
        mc.action(function(ctx)
            local mainCursor = ctx:mainCursor()
            local lastCursor
            local firstCursor
            local changeStart = vim.fn.getpos("'[")
            local changeEnd = vim.fn.getpos("']")
            for i = changeStart[2], changeEnd[2] do
                local col = math.min(
                    curPos[3],
                    vim.fn.col({ i, "$" }) - 1
                )
                lastCursor = mainCursor:clone():setPos({i, col})
                if not firstCursor then
                    firstCursor = lastCursor
                end
            end
            mainCursor:delete()
            if fromVisual then
                if atVisualStart then
                    firstCursor:select()
                else
                    lastCursor:select()
                end
            elseif curPos[2] == lastCursor:line() then
                firstCursor:select()
            else
                lastCursor:select()
            end
        end)
    end)
    vim.fn.feedkeys("g@", "nt")
end

local function matchCursorsRange(pattern, range, selection, visual)
    mc.action(function(ctx)
        if not pattern or pattern == "" then
            return
        end
        --- @type Cursor[]
        local newCursors = {}
        ctx:forEachCursor(function(cursor)
            if cursor:hasSelection() then
                newCursors = tbl.concat(newCursors, cursor:splitVisualLines())
            else
                newCursors[#newCursors + 1] = cursor
                cursor:setMode("v")
            end
        end)
        for _, cursor in ipairs(newCursors) do
            local matches = util.matchlist(selection, pattern, {
                userConfig = true,
            })
            for _, match in ipairs(matches) do
                if #match.text > 0 then
                    local newCursor = cursor:clone()
                    newCursor:setVisual({
                        range.startRow + match.idx,
                        (match.idx == 0 and range.startCol or 0)
                            + match.byteidx
                            + #match.text,
                    }, {
                        range.startRow + match.idx,
                        (match.idx == 0 and range.startCol or 0)
                            + match.byteidx
                            + 1,
                    })
                    if not visual then
                        newCursor:setMode("n")
                    end
                end
            end
            cursor:delete()
        end
    end)
end

-- Works both in visual and normal mode, if called from visual mode, pattern
-- and motion are ignored, wordBoundary defaults to false, the selected range
-- will be used to determine the pattern. You can either pass a motion or a
-- pattern in normal mode, which will be used to create cursors within the
-- range without you explicitly type the motion (e.g. iw) to capture the pattern.
---@param opts? { pattern: string, motion: string, visual: boolean, wordBoundary: boolean }
function examples.operator(opts)
    local function is_visual(mode)
        return mode == "v" or mode == "V" or mode == "\22"
    end

    local vMode
    if is_visual(vim.fn.mode()) then
        vim.cmd([[execute "normal! \<esc>"]])
        vMode = vim.fn.visualmode()
    end

    local state = vim.tbl_extend("force", {
        pattern = "",
        visual = false,
        motion = "",
        -- boundary makes no sense when calling from visual mode, also this
        -- default matches visual/normal mode "*".
        wordBoundary = vMode == nil,
    }, opts or {})

    local function getRange(visual)
        local s = vim.api.nvim_buf_get_mark(0, visual and "<" or "[")
        local e = vim.api.nvim_buf_get_mark(0, visual and ">" or "]")
        return { startRow = s[1], startCol = s[2], endRow = e[1], endCol = e[2] }
    end

    local function getSelection(range, vmode)
        if vmode == "char" or vmode == "v" then
            -- If we want to get selection inside an operatorfunc callback,
            -- vmode is one of "line", "char", or "block"; if we want to get
            -- visual mode selection, vmode is one of "v", "V", or "<CTRL-V>",
            -- in both cases, only if vmode is "char" or "v" we need to use
            -- nvim_buf_get_text.
            return vim.api.nvim_buf_get_text(
                0,
                range.startRow - 1,
                range.startCol,
                math.min(range.endRow - 1, vim.fn.line("$") - 1),
                range.endCol + 1,
                {}
            )
        else
            -- motion is linewise, col position doesn't matter,
            -- return entire lines.
            return vim.api.nvim_buf_get_lines(
                0,
                range.startRow - 1,
                range.endRow,
                false
            )
        end
    end

    setOpfunc(function(opMode)
        -- First stage to get pattern.
        if vMode ~= nil then
            -- If called from visual mode, opts.pattern and opts.motion are ignored,
            -- we get pattern from previous visual selection.
            state.pattern = string.format(
                state.wordBoundary and "\\M\\<%s\\>" or "\\M%s",
                getSelection(getRange(true), vMode)[1]
            )
        elseif state.pattern == "" then
            -- If user doesn't provide a pattern, we get pattern specified by '[
            -- and '] marker.
            state.pattern = string.format(
                state.wordBoundary and "\\<%s\\>" or "%s",
                getSelection(getRange(false), opMode)[1]
            )
        end
        local id = vim.fn.matchadd("MultiCursorMatchPreview", state.pattern, 2)
        vim.schedule(function()
            -- Press any key will clear the match.
            vim.api.nvim_create_autocmd("SafeState", {
                once = true,
                callback = function()
                    pcall(vim.fn.matchdelete, id)
                end,
            })
        end)
        setOpfunc(function(mode)
            -- Second stage to get range, only '[ and '] markers make sense
            -- here, we get selection by mode (one of "char", "line", or "block").
            local range = getRange(false)
            if mode ~= "char" then
                range.startCol = 0
            end
            matchCursorsRange(
                state.pattern,
                range,
                getSelection(range, mode),
                state.visual
            )
        end)
        vim.schedule(function()
            vim.api.nvim_feedkeys(string.format("g@"), "ni", false)
        end)
    end)
    if state.pattern ~= "" or vMode ~= nil then
        vim.api.nvim_feedkeys(string.format("g@l"), "ni", false)
    else
        vim.api.nvim_feedkeys(string.format("g@%s", state.motion or ""), "mi", false)
    end
end

return examples
