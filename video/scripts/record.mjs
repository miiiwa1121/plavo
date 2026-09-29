// 紹介動画の素材を撮る。
//
// 1. アプリと台本（UIテスト DemoTourTests）をビルドする
// 2. シミュレータの画面の録画を始める
// 3. 台本を流す。指の跡はアプリ自身が描く（-showTouches YES・TouchIndicator.swift）
// 4. 録画を止め、Remotion で扱いやすい一定のフレームレートの mp4 に直す
//
// 出力: public/tour.mp4
//
// 撮り直したら、場面の切り出し位置（src/cuts.ts）を録画に合わせて見直すこと。
// 台本の間が同じでも、ビルドや読み込みの具合で数百ミリ秒ずつ前後する
//
// 使い方: npm run record
//   シミュレータを選ぶ: DEVICE_ID=<UDID> npm run record（既定は iPhone 17 の新しいもの）

import { execFileSync, spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const videoDir = join(dirname(fileURLToPath(import.meta.url)), "..");
const iosDir = join(videoDir, "../ios/PlavoApp");
const derivedData = join(iosDir, "build/dd");
const rawPath = join(videoDir, "recordings/raw.mov");
const fps = 30;

function run(cmd, args, options = {}) {
  return execFileSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"], ...options });
}

function pickDevice() {
  if (process.env.DEVICE_ID) return process.env.DEVICE_ID;
  const { devices } = JSON.parse(run("xcrun", ["simctl", "list", "devices", "available", "-j"]));
  const runtimes = Object.keys(devices).filter((r) => r.includes("iOS")).sort().reverse();
  for (const runtime of runtimes) {
    const device = devices[runtime].find((d) => d.name === "iPhone 17");
    if (device) return device.udid;
  }
  throw new Error("iPhone 17 のシミュレータが見つかりません。DEVICE_ID で指定してください");
}

const device = pickDevice();
console.log(`シミュレータ: ${device}`);

try {
  run("xcrun", ["simctl", "boot", device], { stdio: "ignore" });
} catch {
  // 起動済み
}
run("xcrun", ["simctl", "bootstatus", device, "-b"]);
// 時刻と電池の表示を固定する。撮るたびに違うと、つなぎ目で目に付く
run("xcrun", ["simctl", "status_bar", device, "override",
  "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
  "--cellularBars", "4", "--wifiBars", "3"]);

console.log("ビルド中…");
run("xcodegen", ["generate"], { cwd: iosDir });
const xcodebuildArgs = [
  "-project", "PlavoApp.xcodeproj", "-scheme", "PlavoApp",
  "-destination", `id=${device}`, "-derivedDataPath", derivedData,
];
run("xcodebuild", [...xcodebuildArgs, "build-for-testing", "-quiet"], { cwd: iosDir, stdio: ["ignore", "ignore", "inherit"] });

// 録画を始める
mkdirSync(dirname(rawPath), { recursive: true });
const recorder = spawn("xcrun", ["simctl", "io", device, "recordVideo", "--codec=h264", "--force", rawPath]);
await new Promise((resolve, reject) => {
  const onData = (chunk) => {
    if (chunk.toString().includes("Recording started")) resolve();
  };
  recorder.stderr.on("data", onData);
  recorder.stdout.on("data", onData);
  recorder.on("exit", (code) => reject(new Error(`録画が始まりませんでした (${code})`)));
});
console.log("録画を始めました。台本を流します…");

await new Promise((resolve, reject) => {
  const test = spawn("xcodebuild", [...xcodebuildArgs, "test-without-building",
    "-only-testing:PlavoAppUITests/DemoTourTests"], { cwd: iosDir, stdio: "ignore" });
  test.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(`台本が最後まで通りませんでした (${code})`))));
});

// 最後の画面を少し残してから止める
await new Promise((r) => setTimeout(r, 1000));
recorder.kill("SIGINT");
await new Promise((r) => recorder.on("exit", r));

console.log("書き出し中…");
// simctl の録画は画面が変わったときだけフレームを持つ（可変フレームレート）。一定に直す
run("ffmpeg", ["-loglevel", "error", "-y", "-i", rawPath,
  "-vf", `fps=${fps}`, "-c:v", "libx264", "-crf", "14", "-preset", "slow", "-pix_fmt", "yuv420p",
  join(videoDir, "public/tour.mp4")]);
const duration = Number(run("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
  join(videoDir, "public/tour.mp4")]).trim());

console.log(`できました: public/tour.mp4（${duration.toFixed(1)} 秒）`);
