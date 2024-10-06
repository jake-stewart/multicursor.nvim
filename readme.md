# multicursor.nvim

Multiple cursors in Neovim which work how you expect.

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
        set("v", "<leader>a", mc.alignCursors)

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

### Selecting Cursors:
- You can add cursors above/below the current cursor with `<up>` and `<down>`.
- You can skip a line with `<leader><up>` or `<leader><down>`.
- You can match the word/selection under the cursor forwards or backwards with
  `<leader>n` and `<leader>N`.
- You can skip a match forwards or backwards using `<leader>s` and
  `<leader>S`.
- You can add and remove cursors using the mouse with `<c-leftmouse>`.

### Changing Cursors:
- You can rotate through cursors with `<left>` and `<right>`.
- You can delete the current cursor using `<leader>x`
- You can disable cursors with `<c-q>`, which means only the main cursor
  moves.
- You can also press `<leader><c-q>` to duplicate cursors, disabling the
  originals.
- When cursors are disabled, you can press `<c-q>` to add a cursor under the
  main cursor.
- You can press `<esc>` to enable cursors again.

### Using the Cursors:
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

### Finished:
- When you want to collapse your cursors back into one, press `<esc>`.

## Features Documentation
| name               | arguments          | return  | desc                                                                                                                                                                                             |
| ------------       | -----------------  | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| addCursor          | string             | void    | Add a cursor and move only the main cursor using motion.                                                                                                                                         |
| skipCursor         | string             | void    | Move only the main cursor using motion.                                                                                                                                                          |
| lineAddCursor      | -1 \| 1            | void    | Add a cursor above or below the the main cursor, skipping empty lines.                                                                                                                           |
| lineSkipCursor     | -1 \| 1            | void    | Move only the main cursor up or down a line, skipping empty lines.                                                                                                                               |
| matchAddCursor     | -1 \| 1            | void    | Add a new cursor by matching the current word/selection.                                                                                                                                         |
| matchSkipCursor    | -1 \| 1            | void    | Move only the main cursor by matching the current word/selection.                                                                                                                                |
| matchAllAddCursors |                    | void    | Add a cursor for every match of the word/selection under the cursor.                                                                                                                             |
| nextCursor         |                    | void    | Select the cursor after the main cursor.                                                                                                                                                         |
| prevCursor         |                    | void    | Select the cursor before the main cursor.                                                                                                                                                        |
| firstCursor        |                    | void    | Select the first cursor.                                                                                                                                                                         |
| lastCursor         |                    | void    | Select the last cursor.                                                                                                                                                                          |
| hasCursors         |                    | boolean | Returns whether multiple cursors exist.                                                                                                                                                          |
| deleteCursor       |                    | void    | Delete the main cursor.                                                                                                                                                                          |
| clearCursors       |                    | void    | Clear all cursors except main cursor.                                                                                                                                                            |
| handleMouse        |                    | void    | Use in a mouse mapping to handle mouse input.                                                                                                                                                    |
| alignCursors       |                    | void    | Align columns of cursors on multiple lines.                                                                                                                                                      |
| splitCursors       |                    | void    | Split visual selections with a regex separator. For example, visually selecting "a,b,c,d" and splitting with "," will create four cursors, one on each letter.                                   |
| matchCursors       |                    | void    | Match a pattern over a visual selection, creating a new cursor for each match. For example, visually selecting "foo bar foo" and matching with "foo" will create two cursors, one on each "foo". |
| transposeCursors   | -1 \| 1            | void    | Rotate the contents of each visual selection for each cursor. Call with `1` for clockwise rotation and `-1` for anti-clockwise.                                                                  |
| insertVisual       |                    | void    | Create a cursor for each line of the visual selection, and enter insert mode with `I`.                                                                                                           |
| appendVisual       |                    | void    | Create a cursor for each line of the visual selection, and enter insert mode with `A`.                                                                                                           |
| disableCursors     |                    | void    | Locks the cursors from moving. This is useful for repositioning main cursor for adding more cursors.                                                                                             |
| enableCursors      |                    | void    | Unlocks the cursors from moving.                                                                                                                                                                 |
| cursorsEnabled     |                    | boolean | Returns whether the cursors are locked from moving.                                                                                                                                              |
| feedkeys           | string, table?     | void    | Use instead of `vim.fn.feedkeys()` or `vim.api.nvim_feedkeys()` in multicursor mappings to avoid bugs. Opts are `{ remap?: boolean, keycodes?: boolean }`.                                       |
| action             | function           | void    | Perform a complex action using the Cursor API. See below for details.                                                                                                                            |

## Cursor API
All of the provided features are implemented using the Cursor API, which is
accessible for writing your own complex multi-cursor logic.

You can use the Cursor API by calling `mc.action` with a callback, like so:

```lua
mc.action(function(ctx)
    local cursors = ctx:getCursors()
end)
```

The `ctx` is a `CursorContext` which lets you query for cursors.
In the snippet, we simply called `getCursors()` to get a list of all our cursors.

In the next snippet, we will instead call `firstCursor()` to get only the
highest cursor in the document. Once we have our cursor, we can interact with it.

```lua
mc.action(function(ctx)
    local cursor = ctx:firstCursor()
    vim.print(cursor:getLine())
    cursor:feedkeys("ihello world")
end)
```

And that's it. You can view `lua/multicursor-nvim/examples.lua` to
see all the default features implemented using the Cursor API.
Or, you can read the prototypes below.

### Types

```lua
--- @alias CursorQuery {disabledCursors?: boolean, enabledCursors?: boolean}

--- 1-indexed line, 1-indexed col, offset
--- @alias Pos [integer, integer, integer]

--- 1-indexed line, 1-indexed col
--- @alias SimplePos [integer, integer]
```

### Cursor

```lua
--- Returns this cursors current line number, 1 indexed.
--- @return integer
function Cursor:line()

--- Returns this cursors current column number, 1 indexed.
--- @return integer
function Cursor:col()

--- Returns the full line text of where this cursor is located.
--- @return string
function Cursor:getLine()

--- Deletes this cursor.
--- If this is the main cursor then the closest cursor to it.
--- is set as the new main cursor.
--- If this is the last remaining cursor, a new cursor is created
--- at its position.
function Cursor:delete()

--- Returns the disabled cursor underneath this one, if it exists
--- @return Cursor | nil
function Cursor:overlappedCursor()

--- Sets this cursor as the main cursor.
--- @return self
function Cursor:select()

--- Returns whether this cursor is the main cursor.
--- @return boolean
function Cursor:isMainCursor()

--- A cursor can either be at the start or end of a visual selection.
--- For example, if you select lines 10-20, your cursor can either be
--- on line 10 (start) or 20 (end). this method returns true when at
--- the start.
--- @return boolean
function Cursor:atVisualStart()

--- For each line of the cursor's visual selection, a new cursor is
--- created, visually selecting only the single line.
--- This method deletes the original cursor.
--- @return Cursor[]
function Cursor:splitVisualLines()

--- @return Pos
function Cursor:getPos()

--- @param pos SimplePos | Pos
--- @return self
function Cursor:setPos(pos)

--- @param pos SimplePos | Pos
--- @return self
function Cursor:setVisualAnchor(pos)

--- @return Pos
function Cursor:getVisualAnchor()

--- @param pos SimplePos | Pos
function Cursor:setRedoChangePos(pos)

--- Returns a new cursor with the same position, registers,
--- visual selection, and mode as this cursor.
--- @return Cursor
function Cursor:clone()

--- Returns only the text contained in each line of the visual selection.
--- @return string[]
function Cursor:getVisualLines()

--- Returns the full line for each line of the visual selection.
--- @return string[]
function Cursor:getFullVisualLines()

--- Returns start and end positions of visual selection start position
--- is before or equal to end position.
--- @return Pos, Pos
function Cursor:getVisual()

--- Returns this cursor's current mode.
--- It should only ever be in normal, visual, or select modes.
--- @return string: "n" | "v" | "V" | <c-v> | "s" | "S" | <c-s>
function Cursor:mode()

--- Sets this cursor's mode.
--- It should only ever be in normal, visual, or select modes.
--- @param mode string: "n" | "v" | "V" | <c-v> | "s" | "S" | <c-s>
--- @return self
function Cursor:setMode(mode)

function Cursor:disable()

function Cursor:enable()

--- Makes the cursor perform a command/commands.
--- For example, cursor:feedkeys('dw') will delete a word.
--- By default, keys are not remapped and keycodes are not parsed.
--- @param keys string
--- @param opts? { remap?: boolean, keycodes?: boolean }
function Cursor:feedkeys(keys, opts)

--- Call callback with cursor
--- @param callback fun(cursor: Cursor)
function Cursor:perform(callback)

--- Return the <cword> for this cursor
--- @return string
function Cursor:getCursorWord(callback)

--- Set the search register of this cursor
--- @param search string
function Cursor:setSearch(search)

--- Sets the visual selection and sets the cursor position to `visualEnd`.
--- @param visualStart SimplePos | Pos
--- @param visualEnd SimplePos | Pos
--- @return self
function Cursor:setVisual(visualStart, visualEnd)

--- Returns true if cursor is in visual mode
--- @return boolean
function Cursor:inVisualMode()

--- Returns true if cursor is in select mode
--- @return boolean
function Cursor:inSelectMode()

--- Returns true if cursor is in visual or select mode
--- @return boolean
function Cursor:hasSelection()
```

### CursorContext

```lua
--- Enables or disables all cursors
--- @param value boolean
function CursorContext:setCursorsEnabled(value)

--- Returns a list of cursors, sorted by their position.
--- @param opts? CursorQuery
--- @return Cursor[]
function CursorContext:getCursors(opts)

--- Clones and returns the main cursor
--- @return Cursor
function CursorContext:addCursor()

--- Util which executes callback for each cursor, sorted by their position.
--- @param callback fun(cursor: Cursor, i: integer, t: Cursor[])
--- @param opts? CursorQuery
function CursorContext:forEachCursor(callback, opts)

--- Util method which maps each cursor to a value.
--- @generic T
--- @param callback fun(cursor: Cursor, i: integer, t: Cursor[]): T
--- @param opts? CursorQuery
--- @return T[]
function CursorContext:mapCursors(callback, opts)

--- Util method which returns the last cursor matching the predicate.
--- @param predicate fun(cursor: Cursor, i: integer, t: Cursor[]): any
--- @param opts? CursorQuery
--- @return Cursor | nil
function CursorContext:findLastCursor(predicate, opts)

--- Util method which returns the first cursor matching the predicate.
--- @param predicate fun(cursor: Cursor, i: integer, t: Cursor[]): any
--- @param opts? CursorQuery
--- @return Cursor | nil
function CursorContext:findCursor(predicate, opts)

--- Returns the closest cursor which appears AFTER pos.
--- A cursor exactly at pos will not be returned.
--- It does not wrap, so if none are found, then nil is returned.
--- If you wish to wrap, use `ctx:nextCursor(...) or ctx:firstCursor(...)`.
--- @param pos SimplePos | Pos
--- @param opts? CursorQuery
--- @return Cursor | nil
function CursorContext:nextCursor(pos, opts)

--- Returns the closest cursor which appears BEFORE pos.
--- A cursor exactly at pos will not be returned.
--- It does not wrap, so if none are found, then nil is returned.
--- If you wish to wrap, use `ctx:prevCursor(...) or ctx:lastCursor(...)`.
--- @param pos SimplePos | Pos
--- @param opts? CursorQuery
--- @return Cursor | nil
function CursorContext:prevCursor(pos, opts)

--- Returns the nearest cursor to pos, and accepts a cursor exactly at pos.
--- @param pos SimplePos | Pos
--- @param opts? CursorQuery
--- @return Cursor | nil
function CursorContext:nearestCursor(pos, opts)

--- @param pos SimplePos | Pos
--- @param opts? CursorQuery
--- @return Cursor | nil
function CursorContext:getCursorAtPos(pos, opts)

--- Returns the cursor under the main cursor
--- @return Cursor | nil
function CursorContext:overlappedCursor()

--- Returns the main cursor.
--- @return Cursor
function CursorContext:mainCursor()

--- Returns the cursor closest to the start of the document.
--- @param opts? CursorQuery
--- @return Cursor | nil
function CursorContext:firstCursor(opts)

--- Returns the cursor closest to the end of the document.
--- @param opts? CursorQuery
--- @return Cursor | nil
function CursorContext:lastCursor(opts)

--- Returns whether all cursors are enabled
--- @return boolean
function CursorContext:cursorsEnabled()

function CursorContext:hasCursors()

function CursorContext:clear()
```

