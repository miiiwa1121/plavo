// 紹介動画の素材を撮る。
//
// 1. アプリと台本（UIテスト DemoTourTests）をビルドする
// 2. シミュレータの画面の録画を始める
// 3. 台本を流す。指の跡はアプリ自身が描く（-showTouches YES・TouchIndicator.swift）
// 4. 録画を止め、Remotion で扱いやすい一定のフレームレートの mp4 に直す
//
// 使い方: npm run record            … アプリの各タブ（testDemoTour）→ public/tour.mp4
//         npm run record -- camera  … カメラ（testCameraTour・デモカメラ）→ public/camera.mp4
//         npm run record -- flipbook … ひまりのパラパラ（testFlipbookTour）→ public/flipbook.mp4
//
// 撮り直したら、場面の切り出し位置（src/cuts.ts）を録画に合わせて見直すこと。
// 台本の間が同じでも、ビルドや読み込みの具合で数百ミリ秒ずつ前後する
//
//   シミュレータを選ぶ: DEVICE_ID=<UDID> npm run record（既定は iPhone 17 の新しいもの）

import { execFileSync, spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const videoDir = join(dirname(fileURLToPath(import.meta.url)), "..");
const iosDir = join(videoDir, "../ios/PlavoApp");
const derivedData = join(iosDir, "build/dd");
const takes = {
  tour: { test: "testDemoTour", output: "public/tour.mp4" },
  // センサーの値（D64）は server の中継サーバーとモックのガジェットが届ける。アプリは刺した瞬間に取りに来る
  camera: { test: "testCameraTour", output: "public/camera.mp4", sensor: true },
  flipbook: { test: "testFlipbookTour", output: "public/flipbook.mp4" },
};
const takeName = process.argv[2] ?? "tour";
const take = takes[takeName];
if (!take) throw new Error(`知らない撮影です: ${takeName}（${Object.keys(takes).join(" / ")}）`);
const rawPath = join(videoDir, `recordings/${takeName}.mov`);
const outputPath = join(videoDir, take.output);
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

// センサーの中継サーバーとモックのガジェットを立ち上げる（カメラの撮影だけ）。
// ガジェットは水をあげた直後（72%）・日向の明るさから始め、ほとんど乾かさない。気温・湿度・光量は毎回少し揺れる
const serverDir = join(videoDir, "../server");
const helpers = [];
if (take.sensor) {
  helpers.push(spawn("npx", ["tsx", "src/sensor/server.ts"], { cwd: serverDir, stdio: "ignore" }));
  for (let i = 0; ; i++) {
    const ok = await fetch("http://localhost:8787/health").then((r) => r.ok).catch(() => false);
    if (ok) break;
    if (i > 50) throw new Error("センサーの中継サーバーが立ち上がりませんでした");
    await new Promise((r) => setTimeout(r, 200));
  }
  helpers.push(spawn("npx", ["tsx", "src/sensor/mock-gadget.ts",
    "--percent", "72", "--drying", "0.05", "--lux", "18000", "--jitter"], { cwd: serverDir, stdio: ["pipe", "ignore", "ignore"] }));
  console.log("センサーの中継サーバーとモックのガジェットを立ち上げました");
}
const stopHelpers = () => helpers.forEach((p) => p.exitCode === null && p.kill("SIGINT"));
process.on("exit", stopHelpers);

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

// **台本が途中で失敗しても録画は止める。**止めないと録画のプロセスが残り、次の撮影が始まらない
const stopRecording = async () => {
  if (recorder.exitCode !== null) return;
  recorder.kill("SIGINT");
  await new Promise((r) => recorder.on("exit", r));
};

await new Promise((resolve, reject) => {
  const test = spawn("xcodebuild", [...xcodebuildArgs, "test-without-building",
    `-only-testing:PlavoAppUITests/DemoTourTests/${take.test}`], { cwd: iosDir, stdio: "ignore" });
  test.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(`台本が最後まで通りませんでした (${code})`))));
}).catch(async (error) => {
  await stopRecording();
  stopHelpers();
  throw error;
});
stopHelpers();

// 最後の画面を少し残してから止める
await new Promise((r) => setTimeout(r, 1000));
await stopRecording();

console.log("書き出し中…");
// simctl の録画は画面が変わったときだけフレームを持つ（可変フレームレート）。一定に直す
run("ffmpeg", ["-loglevel", "error", "-y", "-i", rawPath,
  "-vf", `fps=${fps}`, "-c:v", "libx264", "-crf", "18", "-preset", "slow", "-pix_fmt", "yuv420p",
  outputPath]);
const duration = Number(run("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
  outputPath]).trim());

console.log(`できました: ${take.output}（${duration.toFixed(1)} 秒）`);
