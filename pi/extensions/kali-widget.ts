import type { ExtensionAPI, ExtensionContext, SessionEntry, Theme } from "@earendil-works/pi-coding-agent";
import type { Component, TUI } from "@earendil-works/pi-tui";

export const KALI_WIDGET_KEY = "gentleman.dots.kali-startup";
// #347AFF, expressed as Pi's public concrete RGB color type.
const PRIMARY = { kind: "rgb", r: 52, g: 122, b: 255 } as const;

// Artwork from nvim/lua/plugins/ui.lua:235–265, with trailing blank cells removed.
// Only Braille cells are used: each code point occupies exactly one terminal column.
const FULL_LOGO = `⢀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⡀
⠉⠉⠉⠉⠉⠉⠉⠉⠉⠉⠙⠛⠛⠛⠛⠿⠿⠿⠿⠶⣶⣶⣶⣦⣤⣄⣀⣀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠉⠛⠛⠻⠿⣿⣷⣶⣤⣄⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣉⣻⣿⣿⣧
⠀⠀⠀⢀⣀⣀⣀⣤⣤⣴⣶⣶⣶⠶⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⢿⣿
⠶⠿⠟⠛⠛⠛⠋⠉⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣤⣤⣴⣶⣶⣾⣿⣿⣿⣿⡀⠀⠀⠀⠀⠀⠀⣄⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣤⣶⣾⡿⠿⠛⠛⠛⠋⠉⠉⠀⠀⠀⠀⢻⣿⣤⣀⠀⠀⠀⠀⠀⠉⠛⠶⣤⣀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣤⣶⠿⠟⠛⠉⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⣿⣿⣿⣶⣶⣶⣶⣤⣄⣀⠀⠉⠻⢶⣄⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣴⡶⠟⠋⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣾⣿⣿⣿⠿⠿⠿⠿⠿⣿⣿⣿⣿⣿⣦⣱⡍⢻⣦⡀
⠀⠀⠀⠀⠀⠀⢠⡶⠟⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣿⣿⡿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠛⠿⣿⣿⣿⣿⣟⣷⡄
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣿⣿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠙⢻⣿⣿⣷⡄
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠿⣿⣿⣿⣆
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢻⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠻⣿⣷⣤
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⣿⣿⣇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠛⠁
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢻⣿⣿⣦⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⢿⣿⣿⣦⣤⣀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠻⠿⣿⣿⣿⣿⣷⣶⣶⣦⣤⣤⣀⣀⣀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠉⠉⠛⠛⠛⠿⠿⠿⣿⣿⣿⣿⣿⣶⣶⣤⣄⣀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠻⣿⣿⣯⡛⠻⢿⣿⣶⣄
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⢿⣿⣦⡀⠈⠙⠿⣷⣄
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⢿⣷⣄⠀⠀⠈⠻⣷⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠻⣿⣧⠀⠀⠀⠘⢷⣄
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⢿⣷⠀⠀⠀⠈⢷
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢿⣧⠀⠀⠀⠸
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⣿⡄
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⣷
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢿⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠁`.split("\n");

const FULL_WIDTH = Math.max(...FULL_LOGO.map((line) => line.length));
// Braille encodes a 2×4 dot grid; its bit order is column-major, except the last row.
const DOT_BITS = [[1, 8], [2, 16], [4, 32], [64, 128]];

/** Pool every source dot, rather than cropping whiskers or dropping thin tail strokes. */
function shrinkLogo(columns: number, rows: number): string[] {
  const cells = Array.from({ length: rows }, () => Array<number>(columns).fill(0));
  for (let row = 0; row < FULL_LOGO.length; row++) {
    for (let column = 0; column < FULL_LOGO[row].length; column++) {
      const bits = FULL_LOGO[row].charCodeAt(column) - 0x2800;
      for (let y = 0; y < 4; y++) {
        for (let x = 0; x < 2; x++) {
          if (!(bits & DOT_BITS[y][x])) continue;
          const targetX = Math.floor((column * 2 + x) * columns / FULL_WIDTH);
          const targetY = Math.floor((row * 4 + y) * rows / FULL_LOGO.length);
          cells[Math.floor(targetY / 4)][Math.floor(targetX / 2)] |= DOT_BITS[targetY % 4][targetX % 2];
        }
      }
    }
  }
  return cells.map((line) => line.map((bits) => String.fromCharCode(0x2800 + bits)).join("")
    .replace(/\u2800+$/u, ""));
}

const MIN_ROWS = 10;
// Narrow Shell header (12) + Pi spacer (1) + fullscreen editor minimum (3)
// + footer minimum (1) + safety slack (1). Keep this conservative at every width:
// the widget's render width may be an editor column, not the terminal width.
const RESERVED_ROWS = 18;
const BOTTOM_GAP = 2;
// Preserve the Neovim cell aspect instead of stretching a half-height master.
// Pool each bounded size once, outside the interactive rendering path.
const RESPONSIVE_LOGOS = new Map<number, string[]>(
  Array.from({ length: FULL_LOGO.length - MIN_ROWS + 1 }, (_, index) => {
    const rows = index + MIN_ROWS;
    return [rows, rows === FULL_LOGO.length ? FULL_LOGO
      : shrinkLogo(Math.round(rows * FULL_WIDTH / FULL_LOGO.length), rows)];
  }),
);

export function renderKaliLogo(width: number, rows: number): string[] {
  if (!Number.isFinite(width) || !Number.isFinite(rows)) return [];
  width = Math.floor(width);
  rows = Math.floor(rows);
  if (width < 24) return [];
  // The public widget API supplies width, but not the other components' heights.
  // Reserve the non-widget budget, plus two blank rows BELOW the artwork:
  // 24 terminal rows → hidden; 38/40 → 18/20 art rows; 48+ → the original 28.
  // Width constraints can reduce the art further; never crop it to force a fit.
  const budget = rows - RESERVED_ROWS - BOTTOM_GAP;
  let logo: string[] | undefined;
  for (let height = Math.min(budget, FULL_LOGO.length); height >= MIN_ROWS; height--) {
    const candidate = RESPONSIVE_LOGOS.get(height)!;
    if (Math.max(...candidate.map((line) => line.length)) <= width) {
      logo = candidate;
      break;
    }
  }
  if (!logo) return [];
  // Center the bounding block, not each row: the dragon's internal blank cells
  // are structural and must stay aligned. Only ordinary spaces are added here.
  const columns = Math.max(...logo.map((line) => line.length));
  const padding = " ".repeat(Math.floor((width - columns) / 2));
  return [...logo.map((line) => padding + line), ...Array<string>(BOTTOM_GAP).fill("")];
}

function createWidget(tui: TUI, theme: Theme): Component {
  return {
    render(width: number) {
      return renderKaliLogo(width, tui.terminal.rows)
        .map((line) => theme.style(line, { fg: PRIMARY }));
    },
    // No cached themed output: each render reads current terminal dimensions and theme.
    invalidate() {},
  };
}

export default function kaliWidget(pi: ExtensionAPI): void {
  let installed = false;
  pi.on("session_start", (_event: unknown, ctx: ExtensionContext) => {
    if (ctx.mode !== "tui" || !ctx.hasUI) return;
    // Inspect raw active history: model context edits can omit messages still in the UI.
    // Metadata and hidden custom messages alone do not make a conversation.
    const hasHistory = ctx.sessionManager.getBranch().some((entry: SessionEntry) => {
      if (entry.type === "message") {
        const message = entry.message;
        return message.role !== "system" && (message.role !== "custom" || message.display);
      }
      return entry.type === "compaction" || entry.type === "branch_summary"
        || (entry.type === "custom_message" && entry.display);
    });
    if (hasHistory) {
      // Also clear a stale widget left by a previous session or extension runtime.
      ctx.ui.setWidget(KALI_WIDGET_KEY, undefined);
      installed = false;
      return;
    }
    ctx.ui.setWidget(KALI_WIDGET_KEY, createWidget, { placement: "aboveEditor" });
    installed = true;
  });

  const clear = (_event: unknown, ctx: ExtensionContext): void => {
    if (!installed || ctx.mode !== "tui" || !ctx.hasUI) return;
    ctx.ui.setWidget(KALI_WIDGET_KEY, undefined);
    installed = false;
  };
  pi.on("agent_start", clear);
  pi.on("session_shutdown", clear);
}
