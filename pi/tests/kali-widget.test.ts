import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import kaliWidget, { KALI_WIDGET_KEY, renderKaliLogo } from "../extensions/kali-widget";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { Component, TUI } from "@earendil-works/pi-tui";
import type { Theme } from "@earendil-works/pi-coding-agent";

type Factory = (tui: TUI, theme: Theme) => Component;
type Handler = (event: unknown, ctx: ExtensionContext) => unknown;

function harness(mode = "tui", hasUI = true) {
  const handlers = new Map<string, Handler>();
  const widgets = new Map<string, Factory>();
  const calls: { key: string; content: Factory | undefined; placement?: string }[] = [];
  const ctx = {
    mode, hasUI,
    ui: {
      setWidget(key: string, content: Factory | undefined, options?: { placement: string }) {
        calls.push({ key, content, placement: options?.placement });
        if (content) widgets.set(key, content);
        else widgets.delete(key);
      },
      setHeader() { throw new Error("The metrics header must remain untouched"); },
    },
  } as unknown as ExtensionContext;
  const api = {
    on(name: string, handler: Handler) { handlers.set(name, handler); },
  } as unknown as ExtensionAPI;
  const emit = (name: string) => handlers.get(name)?.({}, ctx);
  kaliWidget(api);
  return { ctx, api, emit, widgets, calls };
}

const sourceArt = readFileSync(new URL("../../nvim/lua/plugins/ui.lua", import.meta.url), "utf8")
  .split("header = [[\n")[1].split("\n]]")[0].split("\n")
  .map((line) => line.replace(/\u2800+$/u, ""));

const sourceWidth = Math.max(...sourceArt.map((line) => line.length));

// Model the narrow (<122 terminal columns) Shell header independently of widget width.
const NARROW_HEADER_ROWS = 12;
const ABOVE_EDITOR_SPACER_ROWS = 1;
const FULLSCREEN_EDITOR_ROWS = 3;
const FOOTER_ROWS = 1;
const SAFETY_SLACK_ROWS = 1;
const NON_WIDGET_ROWS = NARROW_HEADER_ROWS + ABOVE_EDITOR_SPACER_ROWS
  + FULLSCREEN_EDITOR_ROWS + FOOTER_ROWS + SAFETY_SLACK_ROWS;

// Spaces and Braille are single-column cells; no ANSI or wide glyphs here.
function assertFits(lines: string[], width: number, rows: number) {
  expect(lines.length).toBeLessThanOrEqual(30);
  if (lines.length) {
    expect(lines.length + NON_WIDGET_ROWS).toBeLessThanOrEqual(rows);
    expect(lines.slice(-2)).toEqual(["", ""]);
  }
  for (const line of lines) {
    expect(line.length).toBeLessThanOrEqual(width);
    expect(line).toMatch(/^[ \u2800-\u28ff]*$/u);
  }
}

function artwork(lines: string[]): string[] {
  return lines.filter((line) => line !== "").map((line) => line.replace(/^ +/u, ""));
}

function assertCentered(lines: string[], width: number) {
  const blockWidth = Math.max(...artwork(lines).map((line) => line.length));
  const left = Math.floor((width - blockWidth) / 2);
  for (const line of lines.filter((line) => line !== "")) {
    expect(line.match(/^ */u)![0].length).toBe(left);
  }
  expect(width - left - blockWidth - left).toBeLessThanOrEqual(1);
}

// Independent area-pooling oracle: expand the recognizable source fixture, then
// inspect each destination dot's source rectangle. This catches missing strokes,
// wrong Braille bit order, clipping, and accidental changes to the source shape.
function projectedFixture(columns: number, rows: number): string[] {
  const offsets = [[0, 0], [0, 1], [0, 2], [1, 0], [1, 1], [1, 2], [0, 3], [1, 3]];
  const pixels = Array.from({ length: sourceArt.length * 4 }, () =>
    Array<boolean>(sourceWidth * 2).fill(false));
  sourceArt.forEach((line, row) => {
    [...line].forEach((cell, column) => {
      offsets.forEach(([x, y], bit) => {
        pixels[row * 4 + y][column * 2 + x] = !!((cell.charCodeAt(0) - 0x2800) & (1 << bit));
      });
    });
  });
  return Array.from({ length: rows }, (_, row) =>
    Array.from({ length: columns }, (_, column) => {
      let bits = 0;
      offsets.forEach(([x, y], bit) => {
        const left = Math.ceil((column * 2 + x) * sourceWidth / columns);
        const right = Math.ceil((column * 2 + x + 1) * sourceWidth / columns);
        const top = Math.ceil((row * 4 + y) * sourceArt.length / rows);
        const bottom = Math.ceil((row * 4 + y + 1) * sourceArt.length / rows);
        if (pixels.slice(top, bottom).some((line) => line.slice(left, right).some(Boolean))) {
          bits |= 1 << bit;
        }
      });
      return String.fromCharCode(0x2800 + bits);
    }).join("").replace(/\u2800+$/u, ""));
}

describe("responsive artwork", () => {
  test("preserves the complete Neovim dragon on a sufficiently tall viewport", () => {
    expect(sourceArt.length).toBe(28);
    expect(artwork(renderKaliLogo(240, 112))).toEqual(sourceArt);
    assertCentered(renderKaliLogo(240, 112), 240);
  });

  test.each([[80, 30, 10], [120, 40, 20], [144, 38, 18], [160, 48, 28]])(
    "retains a proportional structured dragon at %i columns / %i rows", (width, rows, height) => {
      const lines = renderKaliLogo(width, rows);
      expect(lines.length).toBe(height + 2);
      assertFits(lines, width, rows);
      assertCentered(lines, width);
      const art = artwork(lines);
      const columns = Math.max(...art.map((line) => line.length));
      expect(Math.abs(columns / height - sourceWidth / sourceArt.length)).toBeLessThan(0.15);
      if (rows >= 38) {
        expect(height).toBeGreaterThan(14);
        expect(columns).toBeGreaterThanOrEqual(42);
        expect(columns).toBeLessThanOrEqual(70);
      }
      expect(art).toEqual(projectedFixture(columns, height));
      const occupied = art.join("").replace(/\u2800/g, "").length;
      // Protect against the screenshot's isolated-dot rendering and a filled rectangle.
      expect(occupied / (columns * height)).toBeGreaterThan(0.15);
      expect(occupied / (columns * height)).toBeLessThan(0.5);
      for (const line of art) expect(line.replace(/\u2800/g, "").length).toBeGreaterThan(0);
      // Whiskers run from the left into the head; the lower curved tail is on the right.
      expect(art.slice(0, 3).some((line) => /[\u2801-\u28ff]/u.test(line.slice(0, 3)))).toBe(true);
      expect(art.at(-1)!.search(/[\u2801-\u28ff]/u)).toBeGreaterThan(columns * 0.8);
    },
  );

  test.each([[0, 24], [23, 40], [80, 19], [80, 0], [-1, 40], [NaN, 40], [80, Infinity]])(
    "hides rather than clipping at %i columns / %i rows", (width, rows) => {
      expect(renderKaliLogo(width, rows)).toEqual([]);
    },
  );

  test("reserves narrow header, spacer, editor, footer and slack before full art", () => {
    expect(NON_WIDGET_ROWS).toBe(18);
    expect(artwork(renderKaliLogo(120, 47))).toHaveLength(27);
    const full = renderKaliLogo(120, 48);
    expect(artwork(full)).toEqual(sourceArt);
    expect(full.slice(-2)).toEqual(["", ""]);
    expect(48 - full.length).toBe(NON_WIDGET_ROWS);
    expect(renderKaliLogo(80, 24)).toEqual([]);
    expect(renderKaliLogo(80, 29)).toEqual([]);
    expect(renderKaliLogo(80, 30)).toHaveLength(12);
    expect(renderKaliLogo(23.9, 40)).toEqual([]);
  });

  test("width-constrained artwork scales the whole dragon instead of clipping it", () => {
    expect(artwork(renderKaliLogo(sourceWidth, 112))).toEqual(sourceArt);
    const lines = renderKaliLogo(sourceWidth - 1, 112);
    expect(lines.length).toBe(29);
    expect(artwork(lines)).toEqual(projectedFixture(Math.round(sourceWidth * 27 / 28), 27));
    assertFits(lines, sourceWidth - 1, 112);
    assertCentered(lines, sourceWidth - 1);
    expect(artwork(lines).at(-1)!.replace(/\u2800/g, "")).not.toBe("");
  });

  test("centers odd widths and scales down for an editor column narrower than the terminal", () => {
    const lines = renderKaliLogo(45, 40);
    expect(lines).toHaveLength(21);
    assertCentered(lines, 45);
    expect(artwork(lines)).toEqual(projectedFixture(Math.round(sourceWidth * 19 / 28), 19));
    expect(renderKaliLogo(23, 40)).toEqual([]);
    expect(renderKaliLogo(80.9, 24.9)).toEqual(renderKaliLogo(80, 24));
  });

  test("never takes over a representative viewport", () => {
    for (const width of [1, 20, 23, 24, 32, 45, 60, 80, 120, 121, 122, 144, 240]) {
      for (const rows of [10, 20, 24, 28, 29, 30, 38, 40, 47, 48, 80, 112, 160]) {
        const lines = renderKaliLogo(width, rows);
        assertFits(lines, width, rows);
        if (lines.length) assertCentered(lines, width);
      }
    }
  });
});

describe("public widget lifecycle", () => {
  test("installs only its uniquely keyed above-editor widget at startup", () => {
    const h = harness();
    expect(h.calls).toHaveLength(0);
    h.emit("session_start");
    expect(h.widgets.size).toBe(1);
    expect(h.calls[0]).toMatchObject({ key: KALI_WIDGET_KEY, placement: "aboveEditor" });
    expect(typeof h.calls[0]?.content).toBe("function");
  });

  test.each([["rpc", true], ["json", false], ["print", false], ["tui", false]])(
    "does not touch terminal UI in %s (hasUI=%s)", (mode, hasUI) => {
      const h = harness(mode, hasUI);
      h.emit("session_start");
      h.emit("agent_start");
      h.emit("session_shutdown");
      expect(h.calls).toHaveLength(0);
    },
  );

  test("removes once at first agent start, with idempotent shutdown", () => {
    const h = harness();
    h.emit("agent_start");
    expect(h.calls).toHaveLength(0);
    h.emit("session_start");
    h.emit("agent_start");
    h.emit("agent_start");
    h.emit("session_shutdown");
    expect(h.widgets.size).toBe(0);
    expect(h.calls).toHaveLength(2);
    expect(h.calls[1]).toMatchObject({ key: KALI_WIDGET_KEY, content: undefined });
  });

  test("shutdown clears only this widget and a subsequent session can display it", () => {
    const h = harness();
    const metrics: Factory = () => ({ render: () => ["GIT/PATH"], invalidate() {} });
    h.widgets.set("shell.metrics", metrics);
    h.emit("session_start");
    h.emit("session_shutdown");
    h.emit("session_shutdown");
    expect(h.calls).toHaveLength(2);
    expect(h.widgets.get("shell.metrics")).toBe(metrics);
    h.emit("session_start");
    expect(h.widgets.size).toBe(2);
    h.emit("agent_start");
    expect(h.widgets.size).toBe(1);
    expect(h.widgets.get("shell.metrics")).toBe(metrics);
  });

  test("startup repeats and runtime reload replace rather than duplicate", () => {
    const h = harness();
    h.emit("session_start");
    h.emit("session_start");
    expect(h.widgets.size).toBe(1);
    h.emit("session_shutdown");
    expect(h.widgets.size).toBe(0);
    kaliWidget(h.api);
    h.emit("session_start");
    expect(h.widgets.size).toBe(1);
    h.emit("session_shutdown");
    h.emit("session_shutdown");
    expect(h.widgets.size).toBe(0);
  });

  test("factory responds to width/height resize and reapplies primary color", () => {
    const h = harness();
    h.emit("session_start");
    const factory = h.widgets.get(KALI_WIDGET_KEY);
    expect(factory).toBeDefined();
    // Terminal columns intentionally differ from the supplied editor-column width.
    const terminal = { rows: 30, columns: 160 };
    const colors: unknown[] = [];
    const theme = {
      style(text: string, options: unknown) { colors.push(options); return text; },
    } as unknown as Theme;
    const component = factory!({ terminal } as unknown as TUI, theme);
    expect(component.render(80)).toEqual(renderKaliLogo(80, 30));
    expect(colors).toHaveLength(12);
    expect(colors[0]).toEqual({ fg: { kind: "rgb", r: 52, g: 122, b: 255 } });
    terminal.rows = 40;
    component.invalidate();
    expect(component.render(120)).toHaveLength(22);
    terminal.rows = 38;
    expect(component.render(144)).toHaveLength(20);
    expect(component.render(45)).toEqual(renderKaliLogo(45, 38));
    assertFits(component.render(45), 45, terminal.rows);
    terminal.columns = 80;
    expect(component.render(45)).toEqual(renderKaliLogo(45, 38));
    terminal.rows = 112;
    component.invalidate();
    expect(artwork(component.render(240))).toEqual(sourceArt);
    terminal.rows = 19;
    expect(component.render(80)).toEqual([]);
    terminal.rows = 24;
    expect(component.render(23)).toEqual([]);
    expect(component.render(80)).toEqual([]);
    terminal.rows = 30;
    expect(component.render(80)).toHaveLength(12);
  });
});
