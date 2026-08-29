// センサー中継サーバー
//
// ガジェット → USB → PC（ここ）→ ローカルHTTP → スマホ（D35）。
// 会場のWi-Fiは使わず、スマホのテザリングでローカルネットワークを作る。
//
// 起動: npm run sensor
// 仕様: docs/design/gadget-interface.md

import { createServer } from "node:http";
import { networkInterfaces } from "node:os";
import { clear, gadgets, latest, recent, record, validate } from "./store.js";
import type { SensorPayload } from "./store.js";

const PORT = Number(process.env.PORT ?? 8787);

function json(res: import("node:http").ServerResponse, status: number, body: unknown): void {
  const text = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(text),
  });
  res.end(text);
}

async function readBody(req: import("node:http").IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  if (chunks.length === 0) return null;
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf-8"));
  } catch {
    return undefined; // 壊れた JSON
  }
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", `http://${req.headers.host}`);

  // アプリが疎通を確かめるために叩く
  if (req.method === "GET" && url.pathname === "/health") {
    return json(res, 200, { ok: true, gadgets: gadgets() });
  }

  if (req.method === "POST" && url.pathname === "/sensor") {
    const body = await readBody(req);
    if (body === undefined) {
      return json(res, 400, { error: "JSON として読めませんでした" });
    }
    const errors = validate(body);
    if (errors.length > 0) {
      return json(res, 400, { error: "ペイロードが仕様と合いません", details: errors });
    }
    record(body as SensorPayload);
    res.writeHead(204).end();
    return;
  }

  if (req.method === "GET" && url.pathname === "/sensor/latest") {
    const gadgetId = url.searchParams.get("gadgetId") ?? undefined;
    const point = latest(gadgetId);
    if (!point) return json(res, 404, { error: "まだ受信していません" });
    return json(res, 200, point);
  }

  if (req.method === "GET" && url.pathname === "/sensor/recent") {
    const gadgetId = url.searchParams.get("gadgetId");
    if (!gadgetId) return json(res, 400, { error: "gadgetId が必要です" });
    const seconds = Number(url.searchParams.get("seconds") ?? 300);
    return json(res, 200, recent(gadgetId, seconds));
  }

  // 展示で次の来場者に移るときに使う
  if (req.method === "POST" && url.pathname === "/reset") {
    clear();
    res.writeHead(204).end();
    return;
  }

  json(res, 404, { error: "そのパスはありません" });
});

/** スマホから繋ぐためのアドレスを表示する。テザリング経由のIPを探す */
function localAddresses(): string[] {
  const out: string[] = [];
  for (const list of Object.values(networkInterfaces())) {
    for (const net of list ?? []) {
      if (net.family === "IPv4" && !net.internal) out.push(net.address);
    }
  }
  return out;
}

server.listen(PORT, () => {
  console.log(`センサー中継サーバーを起動しました  http://localhost:${PORT}`);
  const addresses = localAddresses();
  if (addresses.length > 0) {
    console.log("\nスマホからは以下のいずれかで繋ぎます:");
    for (const a of addresses) console.log(`  http://${a}:${PORT}`);
  } else {
    console.log("\n外部から繋げるアドレスが見つかりません。テザリングを確認してください。");
  }
  console.log("\nエンドポイント:");
  console.log("  POST /sensor              ガジェットからの受信");
  console.log("  GET  /sensor/latest       最新の1点");
  console.log("  GET  /sensor/recent       直近N秒分");
  console.log("  GET  /health              疎通確認");
  console.log("  POST /reset               記録を消す");
});
