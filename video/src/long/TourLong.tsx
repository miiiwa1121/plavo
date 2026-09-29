import {
  AbsoluteFill,
  Audio,
  Easing,
  Freeze,
  Img,
  interpolate,
  OffthreadVideo,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { colors, font } from "../theme";
import { actNames, overview, overviewCaption, sources } from "./cuts";
import {
  FPS,
  INTRO_END,
  OUTRO_START,
  OVERVIEW_START,
  TOTAL,
  clipsEnd,
  frameOf,
  placed,
  NEUTRAL_CAMERA,
  cameraAt,
  sfxEvents,
  type Camera,
  type PlacedClip,
  type ZoomTarget,
} from "./timeline";

// 録画は iPhone 17（402×874pt・1206×2622px）
const SCREEN_WIDTH = 680;
const SCREEN_HEIGHT = Math.round((SCREEN_WIDTH * 874) / 402);
const BEZEL = 14;
const SCREEN_RADIUS = Math.round(SCREEN_WIDTH * (55 / 402));
const PHONE_LEFT = (1080 - SCREEN_WIDTH) / 2 - BEZEL;
const PHONE_TOP = 340 - BEZEL;
const PHONE_WIDTH = SCREEN_WIDTH + BEZEL * 2;
const PHONE_HEIGHT = SCREEN_HEIGHT + BEZEL * 2;
/** 寄ったとき、端末が覆っておく範囲の上端。ここより上は見出し */
const COVER_TOP = 360;
/** 寄ったとき、注目する点を持ってくる場所（キャンバスの座標） */
const ZOOM_ANCHOR = { x: 540, y: 1120 };

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

export const TourLong: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // 端末は、タイトルが引くのと入れ替わりに下から上がる。終盤は縮みながら引く
  const enter = spring({ frame: frame - INTRO_END + 12, fps, config: { damping: 200 }, durationInFrames: 24 });
  const exit = spring({ frame: frame - clipsEnd, fps, config: { damping: 200 }, durationInFrames: 18 });
  const shown = enter * (1 - exit);

  return (
    <AbsoluteFill style={{ backgroundColor: colors.background, fontFamily: font, overflow: "hidden" }}>
      <AbsoluteFill
        style={{ background: `radial-gradient(circle at 50% 58%, ${colors.glow} 0%, rgba(0,0,0,0) 55%)` }}
      />

      <div
        style={{
          position: "absolute",
          left: PHONE_LEFT,
          top: PHONE_TOP,
          opacity: shown,
          transform: `translateY(${(1 - enter) * 320}px) scale(${1 - exit * 0.1})`,
        }}
      >
        <ZoomedPhone />
      </div>

      <Header opacity={shown} />
      <CameraNote />
      <Overview />
      <Title from={0} until={INTRO_END} />
      <Title from={OUTRO_START} until={Infinity} />
      <Soundtrack />
    </AbsoluteFill>
  );
};

// MARK: - 端末と寄り

/**
 * 寄り先の見え方。注目する点をキャンバスの中ほどへ運ぶ倍率と位置を決める。
 *
 * **端末の縁をキャンバスの内側に入れない。**注目する点が画面の端にあると、中ほどへ運んだぶん
 * 反対側に空きができる。端末がキャンバスより大きければ縁が外に出る範囲で、小さければ
 * キャンバスの内側に収まる範囲で止める
 */
function cameraFor(target: ZoomTarget): Camera {
  if (target.scale <= 1.001) return NEUTRAL_CAMERA;
  const s = target.scale;
  const fx = BEZEL + (target.x / 402) * SCREEN_WIDTH;
  const fy = BEZEL + (target.y / 874) * SCREEN_HEIGHT;
  const fit = (value: number, origin: number, size: number, from: number, to: number) => {
    const a = from - origin; // 始まりの縁を from に合わせる移動
    const b = to - origin - size * s; // 終わりの縁を to に合わせる移動
    return Math.min(Math.max(value, Math.min(a, b)), Math.max(a, b));
  };
  return {
    scale: s,
    x: fit(ZOOM_ANCHOR.x - PHONE_LEFT - fx * s, PHONE_LEFT, PHONE_WIDTH, 0, 1080),
    y: fit(ZOOM_ANCHOR.y - PHONE_TOP - fy * s, PHONE_TOP, PHONE_HEIGHT, COVER_TOP, 1920),
  };
}

const ZoomedPhone: React.FC = () => {
  const frame = useCurrentFrame();
  const camera = cameraAt(frame, cameraFor);
  return (
    <div style={{ transformOrigin: "0 0", transform: `translate(${camera.x}px, ${camera.y}px) scale(${camera.scale})` }}>
      <Phone />
    </div>
  );
};

const Phone: React.FC = () => {
  const first = placed[0];
  const last = placed[placed.length - 1];
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
        <Sequence from={0} durationInFrames={first.start} layout="none">
          <Freeze frame={0}>
            <ClipVideo clip={first} />
          </Freeze>
        </Sequence>
        <Sequence from={clipsEnd} layout="none">
          <Freeze frame={last.length - 1}>
            <ClipVideo clip={last} />
          </Freeze>
        </Sequence>
        {placed
          .filter((clip) => clip.water !== undefined)
          .map((clip, i) => (
            <Sequence key={`water-${i}`} from={frameOf(clip, clip.water!)} durationInFrames={40} layout="none">
              <WaterDrops />
            </Sequence>
          ))}
      </div>
    </div>
  );
};

const fill = { position: "absolute", inset: 0, width: "100%", height: "100%" } as const;

const ClipVideo: React.FC<{ clip: { source: PlacedClip["source"]; from: number; to: number; rate?: number } }> = ({
  clip,
}) => (
  <OffthreadVideo
    src={staticFile(sources[clip.source])}
    trimBefore={Math.round(clip.from * FPS)}
    trimAfter={Math.round(clip.to * FPS)}
    playbackRate={clip.rate ?? 1}
    muted
    style={fill}
  />
);

/**
 * 水やりのしずく。アプリの画面には水をやる操作が映らない（展示では説明員の隠し操作、
 * 製品ではガジェットが測る）ので、動画の側で「水をあげた」ことを見せる
 */
const WaterDrops: React.FC = () => {
  const frame = useCurrentFrame();
  const drops = [
    { x: 0.44, delay: 0 },
    { x: 0.53, delay: 5 },
    { x: 0.48, delay: 10 },
  ];
  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      {drops.map((drop, i) => {
        const t = frame - drop.delay;
        const y = interpolate(t, [0, 16], [0.18, 0.5], { ...clamp, easing: Easing.in(Easing.quad) });
        const opacity = interpolate(t, [0, 3, 14, 20], [0, 1, 1, 0], clamp);
        return (
          <svg
            key={i}
            width={34}
            height={46}
            viewBox="0 0 34 46"
            style={{ position: "absolute", left: `${drop.x * 100}%`, top: `${y * 100}%`, opacity }}
          >
            <path
              d="M17 2 C 17 2, 3 20, 3 29 A 14 14 0 0 0 31 29 C 31 20, 17 2, 17 2 Z"
              fill="rgba(90, 170, 255, 0.85)"
              stroke="white"
              strokeWidth={2.5}
            />
          </svg>
        );
      })}
    </AbsoluteFill>
  );
};

/** いま映っている切り出し。前後の間は最初・最後のものを返す */
function clipAt(frame: number): PlacedClip {
  let found = placed[0];
  for (const clip of placed) if (clip.start <= frame) found = clip;
  return found;
}

// MARK: - 章と一言

const Header: React.FC<{ opacity: number }> = ({ opacity }) => (
  <>
    {/* 寄った端末が上へはみ出しても、文字が読めるように地を敷く */}
    <div
      style={{
        position: "absolute",
        top: 0,
        left: 0,
        right: 0,
        height: 330,
        opacity,
        background: `linear-gradient(${colors.background} 72%, rgba(242,245,239,0))`,
      }}
    />
    <div style={{ opacity }}>
      <ActBar />
      <Caption />
    </div>
  </>
);

const PROGRESS_WIDTH = 880;
const PROGRESS_TOP = 150;

/** 章ごとの始まりと終わり（フレーム） */
const actSpans = actNames.map((name) => {
  const clips = placed.filter((clip) => clip.act === name);
  return { name, start: clips[0].start, end: clips[clips.length - 1].start + clips[clips.length - 1].length };
});

/**
 * 話の進み。細い線の上に章の名前を並べ、動画の進みに合わせて線が緑に伸びる。
 * **アプリの切り替えの部品（カプセルと塊）には似せない。**画面の中の UI と見分けがつかなくなる
 */
const ActBar: React.FC = () => {
  const frame = useCurrentFrame();
  const segment = PROGRESS_WIDTH / actNames.length;
  // 章ごとに線の4分の1を受け持ち、その章の中の進み具合だけ伸ばす
  const filled = actSpans.reduce(
    (sum, span) => sum + segment * interpolate(frame, [span.start, span.end], [0, 1], clamp),
    0,
  );
  const active = actSpans.findIndex((span) => frame >= span.start && frame < span.end);
  const current = active >= 0 ? active : frame < actSpans[0].start ? 0 : actNames.length - 1;
  return (
    <div style={{ position: "absolute", top: 0, left: (1080 - PROGRESS_WIDTH) / 2, width: PROGRESS_WIDTH }}>
      {actNames.map((name, i) => {
        const on = i === current;
        return (
          <div
            key={name}
            style={{
              position: "absolute",
              top: PROGRESS_TOP - 50,
              left: segment * i,
              width: segment,
              textAlign: "center",
              fontSize: 30,
              fontWeight: on ? 800 : 500,
              letterSpacing: 2,
              color: on ? colors.accentDeep : colors.subtle,
              opacity: on ? 1 : 0.7,
            }}
          >
            {name}
          </div>
        );
      })}
      <div
        style={{
          position: "absolute",
          top: PROGRESS_TOP,
          width: PROGRESS_WIDTH,
          height: 4,
          borderRadius: 2,
          backgroundColor: "rgba(0,0,0,0.1)",
        }}
      />
      <div
        style={{
          position: "absolute",
          top: PROGRESS_TOP,
          width: filled,
          height: 4,
          borderRadius: 2,
          backgroundColor: colors.accent,
        }}
      />
    </div>
  );
};

const Caption: React.FC = () => {
  const frame = useCurrentFrame();
  const current = clipAt(frame);
  const index = placed.indexOf(current);
  let runStart = current.start;
  for (let i = index - 1; i >= 0 && placed[i].caption === current.caption; i--) runStart = placed[i].start;
  const local = frame - runStart;
  const opacity = interpolate(local, [0, 9], [0, 1], clamp);
  const rise = interpolate(local, [0, 12], [22, 0], { ...clamp, easing: Easing.out(Easing.cubic) });
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

/** カメラの場面は作り物の映像（デモカメラ）なので、そう断っておく */
const CameraNote: React.FC = () => {
  const frame = useCurrentFrame();
  const current = clipAt(frame);
  const cameraShown = current.source === "camera" && frame >= INTRO_END - 12 && frame < clipsEnd;
  if (!cameraShown) return null;
  return (
    <div style={{ position: "absolute", bottom: 28, width: "100%", display: "flex", justifyContent: "center" }}>
      <div
        style={{
          padding: "8px 22px",
          borderRadius: 999,
          backgroundColor: "rgba(0,0,0,0.45)",
          color: "white",
          fontSize: 24,
          letterSpacing: 2,
        }}
      >
        ※ カメラの映像はイメージです
      </div>
    </div>
  );
};

// MARK: - 4つ並べる

const MINI_COLUMNS = 3;
const MINI_ROWS = 2;
const MINI_WIDTH = 300;
const MINI_HEIGHT = Math.round((MINI_WIDTH * 874) / 402);
const MINI_BEZEL = 8;
const MINI_GAP = 32;

const Overview: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (frame < OVERVIEW_START - 6 || frame > OUTRO_START + 20) return null;
  const local = frame - OVERVIEW_START;
  // 全体をゆっくり引く
  const pullBack = interpolate(local, [0, OUTRO_START - OVERVIEW_START], [1.08, 1], clamp);
  const leave = interpolate(frame, [OUTRO_START - 4, OUTRO_START + 14], [1, 0], clamp);
  const gridWidth = (MINI_WIDTH + MINI_BEZEL * 2) * MINI_COLUMNS + MINI_GAP * (MINI_COLUMNS - 1);
  const gridHeight = (MINI_HEIGHT + MINI_BEZEL * 2) * MINI_ROWS + MINI_GAP * (MINI_ROWS - 1);
  const captionIn = interpolate(local, [4, 14], [0, 1], clamp);

  return (
    <AbsoluteFill style={{ opacity: leave }}>
      <div
        style={{
          position: "absolute",
          top: 230,
          width: "100%",
          textAlign: "center",
          fontSize: 58,
          fontWeight: 700,
          letterSpacing: 2,
          color: colors.text,
          opacity: captionIn,
          transform: `translateY(${(1 - captionIn) * 20}px)`,
        }}
      >
        {overviewCaption}
      </div>
      <div
        style={{
          position: "absolute",
          left: (1080 - gridWidth) / 2,
          top: 350,
          width: gridWidth,
          height: gridHeight,
          display: "grid",
          gridTemplateColumns: `repeat(${MINI_COLUMNS}, 1fr)`,
          gap: MINI_GAP,
          transform: `scale(${pullBack})`,
        }}
      >
        {overview.map((shot, i) => {
          const appear = spring({ frame: local - i * 3, fps, config: { damping: 200 }, durationInFrames: 18 });
          const length = Math.round((shot.to - shot.from) * FPS);
          return (
            <div
              key={i}
              style={{
                padding: MINI_BEZEL,
                borderRadius: MINI_WIDTH * (55 / 402) + MINI_BEZEL,
                backgroundColor: colors.bezel,
                boxShadow: "0 24px 50px rgba(20, 60, 30, 0.2)",
                opacity: appear,
                transform: `translateY(${(1 - appear) * 60}px) scale(${0.92 + appear * 0.08})`,
              }}
            >
              <div
                style={{
                  width: MINI_WIDTH,
                  height: MINI_HEIGHT,
                  borderRadius: MINI_WIDTH * (55 / 402),
                  overflow: "hidden",
                  position: "relative",
                  backgroundColor: "white",
                }}
              >
                <Sequence from={OVERVIEW_START - 6} durationInFrames={length} layout="none">
                  <ClipVideo clip={shot} />
                </Sequence>
                <Sequence from={OVERVIEW_START - 6 + length} layout="none">
                  <Freeze frame={length - 1}>
                    <ClipVideo clip={shot} />
                  </Freeze>
                </Sequence>
              </div>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

// MARK: - タイトル

/** アプリのタイトルの絵（TitleScreen）をそのまま使う。ロゴは絵の中ほどにある */
const Title: React.FC<{ from: number; until: number }> = ({ from, until }) => {
  const frame = useCurrentFrame();
  const appear = interpolate(frame, [from, from + 14], [from === 0 ? 1 : 0, 1], clamp);
  const leave = until === Infinity ? 0 : interpolate(frame, [until - 12, until + 4], [0, 1], clamp);
  const opacity = appear * (1 - leave);
  if (opacity <= 0) return null;
  const drift = interpolate(frame, [from, from + 150], [1.08, 1], clamp);
  return (
    <AbsoluteFill style={{ opacity }}>
      <Img
        src={staticFile("title.png")}
        style={{ width: "100%", height: "100%", objectFit: "cover", transform: `scale(${drift})` }}
      />
    </AbsoluteFill>
  );
};

// MARK: - 音

/** BGM と効果音。BGM は最後の3秒で消していく */
const Soundtrack: React.FC = () => (
  <>
    <Audio
      src={staticFile("audio/morning.mp3")}
      volume={(f) => 0.7 * interpolate(f, [TOTAL - 90, TOTAL - 4], [1, 0], clamp)}
    />
    {sfxEvents.map((event, i) => (
      <Sequence key={i} from={event.frame} durationInFrames={FPS * 2} layout="none">
        <Audio src={staticFile(`sfx/${event.name}.wav`)} volume={0.55 * event.volume} />
      </Sequence>
    ))}
  </>
);
