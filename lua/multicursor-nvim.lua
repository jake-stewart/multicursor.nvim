
local function FeedkeysManager()
    local originalFeedkeys = vim.api.nvim_feedkeys
    local fedKeys = ""

    function vim.api.nvim_feedkeys(macro, mode, escape)
        if type(mode) == "string" then
            if string.find(mode, "t") then
                if string.find(mode, "i") then
                    fedKeys = macro .. fedKeys
                else
                    fedKeys = fedKeys .. macro
                end
            end
        end
        return originalFeedkeys(macro, mode, escape)
    end

    local function wasFedKeys(typed)
        if #fedKeys > 0 then
            local start, _end = string.find(fedKeys, typed, 1, true)
            if start == 1 and _end then
                fedKeys = string.sub(fedKeys, _end + 1, #fedKeys)
                return true
            else
                fedKeys = ""
            end
        end
        return false
    end

    return {
        feedkeys = originalFeedkeys,
        wasFedKeys = wasFedKeys,
    }
end

local feedkeysManager = FeedkeysManager()

local function feedkeys(macro, opts)
    local mode = (opts and opts.remap and "" or "n") .. "x"
    feedkeysManager.feedkeys(macro, mode, false)
end

local tbl = {}

function tbl.concat(...)
    local result = {}
    for _, t in ipairs({...}) do
        for _, v in ipairs(t) do
            result[#result + 1] = v
        end
    end
    return result
end

function tbl.map(t, callback)
    local result = {}
    for i, v in ipairs(t) do
        result[#result + 1] = callback(v, i, t)
    end
    return result
end

function tbl.filter(t, callback)
    local result = {}
    for i, v in ipairs(t) do
        if callback(v, i, t) then
            result[#result + 1] = v
        end
    end
    return result
end

function tbl.reduce(t, callback, initial)
    if initial then
        for i, v in ipairs(t) do
            initial = callback(initial, v, i, t)
        end
    else
        initial = t[1]
        for i = 2, #t do
            initial = callback(initial, t[i], i, t)
        end
    end
    return initial
end

function tbl.find(t, callback)
    for i, v in ipairs(t) do
        if callback(v, i, t) then
            return v
        end
    end
end

function tbl.findIndex(t, callback)
    for i, v in ipairs(t) do
        if callback(v, i, t) then
            return i
        end
    end
end

function tbl.indexOf(t, value)
    for i, v in ipairs(t) do
        if v == value then
            return i
        end
    end
end

function tbl.uniq(t)
    return tbl.filter(t, function(v, i)
        return tbl.indexOf(t, v) == i
    end)
end

local function matchlist(lines, pattern, opts)
    opts = opts or {}
    if opts.userConfig then
        if vim.o.ignorecase then
            if vim.o.smartcase and string.find(pattern, "[A-Z]") then
                pattern = "\\C" .. pattern
            else
                pattern = "\\c" .. pattern
            end
        end
        if vim.o.magic then
            pattern = "\\m" .. pattern
        else
            pattern = "\\M" .. pattern
        end
    end
    return vim.fn.matchstrlist(lines, pattern)
end

table.unpack = table.unpack or unpack

local ESC = vim.api.nvim_replace_termcodes("<esc>", true, true, true);
local CTRL_V = vim.api.nvim_replace_termcodes("<c-v>", true, true, true);
local CTRL_S = vim.api.nvim_replace_termcodes("<c-s>", true, true, true);
local CTRL_R = vim.api.nvim_replace_termcodes("<c-r>", true, true, true);
local CTRL_G = vim.api.nvim_replace_termcodes("<c-g>", true, true, true);

-- see :h getcurpos()
-- type CursorPos = [buf: number, lnum: number, col: number, off: number, curswant: number]

-- see :h getpos()
-- type MarkPos = [buf: number, lnum: number, col: number, off: number]

-- interface Cursor {
--     pos: CursorPos;
--     register: string;
--     search: string;
--     visual: [ start: MarkPos, end: MarkPos ];
--     mode: string;
-- }

-- interface CursorExtmark extends Cursor {
--     invisible?: boolean;
--     visualIds?: number[];   // (extarks used for decoration)
--     cursorId: number;       // (extmark used to track cursor)
--     visualStartId?: number; // (extmark used to track start of visual)
--     visualEndId?: number;   // (extmark used to track end of visual)
-- }

-- interface MultiCursorUndo {
--     cursors: Cursor[]; (additional cursors)
--     cursor: Cursor; (main cursor)
-- }

local function echoerr(message)
    message = type(message) == "string"
        and message or vim.inspect(message)
    vim.api.nvim_echo({{message, "Error"}}, false, {})
end

local function shallow_copy(t)
  local t2 = {}
  for k,v in pairs(t) do
    t2[k] = v
  end
  return t2
end

local function ternary(cond, T, F, ...)
    if cond then return T(...) else return F(...) end
end

local visualSelectModes = {
    v = { visual = "v", select = "" },
    V = { visual = "V", select = "" },
    [CTRL_V] = { visual = CTRL_V, select = "" },
    s = { visual = "v", select = CTRL_G },
    S = { visual = "V", select = CTRL_G },
    [CTRL_S] = { visual = CTRL_V, select = CTRL_G },
}

local function setMode(newMode, cursor)
    local mode = vim.fn.mode()
    if mode == newMode then
        return "";
    end
    local result
    if cursor then
        local info = visualSelectModes[newMode]
        if info then
            if mode == "n" then
                if cursor.pos[3] == cursor.visual[1][3]
                    and cursor.pos[2] == cursor.visual[1][2]
                then
                    result = cursor.visual[2][2] .. "G"
                        .. cursor.visual[2][3] .. "|"
                        .. info.visual
                        .. cursor.visual[1][2] .. "G"
                        .. cursor.pos[3] .. "|"
                        .. info.select
                else
                    result = cursor.visual[1][2] .. "G"
                        .. cursor.visual[1][3] .. "|"
                        .. info.visual
                        .. cursor.visual[2][2] .. "G"
                        .. cursor.pos[3] .. "|"
                        .. info.select
                end
            end
        elseif newMode == "n" then
            result = ESC
        end
    else
        if newMode == "n" then
            result = ESC
        else
            local info = visualSelectModes[newMode]
            if info then
                result = info.visual + info.select
            end
        end
    end
    feedkeys(result)
end

local function readCursor()
    local mode = vim.fn.mode();
    local pos = vim.fn.getcurpos();
    setMode("n");
    return {
        mode = mode,
        register = vim.fn.getreg(""),
        search = vim.fn.getreg("/"),
        pos = pos,
        visual = {vim.fn.getpos("'<"), vim.fn.getpos("'>")},
    }
end

local function writeCursor(cursor)
    vim.fn.setreg("", cursor.register);
    vim.fn.setreg("/", cursor.search);
    vim.fn.setpos("'<", cursor.visual[1]);
    vim.fn.setpos("'>", cursor.visual[2]);
    vim.fn.setpos(".", cursor.pos);
    setMode(cursor.mode, cursor);
end

local function compareCursors(a, b)
    if a.pos[2] == b.pos[2] then
        return a.pos[3] < b.pos[3]
    end
    return a.pos[2] < b.pos[2]
end

local function closerCursor(to, a, b)
    local aRowDist = math.abs(a.pos[2] - to.pos[2])
    local bRowDist = math.abs(b.pos[2] - to.pos[2])
    if aRowDist < bRowDist then
        return a
    elseif bRowDist < aRowDist then
        return b
    else
        local aColDist = math.abs(a.pos[3] - to.pos[3])
        local bColDist = math.abs(b.pos[3] - to.pos[3])
        if aColDist < bColDist then
            return a
        else
            return b
        end
    end
end

local cursorManager
local inputManager

local function findNextCursor(cursor, direction)
    local cursors = cursorManager.getCursors()
    if #cursors == 0 then
        return
    elseif #cursors == 1 then
        return cursors[1]
    end
    table.sort(cursors, compareCursors)
    local lastCursor = cursors[#cursors]
    for _, c in ipairs(cursors) do
        if c.pos[2] > cursor.pos[2]
            or c.pos[2] == cursor.pos[2] and c.pos[3] > cursor.pos[3]
        then
            return direction == 1 and c
                or direction == -1 and lastCursor
                or closerCursor(cursor, c, lastCursor)
        else
            lastCursor = c
        end
    end
    return direction == 1 and cursors[1]
        or direction == -1 and cursors[#cursors]
        or closerCursor(cursor, cursors[1], cursors[#cursors])
end

local function deleteCurrentCursor()
    inputManager.performAction(function()
        local cursor = findNextCursor(readCursor())
        if cursor then
            cursorManager.deleteCursor(cursor)
            writeCursor(cursor)
            cursorManager.update(cursor)
        end
    end)
end

local function rotateCursor(direction)
    inputManager.performAction(function()
        local mainCursor = readCursor()
        local cursor = findNextCursor(mainCursor, direction)
        if cursor then
            cursorManager.deleteCursor(cursor)
            cursorManager.insertCursor(1, mainCursor)
            writeCursor(cursor)
            cursorManager.update(cursor)
        end
    end)
end

local function addCursorWithMouse()
    inputManager.performAction(function()
        local mousePos = vim.fn.getmousepos();
        if mousePos.line == vim.fn.line(".") and mousePos.column == vim.fn.col(".") then
            deleteCurrentCursor()
        else
            local existingCursor = cursorManager.getCursorAtPosition(mousePos.line, mousePos.column);
            if existingCursor then
                cursorManager.deleteCursor(existingCursor);
            else
                local cursor = readCursor();
                cursorManager.insertCursor(-1, cursor);
                vim.fn.setpos(".", {
                    cursor.pos[1],
                    mousePos.line,
                    mousePos.column,
                    0,
                    mousePos.column
                });
                cursorManager.update(readCursor());
            end
        end
    end)
end

local function selectCursor(index)
    inputManager.performAction(function()
        local cursor = cursorManager.getCursor(index)
        if cursor then
            local mainCursor = readCursor()
            if index > 0 then
                if compareCursors(mainCursor, cursor) then
                    return
                end
            else
                if compareCursors(cursor, mainCursor) then
                    return
                end
            end
            cursorManager.deleteCursor(cursor)
            cursorManager.insertCursor(1, mainCursor)
            writeCursor(cursor)
            cursorManager.update(cursor)
        end
    end)
end

local function alignCursors()
    inputManager.performAction(function()
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local cursors = cursorManager.getCursors(true)
        local rows = {}

        local lastLine = nil
        for _, cursor in ipairs(cursors) do
            local row
            if lastLine == cursor.pos[2] then
                row = rows[#rows]
            else
                row = {}
                rows[#rows + 1] = row
                lastLine = cursor.pos[2]
            end
            local col = #lines[cursor.pos[2]] > 0 and cursor.pos[3] or 0
            row[#row + 1] = col
        end

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
        cursorManager.performMacro(function(cursor)
            if lastLine ~= cursor.pos[2] then
                lastLine = cursor.pos[2]
                rowIdx = rowIdx + 1
                colIdx = 0
            end
            colIdx = colIdx + 1
            local row = rows[rowIdx]
            local distance = row[colIdx]
            if distance > 0 then
                feedkeys(distance .. "i " .. ESC .. "l")
            end
        end, { mainCursor = true })
    end)
end

local function getLineRange(cursors)
    local lines = {}
    for _, cursor in ipairs(cursors) do
        lines[#lines + 1] = cursor.pos[2]
        if cursor.visual[1][2] > 0 then
            lines[#lines + 1] = cursor.visual[1][2]
        end
        if cursor.visual[2][2] > 0 then
            lines[#lines + 1] = cursor.visual[2][2]
        end
    end
    local min = tbl.reduce(lines,
        function (a, b) return math.min(a, b) end)
    local max = tbl.reduce(lines,
        function (a, b) return math.max(a, b) end)
    return min, max
end


local function CursorManager(nsid)
    local cursors = {} -- CursorExtmark[];
    local undoItems = {} -- LuaMap<number, MultiCursorUndo>;
    local disabled = false

    local function updateCursorPos(cursor)
        local newCursor = shallow_copy(cursor);
        newCursor.visual = {table.unpack(newCursor.visual)};

        local cursorExtmark = vim.api.nvim_buf_get_extmark_by_id(
            0, nsid, cursor.cursorId, {});

        if cursorExtmark and #cursorExtmark > 0 then
            newCursor.pos = {
                newCursor.pos[1],
                cursorExtmark[1] + 1,
                cursorExtmark[2] + 1,
                newCursor.pos[4],
                cursorExtmark[2] + 1 == cursor.pos[3]
                    and math.max(newCursor.pos[5], cursorExtmark[2] + 1)
                    or cursorExtmark[2] + 1
            }
        end

        if cursor.visualStartId then
            local visualStartExtmark = vim.api.nvim_buf_get_extmark_by_id(
                    0, nsid, cursor.visualStartId, {});
            if visualStartExtmark and #visualStartExtmark > 0 then
                newCursor.visual[1] = {
                    newCursor.visual[1][1],
                    visualStartExtmark[1] + 1,
                    visualStartExtmark[2] + 1,
                    newCursor.visual[1][4],
                }
            end
        end

        if cursor.visualEndId then
            local visualEndExtmark = vim.api.nvim_buf_get_extmark_by_id(
                    0, nsid, cursor.visualEndId, {});
            if visualEndExtmark and #visualEndExtmark > 0 then
                newCursor.visual[2] = {
                    newCursor.visual[2][1],
                    visualEndExtmark[1] + 1,
                    visualEndExtmark[2] + 1,
                    newCursor.visual[2][4],
                }
            end
        end

        return newCursor;
    end

    local function drawVisualChar(cursor, lines, start, hl)
        local visualIds = {}
        local i = cursor.visual[1][2]
        while i <= cursor.visual[2][2] do
            local row = i - 1;
            local line = lines[row - start + 1]
            local col = i == cursor.visual[1][2]
                and cursor.visual[1][3] - 1
                or 0
            local endCol = i == cursor.visual[2][2]
                and cursor.visual[2][3] - 1
                or (line and #line or 0)
            local id = vim.api.nvim_buf_set_extmark(0, nsid, row, col, {
                strict = false,
                undo_restore = false,
                virt_text = ternary(i == cursor.visual[2][2],
                    function() return nil end,
                    function() return {{" ", hl}} end
                ),
                end_col = endCol + 1,
                virt_text_pos = "inline",
                virt_text_win_col = line and #line or 0,
                hl_group = hl,
            });
            visualIds[#visualIds + 1] = id;
            i = i + 1
        end
        return visualIds
    end

    local function drawVisualLine(cursor, lines, start, hl)
        local visualIds = {}
        local i = cursor.visual[1][2]
        while i <= cursor.visual[2][2] do
            local row = i - 1;
            local line = lines[row - start + 1];
            local endCol = ternary(line,
                function() return #line end,
                function() return 0 end
            );
            local id = vim.api.nvim_buf_set_extmark(
                0,
                nsid,
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
            );
            visualIds[#visualIds + 1] = id;
            i = i + 1
        end
        return visualIds
    end

    local function drawVisualBlock(cursor, lines, start, hl)
        local visualIds = {}
        local range = {cursor.visual[1][3] - 1, cursor.visual[2][3] - 1};
        local startCol = math.min(range[1], range[2]);
        local endCol = math.max(range[1], range[2]);
        local i = cursor.visual[1][2]
        while i <= cursor.visual[2][2] do
            local row = i - 1;
            local line = lines[row - start + 1];
            if line and #line >= startCol then
                local id = vim.api.nvim_buf_set_extmark(
                    0,
                    nsid,
                    row,
                    startCol,
                    {
                        strict = false,
                        undo_restore = false,
                        end_col = endCol + 1,
                        hl_group = hl,
                    }
                );
                visualIds[#visualIds + 1] = id;
            end
            i = i + 1
        end
        return visualIds
    end

    local function drawCursor(cursor, invisible)
        local visualHL = disabled
            and "MultiCursorDisabledVisual"
            or "MultiCursorVisual"
        local cursorHL = disabled
            and "MultiCursorDisabledCursor"
            or "MultiCursorCursor"
        local start
        local _end

        if visualSelectModes[cursor.mode] then
            start = math.max(math.min(cursor.visual[1][2], cursor.pos[2]) - 1, 0);
            _end = math.max(math.max(cursor.visual[2][2], cursor.pos[2]) - 1, start);
        else
            start = cursor.pos[2] - 1
            _end = cursor.pos[2] - 1
        end
        local lines = vim.api.nvim_buf_get_lines(0, start, _end + 1, true);

        local char = ""
        local charLine = lines[cursor.pos[2] - start];
        if charLine then
            char = string.sub(charLine, cursor.pos[3], cursor.pos[3])
        end
        if #char ~= 1 then
            char = " "
        end

        local visualIds

        if not invisible then
            if cursor.mode == "v" or cursor.mode == "s" then
                visualIds = drawVisualChar(cursor, lines, start, visualHL)
            elseif cursor.mode == "V" or cursor.mode == "S" then
                visualIds = drawVisualLine(cursor, lines, start, visualHL)
            elseif cursor.mode == CTRL_V or cursor.mode == CTRL_S then
                visualIds = drawVisualBlock(cursor, lines, start, visualHL)
            end
        end

        local visualStartId
        local visualEndId
        if cursor.visual[1][2] > 0 and cursor.visual[1][3] > 0 then
            visualStartId = vim.api.nvim_buf_set_extmark(
                0,
                nsid,
                cursor.visual[1][2] - 1,
                cursor.visual[1][3] - 1,
                {
                    strict = false,
                    undo_restore = false
                }
            );
        end

        if cursor.visual[2][2] > 0 and cursor.visual[2][3] > 0 then
            visualEndId = vim.api.nvim_buf_set_extmark(
                0,
                nsid,
                cursor.visual[2][2] - 1,
                cursor.visual[2][3] - 1,
                {
                    strict = false,
                    undo_restore = false
                }
            );
        end

        local cursorId = vim.api.nvim_buf_set_extmark(
            0,
            nsid,
            cursor.pos[2] - 1,
            cursor.pos[3] - 1,
            {
                strict = false,
                undo_restore = false,
                virt_text_pos = "overlay",
                virt_text_hide = true,
                virt_text = {{char, cursorHL}},
                -- right_gravity = false,
                -- line_hl_group: "CursorLine",
                -- number_hl_group: "CursorLineNr",
                -- sign_hl_group: "CursorLineSign",
                -- cursorline_hl_group: "CursorLine",
            }
        );

        local copy = shallow_copy(cursor)
        copy.cursorId = cursorId
        copy.visualIds = visualIds
        copy.visualStartId = visualStartId
        copy.visualEndId = visualEndId
        copy.invisible = invisible
        return copy
    end

    local function clear()
        vim.api.nvim_buf_clear_namespace(0, nsid, 0, -1)
        disabled = false
        cursors = {}
        undoItems = {}
    end

    local function getCursorAtPosition(row, col)
        local extmarks = vim.api.nvim_buf_get_extmarks(
            0,
            nsid,
            {row - 1, col - 1},
            {row, col},
            {}
        );
        for _, extmark in ipairs(extmarks) do
            if extmark[2] == row - 1 and extmark[3] == col - 1 then
                local cursor = tbl.find(cursors, function(c)
                    return c.cursorId == extmark[1]
                end)
                if cursor then
                    return cursor
                end
            end
        end
    end

    local function eraseCursor(cursor)
        if cursor.visualIds then
            for _, id in ipairs(cursor.visualIds) do
                vim.api.nvim_buf_del_extmark(0, nsid, id)
            end
        end
        vim.api.nvim_buf_del_extmark(0, nsid, cursor.cursorId)
        if cursor.visualStartId then
            vim.api.nvim_buf_del_extmark(0, nsid, cursor.visualStartId)
        end
        if cursor.visualEndId then
            vim.api.nvim_buf_del_extmark(0, nsid, cursor.visualEndId)
        end
    end

    local function deleteCursor(cursor)
        eraseCursor(cursor)
        cursors = tbl.filter(cursors, function(c)
            return c ~= cursor
        end)
    end

    local function insertCursor(_end, cursor)
        table.insert(
            cursors, _end == 1 and 1 or #cursors + 1,
            drawCursor(cursor)
        )
    end

    local function mergeCursors(mainCursor, mergeMain)
        local newCursors = {}
        for _, cursor in ipairs(cursors) do
            local exists = false
            if mergeMain
                and cursor.pos[2] == mainCursor.pos[2]
                and cursor.pos[3] == mainCursor.pos[3]
            then
                exists = true
            else
                for _, c in ipairs(newCursors) do
                    if cursor.pos[2] == c.pos[2]
                        and cursor.pos[3] == c.pos[3]
                    then
                        exists = true
                        break
                    end
                end
            end
            if exists then
                eraseCursor(cursor)
            else
                newCursors[#newCursors + 1] = cursor
            end
        end
        cursors = newCursors
    end

    local function update(mainCursor, mergeMain)
        mergeMain = mergeMain == nil and true or mergeMain
        local undoTree = vim.fn.undotree();
        mergeCursors(mainCursor, mergeMain);
        undoItems[undoTree.seq_cur] = {
            cursors = cursors,
            cursor = mainCursor,
        };
    end

    local function hasCursors()
        return #cursors > 0;
    end

    local function getCursors(includeMainCursor)
        local cursorsCopy = {table.unpack(cursors)}
        if includeMainCursor then
            cursorsCopy[#cursorsCopy + 1] = readCursor()
        end
        table.sort(cursorsCopy, compareCursors)
        return cursorsCopy
    end

    local function performMacro(macro, opts)
        opts = opts or {}

        if not hasCursors() and not opts.mainCursor then
            return;
        end

        local origCursor = readCursor()
        local origClipboard = vim.o.clipboard;
        vim.o.clipboard = "";

        local apply = type(macro) == "string"
            and function() feedkeys(macro, opts) end
            or macro

        local newCursors = { table.unpack(cursors) }

        newCursors[#newCursors + 1] = drawCursor(origCursor, true)

        table.sort(newCursors, compareCursors)

        for i, cursor in ipairs(newCursors) do
            if not cursor.invisible or opts.mainCursor then
                local newCursor = updateCursorPos(cursor)
                eraseCursor(cursor)
                writeCursor(newCursor);
                local success, err = pcall(apply, newCursor)
                if not success then
                    echoerr(err)
                end
                newCursor = success and readCursor() or newCursor
                newCursors[i] = drawCursor(newCursor, cursor.invisible)
            end
        end

        newCursors = tbl.map(newCursors, updateCursorPos)

        local mainCursor
        cursors = tbl.filter(newCursors, function(c)
            if c.invisible then
                mainCursor = c
                return false
            end
            return true
        end)
        eraseCursor(mainCursor)
        writeCursor(mainCursor)
        update(mainCursor)
        vim.o.clipboard = origClipboard
    end

    local function loadUndoItem()
        local undoTree = vim.fn.undotree();
        local undoItem = undoItems[undoTree.seq_cur];
        if undoItem then
            cursors = {};
            vim.api.nvim_buf_clear_namespace(0, nsid, 0, -1);
            for _, c in ipairs(undoItem.cursors) do
                cursors[#cursors + 1] = drawCursor(c);
            end
            writeCursor(undoItem.cursor)
            return true
        end
        return false
    end

    local function undo()
        if not loadUndoItem() then
            clear();
        end
    end

    local function redo()
        loadUndoItem()
    end

    local function getCursor(index)
        if #cursors == 0 then
            return
        elseif #cursors == 1 then
            return cursors[1]
        end
        table.sort(cursors, compareCursors)
        if index < 0 then
            index = #cursors + index + 1
        end
        return cursors[index]
    end

    local function setDisabled(value)
        disabled = value
    end

    local function redraw()
        vim.api.nvim_buf_clear_namespace(0, nsid, 0, -1)
        for i, cursor in ipairs(cursors) do
            cursors[i] = drawCursor(cursor)
        end
    end

    local function setCursors(newCursors)
        cursors = {table.unpack(newCursors)}
        local newCursor = cursors[#cursors]
        if newCursor then
            cursors[#cursors] = nil
            update(newCursor)
            writeCursor(newCursor)
        else
            update(readCursor())
        end
        redraw()
    end

    return {
        undo = undo,
        redo = redo,
        getLineRange = getLineRange,
        setDisabled = setDisabled,
        setCursors = setCursors,
        hasCursors = hasCursors,
        getCursors = getCursors,
        deleteCursor = deleteCursor,
        performMacro = performMacro,
        insertCursor = insertCursor,
        getCursorAtPosition = getCursorAtPosition,
        getCursor = getCursor,
        update = update,
        redraw = redraw,
        clear = clear,
    }
end



function InputManager(nsid)
    local cmdType
    local inInsertMode = false
    local applying = false
    local macro = ""
    local specialKey = nil
    local fromSelectMode = false
    local cursorsDisabled = false

    local function performAction(callback)
        if applying or inInsertMode or cmdType then
            return;
        end
        macro = ""
        specialKey = nil
        applying = true
        local status, ret = pcall(callback)
        applying = false
        if status then
            return ret
        else
            echoerr(ret)
        end
    end

    local function areCursorsDisabled()
        return cursorsDisabled
    end

    local function setCursorsDisabled(value)
        return performAction(function()
            cursorsDisabled = value
            cursorManager.setDisabled(value)
            if value then
                local mainCursor = readCursor()
                cursorManager.insertCursor(-1, mainCursor)
                cursorManager.update(mainCursor, false)
            else
                local cursor = findNextCursor(readCursor())
                if cursor then
                    cursorManager.deleteCursor(cursor)
                    writeCursor(cursor)
                    cursorManager.update(cursor)
                end
            end
            cursorManager.redraw()
        end)
    end

    local function adjustVisualCursor(origCursor, newCursor)
        local visStart = origCursor.visual[1]
        local visEnd = origCursor.visual[2]

        local atVisStart = origCursor.pos[2] == visStart[2]
            and origCursor.pos[3] == visStart[3]

        local atVisEnd = origCursor.pos[2] == visEnd[2]
            and origCursor.pos[3] == visEnd[3]

        local rowDiff = newCursor.pos[2] - visEnd[2]
        local colDiff = newCursor.mode == "n"
            and newCursor.pos[3] - visStart[3]
            or atVisStart
                and visEnd[3] - newCursor.pos[3]
                or newCursor.pos[3] - visEnd[3]

        newCursor.visual = {
            {
                visStart[1],
                visStart[2] + rowDiff,
                visStart[3] + colDiff,
                visStart[4],
            },
            {
                visEnd[1],
                visEnd[2] + rowDiff,
                visEnd[3] + colDiff,
                visEnd[4],
            },
        }

        if newCursor.mode == "n" and atVisEnd then
            newCursor.pos = {
                newCursor.visual[2][1],
                newCursor.visual[2][2],
                newCursor.visual[2][3],
                newCursor.visual[2][4],
                newCursor.visual[2][3],
            }
        end
    end

    local function addCursor(motion, opts)
        performAction(function()
            local origCursor = readCursor()
            writeCursor(origCursor)
            if type(motion) == "function" then
                motion()
            elseif type(motion) == "string" then
                feedkeys(motion, {remap = true})
            end
            local newCursor = readCursor();
            if cursorsDisabled then
                if visualSelectModes[origCursor.mode] then
                    adjustVisualCursor(origCursor, newCursor)
                end
                if opts.addCursor then
                    cursorManager.insertCursor(-1, origCursor);
                    cursorManager.insertCursor(-1, newCursor);
                end
                if motion then
                    cursorsDisabled = false
                    cursorManager.setDisabled(false)
                    cursorManager.redraw()
                end
                newCursor.mode = motion and origCursor.mode or "n"
            else
                if opts.addCursor then
                    cursorManager.insertCursor(-1, origCursor);
                end
                if visualSelectModes[origCursor.mode] then
                    adjustVisualCursor(origCursor, newCursor)
                end
                newCursor.mode = origCursor.mode
            end
            writeCursor(newCursor);
            cursorManager.update(newCursor, not cursorsDisabled);
        end)
    end

    local function onInsertMode(enabled, selectMode)
        if applying then
            return
        end
        inInsertMode = enabled;
        if not enabled then
            local insertReg = vim.fn.getreg(".")
            if fromSelectMode then
                macro = macro .. string.sub(insertReg, 2, #insertReg) .. ESC;
            else
                macro = macro .. insertReg .. ESC;
            end
        end
        fromSelectMode = selectMode
    end

    local function onSafeState()
        if applying or inInsertMode then
            return
        end
        if vim.fn.mode() == "c" then
            cmdType = vim.fn.getcmdtype()
            return
        elseif cmdType then
            if cmdType == ":" or cmdType == "@" then
                cmdType = nil
                macro = ""
                return
            end
            cmdType = nil
        end
        applying = true;
        if specialKey then
            if specialKey == "u" then
                cursorManager.undo();
            elseif specialKey == CTRL_R then
                cursorManager.redo();
            elseif specialKey == "." then
                cursorManager.performMacro(".");
            end
            specialKey = nil
        elseif not cursorsDisabled and #macro > 0 then
            cursorManager.performMacro(macro, {remap = true});
        end
        macro = ""
        applying = false
    end

    local function onKey(key, typed)
        if applying or inInsertMode then
            return
        end
        if feedkeysManager.wasFedKeys(typed) then
            return
        end
        if macro == "" and (key == "u" or key == CTRL_R or key == ".") then
            specialKey = key;
        else
            macro = macro .. typed;
        end
    end

    local function clear()
        cursorsDisabled = false
        cursorManager.clear()
    end

    local function convertToSingleLineCursors(cursors, lines, offset)
        local newCursors = {}
        for _, cursor in ipairs(cursors) do
            if visualSelectModes[cursor.mode] then
                local atVisualEnd = cursor.pos[2] == cursor.visual[2][2]
                    and cursor.pos[3] == cursor.visual[2][3]
                if cursor.mode == "v" or cursor.mode == "s" then
                    for i = cursor.visual[1][2], cursor.visual[2][2] do
                        local newCursor = shallow_copy(cursor)
                        newCursor.visual = {
                            {
                                cursor.visual[1][1],
                                i,
                                i == cursor.visual[1][2] and cursor.visual[1][3] or 1,
                                0,
                            },
                            {
                                cursor.visual[2][1],
                                i,
                                i == cursor.visual[2][2] and cursor.visual[2][3] or #lines[i - offset],
                                0,
                            },
                        }
                        local newCursorPos = atVisualEnd
                            and newCursor.visual[2]
                            or newCursor.visual[1]
                        newCursor.pos = { table.unpack(newCursorPos) }
                        newCursor.pos[#newCursor.pos + 1] = newCursor.pos[3]
                        newCursor.mode = "v"
                        newCursors[#newCursors + 1] = newCursor
                    end
                elseif cursor.mode == "V" or cursor.mode == "S" then
                    for i = cursor.visual[1][2], cursor.visual[2][2] do
                        local newCursor = shallow_copy(cursor)
                        newCursor.visual = {
                            { cursor.visual[1][1], i, 1, 0 },
                            { cursor.visual[2][1], i, #lines[i - offset], 0 },
                        }
                        local newCursorPos = atVisualEnd
                            and newCursor.visual[2]
                            or newCursor.visual[1]
                        newCursor.pos = { table.unpack(newCursorPos) }
                        newCursor.pos[#newCursor.pos + 1] = newCursor.pos[3]
                        newCursor.mode = "v"
                        newCursors[#newCursors + 1] = newCursor
                    end
                elseif cursor.mode == CTRL_V or cursor.mode == CTRL_S then
                    for i = cursor.visual[1][2], cursor.visual[2][2] do
                        local newCursor = shallow_copy(cursor)
                        newCursor.visual = {
                            { cursor.visual[1][1], i, cursor.visual[1][3], 0 },
                            { cursor.visual[2][1], i, cursor.visual[2][3], 0 },
                        }
                        local newCursorPos = atVisualEnd
                            and newCursor.visual[2]
                            or newCursor.visual[1]
                        newCursor.pos = { table.unpack(newCursorPos) }
                        newCursor.pos[#newCursor.pos + 1] = newCursor.pos[3]
                        newCursor.mode = "v"
                        newCursors[#newCursors + 1] = newCursor
                    end
                end
            else
                newCursors[#newCursors + 1] = cursor
            end
        end
        return newCursors
    end

    local function matchCursors(pattern)
        performAction(function()
            pattern = pattern or vim.fn.input("Match: ")
            if not pattern or pattern == "" then
                return
            end
            cursorsDisabled = false
            cursorManager.setDisabled(false)
            local cursors = cursorManager.getCursors(true)
            cursors = tbl.filter(cursors,
                function (cursor) return visualSelectModes[cursor.mode] end)
            local start, _end = getLineRange(cursors)
            local offset = start - 1
            local lines = vim.api.nvim_buf_get_lines(0, offset, _end, false)
            cursors = convertToSingleLineCursors(cursors, lines, offset)
            local newCursors = {}
            for _, cursor in ipairs(cursors) do
                local atVisualEnd = cursor.pos[2] == cursor.visual[2][2]
                    and cursor.pos[3] == cursor.visual[2][3]
                local line = lines[cursor.pos[2] - offset]
                local selection = string.sub(line, cursor.visual[1][3], cursor.visual[2][3])
                local matches = matchlist({selection}, pattern, { userConfig = true })
                for _, match in ipairs(matches) do
                    if #match.text then
                        local newCursor = shallow_copy(cursor)
                        newCursor.mode = "n"
                        newCursor.visual = {
                            {
                                cursor.visual[1][1],
                                cursor.pos[2],
                                cursor.visual[1][3] + match.byteidx,
                                0,
                            },
                            {
                                cursor.visual[2][1],
                                cursor.pos[2],
                                cursor.visual[1][3] + match.byteidx + #match.text - 1,
                                0,
                            }
                        }
                        newCursor.pos = atVisualEnd
                            and newCursor.visual[2]
                            or newCursor.visual[1]
                        newCursor.pos[#newCursor.pos + 1] = newCursor.pos[3]
                        newCursors[#newCursors + 1] = newCursor
                    end
                end
            end
            cursorManager.setCursors(newCursors)
        end)
    end

    local function splitCursors(pattern)
        performAction(function()
            pattern = pattern or vim.fn.input("Split: ")
            if not pattern or pattern == "" then
                return
            end
            cursorsDisabled = false
            cursorManager.setDisabled(false)
            local cursors = cursorManager.getCursors(true)
            cursors = tbl.filter(cursors,
                function (cursor) return visualSelectModes[cursor.mode] end)
            local start, _end = getLineRange(cursors)
            local offset = start - 1
            local lines = vim.api.nvim_buf_get_lines(0, offset, _end, false)
            cursors = convertToSingleLineCursors(cursors, lines, offset)
            local newCursors = {}
            local function pushCursor(cursor, atVisualEnd, startCol, endCol)
                local newCursor = shallow_copy(cursor)
                newCursor.visual = {
                    {
                        cursor.visual[1][1],
                        cursor.pos[2],
                        cursor.visual[1][3] + startCol,
                        0,
                    },
                    {
                        cursor.visual[2][1],
                        cursor.pos[2],
                        cursor.visual[1][3] + endCol,
                        0,
                    }
                }
                newCursor.pos = atVisualEnd
                    and newCursor.visual[2]
                    or newCursor.visual[1]
                newCursor.pos[#newCursor.pos + 1] = newCursor.pos[3]
                newCursors[#newCursors + 1] = newCursor
            end
            for _, cursor in ipairs(cursors) do
                local atVisualEnd = cursor.pos[2] == cursor.visual[2][2]
                    and cursor.pos[3] == cursor.visual[2][3]
                local line = lines[cursor.pos[2] - offset]
                local selection = string.sub(line, cursor.visual[1][3], cursor.visual[2][3])
                local matches = matchlist({selection}, pattern, { userConfig = true })
                local nextIdx = 0
                for _, match in ipairs(matches) do
                    if match.byteidx ~= nextIdx then
                        pushCursor(cursor, atVisualEnd, nextIdx, match.byteidx - 1)
                    end
                    nextIdx = match.byteidx + #match.text
                end
                if nextIdx < #selection then
                    pushCursor(cursor, atVisualEnd, nextIdx, #selection - 1)
                end
            end
            cursorManager.setCursors(newCursors)
        end)
    end

    local function visualToCursors()
        performAction(function()
            cursorsDisabled = false
            cursorManager.setDisabled(false)
            local cursors = cursorManager.getCursors(true)
            cursors = tbl.filter(cursors,
                function (cursor) return visualSelectModes[cursor.mode] end)
            local start, _end = getLineRange(cursors)
            local offset = start - 1
            local lines = vim.api.nvim_buf_get_lines(0, offset, _end, false)
            cursors = convertToSingleLineCursors(cursors, lines, offset)
            cursorManager.setCursors(cursors)
            cursorManager.performMacro(ESC, { mainCursor = true })
        end)
    end

    local function transposeCursors(direction)
        performAction(function()
            cursorsDisabled = false
            cursorManager.setDisabled(false)
            local cursors = cursorManager.getCursors(true)
            cursors = tbl.filter(cursors,
                function (cursor) return visualSelectModes[cursor.mode] end)
            local start, _end = getLineRange(cursors)
            local offset = start - 1
            local lines = vim.api.nvim_buf_get_lines(0, offset, _end, false)
            cursors = convertToSingleLineCursors(cursors, lines, offset)
            local values = tbl.map(cursors, function(cursor)
                local line = lines[cursor.pos[2] - offset]
                return string.sub(line, cursor.visual[1][3], cursor.visual[2][3])
            end)

            local pos = vim.fn.getcurpos()
            local origIdx = tbl.findIndex(cursors, function(c)
                return c.pos[2] == pos[2] and c.pos[3] == pos[3]
            end)

            local i = 1
            cursorManager.setCursors(cursors)
            cursorManager.performMacro(function()
                local idx = ((i - direction - 1) % #cursors) + 1
                i = i + 1
                feedkeys('"_c' .. values[idx] .. ESC .. "v`<")
            end, {mainCursor = true})

            if origIdx then
                local newIdx = ((origIdx + direction - 1) % #cursors) + 1
                local cursor = cursorManager.getCursor(newIdx)
                if cursor then
                    local origCursor = readCursor()
                    cursorManager.deleteCursor(cursor)
                    cursorManager.insertCursor(-1, origCursor)
                    cursorManager.update(cursor)
                    writeCursor(cursor)
                end
            end
        end)
    end

    local function au(event, pattern, callback)
        vim.api.nvim_create_autocmd(event, {
            pattern = pattern,
            callback = callback
        });
    end

    au("ModeChanged", "[vV\x16ns]*:[iR]", function() onInsertMode(true) end);
    au("ModeChanged", "[S\x13]*:[iR]", function() onInsertMode(true, true) end);
    au("ModeChanged", "[iR]:*", function() onInsertMode(false) end);
    au("SafeState", "*", onSafeState);

    vim.on_key(function (key, typed) onKey(key, typed) end, nsid);

    return {
        performAction = performAction,
        select = select,
        clear = clear,
        splitCursors = splitCursors,
        matchCursors = matchCursors,
        transposeCursors = transposeCursors,
        visualToCursors = visualToCursors,
        setCursorsDisabled = setCursorsDisabled,
        areCursorsDisabled = areCursorsDisabled,
        addCursor = addCursor,
    };
end

vim.cmd.hi("link", "MultiCursorCursor", "Cursor");
vim.cmd.hi("link", "MultiCursorVisual", "Visual");
vim.cmd.hi("link", "MultiCursorDisabledCursor", "Visual");
vim.cmd.hi("link", "MultiCursorDisabledVisual", "Visual");

local exports = {}

function exports.setup()
    local nsid = vim.api.nvim_create_namespace("multicursor");
    cursorManager = CursorManager(nsid)
    inputManager = InputManager(nsid)

    vim.api.nvim_create_autocmd({ "WinLeave" }, {
        pattern = "*",
        callback = function() cursorManager.clear() end
    });
end

function exports.hasCursors()
    return cursorManager.hasCursors()
end

function exports.clearCursors()
    inputManager.clear()
end

function exports.mainCursorMode(value)
    return inputManager.mainCursorMode(value)
end

function exports.addCursor(motion)
    inputManager.addCursor(motion, {addCursor = true})
end

function exports.skipCursor(motion)
    inputManager.addCursor(motion, {addCursor = false})
end

function exports.handleMouse()
    addCursorWithMouse()
end

function exports.cursorsEnabled()
    return not inputManager.areCursorsDisabled()
end

function exports.disableCursors()
    return inputManager.setCursorsDisabled(true)
end

function exports.enableCursors()
    return inputManager.setCursorsDisabled(false)
end

function exports.splitCursors(pattern)
    inputManager.splitCursors(pattern)
end

function exports.matchCursors(pattern)
    inputManager.matchCursors(pattern)
end

function exports.transposeCursors(direction)
    inputManager.transposeCursors(direction)
end

function exports.visualToCursors()
    inputManager.visualToCursors()
end

function exports.firstCursor()
    selectCursor(1)
end

function exports.lastCursor()
    selectCursor(-1)
end

function exports.nextCursor()
    rotateCursor(1)
end

function exports.prevCursor()
    rotateCursor(-1)
end

function exports.deleteCursor()
    deleteCurrentCursor()
end

function exports.alignCursors()
    alignCursors()
end

return exports
