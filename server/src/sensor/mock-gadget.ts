// モックのガジェット
//
// ハードウェアが無くても、端から端まで動作を確かめられるようにする。
// 実物ができたら、これと同じペイロードを同じエンドポイントへ送るだけでよい。
//
// 起動: npm run mock:gadget
//   引数: --url http://localhost:8787  送信先
//         --id gadget-001              ガジェットID
//         --interval 1000              送信間隔(ms)

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

// D25 のデモに合わせ、水切れの状態から始める
let percent = 15;
let raw = 380;

/** 乾く速さ（%/秒）。実際は数日かけて乾くが、検証では体感できる速さにする */
const dryingRate = 0.6;

function toRaw(p: number): number {
  // 静電容量式センサーの生値を模す。乾いているほど値が大きい向き
  return Math.round(900 - p * 5.2);
}

async function send(): Promise<void> {
  const payload = {
    gadgetId,
    measuredAt: new Date().toISOString(),
    soilMoisture: { raw, percent: Math.round(percent * 10) / 10 },
    lightLux: 12_400,
    temperature: 24.6,
    humidity: 52.1,
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
