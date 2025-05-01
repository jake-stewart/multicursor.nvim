local feedkeysManager = require("multicursor-nvim.feedkeys-manager")
local cursorManager = require("multicursor-nvim.cursor-manager")
local inputManager = require("multicursor-nvim.input-manager")
local snippetManager = require("multicursor-nvim.snippet-manager")
local TERM_CODES = require("multicursor-nvim.term-codes")

local core = {
    --- @type boolean Whether there is an action in progress
    --- (to prevent nested action calls)
    performingAction = false,
}

--- Registers a cursor callback.
--- It will be called for each cursor whenever mode is changed with
--- old mode, new mode.
--- @param callback fun(cursor: mc.Cursor, oldMode: string, newMode: string)
function core.onModeChanged(callback)
    inputManager:onModeChanged(callback)
end

--- Registers a safe state callback.
--- It will be called whenever the input manager is in a safe state.
--- @param callback fun(info: mc.SafeStateInfo)
--- @param opts? { once?: boolean }
function core.onSafeState(callback, opts)
    inputManager:onSafeState(callback, opts)
end

--- Registers a keymap layer callback.
--- It will be called when a buffer has cursors, any mappings set with the
--- provided function
--- (similar to `vim.keymap.set`) will be automatically removed once
--- multicursor ends.
--- @param callback fun(set: mc.KeymapSetterFunc)
function core.addKeymapLayer(callback)
    inputManager:addKeymapLayer(callback)
end

--- Removes a previously registered keymap layer callback.
--- @param callback fun(set: mc.KeymapSetterFunc)
function core.removeKeymapLayer(callback)
    inputManager:removeKeymapLayer(callback)
end

--- @class mc.MultiCursorOpts
--- @field signs? string[] | nil,
--- @field shallowUndo? boolean  (default: false)
--- @field hlsearch? boolean Allow hlsearch when multicursor (default: false)

--- @param opts? mc.MultiCursorOpts
function core.setup(opts)
    opts = opts or {}

    local nsid = vim.api.nvim_create_namespace("multicursor-nvim")

    cursorManager:setup(nsid, opts)
    feedkeysManager:setup()
    inputManager:setup(nsid)
    snippetManager:setup()

    if vim.fn.mapcheck(TERM_CODES.CTRL_I) == ""
        and vim.fn.mapcheck(TERM_CODES.CTRL_O) == ""
    then
        vim.keymap.set("n", TERM_CODES.CTRL_I, core.jumpForward)
        vim.keymap.set("n", TERM_CODES.CTRL_O, core.jumpBackward)
    end

    if vim.fn.mapcheck("<left>", "i") == ""
        and vim.fn.mapcheck("<right>", "i") == ""
    then
        vim.keymap.set("i", "<left>", "<C-g>U<Left>")
        vim.keymap.set("i", "<right>", "<C-g>U<Right>")
    end

    vim.api.nvim_create_autocmd({ "WinLeave" }, {
        pattern = "*",
        callback = function()
            cursorManager:clear()
        end
    })
end

--- @param direction -1|1
--- @param key string
local function jump(direction, key)
    inputManager:performAction(function()
        if cursorManager:hasCursors() then
            cursorManager:navigateJumplist(direction * vim.v.count1)
        else
            feedkeysManager.nvim_feedkeys(vim.v.count1 .. key, "nx", true)
        end
    end)
end

--- Go to the newer cursor position in jump list.
--- Behaves identically to `<C-i>` except it syncs up the cursors.
--- This action is automatically mapped to `<C-i>` unless a mapping
--- already exists.
function core.jumpForward()
    jump(1, TERM_CODES.CTRL_I)
end

--- Go to the older cursor position in jump list.
--- Behaves identically to `<C-o>` except it syncs up the all the cursors.
--- This action is automatically mapped to `<C-o>` unless a mapping
--- already exists.
function core.jumpBackward()
    jump(-1, TERM_CODES.CTRL_O)
end

--- Perform a complex action using the |multicursor-api|.
--- @param callback fun(ctx: mc.CursorContext)
function core.action(callback)
    if core.performingAction then
        error("An action is already being performed")
    end
    core.performingAction = true
    inputManager:performAction(function()
        local mode = vim.fn.mode()
        if mode == "i" or mode == "R" then
            callback() --- @diagnostic disable-line: missing-parameter
        else
            cursorManager:action(callback, { excludeMainCursor = false })
            inputManager:clear()
        end
    end)
    core.performingAction = false
end

--- Use instead of `vim.fn.feedkeys()` or `vim.api.nvim_feedkeys()` in
--- multicursor mappings to avoid bugs.
---
--- @param keys string String representing a command
--- @param opts? { remap?: boolean, keycodes?: boolean }
function core.feedkeys(keys, opts)
    opts = opts or {}
    local mode = opts and opts.remap and "t" or "tn"
    if opts and opts.keycodes then
        keys = vim.api.nvim_replace_termcodes(
            keys, true, true, true)
    end
    feedkeysManager.nvim_feedkeys(keys, mode, false)
end

--- Returns whether multiple cursors exist
--- @return boolean
function core.hasCursors()
    return cursorManager:hasCursors()
end

--- Returns whether the cursors are locked from moving.
--- @return boolean
function core.cursorsEnabled()
    return cursorManager:cursorsEnabled()
end

--- Returns the total number of cursors.
--- There is always at least one cursor (the main cursor).
--- @return integer
function core.numCursors()
    return cursorManager:numCursors()
end

--- Returns number of enabled cursors.
--- There is always at least one enabled cursor (the main cursor).
--- @return integer
function core.numEnabledCursors()
    return cursorManager:numEnabledCursors()
end

--- Returns the number of disabled cursors.
--- @return integer
function core.numDisabledCursors()
    return cursorManager:numDisabledCursors()
end

--- Clear all cursors except the main cursor.
function core.clearCursors()
    cursorManager:clear()
end

return core
