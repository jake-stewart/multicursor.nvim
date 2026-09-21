local cursorManager = require("multicursor-nvim.native.cursor-manager")
local keymapManager = require("multicursor-nvim.keymap-manager")
local adapters = require("multicursor-nvim.adapters")
local util = require("multicursor-nvim.util")
local tbl = require("multicursor-nvim.tbl")

--- @class mc.NativeBackend: mc.Backend
--- @field private _host mc.Host
--- @field private _applying boolean
--- @field private _wasMode string
local NativeBackend = {
    cursorManager = cursorManager,
    _applying = false,
    _wasMode = "n",
}

--- @param callback fun()
function NativeBackend:performAction(callback)
    if not self._applying and not vim.api.nvim__mcursor_cascading() then
        adapters.disable()
        self._applying = true
        local success, err = pcall(callback)
        self._applying = false
        if not success then
            util.echoerr(err)
        end
    end
end

--- @private
--- @param fromMode string
--- @param toMode string
function NativeBackend:_emitModeChanged(fromMode, toMode)
    if #self._host.modeChangeCallbacks > 0 and fromMode ~= toMode then
        self:performAction(function()
            cursorManager:action(function(ctx)
                ctx:forEachCursor(function(cursor)
                    for _, callback in ipairs(self._host.modeChangeCallbacks) do
                        callback(cursor, fromMode, toMode)
                    end
                end)
            end, {})
        end)
    end
end

--- @private
function NativeBackend:_onSafeState()
    if self._applying then
        return
    end
    if cursorManager:hasCursors() then
        keymapManager:apply(vim.fn.bufnr())
        adapters.disable()
    else
        keymapManager:restore()
        adapters.enable()
    end
    cursorManager:onSafeState()
    local mode = vim.fn.mode()
    if mode == "i" or mode == "R" or mode == "c" then
        self._wasMode = mode
        return
    end
    local wasMode = self._wasMode
    self._wasMode = mode
    if mode ~= wasMode and cursorManager:hasCursors() then
        self:_emitModeChanged(wasMode, mode)
    end
    local info = {
        wasMode = wasMode,
    }
    tbl.forEach(tbl.shallow_copy(self._host.safeStateCallbacks), function(f) f(info) end)
end

--- @param nsid integer
--- @param opts mc.MultiCursorOpts
--- @param host mc.Host
function NativeBackend:setup(nsid, opts, host)
    self._host = host

    util.au("SafeState", "*", function() self:_onSafeState() end)
    util.au("BufEnter", "*", function() self:_onSafeState() end)
end

--- @param keys string
--- @param mode string
--- @param escape boolean
function NativeBackend:feedkeys(keys, mode, escape)
    vim.api.nvim_feedkeys(keys, mode, escape)
end

function NativeBackend:clear()
end

return NativeBackend
