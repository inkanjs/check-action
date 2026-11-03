// Turns `inkan check --json` and `inkan diff --json` into the Markdown of the
// PR comment and the job summary, and prints the step outputs as key=value.
// No dependencies: it runs on whatever node the runner has.
//
// node render.mjs --check check.json [--diff diff.json] [--base <label>] [--note <text>] --out report.md

import { readFileSync, writeFileSync } from "node:fs";

export const MARKER = "<!-- inkan-check -->";
const DOCS = "https://inkan-dev.vercel.app/docs/cli";

/** Text that GitHub must not read as Markdown or HTML. */
const md = (s) => String(s).replace(/\r?\n/g, " ").replace(/[\\`*_[\]<>|#~]/g, "\\$&");
/** Text inside a code span. */
const code = (s) => "`" + String(s).replace(/\r?\n/g, " ").replaceAll("`", "'").replaceAll("|", "\\|") + "`";
const plural = (n, one, many = one + "s") => `${n} ${n === 1 ? one : many}`;

/**
 * @param {{ ok: boolean, passed: number, failed: number, results: any[], unchecked: string[], uncovered: any[] } | undefined} check
 * @param {{ breaking: boolean, where: string, message: string }[] | undefined} changes undefined: nothing was compared
 * @param {{ base?: string, note?: string }} [info]
 */
export function render(check, changes, info = {}) {
  const breaking = (changes ?? []).filter((x) => x.breaking);
  const safe = (changes ?? []).filter((x) => !x.breaking);
  const lines = [MARKER, "## 印 inkan check", ""];

  const head = [];
  if (changes) head.push(breaking.length ? `**✗ ${plural(breaking.length, "breaking change")}**` : "**✓ nothing breaks a client**");
  if (changes && safe.length) head.push(plural(safe.length, "safe change"));
  if (check) {
    const examples = `examples: ${check.passed} passed, ${check.failed} failed`;
    head.push(check.ok ? examples : `**✗ ${examples}**`);
  }
  lines.push(head.join(" · "), "");
  if (info.note) lines.push(`> ${md(info.note)}`, "");

  const table = (title, list, mark) => {
    lines.push(`### ${title}`, "", "| | Route | Change |", "|---|---|---|");
    for (const x of list) lines.push(`| ${mark} | ${code(x.where)} | ${md(x.message)} |`);
    lines.push("");
  };
  if (breaking.length) table("Breaks clients", breaking, "✗");
  if (safe.length) table("Safe", safe, "·");

  if (check) {
    const failed = check.results.filter((r) => !r.ok);
    if (failed.length) {
      lines.push("### Examples that fail", "");
      for (const r of failed) {
        lines.push(`- ✗ ${code(`${r.method} ${r.path}`)} ${md(r.example)} (status ${r.status})`);
        for (const p of r.problems) lines.push(`  - ${md(p)}`);
      }
      lines.push("");
    }
    if (check.uncovered.length) {
      lines.push(`### Promised statuses no example covers${check.ok ? "" : " (--strict)"}`, "");
      for (const u of check.uncovered) lines.push(`- ${code(`${u.method} ${u.path}`)} ${u.status}`);
      lines.push("");
    }
    if (check.unchecked.length) {
      lines.push(`<details><summary>${plural(check.unchecked.length, "route")} without an example</summary>`, "");
      for (const r of check.unchecked) lines.push(`- ${code(r)}`);
      lines.push("", "</details>", "");
    }
  }

  const foot = [];
  if (changes) foot.push(`compared with ${info.base ? code(info.base) : "the base"}`);
  foot.push(`[what counts as breaking](${DOCS})`);
  lines.push(`<sub>${foot.join(" · ")}</sub>`, "");
  return {
    markdown: lines.join("\n"),
    outputs: {
      breaking: breaking.length,
      changes: (changes ?? []).length,
      "check-ok": check ? check.ok : false,
      compared: Boolean(changes),
      // worth a new PR comment: something broke, changed or failed
      noteworthy: Boolean((changes ?? []).length || (check && !check.ok) || info.note),
    },
  };
}

function args(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 2) {
    if (!argv[i].startsWith("--")) throw new Error(`unexpected argument ${argv[i]}`);
    out[argv[i].slice(2)] = argv[i + 1];
  }
  return out;
}

const readJson = (file, what) => {
  try {
    return JSON.parse(readFileSync(file, "utf8"));
  } catch (err) {
    throw new Error(`could not read the ${what} JSON (${file}): ${err.message}`);
  }
};

// run as a script (it can also be imported, for render() alone)
if (process.argv[1]?.replaceAll("\\", "/").endsWith("/render.mjs")) {
  const a = args(process.argv.slice(2));
  const check = a.check ? readJson(a.check, "inkan check --json") : undefined;
  const changes = a.diff ? readJson(a.diff, "inkan diff --json") : undefined;
  if (check && (typeof check.ok !== "boolean" || !Array.isArray(check.results))) throw new Error("inkan check --json gave a shape this action does not know");
  if (changes && !Array.isArray(changes)) throw new Error("inkan diff --json gave a shape this action does not know");
  const { markdown, outputs } = render(check, changes, { base: a.base, note: a.note });
  writeFileSync(a.out, markdown);
  for (const [k, v] of Object.entries(outputs)) console.log(`${k}=${v}`);
}
