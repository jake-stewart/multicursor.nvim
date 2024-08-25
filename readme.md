# multicursor.nvim

multiple cursors in neovim which work how you expect.

https://github.com/user-attachments/assets/3b3554e0-3d62-47a0-a4e1-a4fd16a0ed02

### features

- visual modes (char, block, line)
- replace & insert modes
- undo/redo
- cursor specific unnamed register
- should work with most plugins and remaps

### example config (lazy.nvim)

```lua
{
    "jake-stewart/multicursor.nvim",
    config = function()
        local mc = require("multicursor-nvim")

        mc.setup()

        -- use MultiCursorCursor and MultiCursorVisual to customize
        -- additional cursors appearance
        vim.cmd.hi("link", "MultiCursorCursor", "Cursor")
        vim.cmd.hi("link", "MultiCursorVisual", "Visual")

        vim.keymap.set("n", "<esc>", function()
            if mc.hasCursors() then
                mc.clearCursors()
            else
                -- default <esc> handler
            end
        end)

        -- add cursors above/below the main cursor
        vim.keymap.set("n", "<up>", function() mc.addCursor("k") end)
        vim.keymap.set("n", "<down>", function() mc.addCursor("j") end)

        -- add a cursor and jump to the next word under cursor
        vim.keymap.set("n", "<c-n>", function() mc.addCursor("*") end)

        -- jump to the next word under cursor but do not add a cursor
        vim.keymap.set("n", "<c-s>", function() mc.skipCursor("*") end)

        -- add and remove cursors with control + left click
        vim.keymap.set("n", "<c-leftmouse>", mc.handleMouse)
    end,
}
```

### how to use

using the default config, you can add cursors above/below with `<up>` and `<down>`.
you can match the word under the word with `<c-n>` or `<c-s>` to skip.
you can also use the mouse with `<c-leftmouse>`.

once you have your cursors, you use vim normally as you would with a single cursor.

when you want to collapse your cursors back into one, press `<esc>`.
