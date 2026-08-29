// セリフのプールを規則で検証する
//
// D34 により展示は完全オフラインで動くため、来場者が目にするセリフは
// すべて content/dialogues/ に入っている。当日にAIを呼ばない以上、
// この中身が展示の質そのものになる。
//
// 人が数十本を目視でチェックするより、一人称代名詞や字数超過を
// 機械が弾くほうが確実。
//
// 実行: npm run check:dialogues

import { readFileSync, readdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { checkDialogue } from "../diagnosis/rules.js";

const here = dirname(fileURLToPath(import.meta.url));
const dialoguesDir = resolve(here, "../../../content/dialogues");

type Entry = { file: string; group: string; line: string };

function collect(): Entry[] {
  const entries: Entry[] = [];
  for (const file of readdirSync(dialoguesDir).filter((f) => f.endsWith(".json"))) {
    const data = JSON.parse(readFileSync(resolve(dialoguesDir, file), "utf-8"));

    if (Array.isArray(data.lines)) {
      for (const line of data.lines) entries.push({ file, group: data.id, line });
    }
    for (const band of data.bands ?? []) {
      for (const line of band.lines) entries.push({ file, group: band.key, line });
    }
    for (const panel of data.panels ?? []) {
      for (const line of panel.lines) entries.push({ file, group: panel.key, line });
    }
  }
  return entries;
}

const entries = collect();
let violations = 0;
const byFile = new Map<string, number>();

console.log(`セリフ ${entries.length} 本を検証します\n`);

for (const e of entries) {
  const vs = checkDialogue(e.line);
  byFile.set(e.file, (byFile.get(e.file) ?? 0) + 1);
  if (vs.length > 0) {
    violations += vs.length;
    console.log(`  違反  [${e.group}] 「${e.line}」`);
    for (const v of vs) console.log(`        ${v.rule} — ${v.detail}`);
  }
}

console.log("--- ファイル別 ---");
for (const [file, count] of byFile) console.log(`  ${file.padEnd(16)} ${count} 本`);

// 重複の検出。同じセリフが複数の帯域にあると、状態が違うのに同じことを言う。
//
// ただし沈黙（「……」のような記号だけの行）は例外とする。
// これはセリフの重複ではなく、消耗すると言葉が減るという設計（D30 第1層）の
// 一貫した現れであり、複数の状態に現れて正しい。
const isSilence = (line: string): boolean => /^[…・。、．\s]*$/u.test(line);

const seen = new Map<string, string[]>();
for (const e of entries) {
  if (isSilence(e.line)) continue;
  const list = seen.get(e.line) ?? [];
  list.push(e.group);
  seen.set(e.line, list);
}
const dupes = [...seen.entries()].filter(([, groups]) => groups.length > 1);

const silenceCount = entries.filter((e) => isSilence(e.line)).length;

console.log("\n--- 重複 ---");
if (dupes.length === 0) {
  console.log(`  なし（沈黙 ${silenceCount} 本は例外として除外）`);
} else {
  for (const [line, groups] of dupes) {
    console.log(`  「${line}」 が ${groups.join(", ")} に重複`);
  }
}

// 文字数の分布。40字は上限であり、実際は短いほうが吹き出しに収まる
const lengths = entries.map((e) => [...e.line].length);
const max = Math.max(...lengths);
const avg = lengths.reduce((a, b) => a + b, 0) / lengths.length;
console.log("\n--- 文字数 ---");
console.log(`  平均 ${avg.toFixed(1)}字 / 最長 ${max}字（上限40字）`);

console.log("\n" + "=".repeat(48));
console.log(`規則違反: ${violations} 件 / 重複: ${dupes.length} 件`);
if (violations > 0 || dupes.length > 0) process.exit(1);
