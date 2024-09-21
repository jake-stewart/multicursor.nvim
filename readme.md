# multicursor.nvim

Multiple cursors in Neovim which work how you expect.

https://github.com/user-attachments/assets/a8c136dc-4786-447b-95c0-8e2a48f5776f

## Features

- Visual and select modes with char/line/block selections.
- Normal, insert, replace modes.
- Undo/redo
- Virtualedit
- Cursor specific registers for searching and yanking.
- Match & split cursor selections with regex.
- Transpose cursor selections.
- Align cursor columns.
- Easily extended with the Cursor API.
- Works with most plugins and remaps.

## Example Config (lazy.nvim)

```lua
{
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    config = function()
        local mc = require("multicursor-nvim")

        mc.setup()

        -- Add cursors above/below the main cursor.
        vim.keymap.set({"n", "v"}, "<up>", function() mc.addCursor("k") end)
        vim.keymap.set({"n", "v"}, "<down>", function() mc.addCursor("j") end)

        -- Add a cursor and jump to the next word under cursor.
        vim.keymap.set({"n", "v"}, "<c-n>", function() mc.addCursor("*") end)

        -- Jump to the next word under cursor but do not add a cursor.
        vim.keymap.set({"n", "v"}, "<c-s>", function() mc.skipCursor("*") end)

        -- Rotate the main cursor.
        vim.keymap.set({"n", "v"}, "<left>", mc.nextCursor)
        vim.keymap.set({"n", "v"}, "<right>", mc.prevCursor)

        -- Delete the main cursor.
        vim.keymap.set({"n", "v"}, "<leader>x", mc.deleteCursor)

        -- Add and remove cursors with control + left click.
        vim.keymap.set("n", "<c-leftmouse>", mc.handleMouse)

        vim.keymap.set({"n", "v"}, "<c-q>", function()
            if mc.cursorsEnabled() then
                -- Stop other cursors from moving.
                -- This allows you to reposition the main cursor.
                mc.disableCursors()
            else
                mc.addCursor()
            end
        end)

        vim.keymap.set("n", "<esc>", function()
            if not mc.cursorsEnabled() then
                mc.enableCursors()
            elseif mc.hasCursors() then
                mc.clearCursors()
            else
                -- Default <esc> handler.
            end
        end)

        -- Align cursor columns.
        vim.keymap.set("n", "<leader>a", mc.alignCursors) 

        -- Split visual selections by regex.
        vim.keymap.set("v", "S", mc.splitCursors)

        -- Append/insert for each line of visual selections.
        vim.keymap.set("v", "I", mc.insertVisual)
        vim.keymap.set("v", "A", mc.appendVisual)

        -- match new cursors within visual selections by regex.
        vim.keymap.set("v", "M", mc.matchCursors)

        -- Rotate visual selection contents.
        vim.keymap.set("v", "<leader>t", function() mc.transposeCursors(1) end)
        vim.keymap.set("v", "<leader>T", function() mc.transposeCursors(-1) end)

        -- Customize how cursors look.
        vim.api.nvim_set_hl(0, "MultiCursorCursor", { link = "Cursor" })
        vim.api.nvim_set_hl(0, "MultiCursorVisual", { link = "Visual" })
        vim.api.nvim_set_hl(0, "MultiCursorDisabledCursor", { link = "Visual" })
        vim.api.nvim_set_hl(0, "MultiCursorDisabledVisual", { link = "Visual" })
    end,
}
```

## How to Use
This section explains the basic usage of multicursor.nvim with the default config.

#### Selecting Cursors
You can add cursors above/below the current cursor with `<up>` and `<down>`.
You can match the word under the cursor with `<c-n>` or `<c-s>` to skip.
You can also use the mouse with `<c-leftmouse>`.

#### Using the Cursors
Once you have your cursors, you use vim normally as you would
with a single cursor.

#### Finished
When you want to collapse your cursors back into one, press `<esc>`.

#### Getting More Advanced
Read the comments in the default config for each mapping and experiment
with them. You are free to remap or remove any bindings you like.
If you want to do something more complex, see the Cursor API section.

## Features Documentation
| name             | arguments          | return  | desc                                                                                                                                                                                             |
| ------------     | -----------------  | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| addCursor        | string             | void    | Add a cursor and move only the main cursor using motion.                                                                                                                                         |
| skipCursor       | string             | void    | Move only the main cursor using motion.                                                                                                                                                          |
| nextCursor       |                    | void    | Select the cursor after the main cursor.                                                                                                                                                         |
| prevCursor       |                    | void    | Select the cursor before the main cursor.                                                                                                                                                        |
| firstCursor      |                    | void    | Select the first cursor.                                                                                                                                                                         |
| lastCursor       |                    | void    | Select the last cursor.                                                                                                                                                                          |
| hasCursors       |                    | boolean | Returns whether multiple cursors exist.                                                                                                                                                          |
| deleteCursor     |                    | void    | Delete the main cursor.                                                                                                                                                                          |
| clearCursors     |                    | void    | Clear all cursors except main cursor.                                                                                                                                                            |
| handleMouse      |                    | void    | Use in a mouse mapping to handle mouse input.                                                                                                                                                    |
| alignCursors     |                    | void    | Align columns of cursors on multiple lines.                                                                                                                                                      |
| splitCursors     |                    | void    | Split visual selections with a regex separator. For example, visually selecting "a,b,c,d" and splitting with "," will create four cursors, one on each letter.                                   |
| matchCursors     |                    | void    | Match a pattern over a visual selection, creating a new cursor for each match. For example, visually selecting "foo bar foo" and matching with "foo" will create two cursors, one on each "foo". |
| transposeCursors | -1 \| 1            | void    | Rotate the contents of each visual selection for each cursor. Call with `1` for clockwise rotation and `-1` for anti-clockwise.                                                                  |
| insertVisual     |                    | void    | Create a cursor for each line of the visual selection, and enter insert mode with `I`.                                                                                                           |
| appendVisual     |                    | void    | Create a cursor for each line of the visual selection, and enter insert mode with `A`.                                                                                                           |
| disableCursors   |                    | void    | Locks the cursors from moving. This is useful for repositioning main cursor for adding more cursors.                                                                                             |
| enableCursors    |                    | void    | Unlocks the cursors from moving.                                                                                                                                                                 |
| cursorsEnabled   |                    | boolean | Returns whether the cursors are locked from moving.                                                                                                                                              |
| feedkeys         | string, table?     | void    | Use instead of `vim.fn.feedkeys()` or `vim.api.nvim_feedkeys()` in multicursor mappings to avoid bugs. Opts are `{ remap?: boolean, keycodes?: boolean }`.                                       |
| action           | function           | void    | Perform a complex action using the Cursor API. See below for details.                                                                                                                            |

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

--- Sets this cursor as the main cursor (the real one).
function Cursor:select()

--- Returns whether this cursor is the main cursor (the real one).
--- @return boolean | nil
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

--- @return [integer, integer], integer
function Cursor:getPos()

--- @param pos [integer, integer], integer
function Cursor:setPos(pos)

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
--- @return [integer, integer], [integer, integer]
function Cursor:getVisual()

--- Returns this cursor's current mode.
--- It should only ever be in normal, visual, or select modes.
--- @return string: "n" | "v" | "V" | <c-v> | "s" | "S" | <c-s>
function Cursor:mode()

--- Sets this cursor's mode.
--- It should only ever be in normal, visual, or select modes.
--- @param mode string: "n" | "v" | "V" | <c-v> | "s" | "S" | <c-s>
function Cursor:setMode(mode)

--- Makes the cursor perform a command/commands.
--- For example, cursor:feedkeys('dw') will delete a word.
--- By default, keys are not remapped and keycodes are not parsed.
--- @param keys string
--- @param opts? { remap?: boolean, keycodes?: boolean }
function Cursor:feedkeys(keys, opts)

--- Sets the visual selection and sets the cursor position to `visualEnd`.
--- @param visualStart [integer, integer]
--- @param visualEnd [integer, integer]
function Cursor:setVisual(visualStart, visualEnd)

--- Returns true if in visual or select mode.
--- @return boolean
function Cursor:inVisualMode()
```

### CursorContext
```lua
--- Returns a list of cursors, sorted by their position.
--- @return Cursor[]
function CursorContext:getCursors()

--- Clones and returns the main cursor
--- This is the same as doing ctx:mainCursor():clone()
--- @return Cursor
function CursorContext:addCursor()

--- Util which executes callback for each cursor, sorted by their position.
--- @param callback fun(cursor: Cursor, i: integer, t: Cursor[]): boolean | nil
function CursorContext:forEachCursor(callback)

--- Util method which maps each cursor to a value.
--- @generic T
--- @param callback fun(cursor: Cursor, i: integer, t: Cursor[]): T
--- @return T[]
function CursorContext:mapCursors(callback)

--- Util method which returns the first cursor matching the predicate.
--- @param predicate fun(cursor: Cursor, i: integer, t: Cursor[]): any
--- @return Cursor | nil
function CursorContext:findCursor(predicate)

--- @param pos [integer, integer]
--- @param offset? integer
--- @return Cursor | nil
function CursorContext:getCursorAtPos(pos, offset)

--- When cursors are disabled, only the main cursor can be interacted with.
--- @return boolean
function CursorContext:cursorsEnabled()

--- When cursors are disabled, only the main cursor can be interacted with.
--- @param value boolean
function CursorContext:setCursorsEnabled(value)

--- Returns the closest cursor which appears AFTER pos.
--- A cursor exactly at pos will not be returned.
--- It does not wrap, so if none are found, then nil is returned.
--- If you wish to wrap, use `ctx:nextCursor(...) or ctx:firstCursor(...)`.
--- @param pos [integer, integer]
--- @param offset? integer
--- @return Cursor | nil
function CursorContext:nextCursor(pos, offset)

--- Returns the closest cursor which appears BEFORE pos.
--- A cursor exactly at pos will not be returned.
--- It does not wrap, so if none are found, then nil is returned.
--- If you wish to wrap, use `ctx:prevCursor(...) or ctx:lastCursor(...)`.
--- @param pos [integer, integer]
--- @param offset? integer
--- @return Cursor | nil
function CursorContext:prevCursor(pos, offset)

--- Returns the nearest cursor to pos, and accepts a cursor exactly at pos.
--- It is guarenteed to find a cursor.
--- @param pos [integer, integer]
--- @param offset? integer
--- @return Cursor
function CursorContext:nearestCursor(pos, offset)

--- Returns the main cursor (the real one).
--- @return Cursor
function CursorContext:mainCursor()

--- Returns the cursor closest to the start of the document.
--- Guarenteed to find a cursor.
--- @return Cursor
function CursorContext:firstCursor()

--- Returns the cursor closest to the end of the document.
--- Guarenteed to find a cursor.
--- @return Cursor
function CursorContext:lastCursor()

--- Returns the cursor under the main cursor
--- @return Cursor | nil
function CursorContext:overlappedCursor()

--- @return boolean
function CursorContext:hasCursors()

function CursorContext:clear()
```

