// センサー中継サーバー
//
// ガジェット → USB → PC（ここ）→ ローカルHTTP → スマホ（D35）。
// 会場のWi-Fiは使わず、スマホのテザリングでローカルネットワークを作る。
//
// 起動: npm run sensor
// 仕様: docs/design/gadget-interface.md

import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { networkInterfaces } from "node:os";
import { clear, gadgets, latest, recent, record, validate } from "./store.js";
import type { SensorPayload } from "./store.js";

const PORT = Number(process.env.PORT ?? 8787);

/**
 * 受け取る本文の上限。1点のペイロードは 300 バイトほどなので、十分に余裕がある。
 * **上限を置かないと、同じネットワークの誰かが巨大な本文を送るだけでメモリを食い尽くせる。**
 */
const MAX_BODY_BYTES = 16 * 1024;

/** `/sensor/recent` で秒数を省いたときに返す長さ */
const DEFAULT_RECENT_SECONDS = 300;

/** 本文が上限を超えた */
class PayloadTooLargeError extends Error {}

function json(res: ServerResponse, status: number, body: unknown): void {
  const text = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(text),
  });
  res.end(text);
}

/** 本文を JSON として読む。空なら null、壊れていれば undefined */
async function readBody(req: IncomingMessage): Promise<unknown> {
  const declared = Number(req.headers["content-length"]);
  if (declared > MAX_BODY_BYTES) throw new PayloadTooLargeError();

  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    size += (chunk as Buffer).length;
    // Content-Length を偽って送られても、読んだ量で止める
    if (size > MAX_BODY_BYTES) throw new PayloadTooLargeError();
    chunks.push(chunk as Buffer);
  }
  if (chunks.length === 0) return null;
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf-8"));
  } catch {
    return undefined; // 壊れた JSON
  }
}

async function route(req: IncomingMessage, res: ServerResponse): Promise<void> {
  // **基準の URL に Host ヘッダを使わない。**壊れた Host で URL の組み立てが例外を投げる
  let url: URL;
  try {
    url = new URL(req.url ?? "/", "http://localhost");
  } catch {
    return json(res, 400, { error: "パスを読めませんでした" });
  }

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
    const seconds = Number(url.searchParams.get("seconds") ?? DEFAULT_RECENT_SECONDS);
    if (!Number.isFinite(seconds) || seconds <= 0) {
      return json(res, 400, { error: "seconds は正の数が必要です" });
    }
    return json(res, 200, recent(gadgetId, seconds));
  }

  // 展示で次の来場者に移るときに使う
  if (req.method === "POST" && url.pathname === "/reset") {
    clear();
    res.writeHead(204).end();
    return;
  }

  json(res, 404, { error: "そのパスはありません" });
}

/**
 * 1件の失敗でサーバーを落とさない。
 *
 * **非同期の処理で投げられた例外は、拾わないとプロセスごと終わる**（Node の既定）。
 * 途中で切れた送信や、壊れたリクエスト1つで展示中の中継が止まってしまう。
 */
const server = createServer((req, res) => {
  route(req, res).catch((error: unknown) => {
    if (error instanceof PayloadTooLargeError) {
      // 残りを読まずに接続を閉じる。読み続けると上限を置いた意味が無い
      res.setHeader("Connection", "close");
      return json(res, 413, { error: `本文は ${MAX_BODY_BYTES} バイトまでです` });
    }
    console.error(`リクエストの処理に失敗しました: ${req.method} ${req.url}`, error);
    if (res.headersSent) {
      res.destroy();
    } else {
      json(res, 500, { error: "サーバーの内部で失敗しました" });
    }
  });
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
