local TERM_CODES = require("multicursor-nvim.term-codes")
local feedkeysManager = require("multicursor-nvim.feedkeys-manager")
local cursorManager = require("multicursor-nvim.cursor-manager")
local keymapManager = require("multicursor-nvim.keymap-manager")
local snippetManager = require("multicursor-nvim.snippet-manager")
local util = require("multicursor-nvim.util")
local tbl = require("multicursor-nvim.tbl")

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
--- @field private _applying boolean
--- @field private _typed string
--- @field private _keys string
--- @field private _wasMode string
--- @field private _fromSelectMode boolean
--- @field private _modeChangeCallbacks? function[]
--- @field private _keymapLayerCallbacks? mc.KeymapSetterFunc[]
local InputManager = {}

--- @param nsid number
function InputManager:setup(nsid)
    self._nsid = nsid
    self._applying = false
    self._keys = ""
    self._typed = ""
    self._wasMode = "n"
    self._fromSelectMode = false
    self._didUndo = false
    self._didRedo = false
    self._keymapLayerCallbacks = {}

    local originalGetChar = vim.fn.getchar

    --- @diagnostic disable-next-line: duplicate-set-field
    function vim.fn.getchar(...)
        if ({...})[1] == 1 and cursorManager:hasCursors() then
            return 0
        end
        return originalGetChar(...)
    end

    local originalUndo = vim.cmd.undo
    function vim.cmd.undo(...)
        local result = originalUndo(...)
        self._didUndo = true
        return result
    end

    local originalRedo = vim.cmd.redo
    function vim.cmd.redo(...)
        local result = originalRedo(...)
        self._didRedo = true
        return result
    end

    local cmdMetatable = getmetatable(vim.cmd)
    local originalCmd = cmdMetatable.__call
    function cmdMetatable.__call(...)
        local cmd = select(2, ...)
        if cmd == "undo" then
            self._didUndo = true
        elseif cmd == "redo" then
            self._didRedo = true
        end
        return originalCmd(...)
    end

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

--- @param callback fun(set: mc.KeymapSetterFunc)
function InputManager:addKeymapLayer(callback)
    table.insert(self._keymapLayerCallbacks, callback)
end

--- @param callback fun(set: mc.KeymapSetterFunc)
function InputManager:removeKeymapLayer(callback)
    self._keymapLayerCallbacks =
        tbl.filter(self._keymapLayerCallbacks, function(cb)
            return cb ~= callback
        end)
end

--- @param callback fun(cursor: mc.Cursor, from: string, to: string)
function InputManager:onModeChanged(callback)
    if not self._modeChangeCallbacks then
        self._modeChangeCallbacks = {}
    end
    self._modeChangeCallbacks[#self._modeChangeCallbacks + 1] = callback
end

--- @class mc.SafeStateInfo
--- @field wasMode string

--- @param callback fun(info: mc.SafeStateInfo)
--- @param opts? { once?: boolean }
function InputManager:onSafeState(callback, opts)
    if not self._safeStateCallbacks then
        self._safeStateCallbacks = {}
    end
    if opts and opts.once then
        local wrapped = callback
        callback = function(info)
            wrapped(info)
            tbl.remove(self._safeStateCallbacks, callback)
        end
    end
    self._safeStateCallbacks[#self._safeStateCallbacks + 1] = callback
end

--- Call given callback, handling internal state
--- @param callback fun()
function InputManager:performAction(callback)
    if not self._applying then
        self:_disableTogglableAdapters()
        self._applying = true
        local success, err = pcall(callback)
        self._applying = false
        if not success then
            util.echoerr(err)
        end
    end
end

--- Reset internal state
function InputManager:clear()
    self._keys = ""
    self._typed = ""
end

local function isInsertOrReplaceMode(mode)
    return mode == "i" or mode == "R"
end

local function isSelectMode(mode)
    return mode == "s" or mode == "S" or mode == TERM_CODES.CTRL_S
end

--- @private
function InputManager:_emitModeChanged(cursor, fromMode, toMode)
    for _, callback in ipairs(self._modeChangeCallbacks) do
        callback(cursor, fromMode, toMode)
    end
end

function InputManager:_handleExitInsertMode(mode, wasFromSelectMode)
    cursorManager:dirty()
    if cursorManager:hasCursors() then
        local reg = vim.fn.getreg(".")
        cursorManager:action(function(ctx)
            if self._modeChangeCallbacks and self._wasMode ~= mode then
                local changePos = vim.fn.getpos("'[")
                self:_emitModeChanged(ctx:mainCursor(), self._wasMode, mode)
                ctx:mainCursor():setRedoChangePos(
                    {changePos[2], changePos[3]})
            end
            ctx:forEachCursor(function(cursor)
                cursor:perform(function()
                    if cursor:mode() == "n" then
                        feedkeysManager.nvim_feedkeys(".", "nx", false)
                    else
                        if not wasFromSelectMode then
                            feedkeysManager.nvim_feedkeys(self._typed, "", false)
                        end
                        feedkeysManager.nvim_feedkeys(reg, "nx", false)
                    end
                end)
                if self._modeChangeCallbacks and self._wasMode ~= mode then
                    self:_emitModeChanged(cursor, self._wasMode, mode)
                end
            end)
        end, { excludeMainCursor = true, allowUndo = false })
    else
        if self._modeChangeCallbacks and self._wasMode ~= mode then
            cursorManager:action(function(ctx)
                self:_emitModeChanged(ctx:mainCursor(), self._wasMode, mode)
            end, { excludeMainCursor = true, allowUndo = false })
        end
        cursorManager:update()
    end
end

function InputManager:_handleSnippet(wasFromSelectMode)
    snippetManager:performSnippet(
        wasFromSelectMode, self._typed, self._insertModeStartPos)
end

function InputManager:_handleSpecialKey(specialKey)
    cursorManager:dirty()
    if specialKey == "u" then
        cursorManager:loadUndoItem(-1)
    elseif specialKey == TERM_CODES.CTRL_R then
        cursorManager:loadUndoItem(1)
    elseif specialKey == "." then
        if cursorManager:hasCursors() then
            cursorManager:action(function(ctx)
                ctx:forEachCursor(function(cursor)
                    cursor:feedkeys(".")
                end)
            end, { excludeMainCursor = true, allowUndo = true })
        else
            cursorManager:update()
        end
    else
        cursorManager:update()
    end
end

local CLEARABLE_ADAPTERS = {
    ["flash.plugins.char"] = function(m)
        if m.state then
            m.state:hide()
        end
    end,
}

local TOGGLABLE_ADAPTERS = {
    ["snacks.scroll"] = {
        state = {},
        enabled = function(m)
            return m.enabled
        end,
        setEnabled = function(m, enabled)
            if enabled then
                m.enable()
            else
                m.disable()
            end
        end
    },
    ["hardtime"] = {
        state = {},
        enabled = function(m)
            return m.is_plugin_enabled
        end,
        setEnabled = function(m, enabled)
            if enabled then
                m.enable()
            else
                m.disable()
            end
        end,
    },
}

function InputManager:_disableTogglableAdapters()
    for k, v in pairs(TOGGLABLE_ADAPTERS) do
        if v.state.enabled == nil then
            v.state.enabled = false
            if package.loaded[k] then
                local msuccess, m = pcall(require, k)
                if msuccess then
                    local success, enabled = pcall(v.enabled, m)
                    v.state.enabled = success and (enabled or false)
                    if v.state.enabled then
                        v.setEnabled(m, false)
                    end
                end
            end
        end
    end
end

function InputManager:_enableTogglableAdapters()
    for k, v in pairs(TOGGLABLE_ADAPTERS) do
        if v.state.enabled then
            if package.loaded[k] then
                local msuccess, m = pcall(require, k)
                if msuccess then
                    v.setEnabled(m, true)
                end
            end
        end
        v.state.enabled = nil
    end
end

function InputManager:_handleKeys(mode)
    local handled = false
    if #self._typed > 0 and cursorManager:hasCursors() then
        cursorManager:dirty()
        handled = true
        local clearable_adapters = {}
        for k, f in pairs(CLEARABLE_ADAPTERS) do
            if package.loaded[k] then
                local success, m = pcall(require, k)
                if success then
                    clearable_adapters[#clearable_adapters + 1] = function()
                        pcall(f, m)
                    end
                end
            end
        end
        tbl.forEach(clearable_adapters, function(f) f() end)
        cursorManager:action(function(ctx)
            if self._modeChangeCallbacks and self._wasMode ~= mode then
                self:_emitModeChanged(ctx:mainCursor(), self._wasMode, mode)
            end
            ctx:forEachCursor(function(cursor)
                cursor:feedkeys(self._typed, { remap = true })
                if self._modeChangeCallbacks and self._wasMode ~= mode then
                    self:_emitModeChanged(cursor, self._wasMode, mode)
                end
                tbl.forEach(clearable_adapters, function(f) f() end)
            end)
        end, { excludeMainCursor = true, allowUndo = true })
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

function InputManager:_handleLeaveCommandlineMode()
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
end

--- @private
function InputManager:_onSafeState()
    if self._applying then
        return
    end
    if cursorManager:hasCursors() then
        keymapManager:apply(vim.fn.bufnr(), self._keymapLayerCallbacks)
        self:_disableTogglableAdapters()
    else
        keymapManager:restore()
        self:_enableTogglableAdapters()
    end
    local mode = vim.fn.mode()
    if isInsertOrReplaceMode(mode) then
        if not isInsertOrReplaceMode(self._wasMode) then
            self._insertModeStartPos = vim.fn.getpos(".")
            if self._fromSelectMode then
                self._insertModeStartPos[3] = math.max(
                    1, self._insertModeStartPos[3] - 1)
            end
        end
        self._wasMode = mode
        return
    end
    local wasFromSelectMode = self._fromSelectMode
    self._fromSelectMode = isSelectMode(mode)

    local cmdType = vim.fn.getcmdtype()
    if cmdType ~= "" then
        self._wasMode = mode
        self._cmdType = cmdType
        return
    end

    self._applying = true

    if self._cmdType == ":" then
        self:_handleLeaveCommandlineMode()
    elseif self._cmdType
        and string.sub(self._typed, #self._typed, #self._typed)
            == TERM_CODES.ESC
    then
        -- for some reason escape doesn't cancel search when feedkeys
    elseif self._didUndo then
        cursorManager:loadUndoItem(-1)
    elseif self._didRedo then
        cursorManager:loadUndoItem(1)
    elseif snippetManager:hasSnippet() then
        self:_handleSnippet(wasFromSelectMode)
    elseif isInsertOrReplaceMode(self._wasMode) then
        self:_handleExitInsertMode(mode, wasFromSelectMode)
    elseif vim.startswith(self._keys, "q") then
        -- ignore macro start/end recording keys
    else
        local command = string.match(self._keys, "%d*(.*)")
        if self._wasMode ~= "c" and
            (self._wasMode == "n"
                and SPECIAL_NORMAL_KEYS[command]
                or SPECIAL_KEYS[command])
        then
            self:_handleSpecialKey(command)
        else
            local commandChar = string.sub(command, 1, 1)
            if self._wasMode ~= "c" and
                (self._wasMode == "n"
                    and SPECIAL_NORMAL_KEYS[commandChar]
                    or SPECIAL_KEYS[commandChar]
                )
            then
                self:_handleSpecialKey(commandChar)
            else
                self:_handleKeys(mode)
            end
        end
        if #self._typed > 0 then
            local safeStateId = (self._safeStateId or 0) + 1
            self._safeStateId = safeStateId
            vim.schedule(function()
                if self._safeStateId == safeStateId then
                    cursorManager:onSafeState()
                end
            end)
        end
    end
    if self._safeStateCallbacks then
        local info = {
            wasMode = self._wasMode,
        }
        tbl.forEach(self._safeStateCallbacks, function(f) f(info) end)
    end
    self._didUndo = false
    self._didRedo = false
    self._wasMode = vim.fn.mode()
    self._fromSelectMode = isSelectMode(self._wasMode)
    self._cmdType = nil
    self._insertModeStartPos = nil
    self._keys = ""
    self._typed = ""
    self._applying = false
end

--- @private
function InputManager:_onKey(key, typed)
    typed = feedkeysManager:removeFedKeys(typed)
    if #typed == 0 then
        return
    end
    if self._applying or isInsertOrReplaceMode(self._wasMode) then
        return
    end
    self._keys = self._keys .. key
    self._typed = self._typed .. typed
end

return InputManager
