local feedkeysManager = require("multicursor-nvim.feedkeys-manager")
local CursorManager = require("multicursor-nvim.cursor-manager")
local TERM_CODES = require("multicursor-nvim.term-codes")
local InputManager = require("multicursor-nvim.input-manager")
local matchlist = require("multicursor-nvim.matchlist")
local tbl = require("multicursor-nvim.tbl")

table.unpack = table.unpack or unpack

--- @type CursorManager
local cursorManager

--- @type InputManager
local inputManager

vim.cmd.hi("link", "MultiCursorCursor", "Cursor")
vim.cmd.hi("link", "MultiCursorVisual", "Visual")
vim.cmd.hi("link", "MultiCursorDisabledCursor", "Visual")
vim.cmd.hi("link", "MultiCursorDisabledVisual", "Visual")

local mc = {}

function mc.setup()
    local nsid = vim.api.nvim_create_namespace("multicursor-nvim")
    cursorManager = CursorManager(nsid)
    inputManager = InputManager(nsid, cursorManager)
    feedkeysManager:setup()
    inputManager:setup()

    vim.api.nvim_create_autocmd({ "WinLeave" }, {
        pattern = "*",
        callback = function() cursorManager:clear() end
    })
end

--- @param callback fun(ctx: CursorContext)
function mc.action(callback)
    inputManager:performAction(function()
        cursorManager:action(callback)
    end)
end

function mc.hasCursors()
    return cursorManager:hasCursors()
end

function mc.clearCursors()
    cursorManager:clear()
end

vim.o.hlsearch = false

local function addCursor(motion, opts)
    mc.action(function(ctx)
        opts = opts or {}
        if opts.remap == nil then
            opts.remap = true
        end
        local mainCursor = ctx:getMainCursor()
        if opts.addCursor then
            mainCursor:clone()
        end
        if motion then
            local oldVisual = mainCursor:getVisual()
            local vs = oldVisual[1]
            local ve = oldVisual[2]
            local oldMode = mainCursor:mode()
            local atVisStart = mainCursor:atVisualStart()
            mainCursor:perform(motion, opts)
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
            mainCursor:setVisual(atVisStart
                and { endRow, endCol, startRow, startCol }
                or { startRow, startCol, endRow, endCol }
            )
            ctx:setCursorsDisabled(false)
        else
            mainCursor:setMode("n")
        end
    end)
end

--- @param motion? string | fun(cursor: Cursor)
--- @param opts? { remap: boolean }
function mc.addCursor(motion, opts)
    addCursor(motion, { addCursor = true, remap = opts and opts.remap })
end

--- @param motion string | fun(cursor: Cursor)
--- @param opts? { remap: boolean }
function mc.skipCursor(motion, opts)
    addCursor(motion, { addCursor = false, remap = opts and opts.remap })
end

function mc.handleMouse()
    mc.action(function(ctx)
        local mousePos = vim.fn.getmousepos()
        local pos = { mousePos.line, mousePos.column }
        local existingCursor = ctx:getCursorAtPosition(pos)
        if existingCursor then
            existingCursor:delete()
        else
            ctx:getMainCursor():clone():setPos(pos)
        end
    end)
end

function mc.cursorsEnabled()
    return cursorManager:cursorsEnabled()
end

function mc.disableCursors()
    mc.action(function(ctx)
        ctx:setCursorsDisabled(true)
        local mainCursor = ctx:getMainCursor()
        mainCursor:clone()
        mainCursor:setMode("n")
    end)
end

function mc.enableCursors()
    mc.action(function(ctx)
        ctx:setCursorsDisabled(false)
        ctx:getMainCursor():delete()
    end)
end

function mc.splitCursors(pattern)
    mc.action(function(ctx)
        pattern = pattern or vim.fn.input("Split: ")
        if not pattern or pattern == "" then
            return
        end
        ctx:forEach(function(cursor)
            cursor:convertToSingleLines()
        end)
        --- @param cursor Cursor
        local function pushCursor(cursor, startCol, endCol)
            local newCursor = cursor:clone()
            local pos = cursor:getPos()
            local visual = cursor:getVisual()
            local col = visual[1][2]
            newCursor:setVisual({
                pos[1],
                col + startCol,
                pos[1],
                col + endCol
            })
        end
        ctx:forEach(function(cursor)
            local selection = cursor:getVisualLines()
            local matches = matchlist(selection, pattern, { userConfig = true })
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
    end)
end

function mc.matchCursors(pattern)
    mc.action(function(ctx)
        pattern = pattern or vim.fn.input("Match: ")
        if not pattern or pattern == "" then
            return
        end
        ctx:forEach(function(cursor)
            cursor:convertToSingleLines()
        end)
        ctx:forEach(function(cursor)
            local selection = cursor:getVisualLines()
            local matches = matchlist(selection, pattern, { userConfig = true })
            local visual = cursor:getVisual()
            local line, col = table.unpack(visual[1])
            for _, match in ipairs(matches) do
                if #match.text > 0 then
                    local newCursor = cursor:clone()
                    newCursor:setVisual({
                        line,
                        col + match.byteidx + #match.text - 1,
                        line,
                        col + match.byteidx
                    })
                    newCursor:setMode("n")
                end
            end
            cursor:delete()
        end)
    end)
end

function mc.transposeCursors(direction)
    mc.action(function(ctx)
        ctx:forEach(function(cursor)
            cursor:convertToSingleLines()
        end)
        local values = ctx:map(function(cursor)
            return cursor:getVisualLines()[1]
        end)
        ctx:forEach(function(cursor, i)
            local idx = ((i - direction - 1) % #values) + 1
            cursor:perform('"_c' .. values[idx] .. TERM_CODES.ESC .. "v`<o")
        end)
        ctx:findNextCursor(ctx:getMainCursor():getPos(), direction):select()
    end)
end

function mc.visualToCursors()
    mc.action(function(ctx)
        ctx:forEach(function(cursor)
            cursor:convertToSingleLines()
        end)
        ctx:forEach(function(cursor)
            cursor:perform(TERM_CODES.ESC)
        end)
    end)
end

function mc.firstCursor()
    mc.action(function(ctx)
        ctx:firstCursor():select()
    end)
end

function mc.lastCursor()
    mc.action(function(ctx)
        ctx:lastCursor():select()
    end)
end

local function rotateCursor(direction)
    mc.action(function(ctx)
        ctx:findNextCursor(ctx:getMainCursor():getPos(), direction):select()
    end)
end

function mc.nextCursor()
    rotateCursor(1)
end

function mc.prevCursor()
    rotateCursor(-1)
end

function mc.deleteCursor()
    mc.action(function(ctx)
        ctx:getMainCursor():delete()
    end)
end

function mc.alignCursors()
    mc.action(function(ctx)
        local startLine = ctx:firstCursor():line()
        local endLine = ctx:lastCursor():line()

        local lines = vim.api.nvim_buf_get_lines(
            0, startLine - 1, endLine, false)

        local rows = {}
        local lastLine = nil
        ctx:forEach(function(cursor)
            local row
            if lastLine == cursor:line() then
                row = rows[#rows]
            else
                row = {}
                rows[#rows + 1] = row
                lastLine = cursor:line()
            end
            local col = #lines[cursor:line() - startLine + 1] > 0
                and cursor:col()
                or 0
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

        lastLine = nil
        local rowIdx = 0
        local colIdx = 0
        ctx:forEach(function(cursor)
            if lastLine ~= cursor:line() then
                lastLine = cursor:line()
                rowIdx = rowIdx + 1
                colIdx = 0
            end
            colIdx = colIdx + 1
            local row = rows[rowIdx]
            local distance = row[colIdx]
            if distance > 0 then
                cursor:perform(distance .. "i " .. TERM_CODES.ESC .. "l")
            end
        end)
    end)
end

--- @param action string | fun(cursor: Cursor)
function mc.perform(action)
    mc.action(function(ctx)
        ctx:forEach(function(cursor)
            cursor:perform(action)
        end)
    end)
end

function mc.feedkeys(keys, remap, escape_ks)
    feedkeysManager.feedkeys(
        keys,
        remap and "t" or "tn", escape_ks or false
    )
end

return mc
