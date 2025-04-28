--- @class mc.KeymapManager
--- @field private _keymaps table<number, table>
local KeymapManager = {
    _keymaps = {}
}

--- @alias mc.KeymapSetterFunc fun(
---     mode: string | string[],
---     lhs: string,
---     rhs: string | function,
---     opts?: vim.keymap.set.Opts)

--- @param bufnr number
--- @param callbacks fun(set: mc.KeymapSetterFunc)[]
function KeymapManager:apply(bufnr, callbacks)
    if self._keymaps[bufnr] then
        return
    end
    self._keymaps[bufnr] = {}
    local set = function(mode, lhs, rhs, opts)
        opts = opts or {}
        opts.buffer = bufnr
        table.insert(self._keymaps[bufnr], { mode, lhs })
        vim.keymap.set(mode, lhs, rhs, opts)
    end
    for _, callback in ipairs(callbacks) do
        callback(set)
    end
end

function KeymapManager:restore()
    for bufnr, keymaps in pairs(self._keymaps) do
        for _, keymap in pairs(keymaps) do
            pcall(vim.keymap.del, keymap[1], keymap[2], { buffer = bufnr })
        end
    end
    for bufnr in pairs(self._keymaps) do
        self._keymaps[bufnr] = nil
    end
end

return KeymapManager
