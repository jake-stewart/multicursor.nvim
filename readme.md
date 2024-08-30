# multicursor.nvim

multiple cursors in neovim which work how you expect.

https://github.com/user-attachments/assets/3b3554e0-3d62-47a0-a4e1-a4fd16a0ed02

### features

- visual, select, normal, insert, and replace modes
- undo/redo
- cursor specific registers for searching and yanking
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
        vim.keymap.set({"n", "v"}, "<up>", function() mc.addCursor("k") end)
        vim.keymap.set({"n", "v"}, "<down>", function() mc.addCursor("j") end)

        -- add a cursor and jump to the next word under cursor
        vim.keymap.set({"n", "v"}, "<c-n>", function() mc.addCursor("*") end)

        -- jump to the next word under cursor but do not add a cursor
        vim.keymap.set({"n", "v"}, "<c-s>", function() mc.skipCursor("*") end)

        -- rotate the main cursor
        vim.keymap.set({"n", "v"}, "<left>", mc.nextCursor)
        vim.keymap.set({"n", "v"}, "<right>", mc.prevCursor)

        -- delete the main cursor
        vim.keymap.set({"n", "v"}, "<leader>x", mc.deleteCursor)

        -- add and remove cursors with control + left click
        vim.keymap.set("n", "<c-leftmouse>", mc.handleMouse)
    end,
}
```

### how to use

using the default config, you can add cursors above/below with `<up>` and `<down>`.
you can match the word under the cursor with `<c-n>` or `<c-s>` to skip.
you can also use the mouse with `<c-leftmouse>`.

once you have your cursors, you use vim normally as you would with a single cursor.

when you want to collapse your cursors back into one, press `<esc>`.


### api
| name         | arguments          | return  | desc                                                    |
| ------------ | -----------------  | ------- | ------------------------------------------------------- |
| addCursor    | string \| function | void    | add a cursor and move only the main cursor using motion |
| skipCursor   | string \| function | void    | move only the main cursor using motion                  |
| nextCursor   |                    | void    | select the cursor after the main cursor                 |
| prevCursor   |                    | void    | select the cursor before the main cursor                |
| firstCursor  |                    | void    | select the first cursor                                 |
| lastCursor   |                    | void    | select the last cursor                                  |
| hasCursors   |                    | boolean | returns whether multiple cursors exist                  |
| deleteCursor |                    | void    | delete the main cursor                                  |
| clearCursors |                    | void    | clear all cursors except main cursor                    |
| handleMouse  |                    | void    | use in a mouse mapping to handle mouse input            |


### tips

you may find it useful to select the first cursor before clearing cursors.
this makes multiple cursors behave similar to visual mode when performing
operations where it jumps to the first line of your selection.

```lua
vim.keymap.set("n", "<esc>", function()
    if mc.hasCursors() then
        mc.firstCursor()
        mc.clearCursors()
    end
end)
```
