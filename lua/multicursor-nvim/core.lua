local feedkeysManager = require("multicursor-nvim.feedkeys-manager")
local cursorManager = require("multicursor-nvim.cursor-manager")
local inputManager = require("multicursor-nvim.input-manager")

local core = {
    performingAction = false,
}

--- Calls callback for each cursor with old mode, new mode
--- whenever mode is changed
--- @param callback function(cursor: Cursor, oldMode: string, newMode: string)
function core.onModeChanged(callback)
    return inputManager:onModeChanged(callback)
end

--- @class MultiCursorOpts
--- @field signs? string[] | nil,
--- @field shallowUndo? boolean

--- @param opts? MultiCursorOpts
function core.setup(opts)
    opts = opts or {}

    local nsid = vim.api.nvim_create_namespace("multicursor-nvim")

    cursorManager:setup(nsid, opts)
    feedkeysManager:setup()
    inputManager:setup(nsid, cursorManager)

    vim.api.nvim_create_autocmd({ "WinLeave" }, {
        pattern = "*",
        callback = function()
            cursorManager:clear()
        end
    })
end

function core.restoreCursors()
    cursorManager:restoreCursors()
end

--- @param callback fun(ctx: CursorContext)
function core.action(callback)
    if core.performingAction then
        error("An action is already being performed")
    end
    core.performingAction = true
    inputManager:performAction(function()
        local mode = vim.fn.mode()
        if mode == "i" or mode == "R" then
            callback() --- @diagnostic disable-line
        else
            cursorManager:action(callback, { excludeMainCursor = false })
            inputManager:clear()
        end
    end)
    core.performingAction = false
end

--- @param keys string
--- @param opts? { remap?: boolean, keycodes?: boolean }
function core.feedkeys(keys, opts)
    opts = opts or {}
    local mode = opts and opts.remap and "t" or "tn"
    if opts and opts.keycodes then
        keys = vim.api.nvim_replace_termcodes(
            keys, true, true, true)
    end
    feedkeysManager.feedkeys(keys, mode, false)
end

--- Returns whether multiple cursors exist
--- @return boolean
function core.hasCursors()
    return cursorManager:hasCursors()
end

--- @return boolean
function core.cursorsEnabled()
    return cursorManager:cursorsEnabled()
end

function core.numCursors()
    return cursorManager:numCursors()
end

function core.numEnabledCursors()
    return cursorManager:numEnabledCursors()
end

function core.numDisabledCursors()
    return cursorManager:numDisabledCursors()
end

return core
