local TERM_CODES = require("multicursor-nvim.term-codes")
local feedkeysManager = require("multicursor-nvim.feedkeys-manager")
local util = require("multicursor-nvim.util")

local SPECIAL_KEYS = {
    [TERM_CODES.CTRL_R] = true,
    ["u"] = true,
    ["."] = true,
    ["zs"] = true,
    ["ze"] = true,
    ["zh"] = true,
    ["zl"] = true,
    ["zH"] = true,
    ["zL"] = true,
    ["zz"] = true,
    [TERM_CODES.CTRL_Y] = true,
    [TERM_CODES.CTRL_E] = true,
}

--- @class InputManager
--- @field private _nsid number
--- @field private _cursorManager CursorManager
--- @field private _cmdType string | nil
--- @field private _inInsertMode boolean
--- @field private _applying boolean
--- @field private _typed string
--- @field private _keys string
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
    self._keys = ""
    self._typed = ""
    self._fromSelectMode = false

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
    self._keys = ""
    self._typed = ""
    self._applying = true
    local success, err = pcall(callback)
    self._applying = false
    if not success then
        util.echoerr(err)
    end
end

--- @private
function InputManager:_onInsertMode(enabled)
    self._inInsertMode = enabled
    if not enabled then
        local insertReg = vim.fn.getreg(".")
        if self._fromSelectMode then
            self._typed = self._typed
                .. string.sub(insertReg, 2, #insertReg)
                .. TERM_CODES.ESC
        else
            self._typed = self._typed
                .. insertReg
                .. TERM_CODES.ESC
        end
    end
end

--- @private
function InputManager:_onSafeState()
    if self._applying then
        return
    end
    local mode = vim.fn.mode()
    local insertMode = mode == "i" or mode == "R"
    if insertMode ~= self._inInsertMode then
        self:_onInsertMode(insertMode)
    end
    if not insertMode then
        local selectMode = mode == "s"
            or mode == "S"
            or mode == TERM_CODES.CTRL_S
        self._fromSelectMode = selectMode
    end
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
            self._typed = ""
            self._cursorManager:dirty()
            if self._cursorManager:hasCursors() then
                self._cursorManager:action(function(ctx)
                    ctx:forEachCursor(function(cursor)
                        cursor:feedkeys("")
                    end)
                end, false)
            else
                self._cursorManager:update()
            end
            return
        end
        self._cmdType = nil
    end
    self._applying = true

    if SPECIAL_KEYS[string.match(self._keys, "%d*(.*)")] then
        self._cursorManager:dirty()
        if self._keys == "u" then
            self._cursorManager:loadUndoItem(-1)
        elseif self._keys == TERM_CODES.CTRL_R then
            self._cursorManager:loadUndoItem(1)
        elseif self._keys == "." then
            if self._cursorManager:hasCursors() then
                self._cursorManager:action(function(ctx)
                    if ctx:cursorsEnabled() then
                        ctx:forEachCursor(function(cursor)
                            if not cursor:isMainCursor() then
                                cursor:feedkeys(self._keys)
                            end
                        end)
                    end
                end, false)
            else
                self._cursorManager:update()
            end
        else
            self._cursorManager:update()
        end
        self._typed = ""
        self._keys = ""
    elseif #self._typed > 0 and self._cursorManager:hasCursors() then
        self._cursorManager:dirty()
        if self._cursorManager:hasCursors()
            and self._cursorManager:cursorsEnabled()
        then
            self._cursorManager:action(function(ctx)
                if ctx:cursorsEnabled() then
                    ctx:forEachCursor(function(cursor)
                        if not cursor:isMainCursor() then
                            cursor:feedkeys(self._typed, { remap = true })
                        end
                    end)
                end
            end, false)
        else
            self._cursorManager:update()
        end
    else
        self._cursorManager:update()
    end
    self._keys = ""
    self._typed = ""
    self._applying = false
end

--- @private
function InputManager:_onKey(key, typed)
    if feedkeysManager:wasFedKeys(typed) then
        return
    end
    if self._applying or self._inInsertMode then
        return
    end
    self._keys = self._keys .. key
    self._typed = self._typed .. typed
end

return InputManager
