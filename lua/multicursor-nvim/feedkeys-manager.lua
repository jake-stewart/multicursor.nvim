--- @class FeedkeysManager
--- @field nvim_feedkeys function
--- @field private _fedKeys string
local FeedkeysManager = {}

function FeedkeysManager:setup()
    self.nvim_feedkeys = vim.api.nvim_feedkeys
    self._fedKeys = ""

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
        return self.nvim_feedkeys(macro, mode, escape)
    end

    -- self.nvim_input = vim.nvim_input
    -- function vim.nvim_input(keys)
    --     if type(keys) == "string" then
    --         self._fedKeys = self._fedKeys
    --             .. vim.api.replace_termcodes(keys, true, true, true)
    --     end
    --     self.nvim_input(keys)
    -- end

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

function FeedkeysManager:keepjumpsFeedkeys(keys, mode)
    keys = vim.fn.substitute(keys, "'", "'..\"'\"..'", "g")
    vim.cmd("keepjumps call feedkeys('" .. keys .. "', '" .. mode .. "')")
end

function FeedkeysManager:silentKeepjumpsFeedkeys(keys, mode)
    keys = vim.fn.substitute(keys, "'", "'..\"'\"..'", "g")
    vim.cmd("silent keepjumps call feedkeys('" .. keys .. "', '" .. mode .. "')")
end

function FeedkeysManager:noAutocommandsKeepjumpsFeedkeys(keys, mode)
    keys = vim.fn.substitute(keys, "'", "'..\"'\"..'", "g")
    vim.cmd("noautocmd keepjumps call feedkeys('" .. keys .. "', '" .. mode .. "')")
end

--- @param typed string
--- @return string
function FeedkeysManager:removeFedKeys(typed)
    if #self._fedKeys > 0 then
        local start, _end = string.find(self._fedKeys, typed, 1, true)
        if start == 1 and _end then
            self._fedKeys = string.sub(self._fedKeys, _end + 1, #self._fedKeys)
            return ""
        else
            start, _end = string.find(typed, self._fedKeys, 1, true)
            self._fedKeys = ""
            if start == 1 and _end then
                typed = string.sub(typed, _end + 1, #typed)
                return typed
            else
                self._fedKeys = ""
                return typed
            end
        end
    end
    return typed
end

return FeedkeysManager
