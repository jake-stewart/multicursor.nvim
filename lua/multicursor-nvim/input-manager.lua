local TERM_CODES = require("multicursor-nvim.term-codes")
local feedkeysManager = require("multicursor-nvim.feedkeys-manager")
local util = require("multicursor-nvim.util")

--- @class InputManager
--- @field private _nsid number
--- @field private _cursorManager CursorManager
--- @field private _cmdType string | nil
--- @field private _inInsertMode boolean
--- @field private _applying boolean
--- @field private _macro string
--- @field private _specialKey string | nil
--- @field private _fromSelectMode boolean
local InputManager = {}

--- @param nsid number
--- @param cursorManager CursorManager
function InputManager:setup(nsid, cursorManager)
    self._nsid = nsid
    self._cursorManager = cursorManager
    self._inInsertMode = false
    self._applying = false
    self._macro = ""
    self._fromSelectMode = false

    util.au("ModeChanged", "[vV\x16ns]*:[iR]", function()
        self:_onInsertMode(true)
    end)

    util.au("ModeChanged", "[S\x13]*:[iR]", function()
        self:_onInsertMode(true, true)
    end)

    util.au("ModeChanged", "[iR]:*", function()
        self:_onInsertMode(false)
    end)

    util.au("SafeState", "*", function()
        self:_onSafeState()
    end)

    vim.on_key(
        function (key, typed)
            self:_onKey(key, typed)
        end,
        self._nsid
    )
end

--- @param callback function
function InputManager:performAction(callback)
    if self._applying or self._inInsertMode or self._cmdType then
        return nil
    end
    self._macro = ""
    self._specialKey = nil
    self._applying = true
    local success, err = pcall(callback)
    self._applying = false
    if not success then
        util.echoerr(err)
    end
end

--- @private
function InputManager:_onInsertMode(enabled, selectMode)
    if self._applying then
        return
    end
    self._inInsertMode = enabled
    if not enabled then
        local insertReg = vim.fn.getreg(".")
        if self._fromSelectMode then
            self._macro = self._macro
                .. string.sub(insertReg, 2, #insertReg)
                .. TERM_CODES.ESC
        else
            self._macro = self._macro
                .. insertReg
                .. TERM_CODES.ESC
        end
    end
    self._fromSelectMode = selectMode
end

--- @private
function InputManager:_onSafeState()
    if self._applying or self._inInsertMode then
        return
    end
    local cmdType = vim.fn.getcmdtype()
    if cmdType ~= "" then
        self._cmdType = cmdType
        return
    elseif self._cmdType then
        if self._cmdType == ":" then
            self._cmdType = nil
            self._macro = ""
            return
        end
        self._cmdType = nil
    end
    self._applying = true
    if self._specialKey then
        self._cursorManager:dirty()
        if self._specialKey == "u" then
            self._cursorManager:loadUndoItem(-1)
        elseif self._specialKey == TERM_CODES.CTRL_R then
            self._cursorManager:loadUndoItem(1)
        elseif self._specialKey == "." then
            if self._cursorManager:hasCursors() then
                self._cursorManager:action(function(ctx)
                    ctx:forEachCursor(function(cursor)
                        if not cursor:isMainCursor() then
                            cursor:feedkeys(".")
                        end
                    end)
                end)
            end
        end
        self._specialKey = nil
    elseif #self._macro > 0 and self._cursorManager:hasCursors() then
        if self._cursorManager:cursorsEnabled() then
            self._cursorManager:dirty()
            self._cursorManager:action(function(ctx)
                ctx:forEachCursor(function(cursor)
                    if not cursor:isMainCursor() then
                        cursor:feedkeys(self._macro, { remap = true })
                    end
                end)
            end)
        else
            -- to update the undo list
            self._cursorManager:action(function() end)
        end
    else
        -- to update the undo list
        self._cursorManager:action(function() end)
    end
    self._macro = ""
    self._applying = false
end

--- @private
function InputManager:_onKey(key, typed)
    if self._applying or self._inInsertMode or self._specialKey then
        return
    end
    if feedkeysManager:wasFedKeys(typed) then
        return
    end
    if not self._cmdType
        and self._macro == ""
        and (key == "u" or key == TERM_CODES.CTRL_R or key == ".")
    then
        self._specialKey = key
    else
        self._macro = self._macro .. typed
    end
end

return InputManager
