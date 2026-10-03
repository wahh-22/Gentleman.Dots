-- Repository-owned copy of the Gentleman Blue palette; no external theme files required.
local p = {
  background = "#05070F",
  border = "#1C2C54",
  cyan = "#5CE1FF",
  foreground = "#DBE9FF",
  green = "#4DFF88",
  muted = "#4A5578",
  orange = "#FF9F1C",
  primary = "#347AFF",
  red = "#FF3D81",
  surface = "#070B1A",
  user_surface = "#10182E",
  violet = "#7C5CFF",
  yellow = "#FFD23D",
}

vim.opt.background = "dark"
vim.opt.termguicolors = true
vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end
vim.g.colors_name = "gentleman-blue"

local groups = {
  -- Solid editor surfaces, selections, and navigation.
  Normal = { fg = p.foreground, bg = p.background },
  NormalNC = { fg = p.foreground, bg = p.background },
  NormalFloat = { fg = p.foreground, bg = p.surface },
  FloatBorder = { fg = p.border, bg = p.surface },
  FloatTitle = { fg = p.cyan, bg = p.surface, bold = true },
  FloatFooter = { fg = p.muted, bg = p.surface },
  SignColumn = { fg = p.muted, bg = p.background },
  LineNr = { fg = p.muted, bg = p.background },
  CursorLineNr = { fg = p.cyan, bg = p.surface, bold = true },
  CursorLine = { bg = p.surface },
  CursorColumn = { bg = p.surface },
  ColorColumn = { bg = p.user_surface },
  Cursor = { fg = p.background, bg = p.foreground },
  lCursor = { link = "Cursor" },
  CursorIM = { link = "Cursor" },
  TermCursor = { link = "Cursor" },
  TermCursorNC = { fg = p.background, bg = p.muted },
  Visual = { bg = p.border },
  VisualNOS = { link = "Visual" },
  Search = { fg = p.background, bg = p.yellow },
  IncSearch = { fg = p.background, bg = p.orange },
  CurSearch = { link = "IncSearch" },
  Substitute = { fg = p.background, bg = p.red },
  MatchParen = { fg = p.cyan, bg = p.border, bold = true },
  NonText = { fg = p.border },
  EndOfBuffer = { fg = p.border, bg = p.background },
  Whitespace = { fg = p.border },
  SpecialKey = { fg = p.muted },
  Conceal = { fg = p.muted },
  Folded = { fg = p.muted, bg = p.surface },
  FoldColumn = { fg = p.muted, bg = p.background },
  WinSeparator = { fg = p.border, bg = p.background },
  VertSplit = { link = "WinSeparator" },
  StatusLine = { fg = p.foreground, bg = p.border },
  StatusLineNC = { fg = p.muted, bg = p.surface },
  WinBar = { fg = p.foreground, bg = p.background },
  WinBarNC = { fg = p.muted, bg = p.background },
  TabLine = { fg = p.muted, bg = p.surface },
  TabLineFill = { bg = p.surface },
  TabLineSel = { fg = p.cyan, bg = p.border, bold = true },
  Pmenu = { fg = p.foreground, bg = p.surface },
  PmenuSel = { fg = p.foreground, bg = p.border },
  PmenuSbar = { bg = p.user_surface },
  PmenuThumb = { bg = p.border },
  PmenuMatch = { fg = p.cyan, bg = p.surface },
  PmenuMatchSel = { fg = p.cyan, bg = p.border, bold = true },
  WildMenu = { link = "PmenuSel" },
  Title = { fg = p.violet, bold = true },
  SnacksDashboardHeader = { fg = p.primary, bold = true },
  Directory = { fg = p.primary },
  Question = { fg = p.cyan },
  MoreMsg = { fg = p.green },
  ModeMsg = { fg = p.cyan },
  MsgArea = { fg = p.foreground, bg = p.background },
  MsgSeparator = { fg = p.border, bg = p.surface },
  ErrorMsg = { fg = p.red, bg = p.background },
  WarningMsg = { fg = p.yellow, bg = p.background },

  -- Pi's syntax semantics, shared by legacy syntax and Treesitter captures.
  Comment = { fg = p.muted, italic = true },
  Constant = { fg = p.orange },
  String = { fg = p.green },
  Character = { fg = p.green },
  Number = { fg = p.orange },
  Boolean = { fg = p.orange },
  Float = { fg = p.orange },
  Identifier = { fg = p.foreground },
  Function = { fg = p.primary },
  Statement = { fg = p.violet },
  Conditional = { link = "Statement" },
  Repeat = { link = "Statement" },
  Label = { link = "Statement" },
  Operator = { fg = p.yellow },
  Keyword = { link = "Statement" },
  Exception = { link = "Statement" },
  PreProc = { fg = p.violet },
  Include = { link = "PreProc" },
  Define = { link = "PreProc" },
  Macro = { link = "PreProc" },
  PreCondit = { link = "PreProc" },
  Type = { fg = p.violet },
  StorageClass = { link = "Type" },
  Structure = { link = "Type" },
  Typedef = { link = "Type" },
  Special = { fg = p.cyan },
  SpecialChar = { link = "Special" },
  Tag = { fg = p.primary },
  Delimiter = { fg = p.muted },
  SpecialComment = { link = "Comment" },
  Debug = { fg = p.red },
  Underlined = { fg = p.cyan, underline = true },
  Ignore = { fg = p.muted },
  Error = { fg = p.red },
  Todo = { fg = p.yellow, bg = p.surface, bold = true },

  -- Added/removed text keeps Pi's green/red on a solid dark surface.
  DiffAdd = { fg = p.green, bg = p.surface },
  DiffDelete = { fg = p.red, bg = p.surface },
  DiffChange = { fg = p.cyan, bg = p.user_surface },
  DiffText = { fg = p.yellow, bg = p.border, bold = true },
  diffAdded = { fg = p.green },
  diffRemoved = { fg = p.red },
  diffChanged = { fg = p.cyan },
  diffFile = { fg = p.primary },
  diffLine = { fg = p.muted },
  LspReferenceText = { bg = p.border },
  LspReferenceRead = { link = "LspReferenceText" },
  LspReferenceWrite = { link = "LspReferenceText" },
  LspSignatureActiveParameter = { fg = p.cyan, bg = p.border, bold = true },
  LspInlayHint = { fg = p.muted, bg = p.surface },
  SnippetTabstop = { bg = p.border },
}

local captures = {
  ["@variable"] = "Identifier",
  ["@variable.builtin"] = "Special",
  ["@variable.parameter"] = "Identifier",
  ["@variable.member"] = "Identifier",
  ["@constant"] = "Constant",
  ["@constant.builtin"] = "Constant",
  ["@module"] = "Identifier",
  ["@label"] = "Label",
  ["@string"] = "String",
  ["@string.escape"] = "SpecialChar",
  ["@string.regexp"] = "Special",
  ["@character"] = "Character",
  ["@boolean"] = "Boolean",
  ["@number"] = "Number",
  ["@number.float"] = "Float",
  ["@type"] = "Type",
  ["@type.builtin"] = "Type",
  ["@attribute"] = "PreProc",
  ["@property"] = "Identifier",
  ["@function"] = "Function",
  ["@function.builtin"] = "Function",
  ["@function.call"] = "Function",
  ["@function.method"] = "Function",
  ["@function.method.call"] = "Function",
  ["@constructor"] = "Type",
  ["@operator"] = "Operator",
  ["@keyword"] = "Keyword",
  ["@punctuation.delimiter"] = "Delimiter",
  ["@punctuation.bracket"] = "Delimiter",
  ["@punctuation.special"] = "Special",
  ["@comment"] = "Comment",
  ["@comment.error"] = "DiagnosticError",
  ["@comment.warning"] = "DiagnosticWarn",
  ["@comment.todo"] = "Todo",
  ["@comment.note"] = "DiagnosticInfo",
  ["@markup.heading"] = "Title",
  ["@markup.quote"] = "Comment",
  ["@markup.raw"] = "String",
  ["@markup.link"] = "Underlined",
  ["@markup.link.url"] = "Underlined",
  ["@markup.list"] = "Special",
  ["@diff.plus"] = "diffAdded",
  ["@diff.minus"] = "diffRemoved",
  ["@diff.delta"] = "diffChanged",
  ["@tag"] = "Tag",
  ["@tag.attribute"] = "Identifier",
  ["@tag.delimiter"] = "Delimiter",
  ["@lsp.type.variable"] = "Identifier",
  ["@lsp.type.parameter"] = "Identifier",
  ["@lsp.type.property"] = "Identifier",
  ["@lsp.type.function"] = "Function",
  ["@lsp.type.method"] = "Function",
  ["@lsp.type.type"] = "Type",
  ["@lsp.type.class"] = "Type",
  ["@lsp.type.interface"] = "Type",
  ["@lsp.type.enum"] = "Type",
  ["@lsp.type.enumMember"] = "Constant",
  ["@lsp.type.keyword"] = "Keyword",
}
for capture, target in pairs(captures) do
  groups[capture] = { link = target }
end
groups["@markup.strong"] = { bold = true }
groups["@markup.italic"] = { italic = true }
groups["@markup.strikethrough"] = { strikethrough = true }

for severity, color in pairs({ Error = p.red, Warn = p.yellow, Info = p.cyan, Hint = p.primary, Ok = p.green }) do
  groups["Diagnostic" .. severity] = { fg = color }
  groups["DiagnosticSign" .. severity] = { fg = color, bg = p.background }
  groups["DiagnosticFloating" .. severity] = { fg = color, bg = p.surface }
  groups["DiagnosticVirtualText" .. severity] = { fg = color, bg = p.surface }
  groups["DiagnosticVirtualLines" .. severity] = { fg = color, bg = p.surface }
  groups["DiagnosticUnderline" .. severity] = { sp = color, undercurl = true }
end
groups.DiagnosticDeprecated = { fg = p.muted, strikethrough = true }
groups.DiagnosticUnnecessary = { fg = p.muted }

for name, attributes in pairs(groups) do
  vim.api.nvim_set_hl(0, name, attributes)
end

-- ANSI order: black, red, green, yellow, blue, magenta, cyan, white.
-- Bright slots reuse the exact palette rather than inventing lighter variants.
local terminal = {
  p.background, p.red, p.green, p.yellow, p.primary, p.violet, p.cyan, p.foreground,
  p.muted, p.red, p.green, p.yellow, p.primary, p.violet, p.cyan, p.foreground,
}
for index, color in ipairs(terminal) do
  vim.g["terminal_color_" .. (index - 1)] = color
end
