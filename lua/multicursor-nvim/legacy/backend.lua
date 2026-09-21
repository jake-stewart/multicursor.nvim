local feedkeysManager = require("multicursor-nvim.legacy.feedkeys-manager")
local cursorManager = require("multicursor-nvim.legacy.cursor-manager")
local inputManager = require("multicursor-nvim.legacy.input-manager")
local snippetManager = require("multicursor-nvim.legacy.snippet-manager")

--- @class mc.LegacyBackend: mc.Backend
local LegacyBackend = {
    cursorManager = cursorManager,
}

--- @param nsid integer
--- @param opts mc.MultiCursorOpts
--- @param host mc.Host
function LegacyBackend:setup(nsid, opts, host)
    feedkeysManager:setup()
    inputManager:setup(nsid, host)
    snippetManager:setup()

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

--- @param callback fun()
function LegacyBackend:performAction(callback)
    inputManager:performAction(callback)
end

--- @param keys string
--- @param mode string
--- @param escape boolean
function LegacyBackend:feedkeys(keys, mode, escape)
    feedkeysManager.nvim_feedkeys(keys, mode, escape)
end

function LegacyBackend:clear()
    inputManager:clear()
end

return LegacyBackend
