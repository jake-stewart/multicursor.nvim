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
--     visualIds: number[];    // (extarks used for decoration)
--     cursorId: number;       // (extmark used to track cursor)
--     visualStartId?: number; // (extmark used to track start of visual)
--     visualEndId?: number;   // (extmark used to track end of visual)
-- }

-- interface MultiCursorUndo {
--     cursors: Cursor[]; (additional cursors)
--     cursor: Cursor; (main cursor)
-- }

local function shallow_copy(t)
  local t2 = {}
  for k,v in pairs(t) do
    t2[k] = v
  end
  return t2
end

local function map(t, callback)
    local result = {}
    for i, v in ipairs(t) do
        result[#result + 1] = callback(v, i, t)
    end
    return result
end

local function filter(t, callback)
    local result = {}
    for i, v in ipairs(t) do
        if callback(v, i, t) then
            result[#result + 1] = v
        end
    end
    return result
end

local function find(t, callback)
    for i, v in ipairs(t) do
        if callback(v, i, t) then
            return v
        end
    end
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
    vim.fn.feedkeys(result, "nx")
end

local function getCursor()
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

local function setCursor(cursor)
    vim.fn.setreg("", cursor.register);
    vim.fn.setreg("/", cursor.search);
    vim.fn.setpos("'<", cursor.visual[1]);
    vim.fn.setpos("'>", cursor.visual[2]);
    vim.fn.setpos(".", cursor.pos);
    setMode(cursor.mode, cursor);
end


local function CursorManager(nsid)
    local cursors = {} -- CursorExtmark[];
    local undoItems = {} -- LuaMap<number, MultiCursorUndo>;

    local function updateCursorPos(cursor, cursorId, visualStartId, visualEndId)
        local newCursor = shallow_copy(cursor);
        newCursor.visual = {table.unpack(newCursor.visual)};

        local cursorExtmark = vim.api.nvim_buf_get_extmark_by_id(
            0, nsid, cursorId, {});

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

        if visualStartId then
            local visualStartExtmark = vim.api.nvim_buf_get_extmark_by_id(
                    0, nsid, visualStartId, {});
            if visualStartExtmark and #visualStartExtmark > 0 then
                newCursor.visual[1] = {
                    newCursor.visual[1][1],
                    visualStartExtmark[1] + 1,
                    visualStartExtmark[2] + 1,
                    newCursor.visual[1][4],
                }
            end
        end

        if visualEndId then
            local visualEndExtmark = vim.api.nvim_buf_get_extmark_by_id(
                    0, nsid, visualEndId, {});
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

    local function drawCursor(cursor)
        local start
        local _end

        if visualSelectModes[cursor.mode] then
            start = math.max(math.min(cursor.visual[1][2], cursor.pos[2]) - 1, 0);
            _end = math.max(math.max(cursor.visual[2][2], cursor.pos[2]) - 1, start);
        else
            start = cursor.pos[2] - 1;
            _end = cursor.pos[2] - 1;
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

        local visualIds = {}

        if cursor.mode == "v" or cursor.mode == "s" then
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
                        function() return {{" ", "MultiCursorVisual"}} end
                    ),
                    end_col = endCol + 1,
                    virt_text_pos = "inline",
                    virt_text_win_col = line and #line or 0,
                    hl_group = "MultiCursorVisual",
                });
                visualIds[#visualIds + 1] = id;
                i = i + 1
            end
        elseif cursor.mode == "V" or cursor.mode == "S" then
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
                        virt_text = {{" ", "MultiCursorVisual"}},
                        end_col = endCol + 1,
                        virt_text_pos = "inline",
                        virt_text_win_col = line and #line or 0,
                        hl_group = "MultiCursorVisual",
                    }
                );
                visualIds[#visualIds + 1] = id;
                i = i + 1
            end
        elseif cursor.mode == CTRL_V or cursor.mode == CTRL_S then
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
                            hl_group = "MultiCursorVisual",
                        }
                    );
                    visualIds[#visualIds + 1] = id;
                end
                i = i + 1
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
                virt_text = {{char, "MultiCursorCursor"}},
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
        return copy
    end

    local function clear()
        vim.api.nvim_buf_clear_namespace(0, nsid, 0, -1)
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
                local cursor = find(cursors, function(c)
                    return c.cursorId == extmark[1]
                end)
                if cursor then
                    return cursor
                end
            end
        end
    end

    local function eraseCursor(cursor)
        for _, id in ipairs(cursor.visualIds) do
            vim.api.nvim_buf_del_extmark(0, nsid, id)
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
        cursors = filter(cursors, function(c)
            return c ~= cursor
        end)
    end

    local function insertCursor(_end, cursor)
        table.insert(
            cursors, _end == 1 and 1 or #cursors + 1,
            drawCursor(cursor)
        )
    end

    local function mergeCursors(mainCursor)
        local newCursors = {}
        for _, cursor in ipairs(cursors) do
            local exists = false
            if cursor.pos[2] == mainCursor.pos[2]
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

    local function update(mainCursor)
        local undoTree = vim.fn.undotree();
        mergeCursors(mainCursor);
        undoItems[undoTree.seq_cur] = {
            cursors = cursors,
            cursor = mainCursor,
        };
    end

    local function hasCursors()
        return #cursors > 0;
    end

    local function performMacro(macro)
        if not hasCursors() or #macro == 0 then
            return;
        end

        local origCursor = getCursor();

        local origClipboard = vim.o.clipboard;
        vim.o.clipboard = "";

        local cursorId = vim.api.nvim_buf_set_extmark(
            0,
            nsid,
            origCursor.pos[2] - 1,
            origCursor.pos[3] - 1,
            {
                strict = false,
                undo_restore = false
            }
        );

        local visualStartId
        local visualEndId

        if origCursor.visual[1][2] > 0
            and origCursor.visual[1][3] > 0
        then
            visualStartId = vim.api.nvim_buf_set_extmark(
                0,
                nsid,
                origCursor.visual[1][2] - 1,
                origCursor.visual[1][3] - 1,
                {
                    strict = false,
                    undo_restore = false
                }
            );
        end

        if origCursor.visual[2][2] > 0
            and origCursor.visual[2][3] > 0
        then
            visualEndId = vim.api.nvim_buf_set_extmark(
                0,
                nsid,
                origCursor.visual[2][2] - 1,
                origCursor.visual[2][3] - 1,
                {
                    strict = false,
                    undo_restore = false
                }
            );
        end

        for _, cursor in ipairs(cursors) do
            for _, id in ipairs(cursor.visualIds) do
                vim.api.nvim_buf_del_extmark(0, nsid, id)
            end
        end

        local newCursors = {}
        for _, cursor in ipairs(cursors) do
            cursor = updateCursorPos(
                cursor,
                cursor.cursorId,
                cursor.visualStartId,
                cursor.visualEndId
            )
            vim.api.nvim_buf_del_extmark(0, nsid, cursor.cursorId)
            if cursor.visualStartId then
                vim.api.nvim_buf_del_extmark(0, nsid, cursor.visualStartId)
            end
            if cursor.visualEndId then
                vim.api.nvim_buf_del_extmark(0, nsid, cursor.visualEndId)
            end
            setCursor(cursor);
            local success = pcall(function()
                vim.fn.feedkeys(macro, "x");
            end)
            newCursors[#newCursors + 1] = drawCursor(success and getCursor() or cursor)
        end

        newCursors = map(newCursors, function (c)
            return updateCursorPos(
                c,
                c.cursorId,
                c.visualStartId,
                c.visualEndId
            )
        end)

        origCursor = updateCursorPos(
            origCursor, cursorId, visualStartId, visualEndId)
        vim.api.nvim_buf_del_extmark(0, nsid, cursorId)

        if visualStartId then
            vim.api.nvim_buf_del_extmark(0, nsid, visualStartId)
        end
        if visualEndId then
            vim.api.nvim_buf_del_extmark(0, nsid, visualEndId)
        end

        cursors = newCursors
        update(origCursor)
        vim.o.clipboard = origClipboard
        setCursor(origCursor)
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

            setCursor(undoItem.cursor)
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

    local function sortCursors()
        table.sort(cursors, function(a, b)
            if a.pos[2] == b.pos[2] then
                return a.pos[3] < b.pos[3]
            end
            return a.pos[2] < b.pos[2]
        end)
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

    local function findNextCursor(cursor, direction)
        if #cursors == 0 then
            return
        elseif #cursors == 1 then
            return cursors[1]
        end
        sortCursors()
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

    return {
        undo = undo,
        redo = redo,
        hasCursors = hasCursors,
        deleteCursor = deleteCursor,
        performMacro = performMacro,
        insertCursor = insertCursor,
        getCursorAtPosition = getCursorAtPosition,
        findNextCursor = findNextCursor,
        update = update,
        clear = clear,
    }
end

function InputManager(nsid, cursorManager)
    local cmdType
    local inInsertMode = false
    local applying = false
    local macro = ""
    local fromSelectMode = false

    local function onInsertMode(enabled, selectMode)
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
            if cmdType == ":" then
                cmdType = nil
                macro = ""
                return
            end
            cmdType = nil
        end
        applying = true;
        if macro == "u" then
            cursorManager.undo();
        elseif macro == CTRL_R then
            cursorManager.redo();
        elseif #macro > 0 then
            cursorManager.performMacro(macro);
        end
        macro = "";
        applying = false;
    end

    local function onKey(key, typed)
        if applying or inInsertMode then
            return
        end
        if macro == "" and (key == "u" or key == CTRL_R) then
            macro = key;
        else
            macro = macro .. typed;
        end
    end

    local function deleteCursor()
        if applying or inInsertMode or cmdType then
            return;
        end
        local cursor = cursorManager.findNextCursor(getCursor())
        if cursor then
            cursorManager.deleteCursor(cursor)
            setCursor(cursor)
            cursorManager.update(cursor)
        end
    end

    local function addCursorWithMouse()
        if applying or inInsertMode or cmdType then
            return
        end
        local mousePos = vim.fn.getmousepos();
        if mousePos.line == vim.fn.line(".") and mousePos.column == vim.fn.col(".") then
            deleteCursor()
        else
            local existingCursor = cursorManager.getCursorAtPosition(mousePos.line, mousePos.column);
            if existingCursor then
                cursorManager.deleteCursor(existingCursor);
            else
                local cursor = getCursor();
                cursorManager.insertCursor(-1, cursor);
                vim.fn.setpos(".", {
                    cursor.pos[1],
                    mousePos.line,
                    mousePos.column,
                    0,
                    mousePos.column
                });
                cursorManager.update(getCursor());
            end
        end
    end

    local function adjustVisualCursor(origCursor, newCursor)
        local visStart = origCursor.visual[1]
        local visEnd = origCursor.visual[2]

        local atVisStart = origCursor.pos[2] == visStart[2]
            and origCursor.pos[3] == visStart[3]

        local atVisEnd = origCursor.pos[2] == visEnd[2]
            and origCursor.pos[3] == visEnd[3]

        local rowDiff = newCursor.pos[2] - visEnd[2]
        local colDiff

        if newCursor.mode == "n" then
            colDiff = newCursor.pos[3] - visStart[3]
        else
            colDiff = atVisStart
                and visEnd[3] - newCursor.pos[3]
                or newCursor.pos[3] - visEnd[3]
        end

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

    local function applyCursorMotion(motion, skip)
        if applying or inInsertMode or cmdType then
            return;
        end
        applying = true;
        macro = "";
        local origCursor = getCursor();
        setCursor(origCursor);
        if not pcall(function() vim.fn.feedkeys(motion, "x") end) then
            applying = false
            return
        end
        if not skip then
            cursorManager.insertCursor(-1, origCursor);
        end
        local newCursor = getCursor();
        if visualSelectModes[origCursor.mode] then
            adjustVisualCursor(origCursor, newCursor)
        end
        newCursor.mode = origCursor.mode
        setCursor(newCursor);
        cursorManager.update(newCursor);
        applying = false;
    end

    local function addCursorWithMotion(motion)
        applyCursorMotion(motion, false)
    end

    local function skipCursorWithMotion(motion)
        applyCursorMotion(motion, true)
    end


    local function rotateCursor(direction)
        if applying or inInsertMode or cmdType then
            return;
        end
        local mainCursor = getCursor()
        local cursor = cursorManager.findNextCursor(mainCursor, direction)
        if cursor then
            cursorManager.deleteCursor(cursor)
            cursorManager.insertCursor(1, mainCursor)
            setCursor(cursor)
            cursorManager.update(cursor)
        end
    end

    local function au(event, pattern, callback)
        vim.api.nvim_create_autocmd(event, {
            pattern = pattern,
            callback = callback
        });
    end

    local function clear()
        if applying or inInsertMode or cmdType then
            return;
        end
        cursorManager.clear()
    end

    au("ModeChanged", "[vV\x16ns]*:[iR]", function() onInsertMode(true) end);
    au("ModeChanged", "[S\x13]*:[iR]", function() onInsertMode(true, true) end);
    au("ModeChanged", "[iR]:*", function() onInsertMode(false) end);
    au("SafeState", "*", onSafeState);

    vim.on_key(function (key, typed) onKey(key, typed) end, nsid);

    return {
        clear = clear,
        skipCursorWithMotion = skipCursorWithMotion,
        addCursorWithMotion = addCursorWithMotion,
        addCursorWithMouse = addCursorWithMouse,
        rotateCursor = rotateCursor,
        deleteCursor = deleteCursor,
    };
end

vim.cmd.hi("link", "MultiCursorCursor", "Cursor");
vim.cmd.hi("link", "MultiCursorVisual", "Visual");

local cursorManager
local inputManager

local exports = {}

function exports.setup()
    local nsid = vim.api.nvim_create_namespace("multicursor");
    cursorManager = CursorManager(nsid)
    inputManager = InputManager(nsid, cursorManager)

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

function exports.addCursor(motion)
    inputManager.addCursorWithMotion(motion)
end

function exports.skipCursor(motion)
    inputManager.skipCursorWithMotion(motion)
end

function exports.handleMouse()
    inputManager.addCursorWithMouse()
end

function exports.nextCursor()
    inputManager.rotateCursor(1)
end

function exports.prevCursor()
    inputManager.rotateCursor(-1)
end

function exports.deleteCursor()
    inputManager.deleteCursor()
end

return exports
