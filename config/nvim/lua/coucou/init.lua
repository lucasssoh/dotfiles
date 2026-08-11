-- ============================================================
-- COUCOU / INIT.LUA
-- Builds every highlight group from lua/coucou/palette.lua.
-- Entry point is colors/coucou.lua, which calls M.load().
-- ============================================================
local M = {}

local function hl(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
end

-- ============================================================
-- Core editor UI + legacy syntax + treesitter captures
-- ============================================================
function M.set_editor_groups(p)
    -- Base UI
    hl("Normal",       { fg = p.text, bg = p.bg })
    hl("NormalNC",      { fg = p.text, bg = p.bg })
    hl("NormalFloat",  { fg = p.text, bg = p.surface })
    hl("FloatBorder",  { fg = p.border, bg = p.surface })
    hl("FloatTitle",   { fg = p.cyan, bg = p.surface, bold = true })
    hl("CursorLine",   { bg = p.surface })
    hl("CursorLineNr", { fg = p.cyan, bold = true })
    hl("LineNr",       { fg = p.muted })
    hl("Visual",       { bg = p.overlay })
    hl("Search",       { fg = p.bg, bg = p.yellow })
    hl("IncSearch",    { fg = p.bg, bg = p.cyan })
    hl("CurSearch",    { fg = p.bg, bg = p.cyan, bold = true })
    hl("MatchParen",   { fg = p.cyan, bold = true, underline = true })
    hl("WinSeparator", { fg = p.border })
    hl("Pmenu",        { fg = p.text, bg = p.surface })
    hl("PmenuSel",     { fg = p.bg, bg = p.cyan })
    hl("PmenuSbar",    { bg = p.overlay })
    hl("PmenuThumb",   { bg = p.border })
    hl("StatusLine",   { fg = p.text, bg = p.surface })
    hl("StatusLineNC", { fg = p.muted, bg = p.surface })
    hl("TabLine",      { fg = p.muted, bg = p.surface })
    hl("TabLineSel",   { fg = p.text, bg = p.bg })
    hl("TabLineFill",  { bg = p.surface })
    hl("Folded",       { fg = p.subtle, bg = p.surface })
    hl("SignColumn",   { bg = p.bg })
    hl("ColorColumn",  { bg = p.overlay })
    hl("NonText",      { fg = p.muted })
    hl("Whitespace",   { fg = p.muted })
    hl("Title",        { fg = p.cyan, bold = true })
    hl("Directory",    { fg = p.blue })
    hl("ErrorMsg",     { fg = p.red, bold = true })
    hl("WarningMsg",   { fg = p.yellow })
    hl("ModeMsg",      { fg = p.text })
    hl("MoreMsg",      { fg = p.green })
    hl("Question",     { fg = p.cyan })

    -- Legacy vim syntax groups (fallback for anything without a treesitter parser)
    hl("Comment",       { fg = p.muted, italic = true })
    hl("Constant",      { fg = p.yellow })
    hl("String",        { fg = p.green })
    hl("Character",     { fg = p.green })
    hl("Number",        { fg = p.yellow })
    hl("Boolean",       { fg = p.yellow })
    hl("Float",         { fg = p.yellow })
    hl("Identifier",    { fg = p.text })
    hl("Function",      { fg = p.yellow })
    hl("Statement",     { fg = p.blue })
    hl("Conditional",   { fg = p.blue })
    hl("Repeat",        { fg = p.blue })
    hl("Label",         { fg = p.blue })
    hl("Operator",      { fg = p.subtle })
    hl("Keyword",       { fg = p.blue })
    hl("Exception",     { fg = p.red_soft })
    hl("PreProc",       { fg = p.blue })
    hl("Include",       { fg = p.blue })
    hl("Define",        { fg = p.blue })
    hl("Macro",         { fg = p.blue })
    hl("PreCondit",     { fg = p.blue })
    hl("Type",          { fg = p.yellow })
    hl("StorageClass",  { fg = p.blue })
    hl("Structure",     { fg = p.yellow })
    hl("Typedef",       { fg = p.yellow })
    hl("Special",       { fg = p.cyan })
    hl("SpecialChar",   { fg = p.cyan_light })
    hl("Tag",            { fg = p.blue })
    hl("Delimiter",     { fg = p.subtle })
    hl("SpecialComment",{ fg = p.muted, italic = true })
    hl("Debug",          { fg = p.red_soft })
    hl("Underlined",    { fg = p.text, underline = true })
    hl("Ignore",        { fg = p.muted })
    hl("Error",          { fg = p.red, bold = true })
    hl("Todo",            { fg = p.yellow, bold = true })

    -- Treesitter captures
    hl("@variable",            { fg = p.text })
    hl("@variable.builtin",    { fg = p.cyan_light, italic = true })
    hl("@constant",            { fg = p.yellow })
    hl("@constant.builtin",    { fg = p.yellow, bold = true })
    hl("@string",              { fg = p.green })
    hl("@string.escape",       { fg = p.cyan_light })
    hl("@character",           { fg = p.green })
    hl("@number",              { fg = p.yellow })
    hl("@boolean",             { fg = p.yellow })
    hl("@float",               { fg = p.yellow })
    hl("@function",            { fg = p.yellow })
    hl("@function.builtin",    { fg = p.yellow, italic = true })
    hl("@function.call",       { fg = p.yellow })
    hl("@method",              { fg = p.yellow })
    hl("@method.call",         { fg = p.yellow })
    hl("@constructor",         { fg = p.yellow })
    hl("@parameter",           { fg = p.subtle, italic = true })
    hl("@keyword",             { fg = p.blue })
    hl("@keyword.function",    { fg = p.blue })
    hl("@keyword.return",      { fg = p.blue })
    hl("@keyword.operator",    { fg = p.blue })
    hl("@keyword.import",      { fg = p.blue })
    hl("@conditional",         { fg = p.blue })
    hl("@repeat",              { fg = p.blue })
    hl("@label",               { fg = p.blue })
    hl("@operator",            { fg = p.subtle })
    hl("@exception",           { fg = p.red_soft })
    hl("@type",                { fg = p.yellow })
    hl("@type.builtin",        { fg = p.yellow, italic = true })
    hl("@type.definition",     { fg = p.yellow })
    hl("@storageclass",        { fg = p.blue })
    hl("@attribute",           { fg = p.text }) -- Java annotations (@Repository, @Column, ...)
    hl("@field",                { fg = p.text })
    hl("@property",            { fg = p.subtle })
    hl("@punctuation.delimiter", { fg = p.subtle })
    hl("@punctuation.bracket",   { fg = p.subtle })
    hl("@punctuation.special",   { fg = p.subtle })
    hl("@comment",              { fg = p.muted, italic = true })
    hl("@tag",                   { fg = p.blue })
    hl("@tag.attribute",        { fg = p.cyan })
    hl("@tag.delimiter",        { fg = p.subtle })
    hl("@markup.heading",       { fg = p.cyan, bold = true })
    hl("@markup.strong",        { fg = p.text, bold = true })
    hl("@markup.italic",        { fg = p.text, italic = true })
    hl("@markup.underline",     { fg = p.text, underline = true })
    hl("@markup.link",          { fg = p.cyan, underline = true })
    hl("@markup.link.url",      { fg = p.cyan, underline = true })
    hl("@markup.raw",           { fg = p.green })
    hl("@markup.list",          { fg = p.subtle })

    -- Diagnostics
    hl("DiagnosticError", { fg = p.red_soft })
    hl("DiagnosticWarn",  { fg = p.yellow })
    hl("DiagnosticInfo",  { fg = p.blue })
    hl("DiagnosticHint",  { fg = p.cyan })
    hl("DiagnosticOk",    { fg = p.green })
    hl("DiagnosticUnderlineError", { sp = p.red_soft, underline = true })
    hl("DiagnosticUnderlineWarn",  { sp = p.yellow, underline = true })
    hl("DiagnosticUnderlineInfo",  { sp = p.blue, underline = true })
    hl("DiagnosticUnderlineHint",  { sp = p.cyan, underline = true })
    hl("DiagnosticVirtualTextError", { fg = p.red_soft })
    hl("DiagnosticVirtualTextWarn",  { fg = p.yellow })
    hl("DiagnosticVirtualTextInfo",  { fg = p.blue })
    hl("DiagnosticVirtualTextHint",  { fg = p.cyan })
    hl("DiagnosticFloatingError", { fg = p.red_soft })
    hl("DiagnosticFloatingWarn",  { fg = p.yellow })
    hl("DiagnosticFloatingInfo",  { fg = p.blue })
    hl("DiagnosticFloatingHint",  { fg = p.cyan })
    hl("DiagnosticSignError", { fg = p.red_soft })
    hl("DiagnosticSignWarn",  { fg = p.yellow })
    hl("DiagnosticSignInfo",  { fg = p.blue })
    hl("DiagnosticSignHint",  { fg = p.cyan })

    -- Diff (combinations of existing palette entries, no new hexes)
    hl("DiffAdd",    { fg = p.green, bg = p.overlay })
    hl("DiffChange", { fg = p.yellow, bg = p.overlay })
    hl("DiffDelete", { fg = p.red, bg = p.overlay })
    hl("DiffText",   { fg = p.cyan, bg = p.overlay, bold = true })

    -- Spell
    hl("SpellBad",   { sp = p.red_soft, undercurl = true })
    hl("SpellCap",   { sp = p.yellow, undercurl = true })
    hl("SpellRare",  { sp = p.blue, undercurl = true })
    hl("SpellLocal", { sp = p.cyan, undercurl = true })

    -- LSP
    hl("LspReferenceText",  { bg = p.overlay })
    hl("LspReferenceRead",  { bg = p.overlay })
    hl("LspReferenceWrite", { bg = p.overlay, underline = true })
    hl("LspInlayHint",      { fg = p.muted, bg = p.surface, italic = true })
    hl("LspSignatureActiveParameter", { fg = p.cyan, bold = true })
    hl("LspCodeLens",       { fg = p.muted, italic = true })

    -- LSP semantic tokens. These extmarks render ABOVE treesitter, so any
    -- @lsp.type.*/@lsp.mod.* group we leave undefined shows as plain,
    -- uncoloured text instead of falling back to the @-capture below it —
    -- that's what made keywords/declarations look uniform with jdtls
    -- attached. Full list matches jdtls's own tokenTypes/tokenModifiers
    -- legend (see server_capabilities.semanticTokensProvider.legend).
    hl("@lsp.type.namespace",     { fg = p.blue })
    hl("@lsp.type.type",          { fg = p.yellow })
    hl("@lsp.type.class",         { fg = p.yellow })
    hl("@lsp.type.enum",          { fg = p.yellow })
    hl("@lsp.type.interface",     { fg = p.green }) -- light green, distinct from class/struct
    hl("@lsp.type.struct",        { fg = p.yellow })
    hl("@lsp.type.typeParameter", { fg = p.subtle, italic = true })
    hl("@lsp.type.parameter",     { fg = p.subtle, italic = true })
    hl("@lsp.type.variable",      { fg = p.text })
    hl("@lsp.type.property",      { fg = p.text })
    hl("@lsp.type.enumMember",    { fg = p.yellow })
    hl("@lsp.type.event",         { fg = p.yellow })
    hl("@lsp.type.function",      { fg = p.yellow })
    hl("@lsp.type.method",        { fg = p.yellow })
    hl("@lsp.type.macro",         { fg = p.yellow })
    hl("@lsp.type.keyword",       { fg = p.blue })
    hl("@lsp.type.modifier",      { fg = p.blue })
    hl("@lsp.type.comment",       { fg = p.muted, italic = true })
    hl("@lsp.type.string",        { fg = p.green })
    hl("@lsp.type.number",        { fg = p.yellow })
    hl("@lsp.type.regexp",        { fg = p.cyan_light })
    hl("@lsp.type.operator",      { fg = p.subtle })
    hl("@lsp.type.decorator",     { fg = p.text }) -- Java annotations, matches @attribute

    -- Modifiers stack on top of the type token above; keep them mostly
    -- attribute-only so they don't blank out the color set above.
    hl("@lsp.mod.declaration",    {})
    hl("@lsp.mod.definition",     {})
    hl("@lsp.mod.readonly",       { italic = true })
    hl("@lsp.mod.static",         {})
    hl("@lsp.mod.abstract",       {})
    hl("@lsp.mod.async",          {})
    hl("@lsp.mod.modification",   {})
    hl("@lsp.mod.documentation",  { italic = true })
    hl("@lsp.mod.defaultLibrary", { italic = true })
    hl("@lsp.mod.global",         {})
    hl("@lsp.mod.deprecated",     { strikethrough = true })
end

-- ============================================================
-- Plugin-specific groups. Called once synchronously, then again
-- from vim.schedule() in M.load() — bufferline registers its own
-- ColorScheme autocmd that regenerates BufferLine* groups right
-- after `doautocmd ColorScheme` fires (theme.lua:64), so the
-- scheduled re-apply is what actually wins.
-- ============================================================
function M.set_plugin_groups(p)
    -- bufferline
    hl("BufferLineFill",               { bg = p.bg })
    hl("BufferLineBackground",         { fg = p.muted, bg = p.surface })
    hl("BufferLineBufferSelected",     { fg = p.text, bg = p.bg, bold = true })
    hl("BufferLineBufferVisible",      { fg = p.subtle, bg = p.surface })
    hl("BufferLineIndicatorSelected",  { fg = p.cyan, bg = p.bg })
    hl("BufferLineSeparator",          { fg = p.border, bg = p.surface })
    hl("BufferLineSeparatorSelected",  { fg = p.border, bg = p.bg })
    hl("BufferLineSeparatorVisible",   { fg = p.border, bg = p.surface })
    hl("BufferLineModified",           { fg = p.yellow, bg = p.surface })
    hl("BufferLineModifiedSelected",   { fg = p.yellow, bg = p.bg })
    hl("BufferLineModifiedVisible",    { fg = p.yellow, bg = p.surface })
    hl("BufferLineCloseButton",         { fg = p.muted, bg = p.surface })
    hl("BufferLineCloseButtonSelected", { fg = p.red_soft, bg = p.bg })
    hl("BufferLineCloseButtonVisible",  { fg = p.muted, bg = p.surface })
    hl("BufferLineDuplicate",          { fg = p.muted, bg = p.surface, italic = true })
    hl("BufferLineDuplicateSelected",  { fg = p.subtle, bg = p.bg, italic = true })
    hl("BufferLineDuplicateVisible",   { fg = p.muted, bg = p.surface, italic = true })

    -- telescope
    hl("TelescopeNormal",        { fg = p.text, bg = p.surface })
    hl("TelescopeBorder",        { fg = p.border, bg = p.surface })
    hl("TelescopePromptNormal",  { fg = p.text, bg = p.overlay })
    hl("TelescopePromptBorder",  { fg = p.border, bg = p.overlay })
    hl("TelescopePromptTitle",   { fg = p.bg, bg = p.cyan, bold = true })
    hl("TelescopeResultsNormal", { fg = p.text, bg = p.surface })
    hl("TelescopeResultsBorder", { fg = p.border, bg = p.surface })
    hl("TelescopeResultsTitle",  { fg = p.bg, bg = p.blue, bold = true })
    hl("TelescopePreviewNormal", { fg = p.text, bg = p.surface })
    hl("TelescopePreviewBorder", { fg = p.border, bg = p.surface })
    hl("TelescopePreviewTitle",  { fg = p.bg, bg = p.green, bold = true })
    hl("TelescopeSelection",      { fg = p.text, bg = p.overlay, bold = true })
    hl("TelescopeSelectionCaret", { fg = p.cyan, bg = p.overlay })
    hl("TelescopeMatching",       { fg = p.cyan, bold = true })
    hl("TelescopeMultiSelection", { fg = p.yellow, bg = p.overlay })

    -- nvim-tree
    hl("NvimTreeNormal",          { fg = p.text, bg = p.bg })
    hl("NvimTreeRootFolder",      { fg = p.cyan, bold = true })
    hl("NvimTreeFolderIcon",      { fg = p.blue })
    hl("NvimTreeFolderName",      { fg = p.text })
    hl("NvimTreeOpenedFolderName",{ fg = p.cyan_light })
    hl("NvimTreeOpenedFile",      { fg = p.cyan_light })
    hl("NvimTreeSpecialFile",     { fg = p.yellow, underline = true })
    hl("NvimTreeIndentMarker",    { fg = p.muted })
    hl("NvimTreeWinSeparator",    { fg = p.border, bg = p.bg })
    hl("NvimTreeCursorLine",      { bg = p.surface })
    hl("NvimTreeGitDirty",        { fg = p.yellow })
    hl("NvimTreeGitNew",          { fg = p.green })
    hl("NvimTreeGitDeleted",      { fg = p.red_soft })
    hl("NvimTreeGitStaged",       { fg = p.green })
    hl("NvimTreeGitMerge",        { fg = p.yellow })

    -- indent-blankline
    hl("IblIndent",    { fg = p.overlay })
    hl("IblScope",     { fg = p.border })
    hl("IblWhitespace",{ fg = p.overlay })

    -- nvim-cmp
    hl("CmpItemAbbr",             { fg = p.text })
    hl("CmpItemAbbrMatch",        { fg = p.cyan, bold = true })
    hl("CmpItemAbbrMatchFuzzy",   { fg = p.cyan, bold = true })
    hl("CmpItemAbbrDeprecated",   { fg = p.muted, strikethrough = true })
    hl("CmpItemMenu",             { fg = p.subtle, italic = true })
    hl("CmpItemKindFunction",     { fg = p.yellow })
    hl("CmpItemKindMethod",       { fg = p.yellow })
    hl("CmpItemKindClass",        { fg = p.yellow })
    hl("CmpItemKindStruct",       { fg = p.yellow })
    hl("CmpItemKindInterface",    { fg = p.green })
    hl("CmpItemKindModule",       { fg = p.blue })
    hl("CmpItemKindVariable",     { fg = p.text })
    hl("CmpItemKindField",        { fg = p.text })
    hl("CmpItemKindProperty",     { fg = p.text })
    hl("CmpItemKindKeyword",      { fg = p.blue })
    hl("CmpItemKindText",         { fg = p.green })
    hl("CmpItemKindSnippet",      { fg = p.green })
    hl("CmpItemKindConstant",     { fg = p.yellow })
    hl("CmpItemKindEnum",         { fg = p.yellow })
    hl("CmpItemKindEnumMember",   { fg = p.yellow })
    hl("CmpItemKindOperator",     { fg = p.subtle })
    hl("CmpItemKindColor",        { fg = p.cyan_light })

    -- alpha-nvim
    hl("AlphaHeader",   { fg = p.cyan, bold = true })
    hl("AlphaButtons",  { fg = p.text })
    hl("AlphaShortcut", { fg = p.blue, bold = true })
    hl("AlphaFooter",   { fg = p.muted, italic = true })

    -- render-markdown.nvim (group names already referenced in plugins/markdown.lua)
    hl("RenderMarkdownH1", { fg = p.cyan, bold = true })
    hl("RenderMarkdownH2", { fg = p.blue, bold = true })
    hl("RenderMarkdownH3", { fg = p.cyan_light, bold = true })
    hl("RenderMarkdownH4", { fg = p.green, bold = true })
    hl("RenderMarkdownH5", { fg = p.yellow, bold = true })
    hl("RenderMarkdownH6", { fg = p.subtle, bold = true })
    hl("RenderMarkdownH1Bg", { bg = p.overlay })
    hl("RenderMarkdownH2Bg", { bg = p.overlay })
    hl("RenderMarkdownH3Bg", { bg = p.overlay })
    hl("RenderMarkdownH4Bg", { bg = p.overlay })
    hl("RenderMarkdownH5Bg", { bg = p.overlay })
    hl("RenderMarkdownH6Bg", { bg = p.overlay })
    hl("RenderMarkdownCode",       { bg = p.surface })
    hl("RenderMarkdownCodeInline", { fg = p.cyan_light, bg = p.surface })
    hl("RenderMarkdownUnchecked",  { fg = p.muted })
    hl("RenderMarkdownChecked",    { fg = p.green })
    hl("RenderMarkdownTodo",       { fg = p.yellow })
    hl("RenderMarkdownInfo",       { fg = p.blue })
    hl("RenderMarkdownSuccess",    { fg = p.green })
    hl("RenderMarkdownWarn",       { fg = p.yellow })
    hl("RenderMarkdownError",      { fg = p.red_soft })

    -- leetcode.nvim (dynamic-suffix groups like leetcode_lang_* fall back to Normal)
    hl("leetcode_all",         { fg = p.text })
    hl("leetcode_alt",         { fg = p.subtle })
    hl("leetcode_code",        { fg = p.cyan_light, bg = p.surface })
    hl("leetcode_description", { fg = p.text })
    hl("leetcode_easy",        { fg = p.green })
    hl("leetcode_error",       { fg = p.red_soft })
    hl("leetcode_extmarks",    { fg = p.cyan })
    hl("leetcode_hard",        { fg = p.red_soft })
    hl("leetcode_hint",        { fg = p.cyan })
    hl("leetcode_indent",      { fg = p.muted })
    hl("leetcode_info",        { fg = p.blue })
    hl("leetcode_link",        { fg = p.blue, underline = true })
    hl("leetcode_list",        { fg = p.text })
    hl("leetcode_medium",      { fg = p.yellow })
    hl("leetcode_menu",        { fg = p.cyan, bold = true })
    hl("leetcode_normal",      { fg = p.text })
    hl("leetcode_ok",          { fg = p.green })
    hl("leetcode_questions",   { fg = p.text })
    hl("leetcode_ref",         { fg = p.subtle })
    hl("leetcode_session",     { fg = p.cyan })
    hl("leetcode_start",       { fg = p.green, bold = true })

    -- smear-cursor.nvim (cursor.lua:5 hardcodes cursor_color = "#ffffff",
    -- which takes precedence over these — kept themed for when it doesn't)
    hl("SmearCursor",         { fg = p.cyan })
    hl("SmearCursorHideable", { fg = p.cyan })
    hl("SmearCursorToggle",   { fg = p.cyan })

    -- color-picker.nvim (mostly reuses Normal/FloatBorder, already themed above)
    hl("ColorPickerActionGroup", { fg = p.cyan })
end

function M.load()
    local module_name = (vim.o.background == "light") and "coucou.palette_light" or "coucou.palette"
    local p = require(module_name)

    M.set_editor_groups(p)
    M.set_plugin_groups(p)

    -- Terminal palette — kept strictly cool-to-yellow, red reserved for
    -- slots 1/9 (error convention), matching the "never warmer than
    -- yellow" constraint everywhere else in the theme.
    vim.g.terminal_color_0  = p.bg
    vim.g.terminal_color_1  = p.red_soft
    vim.g.terminal_color_2  = p.green
    vim.g.terminal_color_3  = p.yellow
    vim.g.terminal_color_4  = p.blue
    vim.g.terminal_color_5  = p.cyan_light
    vim.g.terminal_color_6  = p.cyan
    vim.g.terminal_color_7  = p.text
    vim.g.terminal_color_8  = p.muted
    vim.g.terminal_color_9  = p.red
    vim.g.terminal_color_10 = p.green
    vim.g.terminal_color_11 = p.yellow
    vim.g.terminal_color_12 = p.blue
    vim.g.terminal_color_13 = p.cyan_light
    vim.g.terminal_color_14 = p.cyan
    vim.g.terminal_color_15 = p.text

    -- theme.lua:64 fires `doautocmd ColorScheme` right after this file's
    -- colorscheme finishes loading; bufferline's own ColorScheme handler
    -- runs on that same event and regenerates BufferLine* groups from
    -- scratch, clobbering what we just set. Re-apply once more on the
    -- next tick so coucou wins the race.
    vim.schedule(function()
        if vim.g.colors_name == "coucou" then
            M.set_plugin_groups(p)
        end
    end)
end

return M
