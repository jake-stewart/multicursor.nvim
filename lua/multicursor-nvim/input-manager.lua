local TERM_CODES = require("multicursor-nvim.term-codes")
local feedkeysManager = require("multicursor-nvim.feedkeys-manager")
local cursorManager = require("multicursor-nvim.cursor-manager")
local snippetManager = require("multicursor-nvim.snippet-manager")
local util = require("multicursor-nvim.util")

local SPECIAL_KEYS = {
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

local SPECIAL_NORMAL_KEYS = {
    [TERM_CODES.CTRL_R] = true,
    ["u"] = true,
}

--- @class InputManager
--- @field private _nsid number
--- @field private _cmdType string | nil
--- @field private _inInsertMode boolean
--- @field private _applying boolean
--- @field private _typed string
--- @field private _keys string
--- @field private _wasMode string
--- @field private _fromSelectMode boolean
--- @field private _snippetText? string
--- @field private _snippetLine? string
--- @field private _snippetCol? integer
--- @field private _snippet table
--- @field private _modeChangeCallbacks? function[]
local InputManager = {}

--- @param nsid number
function InputManager:setup(nsid)
    self._nsid = nsid
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

--- @param callback function(cursor: Cursor, from: string, to: string)
function InputManager:onModeChanged(callback)
    if not self._modeChangeCallbacks then
        self._modeChangeCallbacks = {}
    end
    self._modeChangeCallbacks[#self._modeChangeCallbacks + 1] = callback
end

--- @param callback function
function InputManager:performAction(callback)
    if not self._applying then
        self._applying = true
        local success, err = pcall(callback)
        self._applying = false
        if not success then
            util.echoerr(err)
        end
    end
end

function InputManager:clear()
    self._keys = ""
    self._typed = ""
end

--- @private
function InputManager:_emitModeChanged(cursor, fromMode, toMode)
    for _, callback in ipairs(self._modeChangeCallbacks) do
        callback(cursor, fromMode, toMode)
    end
end

--- @private
function InputManager:_onSafeState()
    if self._applying then
        return
    end
    local mode = vim.fn.mode()
    local insertMode = mode == "i" or mode == "R"
    local insertModeChanged = insertMode ~= self._inInsertMode
    if insertModeChanged then
        self._inInsertMode = insertMode
        if insertMode then
            self._insertModePos = vim.fn.getpos(".")
            if self._fromSelectMode then
                self._insertModePos[3] = math.max(1, self._insertModePos[3] - 1)
            end
        end
    end
    local wasFromSelectMode = self._fromSelectMode
    if insertMode then
        -- if snippetManager:hasSnippet() then
        --     feedkeysManager.feedkeys(TERM_CODES.ESC, "nt", false)
        -- end
        return
    else
        local selectMode = mode == "s"
            or mode == "S"
            or mode == TERM_CODES.CTRL_S
        self._fromSelectMode = selectMode
    end
    if self._applying then
        return
    end
    self._applying = true

    local cmdType = vim.fn.getcmdtype()
    if cmdType ~= "" then
        self._applying = false
        self._cmdType = cmdType
        return
    elseif self._cmdType then
        if self._cmdType == ":" then
            self._cmdType = nil
            self._keys = ""
            self._typed = ""
            cursorManager:dirty()
            if cursorManager:hasCursors() then
                cursorManager:action(function(ctx)
                    ctx:forEachCursor(function(cursor)
                        cursor:feedkeys("")
                    end)
                end, { excludeMainCursor = true })
            else
                cursorManager:update()
            end
            self._applying = false
            return
        end
        self._cmdType = nil
    end

    if snippetManager:hasSnippet() then
        local endMode = snippetManager:performSnippet(
            wasFromSelectMode, self._typed, self._insertModePos)
        if endMode ~= "s" and endMode ~= "S" and endMode ~= TERM_CODES.CTRL_S then
            feedkeysManager.feedkeys("a", "tn", false)
        else
            self._fromSelectMode = true
        end
        self._insertModePos = nil
        self._keys = ""
        self._typed = ""
        self._applying = false
        return
    end

    if insertModeChanged then
        cursorManager:dirty()
        if cursorManager:hasCursors() then
            local reg = vim.fn.getreg(".")
            cursorManager:action(function(ctx)
                ctx:forEachCursor(function(cursor)
                    cursor:perform(function()
                        if not wasFromSelectMode then
                            feedkeysManager.feedkeys(self._typed, "", false)
                        end
                        feedkeysManager.feedkeys(reg, "nx", false)
                    end)
                    if self._modeChangeCallbacks and self._wasMode ~= mode then
                        self:_emitModeChanged(cursor, self._wasMode, mode)
                    end
                end)
            end, {
                excludeMainCursor = true,
                allowUndo = true,
                ifNotUndo = function(mainCursor)
                    if self._modeChangeCallbacks and self._wasMode ~= mode then
                        self:_emitModeChanged(mainCursor, self._wasMode, mode)
                    end
                end
            })
        else
            cursorManager:update()
        end
        self._wasMode = mode
        self._applying = false
        self._typed = ""
        self._keys = ""
        return
    end

    local specialKey = string.match(self._keys, "%d*(.*)")
    if (self._wasMode == "n" and SPECIAL_NORMAL_KEYS[specialKey]) or SPECIAL_KEYS[specialKey] then
        cursorManager:dirty()
        if specialKey == "u" then
            cursorManager:loadUndoItem(-1)
        elseif specialKey == TERM_CODES.CTRL_R then
            cursorManager:loadUndoItem(1)
        elseif specialKey == "." then
            if cursorManager:hasCursors() then
                cursorManager:action(function(ctx)
                    ctx:forEachCursor(function(cursor)
                        cursor:feedkeys(self._keys)
                    end)
                end, { excludeMainCursor = true, allowUndo = true })
            else
                cursorManager:update()
            end
        else
            cursorManager:update()
        end
        self._typed = ""
        self._keys = ""
    else
        local handled = false
        if #self._typed > 0 and cursorManager:hasCursors() then
            cursorManager:dirty()
            if cursorManager:hasCursors() then
                handled = true
                cursorManager:action(function(ctx)
                    if self._modeChangeCallbacks and self._wasMode ~= mode then
                        self:_emitModeChanged(ctx:mainCursor(), self._wasMode, mode)
                    end
                    ctx:forEachCursor(function(cursor)
                        cursor:feedkeys(self._typed, { remap = true })
                        if self._modeChangeCallbacks and self._wasMode ~= mode then
                            self:_emitModeChanged(cursor, self._wasMode, mode)
                        end
                    end)
                end, { excludeMainCursor = true, allowUndo = true })
            end
        end
        if not handled then
            if self._modeChangeCallbacks and self._wasMode ~= mode then
                cursorManager:action(function(ctx)
                    self:_emitModeChanged(ctx:mainCursor(), self._wasMode, mode)
                end, { excludeMainCursor = false })
            else
                cursorManager:update()
            end
        end
    end
    self._wasMode = mode
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
    self._wasMode = vim.fn.mode()
    self._keys = self._keys .. key
    self._typed = self._typed .. typed
end

return InputManager
