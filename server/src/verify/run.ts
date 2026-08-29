// 診断プロンプトの検証ハーネス
//
// docs/design/diagnosis-prompt.md §10 の手順を実行する。
// 実機もカメラもARも不要で、プロンプトの精度だけを単体で確かめられる。
//
// 使い方:
//   npm run verify -- --dry-run            送信内容だけ確認（API不要）
//   npm run verify                         全シナリオを実行
//   npm run verify -- --scenario healthy    1件だけ実行
//   npm run verify -- --repeat 5           同じ入力を5回投げて多様性を見る
//
// 画像は fixtures/images/<scenario>.jpg に置く。

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, extname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { Scenario } from "../domain/types.js";
import { buildContextBlock } from "../domain/summarize.js";
import { SYSTEM_PROMPT } from "../diagnosis/prompt.js";
import { diagnose, estimateCostUsd, MODEL } from "../diagnosis/client.js";
import { checkAppearances, checkDialogue } from "../diagnosis/rules.js";

const here = dirname(fileURLToPath(import.meta.url));
const sensorsDir = resolve(here, "../../fixtures/sensors");
const imagesDir = resolve(here, "../../fixtures/images");

// --- 引数 -----------------------------------------------------------------
const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const scenarioArg = args[args.indexOf("--scenario") + 1];
const only = args.includes("--scenario") ? scenarioArg : undefined;
const repeatArg = args[args.indexOf("--repeat") + 1];
const repeat = args.includes("--repeat") ? Number(repeatArg) : 1;

// --- シナリオの読み込み ---------------------------------------------------
const names = readdirSync(sensorsDir)
  .filter((f) => f.endsWith(".json"))
  .map((f) => f.replace(/\.json$/, ""))
  .filter((n) => !only || n === only);

if (names.length === 0) {
  console.error(`シナリオが見つかりません（--scenario ${only ?? ""}）`);
  process.exit(1);
}

function loadScenario(name: string): Scenario {
  return JSON.parse(readFileSync(resolve(sensorsDir, `${name}.json`), "utf-8"));
}

function findImage(name: string): { path: string; mediaType: "image/jpeg" | "image/png" } | null {
  for (const ext of [".jpg", ".jpeg", ".png"]) {
    const p = resolve(imagesDir, `${name}${ext}`);
    if (existsSync(p)) {
      return { path: p, mediaType: ext === ".png" ? "image/png" : "image/jpeg" };
    }
  }
  return null;
}

// --- ドライラン -----------------------------------------------------------
if (dryRun) {
  console.log(`モデル: ${MODEL}`);
  console.log(`システムプロンプト: ${SYSTEM_PROMPT.length}字（キャッシュ対象）\n`);
  for (const name of names) {
    const s = loadScenario(name);
    const img = findImage(name);
    console.log("=".repeat(72));
    console.log(`シナリオ: ${name}`);
    console.log(`画像: ${img ? img.path : "なし（fixtures/images/ に置いてください）"}`);
    console.log("=".repeat(72));
    console.log(buildContextBlock(s));
    console.log("\n--- 人が先に書いた期待値（プロンプトには渡さない） ---");
    console.log(`段階: ${s.expectation.stage}`);
    console.log(`見えるはず: ${s.expectation.appearanceHints.join(" / ")}`);
    console.log(`セリフの意図: ${s.expectation.dialogueIntent}`);
    console.log(`確信度: ${s.expectation.confidence}\n`);
  }
  process.exit(0);
}

// --- 実行 -----------------------------------------------------------------
const missingImages = names.filter((n) => findImage(n) === null);
if (missingImages.length > 0) {
  console.error(`画像がありません: ${missingImages.join(", ")}`);
  console.error(`fixtures/images/<シナリオ名>.jpg を置いてください。`);
  console.error(`送信内容だけ確認する場合は --dry-run を使ってください。`);
  process.exit(1);
}

let totalCost = 0;
let totalViolations = 0;
const dialogues: Record<string, string[]> = {};

for (const name of names) {
  const s = loadScenario(name);
  const img = findImage(name)!;
  const base64 = readFileSync(img.path).toString("base64");

  console.log("\n" + "=".repeat(72));
  console.log(`シナリオ: ${name}`);
  console.log("=".repeat(72));
  console.log(`期待する段階: ${s.expectation.stage}`);
  console.log(`見えるはず: ${s.expectation.appearanceHints.join(" / ")}`);
  console.log(`セリフの意図: ${s.expectation.dialogueIntent}`);
  console.log("");

  dialogues[name] = [];

  for (let i = 0; i < repeat; i++) {
    try {
      const r = await diagnose(s, base64, img.mediaType);
      const d = r.diagnosis;
      const cost = estimateCostUsd(r.usage);
      totalCost += cost;

      const stageOk = d.stage === s.expectation.stage;
      const confOk = d.confidence === s.expectation.confidence;

      console.log(`[${i + 1}/${repeat}] ${r.elapsedMs}ms  $${cost.toFixed(4)}`);
      console.log(`  植物: ${d.plantDetected ? "検出" : "未検出"}`);
      console.log(`  段階: ${d.stage} ${stageOk ? "✓" : `✗ 期待 ${s.expectation.stage}`}`);
      console.log(`  確信度: ${d.confidence} ${confOk ? "✓" : `（期待 ${s.expectation.confidence}）`}`);
      console.log(`  草丈: ${d.heightCm ?? "—"}`);
      console.log(`  見えたこと:`);
      for (const a of d.appearances) console.log(`    - ${a}`);
      console.log(`  セリフ: 「${d.dialogue}」（${[...d.dialogue].length}字）`);

      const violations = [...checkDialogue(d.dialogue), ...checkAppearances(d.appearances)];
      totalViolations += violations.length;
      if (violations.length === 0) {
        console.log(`  規則: 違反なし`);
      } else {
        for (const v of violations) console.log(`  規則違反: ${v.rule} — ${v.detail}`);
      }

      console.log(
        `  トークン: in ${r.usage.inputTokens} / out ${r.usage.outputTokens} / ` +
          `キャッシュ書込 ${r.usage.cacheCreationTokens} 読出 ${r.usage.cacheReadTokens}`,
      );
      dialogues[name]!.push(d.dialogue);
    } catch (e) {
      console.log(`[${i + 1}/${repeat}] 失敗: ${e instanceof Error ? e.message : String(e)}`);
    }
  }
}

// --- 多様性の確認 ---------------------------------------------------------
if (repeat > 1) {
  console.log("\n" + "=".repeat(72));
  console.log("多様性（同じ入力での言い回しの重複）");
  console.log("=".repeat(72));
  for (const [name, list] of Object.entries(dialogues)) {
    const unique = new Set(list).size;
    console.log(`${name.padEnd(16)} ${unique}/${list.length} 種類 ${unique === list.length ? "✓" : "✗ 重複あり"}`);
  }
}

console.log("\n" + "=".repeat(72));
console.log(`合計費用: $${totalCost.toFixed(4)}（約${Math.round(totalCost * 150)}円）`);
console.log(`規則違反: ${totalViolations} 件`);
