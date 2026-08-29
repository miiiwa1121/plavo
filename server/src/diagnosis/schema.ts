// 診断の出力スキーマ
//
// D23 により、診断が返すのは「画像からしか取れない観測」と「セリフ」だけ。
// DLI・GDD・VPD・開花予測などの導出指標は含めない（元データから計算できるため）。
//
// 詳細は docs/design/diagnosis-prompt.md §4

import { z } from "zod/v4";

export const DiagnosisSchema = z.object({
  plantDetected: z.boolean().describe("画像に植物が写っているか"),
  stage: z
    .enum(["seed", "sprout", "trueLeaf", "bud", "bloom", "seedSet", "withered"])
    .describe("見た目から判断した生育段階"),
  appearances: z
    .array(z.string())
    .describe("画像から見えたことだけを、具体的に。主観を混ぜない"),
  heightCm: z.number().nullable().describe("草丈の推定。判断できなければ null"),
  confidence: z.enum(["low", "medium", "high"]).describe("この観察がどれだけ確かか"),
  dialogue: z
    .string()
    .describe("植物が言うこと。1〜2文、40字以内。一人称代名詞と数値を使わない"),
});

export type Diagnosis = z.infer<typeof DiagnosisSchema>;
