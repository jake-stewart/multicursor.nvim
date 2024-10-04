local core = require("multicursor-nvim.core")
local examples = require("multicursor-nvim.examples")

table.unpack = table.unpack or unpack

local function setDefaultHighlight(name, link)
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
end

setDefaultHighlight("MultiCursorCursor", "Cursor")
setDefaultHighlight("MultiCursorVisual", "Visual")
setDefaultHighlight("MultiCursorSign", "SignColumn")
setDefaultHighlight("MultiCursorDisabledCursor", "Visual")
setDefaultHighlight("MultiCursorDisabledVisual", "Visual")
setDefaultHighlight("MultiCursorDisabledSign", "SignColumn")

return {
    setup = core.setup,
    action = core.action,
    runOnce = core.runOnce,
    feedkeys = core.feedkeys,
    hasCursors = core.hasCursors,
    onModeChanged = core.onModeChanged,
    cursorsEnabled = core.cursorsEnabled,
    numCursors = core.numCursors,
    numEnabledCursors = core.numEnabledCursors,
    numDisabledCursors = core.numDisabledCursors,
    splitCursors = examples.splitCursors,
    alignCursors = examples.alignCursors,
    matchCursors = examples.matchCursors,
    transposeCursors = examples.transposeCursors,
    addCursor = examples.addCursor,
    skipCursor = examples.skipCursor,
    matchAddCursor = examples.matchAddCursor,
    matchSkipCursor = examples.matchSkipCursor,
    matchAllAddCursors = examples.matchAllAddCursors,
    lineAddCursor = examples.lineAddCursor,
    lineSkipCursor = examples.lineSkipCursor,
    handleMouse = examples.handleMouse,
    clearCursors = examples.clearCursors,
    restoreCursors = core.restoreCursors,
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
    deleteCursor = examples.deleteCursor
}
