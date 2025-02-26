local feedkeysManager = require("multicursor-nvim.feedkeys-manager")
local cursorManager = require("multicursor-nvim.cursor-manager")
local inputManager = require("multicursor-nvim.input-manager")
local snippetManager = require("multicursor-nvim.snippet-manager")
local TERM_CODES = require("multicursor-nvim.term-codes")

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

local function jump(direction, key)
    inputManager:performAction(function()
        if cursorManager:hasCursors() then
            cursorManager:navigateJumplist(direction * vim.v.count1)
        else
            feedkeysManager.nvim_feedkeys(vim.v.count1 .. key, "nx", true)
        end
    end)
end

function core.jumpForward()
    jump(1, TERM_CODES.CTRL_I)
end

function core.jumpBackward()
    jump(-1, TERM_CODES.CTRL_O)
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
    feedkeysManager.nvim_feedkeys(keys, mode, false)
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

function core.clearCursors()
    cursorManager:clear()
end

return core
