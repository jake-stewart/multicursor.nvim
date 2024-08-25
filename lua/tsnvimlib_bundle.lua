-------------------------------------------
-- THIS FILE WAS GENERATED AUTOMATICALLY --
-------------------------------------------
local console = {
    __createLog = function(hl) return function(...)
        vim.api.nvim_echo({{
            table.concat(vim.tbl_map(function(e)
                return type(e) == "string" and e or vim.inspect(e)
            end, {...}), " "),
            hl
        }}, true, {})
    end end
}
console.log = console.__createLog("Normal")
console.warn = console.__createLog("WarningMsg")
console.error = console.__createLog("ErrorMsg")

local function __MapSource(luaFile, tsFile, sourceMap)
    _G.__TSNVIM__SourceMap = _G.__TSNVIM__SourceMap or ({})
    _G.__TSNVIM__SourceMap[luaFile] = {tsFile, sourceMap}
end

return {
    console = console,
    __MapSource = __MapSource
}