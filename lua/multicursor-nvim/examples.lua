local mc = require("multicursor-nvim.core")
local tbl = require("multicursor-nvim.tbl")
local util = require("multicursor-nvim.util")
local TERM_CODES = require("multicursor-nvim.term-codes")

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
        ctx:forEachCursor(function(cursor)
            cursor:splitVisualLines()
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
        ctx:forEachCursor(function(cursor)
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
        end)
        ctx:setCursorsEnabled(true)
    end)
end

function examples.matchCursors(pattern)
    mc.action(function(ctx)
        pattern = pattern or vim.fn.input("Match: ")
        if not pattern or pattern == "" then
            return
        end
        ctx:forEachCursor(function(cursor)
            cursor:splitVisualLines()
        end)
        ctx:forEachCursor(function(cursor)
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
        end)
        ctx:setCursorsEnabled(true)
    end)
end

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
        local pos = ctx:mainCursor():getPos()
        local cursor = direction == -1
            and (ctx:prevCursor(pos) or ctx:lastCursor())
            or (ctx:nextCursor(pos) or ctx:firstCursor())
        cursor:select()
        ctx:setCursorsEnabled(true)
    end)
end

function examples.alignCursors()
    mc.action(function(ctx)
        ctx:setCursorsEnabled(true)
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
            end
        end)
    end)
end

local function addCursor(motion, opts)
    mc.action(function(ctx)
        opts = opts or {}
        if opts.remap == nil then
            opts.remap = true
        end
        local mainCursor = ctx:mainCursor()
        if opts.addCursor then
            mainCursor:clone()
        end
        if motion then
            local vs, ve = mainCursor:getVisual()
            local oldMode = mainCursor:mode()
            local atVisStart = mainCursor:atVisualStart()
            mainCursor:feedkeys(motion, opts)
            local newPos = mainCursor:getPos()
            local rowDiff = newPos[1] - ve[1]
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
            ctx:setCursorsEnabled(true)
        else
            mainCursor:setMode("n")
        end
    end)
end

--- @param motion? string | fun(cursor: Cursor)
--- @param opts? { remap?: boolean }
function examples.addCursor(motion, opts)
    addCursor(motion, {
        addCursor = true,
        remap = opts and opts.remap,
    })
end

--- @param motion string | fun(cursor: Cursor)
--- @param opts? { remap?: boolean }
function examples.skipCursor(motion, opts)
    addCursor(motion, {
        addCursor = false,
        remap = opts and opts.remap,
    })
end

function examples.handleMouse()
    mc.action(function(ctx)
        local mousePos = vim.fn.getmousepos()
        local pos = {mousePos.line, mousePos.column}
        local existingCursor = ctx:getCursorAtPos(pos)
        if existingCursor then
            existingCursor:delete()
        else
            ctx:addCursor():setPos(pos)
        end
    end)
end

function examples.clearCursors()
    mc.action(function(ctx)
        ctx:clear()
    end)
end

function examples.disableCursors()
    mc.action(function(ctx)
        ctx:setCursorsEnabled(false)
        local mainCursor = ctx:mainCursor()
        mainCursor:clone()
        mainCursor:setMode("n")
    end)
end

function examples.enableCursors()
    mc.action(function(ctx)
        ctx:setCursorsEnabled(true)
        ctx:mainCursor():delete()
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

function examples.firstCursor()
    mc.action(function(ctx)
        ctx:firstCursor():select()
    end)
end

function examples.lastCursor()
    mc.action(function(ctx)
        ctx:lastCursor():select()
    end)
end

function examples.nextCursor()
    mc.action(function(ctx)
        local cursor = ctx:nextCursor(ctx:mainCursor():getPos())
            or ctx:firstCursor()
        cursor:select()
    end)
end

function examples.prevCursor()
    mc.action(function(ctx)
        local cursor = ctx:prevCursor(ctx:mainCursor():getPos())
            or ctx:lastCursor()
        cursor:select()
    end)
end

function examples.deleteCursor()
    mc.action(function(ctx)
        ctx:mainCursor():delete()
    end)
end

return examples
