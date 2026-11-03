// Turns `inkan check --json` and `inkan diff --json` into the Markdown of the
// PR comment and the job summary, and prints the step outputs as key=value.
// With inkan 0.9.0 and newer, run.sh also passes what `--format markdown` wrote
// (--check-md, --diff-md), and that is used in place of the tables written here.
// No dependencies: it runs on whatever node the runner has.
//
// node render.mjs --check check.json [--diff diff.json] [--base <label>] [--note <text>]
//   [--check-md check.md] [--diff-md diff.md] --out report.md

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
 * @param {{ breaking: boolean, kind?: string, where: string, message: string }[] | undefined} changes undefined: nothing was compared
 * @param {{ base?: string, note?: string, checkMd?: string, diffMd?: string }} [info] checkMd, diffMd: the core's own Markdown (0.9.0+)
 */
export function render(check, changes, info = {}) {
  const breaking = (changes ?? []).filter((x) => x.breaking);
  const safe = (changes ?? []).filter((x) => !x.breaking);
  const lines = [MARKER, "## 印 inkan check", ""];

  // a part the core wrote Markdown for brings its own headline
  const head = [];
  if (changes && info.diffMd === undefined) head.push(breaking.length ? `**✗ ${plural(breaking.length, "breaking change")}**` : "**✓ nothing breaks a client**");
  if (changes && info.diffMd === undefined && safe.length) head.push(plural(safe.length, "safe change"));
  if (check && info.checkMd === undefined) {
    const examples = `examples: ${check.passed} passed, ${check.failed} failed`;
    head.push(check.ok ? examples : `**✗ ${examples}**`);
  }
  if (head.length) lines.push(head.join(" · "), "");
  if (info.note) lines.push(`> ${md(info.note)}`, "");

  // the core's diff heading names its input files, a temporary one among them
  if (info.diffMd !== undefined) lines.push(info.diffMd.trim().replace(/^### 印 inkan diff.*$/m, "### 印 inkan diff"), "");
  else {
    const kinds = (changes ?? []).some((x) => x.kind);
    const table = (title, list, mark) => {
      lines.push(`### ${title}`, "", kinds ? "| | Route | Change | Kind |" : "| | Route | Change |", kinds ? "|---|---|---|---|" : "|---|---|---|");
      for (const x of list) lines.push(`| ${mark} | ${code(x.where)} | ${md(x.message)} |${kinds ? ` ${x.kind ? code(x.kind) : ""} |` : ""}`);
      lines.push("");
    };
    if (breaking.length) table("Breaks clients", breaking, "✗");
    if (safe.length) table("Safe", safe, "·");
  }

  if (info.checkMd !== undefined) lines.push(info.checkMd.trim(), "");
  else if (check) {
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
  const text = (file) => (file ? readFileSync(file, "utf8") : undefined);
  const { markdown, outputs } = render(check, changes, { base: a.base, note: a.note, checkMd: text(a["check-md"]), diffMd: text(a["diff-md"]) });
  writeFileSync(a.out, markdown);
  for (const [k, v] of Object.entries(outputs)) console.log(`${k}=${v}`);
}
