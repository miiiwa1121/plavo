// セリフの規則チェック
//
// システムプロンプトで規則を課しているが、モデルが自然な文を書こうとすると外れやすい。
// 特に一人称代名詞の禁止と字数制限は破られやすいと予想している（P-2）。
// 自動で検出できるようにしておき、違反率を計測できる状態にする。
//
// 詳細は docs/design/diagnosis-prompt.md §10

export type Severity = "violation" | "warning";
export type RuleViolation = { rule: string; detail: string; severity: Severity };

/**
 * violation … 機械的に黒と言える。必ず直す
 * warning   … 設計意図と衝突しうるが、文脈によっては許容できる。人が判断する
 */

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

/** D30: ユーザーを責めない。断定的に責める表現は violation */
const BLAMING = [
  "くれなかった",
  "してくれない",
  "気づいてほしかった",
  "遅かった",
  "忘れてた",
  "忘れてない",
  "忘れちゃった",
  "放っておかれ",
  "ほったらかし",
  "ずっと待ってたのに",
];

/** 明確な命令形。ユーザーに指示しない */
const COMMANDING = ["ください", "ましょう", "しなさい", "してね", "あげて"];

/**
 * 依頼・お願いの表現。
 * 「水をあげてください」ではなく「のどが渇いたよ」という設計意図（D30）と衝突しうるが、
 * 丁寧な依頼は命令ほど強くない。文脈によっては許容できるため warning とする。
 */
const REQUESTING = [
  "もらえる",
  "もらえますか",
  "てほしい",
  "ほしいな",
  "お願い",
  "くれる？",
  "くれない？",
];

/**
 * 「見て見て」のような、ユーザーの行動を促す呼びかけ。
 * 「見てる」「見てた」は進行形であって呼びかけではないため除外する
 * （例:「こっち見てる？」は状態の確認であり、指示ではない）。
 */
const CALLING_ATTENTION: { re: RegExp; label: string }[] = [
  { re: /見て(?!る|た|い)/, label: "見て" },
  { re: /チェックして/, label: "チェックして" },
  { re: /確認して/, label: "確認して" },
];

const MAX_CHARS = 40;

export function checkDialogue(dialogue: string): RuleViolation[] {
  const v: RuleViolation[] = [];

  for (const p of PRONOUNS) {
    if (dialogue.includes(p)) {
      v.push({ rule: "一人称代名詞(D31)", detail: `「${p}」を含む`, severity: "violation" });
      break;
    }
  }

  if ([...dialogue].length > MAX_CHARS) {
    v.push({
      rule: "字数",
      detail: `${[...dialogue].length}字（上限${MAX_CHARS}字）`,
      severity: "violation",
    });
  }

  for (const m of MEASUREMENT_PATTERNS) {
    if (m.re.test(dialogue)) {
      v.push({ rule: "計測値の露出(原則2)", detail: m.label, severity: "violation" });
      break;
    }
  }

  if (EMOJI.test(dialogue)) {
    v.push({ rule: "絵文字・顔文字", detail: "含まれている", severity: "violation" });
  }

  for (const b of BLAMING) {
    if (dialogue.includes(b)) {
      v.push({ rule: "ユーザーを責める(D30)", detail: `「${b}」を含む`, severity: "violation" });
      break;
    }
  }

  for (const c of COMMANDING) {
    if (dialogue.includes(c)) {
      v.push({ rule: "ユーザーへの命令", detail: `「${c}」を含む`, severity: "violation" });
      break;
    }
  }

  for (const r of REQUESTING) {
    if (dialogue.includes(r)) {
      v.push({
        rule: "ユーザーへの依頼",
        detail: `「${r}」を含む。状態の表明か、お願いか`,
        severity: "warning",
      });
      break;
    }
  }

  for (const c of CALLING_ATTENTION) {
    if (c.re.test(dialogue)) {
      v.push({
        rule: "行動をうながす呼びかけ",
        detail: `「${c.label}」を含む`,
        severity: "warning",
      });
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
        v.push({ rule: "観察に主観が混入", detail: `「${a}」`, severity: "warning" });
        break;
      }
    }
  }
  return v;
}
