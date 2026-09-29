import {
  AbsoluteFill,
  Easing,
  Freeze,
  interpolate,
  OffthreadVideo,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { chapters } from "./cuts";
import { colors, font } from "./theme";
import { FPS, INTRO, clipsEnd, placed, type PlacedClip } from "./timeline";

// 録画は iPhone 17（1206×2622）
const SCREEN_WIDTH = 680;
const SCREEN_HEIGHT = Math.round((SCREEN_WIDTH * 2622) / 1206);
const BEZEL = 14;
// 画面の角の丸み。iPhone 17 の画面の角（約55pt / 幅402pt）に合わせる
const SCREEN_RADIUS = Math.round(SCREEN_WIDTH * (55 / 402));
const PHONE_TOP = 330;

export const Tour: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // 端末は下から上がってきて、終わりに少し縮みながら消える
  const enter = spring({ frame: frame - INTRO + 10, fps, config: { damping: 200 }, durationInFrames: 24 });
  const exit = spring({ frame: frame - clipsEnd, fps, config: { damping: 200 }, durationInFrames: 18 });
  const shown = enter * (1 - exit);

  return (
    <AbsoluteFill style={{ backgroundColor: colors.background, fontFamily: font }}>
      <AbsoluteFill
        style={{
          background: `radial-gradient(circle at 50% 58%, ${colors.glow} 0%, rgba(0,0,0,0) 55%)`,
        }}
      />

      <div style={{ opacity: shown, transform: `translateY(${(1 - enter) * -30}px)` }}>
        <ChapterBar />
        <Caption />
      </div>

      <div
        style={{
          position: "absolute",
          left: (1080 - SCREEN_WIDTH) / 2 - BEZEL,
          top: PHONE_TOP - BEZEL,
          opacity: shown,
          transform: `translateY(${(1 - enter) * 320}px) scale(${1 - exit * 0.08})`,
        }}
      >
        <Phone />
      </div>

      <Wordmark from={0} until={INTRO} />
      <Wordmark from={clipsEnd + 10} until={Infinity} />
    </AbsoluteFill>
  );
};

/** 端末の枠と、その中の録画 */
const Phone: React.FC = () => {
  const last = placed.at(-1)!;
  return (
    <div
      style={{
        padding: BEZEL,
        borderRadius: SCREEN_RADIUS + BEZEL,
        backgroundColor: colors.bezel,
        boxShadow: "0 40px 90px rgba(20, 60, 30, 0.22), 0 8px 24px rgba(0,0,0,0.12)",
      }}
    >
      <div
        style={{
          width: SCREEN_WIDTH,
          height: SCREEN_HEIGHT,
          borderRadius: SCREEN_RADIUS,
          overflow: "hidden",
          backgroundColor: "white",
          position: "relative",
        }}
      >
        {placed.map((clip, i) => (
          <Sequence key={i} from={clip.start} durationInFrames={clip.length} layout="none">
            <ClipVideo clip={clip} />
          </Sequence>
        ))}
        {/* 切り出しの前後は、最初と最後のコマで止めておく（端末が出入りする間） */}
        <Sequence from={0} durationInFrames={placed[0].start} layout="none">
          <Freeze frame={0}>
            <ClipVideo clip={placed[0]} />
          </Freeze>
        </Sequence>
        <Sequence from={clipsEnd} layout="none">
          <Freeze frame={last.length - 1}>
            <ClipVideo clip={last} />
          </Freeze>
        </Sequence>
      </div>
    </div>
  );
};

const ClipVideo: React.FC<{ clip: PlacedClip }> = ({ clip }) => (
  <OffthreadVideo
    src={staticFile("tour.mp4")}
    trimBefore={Math.round(clip.from * FPS)}
    trimAfter={Math.round(clip.to * FPS)}
    playbackRate={clip.rate ?? 1}
    muted
    style={{ position: "absolute", inset: 0, width: "100%", height: "100%" }}
  />
);

/** いま映っている切り出し。前後の間は最初・最後のものを返す */
function clipAt(frame: number): PlacedClip {
  return placed.findLast((clip) => clip.start <= frame) ?? placed[0];
}

// MARK: - 章の切り替え

const PILL_WIDTH = 210;
const PILL_GAP = 10;

/**
 * いまどのタブを見せているか。アプリの切り替えの部品（CapsuleTabBar）に倣い、
 * 選択中の塊が横へ移る
 */
const ChapterBar: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // 章が変わった時刻ごとに、塊を1つぶんずつ動かす
  let position = chapters.indexOf(placed[0].chapter);
  for (let i = 1; i < placed.length; i++) {
    const from = chapters.indexOf(placed[i - 1].chapter);
    const to = chapters.indexOf(placed[i].chapter);
    if (from === to) continue;
    const progress = spring({ frame: frame - placed[i].start, fps, config: { damping: 18, mass: 0.6 } });
    position += (to - from) * progress;
  }
  const active = Math.round(position);
  const total = chapters.length * PILL_WIDTH + (chapters.length - 1) * PILL_GAP;

  return (
    <div
      style={{
        position: "absolute",
        top: 96,
        left: (1080 - total) / 2 - 8,
        padding: 8,
        borderRadius: 999,
        backgroundColor: "rgba(255,255,255,0.75)",
        boxShadow: "0 6px 20px rgba(20, 60, 30, 0.08)",
        display: "flex",
        gap: PILL_GAP,
      }}
    >
      <div
        style={{
          position: "absolute",
          top: 8,
          left: 8 + position * (PILL_WIDTH + PILL_GAP),
          width: PILL_WIDTH,
          height: 64,
          borderRadius: 999,
          backgroundColor: "rgba(0,0,0,0.06)",
        }}
      />
      {chapters.map((chapter, i) => (
        <div
          key={chapter}
          style={{
            position: "relative",
            width: PILL_WIDTH,
            height: 64,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 30,
            fontWeight: 700,
            color: i === active ? colors.accentDeep : colors.subtle,
          }}
        >
          {chapter}
        </div>
      ))}
    </div>
  );
};

// MARK: - 一言

/** 同じ一言が続く切り出しは1つの塊として扱い、変わったときだけ出し直す */
const Caption: React.FC = () => {
  const frame = useCurrentFrame();
  const current = clipAt(frame);
  const index = placed.indexOf(current);
  let runStart = current.start;
  for (let i = index - 1; i >= 0 && placed[i].caption === current.caption; i--) {
    runStart = placed[i].start;
  }
  const local = frame - runStart;
  const ease = Easing.out(Easing.cubic);
  const opacity = interpolate(local, [0, 9], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const rise = interpolate(local, [0, 12], [22, 0], { easing: ease, extrapolateLeft: "clamp", extrapolateRight: "clamp" });

  return (
    <div
      style={{
        position: "absolute",
        top: 200,
        width: "100%",
        textAlign: "center",
        fontSize: 64,
        fontWeight: 700,
        letterSpacing: 2,
        color: colors.text,
        opacity,
        transform: `translateY(${rise}px)`,
      }}
    >
      {current.caption}
    </div>
  );
};

// MARK: - 名前

const Wordmark: React.FC<{ from: number; until: number }> = ({ from, until }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const appear = spring({ frame: frame - from, fps, config: { damping: 200 }, durationInFrames: 16 });
  const leave = until === Infinity ? 0 : interpolate(frame, [until - 12, until], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const opacity = appear * (1 - leave);
  if (opacity <= 0) return null;

  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", opacity }}>
      <div
        style={{
          transform: `translateY(${(1 - appear) * 30 - leave * 40}px)`,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 28,
        }}
      >
        <div style={{ fontSize: 180, fontWeight: 800, color: colors.accentDeep, letterSpacing: 4 }}>plavo</div>
        <div style={{ fontSize: 40, fontWeight: 700, color: colors.subtle, letterSpacing: 6 }}>
          植物の気持ち翻訳アプリ
        </div>
      </div>
    </AbsoluteFill>
  );
};
