local keymapManager = require("multicursor-nvim.keymap-manager")
local TERM_CODES = require("multicursor-nvim.term-codes")
local tbl = require("multicursor-nvim.tbl")

local function nativeAvailable()
    return vim.fn.has("nvim-0.13") == 1
        and vim.api.nvim_mcursor ~= nil
end

local backend

local host = {
    modeChangeCallbacks = {},
    safeStateCallbacks = {},
}

local core = {
    --- @type boolean Whether there is an action in progress
    --- (to prevent nested action calls)
    performingAction = false,
}

--- @class mc.SafeStateInfo
--- @field wasMode string

--- @alias mc.ModeChangedCallback fun(
---     cursor: mc.Cursor,
---     oldMode: string,
---     newMode: string)

--- @class mc.Host
--- @field modeChangeCallbacks mc.ModeChangedCallback[]
--- @field safeStateCallbacks fun(info: mc.SafeStateInfo)[]

--- @class mc.Backend
--- @field cursorManager mc.CursorManager
--- @field setup fun(
---     self: mc.Backend,
---     nsid: integer,
---     opts: mc.MultiCursorOpts,
---     host: mc.Host)
--- @field performAction fun(self: mc.Backend, callback: fun())
--- @field feedkeys fun(
---     self: mc.Backend,
---     keys: string,
---     mode: string,
---     escape: boolean)
--- @field clear fun(self: mc.Backend)

--- @class mc.MultiCursorOpts
--- @field signs? string[] | nil,
--- @field shallowUndo? boolean  (default: false)
--- @field hlsearch? boolean Allow hlsearch when multicursor (default: false)
--- @field native? boolean Use the native multicursor engine (default: auto)

--- Registers a cursor callback.
--- It will be called for each cursor whenever mode is changed with
--- old mode, new mode.
--- @param callback fun(cursor: mc.Cursor, oldMode: string, newMode: string)
function core.onModeChanged(callback)
    host.modeChangeCallbacks[#host.modeChangeCallbacks + 1] = callback
end

--- Registers a safe state callback.
--- It will be called whenever the input manager is in a safe state.
--- @param callback fun(info: mc.SafeStateInfo)
--- @param opts? { once?: boolean }
function core.onSafeState(callback, opts)
    if opts and opts.once then
        local wrapped = callback
        callback = function(info)
            wrapped(info)
            tbl.remove(host.safeStateCallbacks, callback)
        end
    end
    host.safeStateCallbacks[#host.safeStateCallbacks + 1] = callback
end

--- Registers a keymap layer callback.
--- It will be called when a buffer has cursors, any mappings set with the
--- provided function
--- (similar to `vim.keymap.set`) will be automatically removed once
--- multicursor ends.
--- @param callback fun(set: mc.KeymapSetterFunc)
function core.addKeymapLayer(callback)
    keymapManager:addLayer(callback)
end

--- Removes a previously registered keymap layer callback.
--- @param callback fun(set: mc.KeymapSetterFunc)
function core.removeKeymapLayer(callback)
    keymapManager:removeLayer(callback)
end

--- @param opts? mc.MultiCursorOpts
function core.setup(opts)
    opts = opts or {}
    if opts.native ~= false and nativeAvailable() then
        backend = require("multicursor-nvim.native.backend")
    else
        backend = require("multicursor-nvim.legacy.backend")
    end

    local nsid = vim.api.nvim_create_namespace("multicursor-nvim")

    backend.cursorManager:setup(nsid, opts)
    backend:setup(nsid, opts, host)

    if vim.fn.mapcheck(TERM_CODES.CTRL_I) == ""
        and vim.fn.mapcheck(TERM_CODES.CTRL_O) == ""
    then
        vim.keymap.set("n", TERM_CODES.CTRL_I, core.jumpForward)
        vim.keymap.set("n", TERM_CODES.CTRL_O, core.jumpBackward)
    end
end

--- @param direction -1|1
--- @param key string
local function jump(direction, key)
    backend:performAction(function()
        if backend.cursorManager:hasCursors() then
            backend.cursorManager:navigateJumplist(direction * vim.v.count1)
        else
            backend:feedkeys(vim.v.count1 .. key, "nx", true)
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
    backend:performAction(function()
        local mode = vim.fn.mode()
        if mode == "i" or mode == "R" then
            callback() --- @diagnostic disable-line: missing-parameter
        else
            backend.cursorManager:action(
                callback, { excludeMainCursor = false })
            backend:clear()
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
    backend:feedkeys(keys, mode, false)
end

--- Returns whether multiple cursors exist
--- @return boolean
function core.hasCursors()
    return backend.cursorManager:hasCursors()
end

--- Returns whether the cursors are locked from moving.
--- @return boolean
function core.cursorsEnabled()
    return backend.cursorManager:cursorsEnabled()
end

--- Returns the total number of cursors.
--- There is always at least one cursor (the main cursor).
--- @return integer
function core.numCursors()
    return backend.cursorManager:numCursors()
end

--- Returns number of enabled cursors.
--- There is always at least one enabled cursor (the main cursor).
--- @return integer
function core.numEnabledCursors()
    return backend.cursorManager:numEnabledCursors()
end

--- Returns the number of disabled cursors.
--- @return integer
function core.numDisabledCursors()
    return backend.cursorManager:numDisabledCursors()
end

--- Clear all cursors except the main cursor.
function core.clearCursors()
    backend.cursorManager:clear()
end

return core
