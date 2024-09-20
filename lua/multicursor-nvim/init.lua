local core = require("multicursor-nvim.core")
local examples = require("multicursor-nvim.examples")

table.unpack = table.unpack or unpack

vim.api.nvim_set_hl(0, "MultiCursorCursor", { link = "Cursor" })
vim.api.nvim_set_hl(0, "MultiCursorVisual", { link = "Visual" })
vim.api.nvim_set_hl(0, "MultiCursorDisabledCursor", { link = "Visual" })
vim.api.nvim_set_hl(0, "MultiCursorDisabledVisual", { link = "Visual" })

return {
    setup = core.setup,
    action = core.action,
    feedkeys = core.feedkeys,
    hasCursors = core.hasCursors,
    cursorsEnabled = core.cursorsEnabled,
    splitCursors = examples.splitCursors,
    alignCursors = examples.alignCursors,
    matchCursors = examples.matchCursors,
    transposeCursors = examples.transposeCursors,
    addCursor = examples.addCursor,
    skipCursor = examples.skipCursor,
    handleMouse = examples.handleMouse,
    clearCursors = examples.clearCursors,
    disableCursors = examples.disableCursors,
    enableCursors = examples.enableCursors,
    visualToCursors = examples.visualToCursors,
    insertVisual = examples.insertVisual,
    appendVisual = examples.appendVisual,
    firstCursor = examples.firstCursor,
    lastCursor = examples.lastCursor,
    nextCursor = examples.nextCursor,
    prevCursor = examples.prevCursor,
    deleteCursor = examples.deleteCursor
}
