import { describe, expect, test } from "bun:test";
import { installKaliWidget } from "../install-kali-widget.mjs";

// In-memory filesystem fixtures keep validation away from real agent homes.
function fixture() {
  const entries = new Map<string, any>([["/", { type: "dir", mode: 0o755 }]]);
  let clock = 1;
  const error = (code: string) => Object.assign(new Error(code), { code });
  const stat = (path: string) => {
    const value = entries.get(path);
    if (!value) throw error("ENOENT");
    return { ...value, isDirectory: () => value.type === "dir",
      isFile: () => value.type === "file", isSymbolicLink: () => value.type === "link" };
  };
  const fs = {
    lstatSync: stat,
    mkdirSync(path: string) {
      if (entries.has(path)) throw error("EEXIST");
      if (!stat(path.slice(0, path.lastIndexOf("/")) || "/").isDirectory()) throw error("ENOTDIR");
      entries.set(path, { type: "dir", mode: 0o700, ino: clock++ });
    },
    readFileSync(path: string) {
      const value = entries.get(path);
      if (!value) throw error("ENOENT");
      if (value.type !== "file") throw error("EINVAL");
      return value.text;
    },
    writeFileSync(path: string, text: string, options: any) {
      if (options.flag === "wx" && entries.has(path)) throw error("EEXIST");
      entries.set(path, { type: "file", text, mode: options.mode, ino: clock++, mtimeMs: clock });
    },
    chmodSync(path: string, mode: number) { entries.get(path).mode = mode; },
    renameSync(from: string, to: string) { entries.set(to, entries.get(from)); entries.delete(from); },
    unlinkSync(path: string) { entries.delete(path); },
    rmdirSync(path: string) { entries.delete(path); },
  };
  const dir = (path: string) => {
    for (const part of path.split("/").filter(Boolean)) {
      const parent = dir.current || "";
      dir.current = `${parent}/${part}`;
      if (!entries.has(dir.current)) fs.mkdirSync(dir.current);
    }
    dir.current = "";
  };
  dir.current = "";
  const file = (path: string, text: string, mode = 0o640) => {
    dir(path.slice(0, path.lastIndexOf("/")));
    fs.writeFileSync(path, text, { mode });
  };
  dir("/home/user");
  file("/source/kali-widget.ts", "export default function widget() {}\n");
  const messages: string[] = [];
  const run = (env = {}) => installKaliWidget({ fs, home: "/home/user", env,
    source: "/source/kali-widget.ts", log: (message: string) => messages.push(message) });
  const normal = "/home/user/.pi/agent";
  const isolated = "/home/user/.gentle-shell/agent";
  const banner = "/home/user/.pi/gentle-ai/banner.json";
  const boot = () => file(`${isolated}/.gentle-shell-home`, "gentle-shell\n");
  const json = (path: string) => JSON.parse(fs.readFileSync(path));
  return { entries, fs, file, dir, run, normal, isolated, banner, boot, json, messages };
}

const visualSettings = {
  schema: "gentle-pi.visual-customization/v1", statusPlacement: "right",
  headerPlacement: "below-input", density: "compact",
  visibility: { changes: false, rdd: true, agents: false, todo: true,
    usageCost: false, modelDetails: true },
};
const visualPath = "/home/user/.pi/gentle-ai/visual-customization.json";

describe("installer does not own visual preferences", () => {
  function ignoreVisualAccess(f: ReturnType<typeof fixture>, path = visualPath) {
    for (const method of ["lstatSync", "readFileSync", "mkdirSync", "writeFileSync",
      "chmodSync", "renameSync", "unlinkSync", "rmdirSync"] as const) {
      const original = f.fs[method];
      (f.fs as any)[method] = (...args: any[]) => {
        if (args.some((arg) => typeof arg === "string" &&
          (arg === path || arg.startsWith(`${path}.`)))) {
          throw new Error(`Unexpected visual access: ${method} ${path}`);
        }
        return (original as any)(...args);
      };
    }
  }

  test("preserves full preferences byte-for-byte and inode-stable on install and rerun", () => {
    const f = fixture();
    f.file(visualPath, JSON.stringify(visualSettings), 0o600);
    f.file(f.banner, JSON.stringify({ showTextLogo: false, showRose: false, metrics: true }));
    const bannerBefore = f.fs.readFileSync(f.banner);
    const visualBefore = { ...f.entries.get(visualPath) };
    ignoreVisualAccess(f);
    f.run();
    expect(f.entries.get(visualPath)).toEqual(visualBefore);
    expect(f.entries.get(visualPath).mode).toBe(0o600);
    expect(f.fs.readFileSync(f.banner)).toBe(bannerBefore);
    expect(f.entries.has(f.isolated)).toBe(false);
    const before = JSON.stringify([...f.entries]);
    f.run();
    expect(JSON.stringify([...f.entries])).toBe(before);
  });

  for (const statusPlacement of ["auto", "right", "bottom", "hidden"]) {
    test(`preserves ${statusPlacement} placement through bootstrapped installs and upgrades`, () => {
      const f = fixture(); f.boot();
      f.file(visualPath, `${JSON.stringify({ ...visualSettings, statusPlacement }, null, 4)}\n`);
      const before = { ...f.entries.get(visualPath) };
      ignoreVisualAccess(f);
      f.run();
      expect(f.entries.get(visualPath)).toEqual(before);
      f.file("/source/kali-widget.ts", "export default function upgraded() {}\n");
      for (let run = 0; run < 2; run++) {
        f.run();
        expect(f.entries.get(visualPath)).toEqual(before);
        expect(f.entries.has(`${f.isolated}/extensions/kali-widget.ts`)).toBe(true);
      }
    });
  }

  test("uses shared config override without creating isolated home", () => {
    const f = fixture();
    const path = "/home/user/shared/visual-customization.json";
    f.file(path, JSON.stringify(visualSettings));
    const before = { ...f.entries.get(path) };
    ignoreVisualAccess(f, path);
    for (let run = 0; run < 2; run++) {
      f.run({ GENTLE_PI_CONFIG_HOME: "~/shared" });
      expect(f.entries.get(path)).toEqual(before);
    }
    expect(f.entries.has(visualPath)).toBe(false);
    expect(f.entries.has(f.isolated)).toBe(false);
  });

  test("preserves supported legacy visibility without adding fields", () => {
    const f = fixture();
    const { rdd: _rdd, ...visibility } = visualSettings.visibility;
    const legacy = { ...visualSettings, visibility };
    f.file(visualPath, JSON.stringify(legacy));
    const before = { ...f.entries.get(visualPath) };
    ignoreVisualAccess(f);
    for (let run = 0; run < 2; run++) {
      f.run();
      expect(f.entries.get(visualPath)).toEqual(before);
    }
  });

  for (const key of ["changes", "agents", "todo", "usageCost", "modelDetails"]) {
    test(`preserves parser-valid legacy null visibility for ${key}`, () => {
      const f = fixture();
      const { rdd: _rdd, ...visibility } = visualSettings.visibility;
      const legacy = { ...visualSettings, visibility: { ...visibility, [key]: null } };
      f.file(visualPath, JSON.stringify(legacy), 0o600);
      const visualBefore = { ...f.entries.get(visualPath) };
      ignoreVisualAccess(f);
      f.run();
      expect(f.entries.get(visualPath)).toEqual(visualBefore);
      expect(f.entries.get(visualPath).mode).toBe(0o600);
      const before = JSON.stringify([...f.entries]);
      f.run();
      expect(JSON.stringify([...f.entries])).toBe(before);
    });
  }

  const { rdd: _rdd, ...legacyVisibility } = visualSettings.visibility;
  const { todo: _todo, ...incompleteLegacyVisibility } = legacyVisibility;
  for (const content of [undefined, "{bad", "null", "[]", '{"statusPlacement":"right"}',
    JSON.stringify({ ...visualSettings, schema: "v2" }),
    JSON.stringify({ ...visualSettings, density: "unknown" }),
    JSON.stringify({ ...visualSettings, headerPlacement: "hidden" }),
    JSON.stringify({ ...visualSettings, statusPlacement: "unknown" }),
    JSON.stringify({ ...visualSettings, visibility: { changes: true } }),
    JSON.stringify({ ...visualSettings, visibility: { ...visualSettings.visibility, todo: "true" } }),
    ...Object.keys(visualSettings.visibility).map((key) => JSON.stringify({
      ...visualSettings, visibility: { ...visualSettings.visibility, [key]: null },
    })),
    ...["true", 0, [], {}].map((todo) => JSON.stringify({
      ...visualSettings, visibility: { ...legacyVisibility, todo },
    })),
    JSON.stringify({ ...visualSettings, visibility: incompleteLegacyVisibility }),
    JSON.stringify({ ...visualSettings, visibility: { ...legacyVisibility, extra: null } }),
    JSON.stringify({ ...visualSettings, extra: true })]) {
    test(`never accesses missing/invalid visual config: ${content}`, () => {
      const f = fixture();
      if (content !== undefined) f.file(visualPath, content);
      const before = f.entries.has(visualPath) ? { ...f.entries.get(visualPath) } : undefined;
      ignoreVisualAccess(f);
      for (let run = 0; run < 2; run++) {
        f.run();
        expect(f.entries.get(visualPath)).toEqual(before);
        expect(f.entries.has(`${visualPath}.lock`)).toBe(false);
        expect(f.messages.join(" ")).not.toContain("Status rail");
      }
    });
  }

  for (const type of ["dir", "file", "link"]) {
    for (const present of [true, false]) {
      test(`ignores visual ${type} lock with config ${present ? "present" : "missing"}`, () => {
        const f = fixture(); f.dir("/home/user/.pi/gentle-ai");
        if (present) f.file(visualPath, JSON.stringify(visualSettings));
        f.entries.set(`${visualPath}.lock`, { type, mode: 0o700, ino: 9999 });
        const before = f.entries.has(visualPath) ? { ...f.entries.get(visualPath) } : undefined;
        const lockBefore = { ...f.entries.get(`${visualPath}.lock`) };
        ignoreVisualAccess(f);
        for (let run = 0; run < 2; run++) {
          f.run();
          expect(f.entries.get(visualPath)).toEqual(before);
          expect(f.entries.get(`${visualPath}.lock`)).toEqual(lockBefore);
          expect(f.entries.has(`${f.normal}/settings.json`)).toBe(true);
        }
      });
    }
  }

  for (const type of ["link", "dir"]) {
    test(`leaves visual ${type} untouched on install and rerun`, () => {
      const f = fixture(); f.dir("/home/user/.pi/gentle-ai");
      f.entries.set(visualPath, { type, mode: 0o777, ino: 9999, target: "/external/preferences" });
      const before = { ...f.entries.get(visualPath) };
      ignoreVisualAccess(f);
      for (let run = 0; run < 2; run++) {
        f.run();
        expect(f.entries.get(visualPath)).toEqual(before);
        expect(f.entries.has(`${f.normal}/settings.json`)).toBe(true);
      }
    });
  }
});

describe("safe Kali deployment", () => {
  // Mirrors startup-banner.ts normalizeBannerConfig's independent boolean
  // defaults without importing the installed package or accessing real homes.
  const normalizedArt = (record: Record<string, unknown>) => ({
    showRose: typeof record.showRose === "boolean" ? record.showRose : true,
    showTextLogo: typeof record.showTextLogo === "boolean" ? record.showTextLogo : true,
  });

  for (const initial of [undefined, {}, { showRose: true, showTextLogo: true },
    { showTextLogo: false }, { showRose: false }]) {
    test(`disables both independently normalized banner flags: ${JSON.stringify(initial)}`, () => {
      const f = fixture();
      const unrelated = { color: "cyan", unknown: { metrics: true, future: [1, 2] } };
      if (initial !== undefined) f.file(f.banner, JSON.stringify({ ...unrelated, ...initial }));
      f.run();
      const banner = f.json(f.banner);
      expect(normalizedArt(banner)).toEqual({ showRose: false, showTextLogo: false });
      expect(banner).toEqual({ ...(initial === undefined ? {} : unrelated),
        showRose: false, showTextLogo: false });
      expect(f.entries.get(f.banner).mode).toBe(initial === undefined ? 0o600 : 0o640);
      expect(f.entries.has(`${f.banner}.lock`)).toBe(false);
      const before = JSON.stringify([...f.entries]);
      f.run();
      expect(JSON.stringify([...f.entries])).toBe(before);
    });
  }

  test("already disabled banner preserves bytes, inode and permissions through reruns", () => {
    const f = fixture();
    f.file(f.banner, '{ "color": "#347AFF", "showRose": false, "unknown": [1], "showTextLogo": false }\n', 0o600);
    const before = { ...f.entries.get(f.banner) };
    for (let run = 0; run < 2; run++) {
      f.run();
      expect(f.entries.get(f.banner)).toEqual(before);
      expect(normalizedArt(f.json(f.banner))).toEqual({ showRose: false, showTextLogo: false });
    }
  });
  test("creates ordinary home but never an absent isolated home, with actionable notice", () => {
    const f = fixture(); f.run();
    expect(f.json(`${f.normal}/settings.json`)).toEqual({ quietStartup: true });
    expect(f.entries.has(`${f.normal}/extensions/kali-widget.ts`)).toBe(true);
    expect(f.entries.has(f.isolated)).toBe(false);
    expect(f.messages.join(" ")).toContain("gentle-shell --isolated");
    expect(f.messages.join(" ")).toContain("rerun");
  });

  test("merges both bootstrapped homes and banner without changing unrelated values", () => {
    const f = fixture(); f.boot();
    const settings = { quietStartup: false, packages: [{ source: "npm:gentle-shell", skills: [] }],
      extensions: ["-builtin:mcp"], theme: "gentleman", tuiMode: "fullscreen", unknown: { a: [1, 2] } };
    for (const home of [f.normal, f.isolated]) {
      f.file(`${home}/settings.json`, JSON.stringify(settings));
      f.file(`${home}/extensions/other.ts`, "untouched");
    }
    f.file(f.banner, JSON.stringify({ showRose: false, color: "#347AFF", showTextLogo: true, unknown: [1] }));
    f.run();
    for (const home of [f.normal, f.isolated]) {
      expect(f.json(`${home}/settings.json`)).toEqual({ ...settings, quietStartup: true });
      expect(f.fs.readFileSync(`${home}/extensions/other.ts`)).toBe("untouched");
      expect(f.entries.get(`${home}/settings.json`).mode).toBe(0o640);
      expect(f.entries.has(`${home}/settings.json.lock`)).toBe(false);
    }
    expect(f.json(f.banner)).toEqual({ showRose: false, color: "#347AFF", showTextLogo: false, unknown: [1] });
    expect(f.entries.get(f.banner).mode).toBe(0o640);
  });

  test("rerun is byte- and inode-stable; owned extension upgrades preserve permissions", () => {
    const f = fixture(); f.run();
    const before = JSON.stringify([...f.entries]); f.run();
    expect(JSON.stringify([...f.entries])).toBe(before);
    const target = `${f.normal}/extensions/kali-widget.ts`;
    f.fs.chmodSync(target, 0o600);
    f.file("/source/kali-widget.ts", "export default function upgraded() {}\n");
    f.run();
    expect(f.fs.readFileSync(target)).toContain("upgraded");
    expect(f.entries.get(target).mode).toBe(0o600);
  });

  test("honors banner config override, not as an agent directory", () => {
    const f = fixture(); f.run({ GENTLE_PI_CONFIG_HOME: "/home/user/banner-config" });
    expect(f.json("/home/user/banner-config/banner.json")).toEqual({ showRose: false, showTextLogo: false });
    expect(f.entries.has(f.banner)).toBe(false);
    expect(f.entries.has(`${f.normal}/settings.json`)).toBe(true);
  });

  test("existing unowned isolated home is skipped without being claimed", () => {
    const f = fixture(); f.dir(f.isolated); f.run();
    expect(f.entries.has(`${f.isolated}/settings.json`)).toBe(false);
    expect(f.messages.join(" ")).toContain("ownership marker");
  });

  for (const content of ["{broken", "[]", "null", '"string"']) {
    test(`rejects malformed/non-object settings: ${content}`, () => {
      const f = fixture(); f.file(`${f.normal}/settings.json`, content);
      expect(() => f.run()).toThrow();
      expect(f.fs.readFileSync(`${f.normal}/settings.json`)).toBe(content);
      expect(f.entries.has(`${f.normal}/settings.json.lock`)).toBe(false);
    });
  }

  for (const target of ["settings.json", "extensions", "extensions/kali-widget.ts"]) {
    test(`refuses symlink target ${target}`, () => {
      const f = fixture(); f.dir(`${f.normal}/extensions`);
      f.entries.set(`${f.normal}/${target}`, { type: "link", mode: 0o777 });
      expect(() => f.run()).toThrow(/symlink/);
      expect(f.entries.get(`${f.normal}/${target}`).type).toBe("link");
    });
  }

  test("refuses a symlink ancestor and malformed banner", () => {
    const f = fixture(); f.entries.set("/home/user/.pi", { type: "link" });
    expect(() => f.run()).toThrow(/symlink/);
    const g = fixture(); g.file(g.banner, "{bad");
    expect(() => g.run()).toThrow();
    expect(g.fs.readFileSync(g.banner)).toBe("{bad");
  });

  for (const type of ["dir", "file", "link"]) {
    test(`never steals a ${type} settings lock`, () => {
      const f = fixture(); f.dir(f.normal);
      f.entries.set(`${f.normal}/settings.json.lock`, { type, mode: 0o700 });
      expect(() => f.run()).toThrow(/lock/);
      expect(f.entries.get(`${f.normal}/settings.json.lock`).type).toBe(type);
      expect(f.entries.has(`${f.normal}/settings.json`)).toBe(false);
    });
  }

  test("supports an explicit ordinary agent directory", () => {
    const f = fixture(); f.run({ PI_CODING_AGENT_DIR: "~/custom-agent" });
    expect(f.json("/home/user/custom-agent/settings.json")).toEqual({ quietStartup: true });
    expect(f.entries.has(f.normal)).toBe(false);
  });

  test("cannot bypass absent-home protection with nested environment overrides", () => {
    for (const key of ["PI_CODING_AGENT_DIR", "GENTLE_PI_CONFIG_HOME"]) {
      const f = fixture();
      expect(() => f.run({ [key]: `${f.isolated}/nested` })).toThrow(/unbootstrapped/);
      expect(f.entries.has(f.isolated)).toBe(false);
    }
  });

  test("preflight failures do not partially install into the ordinary home", () => {
    const f = fixture(); f.file(f.banner, "{bad");
    expect(() => f.run()).toThrow(/Malformed/);
    expect(f.entries.has(f.normal)).toBe(false);
  });

  test("detects concurrent target edits and releases every acquired lock", () => {
    const f = fixture(); f.file(`${f.normal}/settings.json`, "{}");
    const mkdir = f.fs.mkdirSync;
    f.fs.mkdirSync = (path: string) => {
      mkdir(path);
      if (path === `${f.banner}.lock`) f.file(`${f.normal}/settings.json`, '{"other":true}');
    };
    expect(() => f.run()).toThrow(/Target changed/);
    expect(f.json(`${f.normal}/settings.json`)).toEqual({ other: true });
    expect([...f.entries.keys()].some((path) => path.endsWith(".lock"))).toBe(false);
  });

  test("rename failure keeps the old file, cleans temp files, and releases locks", () => {
    const f = fixture(); f.file(`${f.normal}/settings.json`, "{}", 0o600);
    f.fs.renameSync = () => { throw new Error("simulated rename failure"); };
    expect(() => f.run()).toThrow(/rename failure/);
    expect(f.fs.readFileSync(`${f.normal}/settings.json`)).toBe("{}");
    expect([...f.entries.keys()].some((path) => /\.(lock|tmp)$/.test(path))).toBe(false);
  });

  test("does not remove a replaced lock, but still releases other owned locks", () => {
    const f = fixture();
    const rename = f.fs.renameSync;
    f.fs.renameSync = (from: string, to: string) => {
      rename(from, to);
      if (to === f.banner) f.entries.set(`${f.banner}.lock`, { type: "dir", ino: 9999 });
    };
    expect(() => f.run()).toThrow(/release owned locks/);
    expect(f.entries.get(`${f.banner}.lock`).ino).toBe(9999);
    expect(f.entries.has(`${f.normal}/settings.json.lock`)).toBe(false);
  });

  test("rejects an unrelated extension collision", () => {
    const f = fixture(); f.file(`${f.normal}/extensions/kali-widget.ts`, "someone else's extension");
    expect(() => f.run()).toThrow(/unowned/);
    expect(f.fs.readFileSync(`${f.normal}/extensions/kali-widget.ts`)).toBe("someone else's extension");
  });
});
