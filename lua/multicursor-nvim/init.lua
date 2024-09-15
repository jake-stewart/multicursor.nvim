local core = require("multicursor-nvim.core")
local examples = require("multicursor-nvim.examples")

vim.cmd.hi("link", "MultiCursorCursor", "Cursor")
vim.cmd.hi("link", "MultiCursorVisual", "Visual")
vim.cmd.hi("link", "MultiCursorDisabledCursor", "Visual")
vim.cmd.hi("link", "MultiCursorDisabledVisual", "Visual")

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
