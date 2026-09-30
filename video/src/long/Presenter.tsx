import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { colors } from "../theme";

// 横画面で一言を話す案内役。**オリジナルのキャラクター**（既存のキャラクターは写さない）。
// 形はシンプルにする: 丸みのある三角のからだに、大きな目と小さな口だけ。
// plavo に合わせて緑にし、頭に双葉を1つのせる。

const BODY = "#3CC062";
const LEAF = "#2FA24F";
const INK = "#1E1E24";

/** 話し始めてから口を動かす長さ（フレーム） */
const TALK_FRAMES = 30;

/**
 * @param talkingSince 一言が変わったフレーム。そこから少しのあいだ口を動かす
 */
export const PresenterCharacter: React.FC<{ width: number; talkingSince: number }> = ({ width, talkingSince }) => {
  const frame = useCurrentFrame();
  const talk = frame - talkingSince;
  const talking = talk >= 0 && talk < TALK_FRAMES;
  // 口の開き。話しているあいだ、ぱくぱくさせる
  const open = talking
    ? Math.abs(Math.sin(talk * 0.75)) * interpolate(talk, [TALK_FRAMES - 6, TALK_FRAMES], [1, 0], clamp)
    : 0;
  // 待機中はゆっくり弾む。話すときは口に合わせて少し伸び縮みする（足もとを基点に）
  const bounce = Math.abs(Math.sin(frame / 18)) * 6;
  const stretch = 1 + 0.035 * open;
  // まばたき（3.4秒ごと・4フレーム）
  const eyeOpen = frame % 102 < 4 ? 0.1 : 1;
  // 双葉は風に揺れるように
  const leafSway = Math.sin(frame / 14) * 6;

  return (
    <svg width={width} height={(width * 330) / 300} viewBox="0 0 300 330" style={{ overflow: "visible" }}>
      {/* 足もとの影。弾むと小さくなる */}
      <ellipse cx={150} cy={318} rx={96 - bounce * 2} ry={11} fill="rgba(20, 60, 30, 0.14)" />
      <g transform={`translate(0 ${-bounce}) translate(150 305) scale(${1 / stretch} ${stretch}) translate(-150 -305)`}>
        {/* 双葉 */}
        <g transform={`rotate(${leafSway} 150 62)`}>
          <path d="M150 62 L 150 30" stroke={LEAF} strokeWidth={8} strokeLinecap="round" />
          <path d="M150 34 C 128 10, 100 20, 104 36 C 110 50, 138 46, 150 34 Z" fill={LEAF} />
          <path d="M150 34 C 172 10, 200 20, 196 36 C 190 50, 162 46, 150 34 Z" fill={LEAF} />
        </g>
        {/* からだ（角の丸い三角） */}
        <path
          d="M150 58 C 178 58, 196 90, 232 170 C 262 236, 292 272, 268 296 C 250 314, 50 314, 32 296 C 8 272, 38 236, 68 170 C 104 90, 122 58, 150 58 Z"
          fill={BODY}
        />
        {/* 目。白目は大きく、黒目は吹き出しのある左上を見る */}
        {[
          { x: 112, y: 196 },
          { x: 190, y: 190 },
        ].map((eye) => (
          <g key={eye.x} transform={`translate(${eye.x} ${eye.y}) scale(1 ${eyeOpen}) translate(${-eye.x} ${-eye.y})`}>
            <circle cx={eye.x} cy={eye.y} r={34} fill="#FFFFFF" />
            <ellipse cx={eye.x - 6} cy={eye.y - 8} rx={15} ry={18} fill={INK} />
          </g>
        ))}
        {/* 口。閉じているときは小さな笑顔、話すときは開く */}
        {open < 0.08 ? (
          <path d="M132 250 Q 150 268, 168 250" stroke={INK} strokeWidth={12} strokeLinecap="round" fill="none" />
        ) : (
          <path d={`M130 248 Q 150 ${252 + 30 * open}, 170 248 Z`} fill={INK} stroke={INK} strokeWidth={10} strokeLinejoin="round" />
        )}
      </g>
    </svg>
  );
};

/**
 * 吹き出し。一言が変わるたびに、ぽんと出し直す。
 * 幅は一言に合わせる（maxWidth で折り返す）。しっぽは下（キャラクターが下にいる）か左（左にいる）に出す
 */
export const PresenterBubble: React.FC<{
  text: string;
  since: number;
  maxWidth: number;
  minWidth: number;
  fontSize: number;
  tail: "bottom" | "left";
  /** しっぽの位置（下なら吹き出しの右端から、左なら上端から） */
  tailOffset: number;
}> = ({ text, since, maxWidth, minWidth, fontSize, tail, tailOffset }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pop = spring({ frame: frame - since, fps, config: { damping: 14, mass: 0.6 } });
  const fade = interpolate(frame - since, [0, 6], [0, 1], clamp);
  const origin = tail === "bottom" ? `calc(100% - ${tailOffset + 20}px) 100%` : `0px ${tailOffset + 20}px`;
  return (
    <div style={{ display: "inline-block", transformOrigin: origin, transform: `scale(${0.86 + 0.14 * pop})`, opacity: fade }}>
      <div
        lang="ja"
        style={{
          position: "relative",
          // 文節で折り返す（「うれ／しそう」のような途中の折り返しを避ける）
          wordBreak: "auto-phrase" as React.CSSProperties["wordBreak"],
          maxWidth,
          minWidth,
          boxSizing: "border-box",
          padding: `${fontSize * 0.6}px ${fontSize * 0.8}px`,
          borderRadius: fontSize * 0.8,
          backgroundColor: "#FFFFFF",
          border: `4px solid ${colors.accent}`,
          boxShadow: "0 16px 36px rgba(20, 60, 30, 0.14)",
          fontSize,
          fontWeight: 800,
          lineHeight: 1.35,
          letterSpacing: 1,
          color: colors.text,
        }}
      >
        {text}
        {/* しっぽ。キャラクターへ向ける */}
        {tail === "bottom" ? (
          <svg width={60} height={46} viewBox="0 0 60 46" style={{ position: "absolute", right: tailOffset, bottom: -40, overflow: "visible" }}>
            <path d="M4 0 L 14 42 L 44 0 Z" fill="#FFFFFF" stroke={colors.accent} strokeWidth={4} strokeLinejoin="round" />
            <rect x={0} y={-8} width={52} height={10} fill="#FFFFFF" />
          </svg>
        ) : (
          <svg width={46} height={44} viewBox="0 0 46 44" style={{ position: "absolute", left: -40, top: tailOffset, overflow: "visible" }}>
            <path d="M46 4 L 2 22 L 46 38 Z" fill="#FFFFFF" stroke={colors.accent} strokeWidth={4} strokeLinejoin="round" />
            <rect x={44} y={0} width={10} height={44} fill="#FFFFFF" />
          </svg>
        )}
      </div>
    </div>
  );
};

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
