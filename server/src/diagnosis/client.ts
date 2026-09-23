// 診断クライアント
//
// Claude に画像とセンサーの文脈を渡し、観測とセリフを受け取る。
// このコードはいずれプロキシ（アプリからAPIキーを隠す中継）に育つ。
//
// 詳細は docs/design/diagnosis-prompt.md §2 / §9

import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import type { DiagnosisContext } from "../domain/types.js";
import { DEFAULT_PROFILE, type PlantProfile } from "../domain/profile.js";
import { buildContextBlock } from "../domain/summarize.js";
import { buildSystemPrompt } from "./prompt.js";
import { DiagnosisSchema, type Diagnosis } from "./schema.js";

export const MODEL = "claude-opus-5";

/** 20秒を超えたら事前定義セリフへフォールバックする（D28） */
const DEFAULT_TIMEOUT_MS = 20_000;

/**
 * API の呼び出し口。**1つを使い回す。**呼ぶたびに作ると、接続の使い回しが効かない。
 * 最初に呼ばれたときに作るのは、`--dry-run` のように API を呼ばない使い方で
 * 認証情報を要求しないため
 */
let sharedClient: Anthropic | undefined;
function client(): Anthropic {
  sharedClient ??= new Anthropic();
  return sharedClient;
}

export type DiagnoseOptions = {
  /** 品質とレイテンシと費用の折衷。実測して調整する（P-1） */
  effort?: "low" | "medium" | "high";
  /** 20秒を超えたら事前定義セリフへフォールバックする（D28） */
  timeoutMs?: number;
  /** 展示に使う植物のプロファイル。未指定なら既定 */
  profile?: PlantProfile;
};

export type DiagnoseResult = {
  diagnosis: Diagnosis;
  usage: {
    inputTokens: number;
    outputTokens: number;
    cacheCreationTokens: number;
    cacheReadTokens: number;
  };
  elapsedMs: number;
};

/** 画像とセンサーの文脈から、観測とセリフを得る */
export async function diagnose(
  ctx: DiagnosisContext,
  imageBase64: string,
  mediaType: "image/jpeg" | "image/png",
  options: DiagnoseOptions = {},
): Promise<DiagnoseResult> {
  const profile = options.profile ?? DEFAULT_PROFILE;
  const started = Date.now();

  const response = await client().messages.parse(
    {
      model: MODEL,
      max_tokens: 8000,
      // システムプロンプトは不変なのでキャッシュする。
      // 可変部分（文脈と画像）は必ずこの後ろに置く。
      system: [
        {
          type: "text",
          text: buildSystemPrompt(profile),
          cache_control: { type: "ephemeral" },
        },
      ],
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image",
              source: { type: "base64", media_type: mediaType, data: imageBase64 },
            },
            { type: "text", text: buildContextBlock(ctx, profile) },
          ],
        },
      ],
      thinking: { type: "adaptive" },
      output_config: {
        effort: options.effort ?? "medium",
        format: zodOutputFormat(DiagnosisSchema),
      },
    },
    { timeout: options.timeoutMs ?? DEFAULT_TIMEOUT_MS },
  );

  // 想定外のレスポンスはすべてフォールバック対象にする（D28）。
  // 植物の写真で拒否が起きることはまずないが、無言になるのが最悪なので防御的に扱う。
  if (response.stop_reason === "refusal") {
    throw new Error(
      `診断が拒否されました: ${response.stop_details?.explanation ?? "理由なし"}`,
    );
  }
  if (!response.parsed_output) {
    throw new Error(`構造化出力の解析に失敗しました (stop_reason=${response.stop_reason})`);
  }

  return {
    diagnosis: response.parsed_output,
    usage: {
      inputTokens: response.usage.input_tokens,
      outputTokens: response.usage.output_tokens,
      cacheCreationTokens: response.usage.cache_creation_input_tokens ?? 0,
      cacheReadTokens: response.usage.cache_read_input_tokens ?? 0,
    },
    elapsedMs: Date.now() - started,
  };
}

/**
 * MODEL の料金（100万トークンあたりのドル）。**モデルを変えたらここも直す。**
 * キャッシュは入力の料金に倍率を掛ける（書き込みは5分の保持で 1.25 倍、読み出しは 0.1 倍）
 */
const PRICE_USD_PER_MTOK = { input: 5, output: 25 } as const;
const CACHE_WRITE_MULTIPLIER = 1.25;
const CACHE_READ_MULTIPLIER = 0.1;

/** 1回あたりの費用を概算する */
export function estimateCostUsd(usage: DiagnoseResult["usage"]): number {
  const perToken = (usdPerMTok: number) => usdPerMTok / 1_000_000;
  const input = perToken(PRICE_USD_PER_MTOK.input);
  return (
    usage.inputTokens * input +
    usage.cacheCreationTokens * input * CACHE_WRITE_MULTIPLIER +
    usage.cacheReadTokens * input * CACHE_READ_MULTIPLIER +
    usage.outputTokens * perToken(PRICE_USD_PER_MTOK.output)
  );
}
