local tbl = require("multicursor-nvim.tbl")
local util = require("multicursor-nvim.util")
local TERM_CODES = require("multicursor-nvim.term-codes")
local feedkeysManager = require("multicursor-nvim.feedkeys-manager")
local cursorManager = require("multicursor-nvim.cursor-manager")

--- @class SnippetManager
--- @field private _snippet table
--- @field private _hasSnippet boolean
--- @field private _snippetText string
--- @field private _snippetLine string
--- @field private _snippetCol integer
local SnippetManager = {}

function SnippetManager:setup()
    self._snippet = vim.snippet
    vim.snippet = tbl.shallow_copy(self._snippet)
    function vim.snippet.expand(snippetText, ...)
        if cursorManager:hasCursors() then
            self._hasSnippet = true
            self._snippetText = snippetText
            self._snippetLine = vim.fn.getline(".")
            self._snippetCol = vim.fn.col(".")
            feedkeysManager.nvim_feedkeys(TERM_CODES.ESC, "nt", false)
        else
            self._snippet.expand(snippetText, ...)
        end
    end
end

function SnippetManager:hasSnippet()
    return self._hasSnippet
end

--- @param wasFromSelectMode boolean
--- @param typed? string
--- @param insertModePos? boolean
function SnippetManager:performSnippet(wasFromSelectMode, typed, insertModePos)
    self._hasSnippet = false
    cursorManager:dirty()
    local reg = vim.fn.getreg(".")
    reg = util.removeStartFromEnd(reg, self._snippetText)

    -- can't seem leave insert mode after using feedkeys mode "x!"
    -- which is required since we must stay in insert mode so that
    -- snippet.expand() has the correct position/state.
    -- as a hacky workaround, we will map it to ascii bell (which
    -- nobody should be using), and call it from insert mode.
    vim.keymap.set("i", "\7", function()
        self._snippet.expand(self._snippetText)
    end)

    cursorManager:action(function(ctx)
        local mainCursor = ctx:mainCursor()
        local col = mainCursor:col()
        mainCursor:perform(function()
            local atStartCol = self._snippetCol <= 1
            if col + 1 < self._snippetCol then
                local text = string.sub(self._snippetLine, col, self._snippetCol)
                if #text > 0 then
                    atStartCol = false
                    feedkeysManager.nvim_feedkeys("a" .. text .. TERM_CODES.ESC, "n", false)
                end
            end
            feedkeysManager.nvim_feedkeys(atStartCol and "i" or "a", "n", false)
            feedkeysManager.nvim_feedkeys("\7", "", false)
            feedkeysManager.nvim_feedkeys(TERM_CODES.ESC, "nx", false)
        end)
        if insertModePos then
            mainCursor:setRedoChangePos({
                insertModePos[2],
                insertModePos[3],
            })
            mainCursor:setUndoChangePos({
                insertModePos[2],
                insertModePos[3],
            })
        end

        ctx:forEachCursor(function(cursor)
            cursor:perform(function()
                if wasFromSelectMode then
                    feedkeysManager.nvim_feedkeys(
                        TERM_CODES.CTRL_G .. "c", "n", false)
                else
                    if #typed then
                        feedkeysManager.nvim_feedkeys(typed, "", false)
                    end
                end
                if #reg > 0 then
                    feedkeysManager.nvim_feedkeys(reg, "n", false)
                end
                feedkeysManager.nvim_feedkeys("\7", "", false)
                feedkeysManager.nvim_feedkeys(TERM_CODES.ESC, "nx", false)
            end)
        end)
    end, { excludeMainCursor = true, fixWindow = false })
    vim.keymap.del("i", "\7")
    self._snippet.stop()
    if vim.fn.mode() == "n" then
        feedkeysManager.nvim_feedkeys("a", "tn", false)
    end
end

return SnippetManager
