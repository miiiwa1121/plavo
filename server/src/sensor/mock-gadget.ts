// モックのガジェット
//
// ハードウェアが無くても、端から端まで動作を確かめられるようにする。
// 実物ができたら、これと同じペイロードを同じエンドポイントへ送るだけでよい。
//
// 起動: npm run mock:gadget
//   引数: --url http://localhost:8787  送信先
//         --id gadget-001              ガジェットID
//         --interval 1000              送信間隔(ms)
//         --percent 15                 土の湿りの始まり(%)。既定は水切れ（D25）
//         --drying 0.6                 乾く速さ(%/秒)
//         --lux 12400                  光量(lx)
//         --jitter                     気温・湿度・光量を毎回少し揺らす（紹介動画で「届き続けている」を見せる）

const args = process.argv.slice(2);
function arg(name: string, fallback: string): string {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? (args[i + 1] ?? fallback) : fallback;
}

const url = arg("url", "http://localhost:8787");
const gadgetId = arg("id", "gadget-001");
const interval = Number(arg("interval", "1000"));
// 数でない値を渡すと setInterval が 1ms 間隔になり、中継サーバーへ送り続けてしまう
if (!Number.isFinite(interval) || interval < 100) {
  console.error(`--interval は100以上のミリ秒で指定してください（受け取った値: ${arg("interval", "")}）`);
  process.exit(1);
}

/** Enter 1回の水やりで上がる量（ポイント）。アプリのモック操作と同じ */
const WATERING_JUMP = 45;

/** 数の引数。数でなければ止める（下の --interval と同じ理由） */
function numberArg(name: string, fallback: number): number {
  const value = Number(arg(name, String(fallback)));
  if (!Number.isFinite(value)) {
    console.error(`--${name} は数で指定してください（受け取った値: ${arg(name, "")}）`);
    process.exit(1);
  }
  return value;
}

// 既定は D25 のデモに合わせ、水切れの状態から始める
let percent = numberArg("percent", 15);
let raw = toRaw(percent);

/** 乾く速さ（%/秒）。実際は数日かけて乾くが、検証では体感できる速さにする */
const dryingRate = numberArg("drying", 0.6);
const baseLux = numberArg("lux", 12_400);
const jitter = args.includes("--jitter");
/** 揺らす量。jitter のときだけ、中心の値のまわりで小さく動かす */
const wobble = (center: number, amount: number, digits: number) => {
  if (!jitter) return center;
  const value = center + (Math.random() * 2 - 1) * amount;
  const scale = 10 ** digits;
  return Math.round(value * scale) / scale;
};

function toRaw(p: number): number {
  // 静電容量式センサーの生値を模す。乾いているほど値が大きい向き
  return Math.round(900 - p * 5.2);
}

async function send(): Promise<void> {
  const payload = {
    gadgetId,
    measuredAt: new Date().toISOString(),
    soilMoisture: { raw, percent: Math.round(percent * 10) / 10 },
    lightLux: Math.round(wobble(baseLux, baseLux * 0.02, 0)),
    temperature: wobble(24.6, 0.2, 1),
    humidity: wobble(52.1, 0.6, 1),
    nutrientEc: 1.4,
    battery: 87,
  };
  try {
    const res = await fetch(`${url}/sensor`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    if (!res.ok) {
      console.log(`送信失敗 ${res.status}: ${await res.text()}`);
    }
  } catch (e) {
    console.log(`接続できません: ${e instanceof Error ? e.message : e}`);
  }
}

// 標準入力で水やりを起こせるようにする。Enter を押すと跳ね上がる
process.stdin.setEncoding("utf-8");
process.stdin.on("data", () => {
  percent = Math.min(100, percent + WATERING_JUMP);
  raw = toRaw(percent);
  console.log(`水やり → ${percent.toFixed(1)}%`);
});

console.log(`モックガジェットを起動しました → ${url}`);
console.log(`  ID: ${gadgetId} / 送信間隔: ${interval}ms`);
console.log(`  Enter を押すと水やりが起きます\n`);

setInterval(async () => {
  percent = Math.max(0, percent - dryingRate * (interval / 1000));
  raw = toRaw(percent);
  await send();
  process.stdout.write(`\r土の湿り ${percent.toFixed(1)}%  (raw ${raw})     `);
}, interval);
