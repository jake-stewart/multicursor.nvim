local TERM_CODES = require("multicursor-nvim.term-codes")
local feedkeysManager = require("multicursor-nvim.feedkeys-manager")

local function echoerr(message)
    message = type(message) == "string"
        and message or vim.inspect(message)
    vim.api.nvim_echo({ { message, "Error" } }, false, {})
end

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
InputManager.__index = InputManager

--- @param nsid number
--- @param cursorManager CursorManager
--- @return InputManager
local function newInputManager(nsid, cursorManager)
    --- @type InputManager
    local fields = {
        _nsid = nsid,
        _cursorManager = cursorManager,
        _inInsertMode = false,
        _applying = false,
        _macro = "",
        _fromSelectMode = false
    }
    return setmetatable(fields, InputManager)
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
        echoerr(err)
    end
end

function InputManager:setup()
    local function au(event, pattern, callback)
        vim.api.nvim_create_autocmd(event, {
            pattern = pattern,
            callback = callback
        })
    end
    au("ModeChanged", "[vV\x16ns]*:[iR]", function() self:onInsertMode(true) end)
    au("ModeChanged", "[S\x13]*:[iR]", function() self:onInsertMode(true, true) end)
    au("ModeChanged", "[iR]:*", function() self:onInsertMode(false) end)
    au("SafeState", "*", function() self:onSafeState() end)
    vim.on_key(function (key, typed) self:onKey(key, typed) end, self._nsid)
end

--- @private
function InputManager:onInsertMode(enabled, selectMode)
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
function InputManager:onSafeState()
    if self._applying or self._inInsertMode then
        return
    end
    if vim.fn.mode() == "c" then
        self._cmdType = vim.fn.getcmdtype()
        return
    elseif self._cmdType then
        if self._cmdType == ":" or self._cmdType == "@" then
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
            self._cursorManager:undo()
        elseif self._specialKey == TERM_CODES.CTRL_R then
            self._cursorManager:redo()
        elseif self._specialKey == "." then
            if self._cursorManager:hasCursors() then
                self._cursorManager:action(function(ctx)
                    ctx:forEach(function(cursor)
                        if not cursor:isMainCursor() then
                            cursor:perform(".")
                        end
                    end)
                end)
            end
        end
        self._specialKey = nil
    elseif self._cursorManager:cursorsEnabled() and #self._macro > 0 then
        if self._cursorManager:hasCursors() then
            self._cursorManager:dirty()
            self._cursorManager:action(function(ctx)
                ctx:forEach(function(cursor)
                    if not cursor:isMainCursor() then
                        cursor:perform(self._macro, { remap = true })
                    end
                end)
            end)
        end
    end
    self._macro = ""
    self._applying = false
end

--- @private
function InputManager:onKey(key, typed)
    if self._applying or self._inInsertMode then
        return
    end
    if feedkeysManager:wasFedKeys(typed) then
        return
    end
    if self._macro == "" and (key == "u" or key == TERM_CODES.CTRL_R or key == ".") then
        self._specialKey = key
    else
        self._macro = self._macro .. typed
    end
end

return newInputManager
