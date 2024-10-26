# multicursor.nvim

Multiple cursors in Neovim which work how you expect. Now with help pages! `:h multicursor`.

https://github.com/user-attachments/assets/a8c136dc-4786-447b-95c0-8e2a48f5776f

## Features

- Visual and select modes with char/line/block selections
- Normal, insert, replace modes
- Undo/redo
- Virtualedit
- Autocompletion
- Snippet expansion (use `vim.snippet.expand`)
- Cursor specific registers for searching and yanking
- Match & split cursor selections with regex
- Transpose cursor selections
- Align cursor columns
- Easily extended with the Cursor API
- Works with most plugins and remaps

## Example Config (lazy.nvim)

```lua
{
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    config = function()
        local mc = require("multicursor-nvim")

        mc.setup()

        local set = vim.keymap.set

        -- Add or skip cursor above/below the main cursor.
        set({"n", "v"}, "<up>",
            function() mc.lineAddCursor(-1) end)
        set({"n", "v"}, "<down>",
            function() mc.lineAddCursor(1) end)
        set({"n", "v"}, "<leader><up>",
            function() mc.lineSkipCursor(-1) end)
        set({"n", "v"}, "<leader><down>",
            function() mc.lineSkipCursor(1) end)

        -- Add or skip adding a new cursor by matching word/selection
        set({"n", "v"}, "<leader>n",
            function() mc.matchAddCursor(1) end)
        set({"n", "v"}, "<leader>s",
            function() mc.matchSkipCursor(1) end)
        set({"n", "v"}, "<leader>N",
            function() mc.matchAddCursor(-1) end)
        set({"n", "v"}, "<leader>S",
            function() mc.matchSkipCursor(-1) end)

        -- Add all matches in the document
        set({"n", "v"}, "<leader>A", mc.matchAllAddCursors)

        -- You can also add cursors with any motion you prefer:
        -- set("n", "<right>", function()
        --     mc.addCursor("w")
        -- end)
        -- set("n", "<leader><right>", function()
        --     mc.skipCursor("w")
        -- end)

        -- Rotate the main cursor.
        set({"n", "v"}, "<left>", mc.nextCursor)
        set({"n", "v"}, "<right>", mc.prevCursor)

        -- Delete the main cursor.
        set({"n", "v"}, "<leader>x", mc.deleteCursor)

        -- Add and remove cursors with control + left click.
        set("n", "<c-leftmouse>", mc.handleMouse)

        -- Easy way to add and remove cursors using the main cursor.
        set({"n", "v"}, "<c-q>", mc.toggleCursor)

        -- Clone every cursor and disable the originals.
        set({"n", "v"}, "<leader><c-q>", mc.duplicateCursors)

        set("n", "<esc>", function()
            if not mc.cursorsEnabled() then
                mc.enableCursors()
            elseif mc.hasCursors() then
                mc.clearCursors()
            else
                -- Default <esc> handler.
            end
        end)

        -- bring back cursors if you accidentally clear them
        set("n", "<leader>gv", mc.restoreCursors)

        -- Align cursor columns.
        set("n", "<leader>a", mc.alignCursors)

        -- Split visual selections by regex.
        set("v", "S", mc.splitCursors)

        -- Append/insert for each line of visual selections.
        set("v", "I", mc.insertVisual)
        set("v", "A", mc.appendVisual)

        -- match new cursors within visual selections by regex.
        set("v", "M", mc.matchCursors)

        -- Rotate visual selection contents.
        set("v", "<leader>t",
            function() mc.transposeCursors(1) end)
        set("v", "<leader>T",
            function() mc.transposeCursors(-1) end)

        -- Jumplist support
        set({"v", "n"}, "<c-i>", mc.jumpForward)
        set({"v", "n"}, "<c-o>", mc.jumpBackward)

        -- Customize how cursors look.
        local hl = vim.api.nvim_set_hl
        hl(0, "MultiCursorCursor", { link = "Cursor" })
        hl(0, "MultiCursorVisual", { link = "Visual" })
        hl(0, "MultiCursorSign", { link = "SignColumn"})
        hl(0, "MultiCursorDisabledCursor", { link = "Visual" })
        hl(0, "MultiCursorDisabledVisual", { link = "Visual" })
        hl(0, "MultiCursorDisabledSign", { link = "SignColumn"})
    end
}
```

## How to Use
This section explains the basic usage of multicursor.nvim with the default config.

#### Selecting Cursors:
- You can add cursors above/below the current cursor with `<up>` and `<down>`.
- You can skip a line with `<leader><up>` or `<leader><down>`.
- You can match the word/selection under the cursor forwards or backwards with
  `<leader>n` and `<leader>N`.
- You can skip a match forwards or backwards using `<leader>s` and
  `<leader>S`.
- You can add and remove cursors using the mouse with `<c-leftmouse>`.

#### Changing Cursors:
- You can rotate through cursors with `<left>` and `<right>`.
- You can delete the current cursor using `<leader>x`
- You can disable cursors with `<c-q>`, which means only the main cursor
  moves.
- You can also press `<leader><c-q>` to duplicate cursors, disabling the
  originals.
- When cursors are disabled, you can press `<c-q>` to add a cursor under the
  main cursor.
- You can press `<esc>` to enable cursors again.

#### Using the Cursors:
- Once you have your cursors, you use vim normally as you would with a single
  cursor.
- You can press `<leader>a` to align cursor columns.
- You can press `S` to split a visual selection by regex into multiple
  selections.
- You can press `M` to run a regex within your visual selection, creating
  a new cursor for each match.
- You can press `<leader>t` and `<leader>T` to transpose visual selections,
  which means the text within each visual selection will be rotated between
  cursors.

#### Finished:
- When you want to collapse your cursors back into one, press `<esc>`.

## Cursor API
All of the provided features are implemented using the Cursor API, which is
accessible for writing your own complex multi-cursor logic. You can view
the docs at `:h multicursor-api`.

