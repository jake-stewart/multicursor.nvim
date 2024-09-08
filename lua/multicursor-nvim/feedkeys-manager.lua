--- @class FeedkeysManager
--- @field feedkeys function
--- @field private _fedKeys string
local FeedkeysManager = {}
FeedkeysManager.__index = FeedkeysManager

--- @return FeedkeysManager
local function newFeedkeysManager()
    --- @type FeedkeysManager
    local fields = {
        feedkeys = vim.api.nvim_feedkeys,
        _fedKeys = "",
    }
    return setmetatable(fields, FeedkeysManager)
end

function FeedkeysManager:setup()
    function vim.api.nvim_feedkeys(macro, mode, escape)
        if type(mode) == "string" then
            if string.find(mode, "t") then
                if string.find(mode, "i") then
                    self._fedKeys = macro .. self._fedKeys
                else
                    self._fedKeys = self._fedKeys .. macro
                end
            end
        end
        return self.feedkeys(macro, mode, escape)
    end

    local originalFeedkeys = vim.fn.feedkeys
    function vim.fn.feedkeys(macro, mode)
        if type(mode) == "string" then
            if string.find(mode, "t") then
                if string.find(mode, "i") then
                    self._fedKeys = macro .. self._fedKeys
                else
                    self._fedKeys = self._fedKeys .. macro
                end
            end
        end
        return originalFeedkeys(macro, mode)
    end
end

--- @param typed string
--- @return boolean
function FeedkeysManager:wasFedKeys(typed)
    if #self._fedKeys > 0 then
        local start, _end = string.find(self._fedKeys, typed, 1, true)
        if start == 1 and _end then
            self._fedKeys = string.sub(self._fedKeys, _end + 1, #self._fedKeys)
            return true
        else
            self._fedKeys = ""
        end
    end
    return false
end


return newFeedkeysManager()
