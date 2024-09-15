local feedkeysManager = require("multicursor-nvim.feedkeys-manager")
local cursorManager = require("multicursor-nvim.cursor-manager")
local inputManager = require("multicursor-nvim.input-manager")

local core = {
    performingAction = false,
}

--- @param opts? { shallowUndo?: boolean }
function core.setup(opts)
    opts = opts or {}

    local nsid = vim.api.nvim_create_namespace("multicursor-nvim")

    cursorManager:setup(nsid, opts.shallowUndo)
    feedkeysManager:setup()
    inputManager:setup(nsid, cursorManager)

    vim.api.nvim_create_autocmd({ "WinLeave" }, {
        pattern = "*",
        callback = function()
            cursorManager:clear()
        end
    })
end

--- @param callback fun(ctx: CursorContext)
function core.action(callback)
    if core.performingAction then
        error("An action is already being performed")
    end
    core.performingAction = true
    inputManager:performAction(function()
        cursorManager:action(callback, true)
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

return core
