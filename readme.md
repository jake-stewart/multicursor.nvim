# multicursor.nvim

Multiple cursors in Neovim which work how you expect.
Now with help pages! `:h multicursor`.

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
        set({"n", "x"}, "<up>", function() mc.lineAddCursor(-1) end)
        set({"n", "x"}, "<down>", function() mc.lineAddCursor(1) end)
        set({"n", "x"}, "<leader><up>", function() mc.lineSkipCursor(-1) end)
        set({"n", "x"}, "<leader><down>", function() mc.lineSkipCursor(1) end)

        -- Add or skip adding a new cursor by matching word/selection
        set({"n", "x"}, "<leader>n", function() mc.matchAddCursor(1) end)
        set({"n", "x"}, "<leader>s", function() mc.matchSkipCursor(1) end)
        set({"n", "x"}, "<leader>N", function() mc.matchAddCursor(-1) end)
        set({"n", "x"}, "<leader>S", function() mc.matchSkipCursor(-1) end)

        -- Add and remove cursors with control + left click.
        set("n", "<c-leftmouse>", mc.handleMouse)
        set("n", "<c-leftdrag>", mc.handleMouseDrag)
        set("n", "<c-leftrelease>", mc.handleMouseRelease)

        -- Disable and enable cursors.
        set({"n", "x"}, "<c-q>", mc.toggleCursor)

        -- Mappings defined in a keymap layer only apply when there are
        -- multiple cursors. This lets you have overlapping mappings.
        mc.addKeymapLayer(function(layerSet)

            -- Select a different cursor as the main one.
            layerSet({"n", "x"}, "<left>", mc.prevCursor)
            layerSet({"n", "x"}, "<right>", mc.nextCursor)

            -- Delete the main cursor.
            layerSet({"n", "x"}, "<leader>x", mc.deleteCursor)

            -- Enable and clear cursors using escape.
            layerSet("n", "<esc>", function()
                if not mc.cursorsEnabled() then
                    mc.enableCursors()
                else
                    mc.clearCursors()
                end
            end)
        end)

        -- Customize how cursors look.
        local hl = vim.api.nvim_set_hl
        hl(0, "MultiCursorCursor", { reverse = true })
        hl(0, "MultiCursorVisual", { link = "Visual" })
        hl(0, "MultiCursorSign", { link = "SignColumn"})
        hl(0, "MultiCursorMatchPreview", { link = "Search" })
        hl(0, "MultiCursorDisabledCursor", { reverse = true })
        hl(0, "MultiCursorDisabledVisual", { link = "Visual" })
        hl(0, "MultiCursorDisabledSign", { link = "SignColumn"})
    end
}
```

## How to Use
This section explains the basic usage of multicursor.nvim with
the default config.

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
- When cursors are disabled, you can press `<c-q>` to add a cursor under the
  main cursor.
- You can press `<esc>` to enable the cursors again.

#### Using the Cursors:
- Once you have your cursors, you use vim normally as you would with a single
  cursor.
- When you want to collapse your cursors back into one, press `<esc>`.

## Advanced Actions
The example config only has a few actions to keep it easy to understand.
Below are a lot of powerful multicursor actions for quick reference, so
you can pick which you find useful.

```lua
-- Pressing `gaip` will add a cursor on each line of a paragraph.
-- Can also be used to add cursor for each line of visual selection.
set({"n", "x"}, "ga", mc.addCursorOperator)

-- Clone every cursor and disable the originals.
set({"n", "x"}, "<leader><c-q>", mc.duplicateCursors)

-- Align cursor columns.
set("n", "<leader>a", mc.alignCursors)

-- Split visual selections by regex.
set("x", "S", mc.splitCursors)

-- match new cursors within visual selections by regex.
set("x", "M", mc.matchCursors)

-- bring back cursors if you accidentally clear them
set("n", "<leader>gv", mc.restoreCursors)

-- Add a cursor for all matches of cursor word/selection in the document.
set({"n", "x"}, "<leader>A", mc.matchAllAddCursors)

-- Rotate the text contained in each visual selection between cursors.
set("x", "<leader>t", function() mc.transposeCursors(1) end)
set("x", "<leader>T", function() mc.transposeCursors(-1) end)

-- Append/insert for each line of visual selections.
-- Similar to block selection insertion.
set("x", "I", mc.insertVisual)
set("x", "A", mc.appendVisual)

-- Increment/decrement sequences, treating all cursors as one sequence.
set({"n", "x"}, "g<c-a>", mc.sequenceIncrement)
set({"n", "x"}, "g<c-x>", mc.sequenceDecrement)

-- Add a cursor and jump to the next/previous search result.
set("n", "<leader>/n", function() mc.searchAddCursor(1) end)
set("n", "<leader>/N", function() mc.searchAddCursor(-1) end)

-- Jump to the next/previous search result without adding a cursor.
set("n", "<leader>/s", function() mc.searchSkipCursor(1) end)
set("n", "<leader>/S", function() mc.searchSkipCursor(-1) end)

-- Add a cursor to every search result in the buffer.
set("n", "<leader>/A", mc.searchAllAddCursors)

-- Pressing `<leader>miwap` will create a cursor in every match of the
-- string captured by `iw` inside range `ap`.
-- This action is highly customizable, see `:h multicursor-operator`.
set({"n", "x"}, "<leader>m", mc.operator)

-- Add or skip adding a new cursor by matching diagnostics.
set({"n", "x"}, "]d", function() mc.diagnosticAddCursor(1) end)
set({"n", "x"}, "[d", function() mc.diagnosticAddCursor(-1) end)
set({"n", "x"}, "]s", function() mc.diagnosticSkipCursor(1) end)
set({"n", "x"}, "[S", function() mc.diagnosticSkipCursor(-1) end)

-- Press `mdip` to add a cursor for every error diagnostic in the range `ip`.
set({"n", "x"}, "md", function()
    -- See `:h vim.diagnostic.GetOpts`.
    mc.diagnosticMatchCursors({ severity = vim.diagnostic.severity.ERROR })
end)
```

## Cursor API
All of the provided actions are implemented using the Cursor API, which is
accessible for writing your own complex multi-cursor logic. You can view
the docs at `:h multicursor-api`.
