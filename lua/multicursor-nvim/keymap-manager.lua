--- @class KeymapManager
--- @field private _keymaps? [string | string[], string, integer][]
local KeymapManager = {}

--- @alias KeymapSetCallback fun(mode: string | string[], lhs: string, rhs: string | function, opts?: vim.keymap.set.Opts)
--- @param callbacks fun(set: KeymapSetCallback)[]
function KeymapManager:apply(callbacks)
    if self._keymaps then
        return
    end
    self._keymaps = {}
    local set = function(mode, lhs, rhs, opts)
        opts = opts or {}
        opts.buffer = true
        table.insert(self._keymaps, { mode, lhs, vim.fn.bufnr() })
        vim.keymap.set(mode, lhs, rhs, opts)
    end
    for _, callback in ipairs(callbacks) do
        callback(set)
    end
end

function KeymapManager:restore()
    if not self._keymaps then
        return
    end
    for _, keymap in pairs(self._keymaps) do
        vim.keymap.del(keymap[1], keymap[2], { buffer = keymap[3] })
    end
    self._keymaps = nil
end

return KeymapManager
