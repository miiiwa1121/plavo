// センサー値の保管
//
// PC 上で動き、ガジェットから受け取った値をアプリに配る（D35）。
// 展示中しか動かさないため、メモリに持つだけで永続化しない（D36）。
//
// 仕様は docs/design/gadget-interface.md

/** ガジェットが送ってくる1点。gadget-interface.md §3 のペイロード */
export type SensorPayload = {
  gadgetId: string;
  measuredAt: string;
  soilMoisture: { raw: number; percent: number };
  lightLux?: number | null;
  temperature?: number | null;
  humidity?: number | null;
  nutrientEc?: number | null;
  battery?: number | null;
};

/** 1秒に1回×数時間を想定し、それを超えたら古いものから捨てる */
const MAX_POINTS_PER_GADGET = 60 * 60 * 6;

const store = new Map<string, SensorPayload[]>();

export type ValidationError = { field: string; reason: string };

/**
 * 受け取った値を検証する。
 *
 * ハード担当がこのエンドポイントに向けて開発するため、
 * 何が足りないのかが分かるエラーを返す。
 */
export function validate(body: unknown): ValidationError[] {
  const errors: ValidationError[] = [];
  if (typeof body !== "object" || body === null) {
    return [{ field: "(body)", reason: "JSON オブジェクトである必要があります" }];
  }
  const b = body as Record<string, unknown>;

  if (typeof b.gadgetId !== "string" || b.gadgetId.length === 0) {
    errors.push({ field: "gadgetId", reason: "空でない文字列が必要です" });
  }

  if (typeof b.measuredAt !== "string" || Number.isNaN(Date.parse(b.measuredAt))) {
    errors.push({
      field: "measuredAt",
      reason: "ISO 8601 の日時が必要です（例: 2026-08-31T18:20:00+09:00）",
    });
  }

  const m = b.soilMoisture;
  if (typeof m !== "object" || m === null) {
    errors.push({
      field: "soilMoisture",
      reason: "{ raw: number, percent: number } が必要です",
    });
  } else {
    const mm = m as Record<string, unknown>;
    if (typeof mm.raw !== "number") {
      errors.push({ field: "soilMoisture.raw", reason: "センサーの生値（数値）が必要です" });
    }
    if (typeof mm.percent !== "number") {
      errors.push({ field: "soilMoisture.percent", reason: "0〜100 の数値が必要です" });
    } else if (mm.percent < 0 || mm.percent > 100) {
      errors.push({
        field: "soilMoisture.percent",
        reason: `0〜100 の範囲である必要があります（受信値: ${mm.percent}）`,
      });
    }
  }

  // 任意項目は、あれば型だけ見る
  for (const key of ["lightLux", "temperature", "humidity", "nutrientEc", "battery"]) {
    const v = b[key];
    if (v !== undefined && v !== null && typeof v !== "number") {
      errors.push({ field: key, reason: "数値または null が必要です" });
    }
  }

  return errors;
}

export function record(payload: SensorPayload): void {
  const list = store.get(payload.gadgetId) ?? [];
  list.push(payload);
  if (list.length > MAX_POINTS_PER_GADGET) {
    list.splice(0, list.length - MAX_POINTS_PER_GADGET);
  }
  store.set(payload.gadgetId, list);
}

export function latest(gadgetId?: string): SensorPayload | null {
  if (gadgetId) return store.get(gadgetId)?.at(-1) ?? null;
  // 指定がなければ、最後に更新されたものを返す。展示では1台しか使わない
  let newest: SensorPayload | null = null;
  for (const list of store.values()) {
    const last = list.at(-1);
    if (!last) continue;
    if (!newest || Date.parse(last.measuredAt) > Date.parse(newest.measuredAt)) {
      newest = last;
    }
  }
  return newest;
}

export function recent(gadgetId: string, seconds: number): SensorPayload[] {
  const list = store.get(gadgetId) ?? [];
  const cutoff = Date.now() - seconds * 1000;
  return list.filter((p) => Date.parse(p.measuredAt) >= cutoff);
}

export function gadgets(): { gadgetId: string; points: number; lastSeen: string }[] {
  return [...store.entries()].map(([gadgetId, list]) => ({
    gadgetId,
    points: list.length,
    lastSeen: list.at(-1)?.measuredAt ?? "—",
  }));
}

export function clear(): void {
  store.clear();
}
