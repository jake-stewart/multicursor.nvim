local core = require("multicursor-nvim.core")
local examples = require("multicursor-nvim.examples")

table.unpack = table.unpack or unpack

local function setDefaultHighlight(name, link)
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
end

setDefaultHighlight("MultiCursorCursor", "Cursor")
setDefaultHighlight("MultiCursorVisual", "Visual")
setDefaultHighlight("MultiCursorSign", "SignColumn")
setDefaultHighlight("MultiCursorMatchPreview", "Search")
setDefaultHighlight("MultiCursorDisabledCursor", "Visual")
setDefaultHighlight("MultiCursorDisabledVisual", "Visual")
setDefaultHighlight("MultiCursorDisabledSign", "SignColumn")

return {
    setup = core.setup,
    action = core.action,
    feedkeys = core.feedkeys,
    hasCursors = core.hasCursors,
    onModeChanged = core.onModeChanged,
    cursorsEnabled = core.cursorsEnabled,
    numCursors = core.numCursors,
    numEnabledCursors = core.numEnabledCursors,
    numDisabledCursors = core.numDisabledCursors,
    jumpForward = core.jumpForward,
    jumpBackward = core.jumpBackward,
    splitCursors = examples.splitCursors,
    alignCursors = examples.alignCursors,
    matchCursors = examples.matchCursors,
    transposeCursors = examples.transposeCursors,
    swapCursors = examples.swapCursors,
    addCursor = examples.addCursor,
    addCursorOperator = examples.addCursorOperator,
    skipCursor = examples.skipCursor,
    matchAddCursor = examples.matchAddCursor,
    matchSkipCursor = examples.matchSkipCursor,
    matchAllAddCursors = examples.matchAllAddCursors,
    lineAddCursor = examples.lineAddCursor,
    lineSkipCursor = examples.lineSkipCursor,
    handleMouse = examples.handleMouse,
    clearCursors = core.clearCursors,
    restoreCursors = examples.restoreCursors,
    disableCursors = examples.disableCursors,
    enableCursors = examples.enableCursors,
    toggleCursor = examples.toggleCursor,
    duplicateCursors = examples.duplicateCursors,
    visualToCursors = examples.visualToCursors,
    insertVisual = examples.insertVisual,
    appendVisual = examples.appendVisual,
    firstCursor = examples.firstCursor,
    lastCursor = examples.lastCursor,
    nextCursor = examples.nextCursor,
    prevCursor = examples.prevCursor,
    deleteCursor = examples.deleteCursor,
    operator = examples.operator
}
