#!/usr/bin/env node
import * as nodeFs from "node:fs";
import { randomUUID } from "node:crypto";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const OWNED = "// Managed by Gentleman.Dots pi/install-kali-widget.mjs\n";
const DEFAULT_SOURCE = fileURLToPath(new URL("./extensions/kali-widget.ts", import.meta.url));

function optionalStat(fs, path) {
  try { return fs.lstatSync(path); }
  catch (error) { if (error.code === "ENOENT") return undefined; throw error; }
}

// Do not follow symlinks, including directory ancestors. No recursive mkdir that
// might silently traverse a redirected agent/config home.
function checkPath(fs, path) {
  const parent = dirname(path);
  if (parent !== path) checkPath(fs, parent);
  const stat = optionalStat(fs, path);
  if (stat?.isSymbolicLink()) throw new Error(`Refusing symlink: ${path}`);
  if (parent !== path) {
    const parentStat = optionalStat(fs, parent);
    if (parentStat && !parentStat.isDirectory()) throw new Error(`Not a directory: ${parent}`);
  }
  return stat;
}

function ensureDirectory(fs, path) {
  const stat = checkPath(fs, path);
  if (stat) {
    if (!stat.isDirectory()) throw new Error(`Not a directory: ${path}`);
    return;
  }
  const parent = dirname(path);
  if (parent !== path) ensureDirectory(fs, parent);
  fs.mkdirSync(path, { mode: 0o700 });
}

function snapshot(fs, path) {
  const stat = checkPath(fs, path);
  if (!stat) return { text: undefined, mode: 0o600, ino: undefined };
  if (!stat.isFile()) throw new Error(`Not a regular file: ${path}`);
  return { text: fs.readFileSync(path, "utf8"), mode: stat.mode & 0o777, ino: stat.ino };
}

function assertUnchanged(fs, path, before) {
  const now = snapshot(fs, path);
  if (now.text !== before.text || now.ino !== before.ino || now.mode !== before.mode) {
    throw new Error(`Target changed during deployment; rerun after other writers stop: ${path}`);
  }
}

function mergeJson(before, values, path) {
  let object = {};
  if (before.text !== undefined) {
    try { object = JSON.parse(before.text.replace(/^\uFEFF/u, "")); }
    catch { throw new Error(`Malformed JSON; repair manually before rerunning: ${path}`); }
    if (!object || typeof object !== "object" || Array.isArray(object)) {
      throw new Error(`Expected a JSON object: ${path}`);
    }
  }
  if (Object.entries(values).every(([key, value]) => object[key] === value)) return before.text;
  return `${JSON.stringify({ ...object, ...values }, null, 2)}\n`;
}

function acquireLock(fs, path) {
  checkPath(fs, path);
  try {
    // Pi uses proper-lockfile with realpath:false: an exclusive mkdir at
    // settings.json.lock, NOT an exclusive file. Never reclaim even stale locks.
    fs.mkdirSync(path, { mode: 0o700 });
  } catch (error) {
    if (error.code === "EEXIST") {
      throw new Error(`Busy lock (not reclaimed): ${path}. Close other writers, then rerun.`);
    }
    throw error;
  }
  const owned = fs.lstatSync(path);
  return () => {
    const current = checkPath(fs, path);
    if (!current?.isDirectory() || current.ino !== owned.ino) {
      throw new Error(`Lock ownership changed; leaving it untouched: ${path}`);
    }
    fs.rmdirSync(path);
  };
}

function atomicWrite(fs, path, before, text) {
  if (text === before.text) return;
  const temp = join(dirname(path), `.kali-${randomUUID()}.tmp`);
  let created = false;
  try {
    // Same-directory rename prevents partial JSON/files from being observed.
    fs.writeFileSync(temp, text, { flag: "wx", mode: 0o600 });
    created = true;
    fs.chmodSync(temp, before.mode);
    assertUnchanged(fs, path, before);
    fs.renameSync(temp, path);
    created = false;
  } finally {
    if (created) fs.unlinkSync(temp);
  }
}

function homePath(value, home) {
  if (value === "~") return home;
  if (value.startsWith("~/")) return join(home, value.slice(2));
  return resolve(value);
}

/** Deploy only our resource; injectable filesystem supports isolated fixtures. */
export function installKaliWidget({ fs = nodeFs, env = process.env, home = env.HOME,
  source = DEFAULT_SOURCE, log = console.log } = {}) {
  if (!home || !isAbsolute(home)) throw new Error("HOME must be an absolute directory");
  home = resolve(home);
  const normal = homePath(env.PI_CODING_AGENT_DIR || join(home, ".pi/agent"), home);
  const isolated = homePath(env.GENTLE_SHELL_HOME || join(home, ".gentle-shell/agent"), home);
  // This override belongs to shared Gentle AI configuration, NOT Pi's agent home.
  const config = homePath(env.GENTLE_PI_CONFIG_HOME || join(home, ".pi/gentle-ai"), home);
  const homes = [normal];
  const isolatedStat = checkPath(fs, isolated);
  if (!isolatedStat) {
    log(`Skipped absent isolated home ${isolated}. Run gentle-shell --isolated first (or --home "${isolated}" for a custom home), then rerun this installer or Home Manager switch.`);
  } else {
    if (!isolatedStat.isDirectory()) throw new Error(`Not a directory: ${isolated}`);
    const marker = checkPath(fs, join(isolated, ".gentle-shell-home"));
    if (marker?.isFile()) homes.push(isolated);
    else log(`Skipped isolated home ${isolated}: no regular .gentle-shell-home ownership marker. Complete launcher bootstrap before rerunning; do not create the marker manually.`);
  }
  if (!homes.includes(isolated, 1) && [normal, config].some((path) =>
    path === isolated || path.startsWith(`${isolated}/`))) {
    throw new Error("Configuration targets an unbootstrapped isolated home; refusing to create it");
  }
  const sourceStat = fs.lstatSync(source);
  if (!sourceStat.isFile() || sourceStat.isSymbolicLink()) throw new Error(`Invalid extension source: ${source}`);
  const extension = OWNED + fs.readFileSync(source, "utf8");
  const targets = [];
  for (const agent of new Set(homes)) {
    targets.push({ path: join(agent, "settings.json"), values: { quietStartup: true } });
    targets.push({ path: join(agent, "extensions/kali-widget.ts"), extension: true });
  }
  // Shell defaults each art flag independently; suppress both in one locked merge.
  targets.push({ path: join(config, "banner.json"), values: { showRose: false, showTextLogo: false } });

  // Preflight all targets before creating directories or changing any content.
  for (const target of targets) {
    target.before = snapshot(fs, target.path);
    if (checkPath(fs, `${target.path}.lock`)) throw new Error(`Busy lock (not reclaimed): ${target.path}.lock; close other writers and rerun.`);
    if (target.extension) {
      if (target.before.text !== undefined && !target.before.text.startsWith(OWNED)
        && target.before.text !== extension.slice(OWNED.length)) {
        throw new Error(`Refusing unowned extension collision: ${target.path}. Move it manually before rerunning.`);
      }
      target.text = extension;
    } else target.text = mergeJson(target.before, target.values, target.path);
  }

  const releases = [];
  try {
    for (const target of targets) {
      ensureDirectory(fs, dirname(target.path));
      releases.push(acquireLock(fs, `${target.path}.lock`));
    }
    // Recheck under the cooperative locks; preserve any edits completed between
    // preflight and acquisition rather than applying a stale JSON snapshot.
    for (const target of targets) {
      assertUnchanged(fs, target.path, target.before);
    }
    for (const target of targets) atomicWrite(fs, target.path, target.before, target.text);
    log(`Kali widget deployed to ${[...new Set(homes)].join(", ")}. Restart Pi/Gentle Shell to load it.`);
  } finally {
    const errors = [];
    for (const release of releases.reverse()) {
      try { release(); } catch (error) { errors.push(error); }
    }
    if (errors.length) throw new AggregateError(errors, "Could not release owned locks; inspect before rerunning");
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv.length > 3) throw new Error("Usage: node pi/install-kali-widget.mjs [extension-source]");
    installKaliWidget({ source: process.argv[2] || DEFAULT_SOURCE });
  } catch (error) {
    console.error(`Kali deployment stopped: ${error.message}`);
    process.exitCode = 1;
  }
}
