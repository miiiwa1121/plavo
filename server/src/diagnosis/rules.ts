// セリフの規則チェック
//
// システムプロンプトで規則を課しているが、モデルが自然な文を書こうとすると外れやすい。
// 特に一人称代名詞の禁止と字数制限は破られやすいと予想している（P-2）。
// 自動で検出できるようにしておき、違反率を計測できる状態にする。
//
// 詳細は docs/design/diagnosis-prompt.md §10

export type RuleViolation = { rule: string; detail: string };

/** D31: 一人称代名詞を使わない */
const PRONOUNS = ["ぼく", "僕", "わたし", "私", "おれ", "俺", "自分", "あたし", "わし"];

/** 原則2: 計測値そのものを言わない */
const MEASUREMENT_PATTERNS: { re: RegExp; label: string }[] = [
  { re: /\d+\s*%/, label: "パーセント表記" },
  { re: /\d+\s*(℃|°C|度)/, label: "気温表記" },
  { re: /\d+\s*(ルクス|lux|lx)/i, label: "照度表記" },
  { re: /\d+\s*(mol|kPa|mS|EC)/i, label: "単位付きの計測値" },
];

const EMOJI =
  /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{2190}-\u{21FF}]|[（(][^）)]{0,6}[｀´ω・ｰ^][^）)]{0,6}[）)]/u;

/** D30: ユーザーを責めない */
const BLAMING = [
  "くれなかった",
  "してくれない",
  "気づいてほしかった",
  "遅かった",
  "忘れてた",
  "放っておかれ",
  "ほったらかし",
];

/** ユーザーへの指示（「〜してください」）を出さない */
const INSTRUCTING = ["ください", "ましょう", "してね", "あげて"];

const MAX_CHARS = 40;

export function checkDialogue(dialogue: string): RuleViolation[] {
  const v: RuleViolation[] = [];

  for (const p of PRONOUNS) {
    if (dialogue.includes(p)) {
      v.push({ rule: "一人称代名詞(D31)", detail: `「${p}」を含む` });
      break;
    }
  }

  if ([...dialogue].length > MAX_CHARS) {
    v.push({ rule: "字数", detail: `${[...dialogue].length}字（上限${MAX_CHARS}字）` });
  }

  for (const m of MEASUREMENT_PATTERNS) {
    if (m.re.test(dialogue)) {
      v.push({ rule: "計測値の露出(原則2)", detail: m.label });
      break;
    }
  }

  if (EMOJI.test(dialogue)) {
    v.push({ rule: "絵文字・顔文字", detail: "含まれている" });
  }

  for (const b of BLAMING) {
    if (dialogue.includes(b)) {
      v.push({ rule: "ユーザーを責める(D30)", detail: `「${b}」を含む` });
      break;
    }
  }

  for (const i of INSTRUCTING) {
    if (dialogue.includes(i)) {
      v.push({ rule: "ユーザーへの指示", detail: `「${i}」を含む` });
      break;
    }
  }

  return v;
}

/** 観察に主観が混ざっていないか。完全な判定はできないので目安 */
const SUBJECTIVE = ["元気", "かわいい", "きれい", "美しい", "つらそう", "うれしそう", "悲しそう"];

export function checkAppearances(appearances: string[]): RuleViolation[] {
  const v: RuleViolation[] = [];
  for (const a of appearances) {
    for (const s of SUBJECTIVE) {
      if (a.includes(s)) {
        v.push({ rule: "観察に主観が混入", detail: `「${a}」` });
        break;
      }
    }
  }
  return v;
}
