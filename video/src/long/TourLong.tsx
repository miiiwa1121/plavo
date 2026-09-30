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
import { createContext, useContext } from "react";
import { colors, font } from "../theme";
import { actNames, overview, overviewCaption, sources } from "./cuts";
import { landscape, portrait, type Layout } from "./layout";
import { PresenterBubble, PresenterCharacter } from "./Presenter";
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
const screenHeightOf = (width: number) => Math.round((width * 874) / 402);

/** 縦画面・横画面の置き場所（layout.ts）。組み立ては共通で、ここから読む */
const LayoutContext = createContext<Layout>(portrait);
const useLayout = () => useContext(LayoutContext);

/** 端末の寸法（枠を含む） */
function phoneOf(layout: Layout) {
  const screenHeight = screenHeightOf(layout.screenWidth);
  return {
    screenHeight,
    width: layout.screenWidth + layout.bezel * 2,
    height: screenHeight + layout.bezel * 2,
    radius: Math.round(layout.screenWidth * (55 / 402)),
  };
}

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** 縦画面（1080×1920） */
export const TourLong: React.FC = () => (
  <LayoutContext.Provider value={portrait}>
    <Tour />
  </LayoutContext.Provider>
);

/** 横画面（1920×1080）。構成・時間・寄り先は縦画面と同じ */
export const TourLongWide: React.FC = () => (
  <LayoutContext.Provider value={landscape}>
    <Tour />
  </LayoutContext.Provider>
);

const Tour: React.FC = () => {
  const layout = useLayout();
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // 端末は、タイトルが引くのと入れ替わりに下から上がる。終盤は縮みながら引く
  const enter = spring({ frame: frame - INTRO_END + 12, fps, config: { damping: 200 }, durationInFrames: 24 });
  const exit = spring({ frame: frame - clipsEnd, fps, config: { damping: 200 }, durationInFrames: 18 });
  const shown = enter * (1 - exit);

  return (
    <AbsoluteFill style={{ backgroundColor: colors.background, fontFamily: font, overflow: "hidden" }}>
      <AbsoluteFill
        style={{ background: `radial-gradient(circle at ${layout.glow}, ${colors.glow} 0%, rgba(0,0,0,0) 55%)` }}
      />

      <div
        style={{
          position: "absolute",
          left: layout.phoneLeft,
          top: layout.phoneTop,
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
function cameraFor(layout: Layout, target: ZoomTarget): Camera {
  if (target.scale <= 1.001) return NEUTRAL_CAMERA;
  const phone = phoneOf(layout);
  const s = target.scale;
  const fx = layout.bezel + (target.x / 402) * layout.screenWidth;
  const fy = layout.bezel + (target.y / 874) * phone.screenHeight;
  const fit = (value: number, origin: number, size: number, from: number, to: number) => {
    const a = from - origin; // 始まりの縁を from に合わせる移動
    const b = to - origin - size * s; // 終わりの縁を to に合わせる移動
    return Math.min(Math.max(value, Math.min(a, b)), Math.max(a, b));
  };
  const { cover } = layout;
  return {
    scale: s,
    x: fit(layout.zoomAnchor.x - layout.phoneLeft - fx * s, layout.phoneLeft, phone.width, cover.left, cover.right),
    y: fit(layout.zoomAnchor.y - layout.phoneTop - fy * s, layout.phoneTop, phone.height, cover.top, cover.bottom),
  };
}

const ZoomedPhone: React.FC = () => {
  const layout = useLayout();
  const frame = useCurrentFrame();
  const camera = cameraAt(frame, (target) => cameraFor(layout, target));
  return (
    <div style={{ transformOrigin: "0 0", transform: `translate(${camera.x}px, ${camera.y}px) scale(${camera.scale})` }}>
      <Phone />
    </div>
  );
};

const Phone: React.FC = () => {
  const layout = useLayout();
  const phone = phoneOf(layout);
  const first = placed[0];
  const last = placed[placed.length - 1];
  return (
    <div
      style={{
        padding: layout.bezel,
        borderRadius: phone.radius + layout.bezel,
        backgroundColor: colors.bezel,
        boxShadow: "0 40px 90px rgba(20, 60, 30, 0.22), 0 8px 24px rgba(0,0,0,0.12)",
      }}
    >
      <div
        style={{
          width: layout.screenWidth,
          height: phone.screenHeight,
          borderRadius: phone.radius,
          overflow: "hidden",
          backgroundColor: "white",
          position: "relative",
        }}
      >
        {placed.map((clip, i) => (
          <Sequence key={i} from={clip.start} durationInFrames={clip.length - clip.hold} layout="none">
            <ClipVideo clip={clip} />
          </Sequence>
        ))}
        {/* 章の長さに足りないぶん、最後のコマで止めておく（timeline.ts） */}
        {placed
          .filter((clip) => clip.hold > 0)
          .map((clip, i) => (
            <Sequence key={`hold-${i}`} from={clip.start + clip.length - clip.hold} durationInFrames={clip.hold} layout="none">
              <Freeze frame={clip.length - clip.hold - 1}>
                <ClipVideo clip={clip} />
              </Freeze>
            </Sequence>
          ))}
        <Sequence from={0} durationInFrames={first.start} layout="none">
          <Freeze frame={0}>
            <ClipVideo clip={first} />
          </Freeze>
        </Sequence>
        <Sequence from={clipsEnd} layout="none">
          <Freeze frame={last.length - last.hold - 1}>
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
        {placed
          .filter((clip) => clip.sun !== undefined)
          .map((clip, i) => (
            <Sequence
              key={`sun-${i}`}
              from={frameOf(clip, clip.sun!)}
              durationInFrames={clip.start + clip.length - frameOf(clip, clip.sun!)}
              layout="none"
            >
              <SunBeams />
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
  const size = useLayout().screenWidth / 680;
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
            width={34 * size}
            height={46 * size}
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

/**
 * 日向の光の筋。右上から斜めに差し込み、ゆっくり揺れる。
 * 映像の明るさと暖かさはアプリの側（DemoStage）で変えてある。ここでは「日が差した」ことを見せる
 */
const SunBeams: React.FC = () => {
  const frame = useCurrentFrame();
  const appear = interpolate(frame, [0, 24], [0, 1], { ...clamp, easing: Easing.out(Easing.quad) });
  const beams = [
    { offset: 0.1, width: 0.16, strength: 0.55 },
    { offset: 0.36, width: 0.1, strength: 0.4 },
    { offset: 0.56, width: 0.2, strength: 0.3 },
  ];
  return (
    <AbsoluteFill style={{ pointerEvents: "none", overflow: "hidden", opacity: appear, mixBlendMode: "screen" }}>
      {beams.map((beam, i) => {
        const sway = Math.sin((frame + i * 20) / 38) * 0.02;
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              top: "-30%",
              left: `${(beam.offset + sway) * 100 + 40}%`,
              width: `${beam.width * 100}%`,
              height: "160%",
              transform: "rotate(28deg)",
              transformOrigin: "top center",
              background: `linear-gradient(rgba(255, 226, 150, ${beam.strength}), rgba(255, 226, 150, 0) 75%)`,
              filter: "blur(6px)",
            }}
          />
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

// MARK: - 章・語り手・案内役

const Header: React.FC<{ opacity: number }> = ({ opacity }) => {
  const layout = useLayout();
  return (
    <>
      {/* 寄った端末が見出しの下へ入っても、文字が読めるように地を敷く */}
      <div style={{ position: "absolute", opacity, ...layout.backdrop }} />
      <div style={{ opacity }}>
        {layout.header.steps.kind === "line" ? <ActBar /> : <ActStepper />}
        <Narration />
        <Presenter />
      </div>
    </>
  );
};

/** 章ごとの始まりと終わり（フレーム） */
const actSpans = actNames.map((name) => {
  const clips = placed.filter((clip) => clip.act === name);
  return { name, start: clips[0].start, end: clips[clips.length - 1].start + clips[clips.length - 1].length };
});

/** いまの章の番号と、章の中の進み具合（0〜1） */
function actProgress(frame: number) {
  const active = actSpans.findIndex((span) => frame >= span.start && frame < span.end);
  const current = active >= 0 ? active : frame < actSpans[0].start ? 0 : actNames.length - 1;
  const span = actSpans[current];
  return { current, within: interpolate(frame, [span.start, span.end], [0, 1], clamp) };
}

/**
 * 縦画面の上。細い線の上に章の名前を並べ、動画の進みに合わせて線が緑に伸びる。
 * **アプリの切り替えの部品（カプセルと塊）には似せない。**画面の中の UI と見分けがつかなくなる
 */
const ActBar: React.FC = () => {
  const frame = useCurrentFrame();
  const { steps } = useLayout().header;
  if (steps.kind !== "line") return null;
  const segment = steps.width / actNames.length;
  // 章ごとに線の4分の1を受け持ち、その章の中の進み具合だけ伸ばす
  const filled = actSpans.reduce(
    (sum, span) => sum + segment * interpolate(frame, [span.start, span.end], [0, 1], clamp),
    0,
  );
  const { current } = actProgress(frame);
  return (
    <div style={{ position: "absolute", top: 0, left: steps.left, width: steps.width }}>
      {actNames.map((name, i) => {
        const on = i === current;
        return (
          <div
            key={name}
            style={{
              position: "absolute",
              top: steps.top - steps.fontSize - 20,
              left: segment * i,
              width: segment,
              textAlign: "center",
              fontSize: steps.fontSize,
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
      <div style={{ position: "absolute", top: steps.top, width: steps.width, height: 4, borderRadius: 2, backgroundColor: "rgba(0,0,0,0.1)" }} />
      <div style={{ position: "absolute", top: steps.top, width: filled, height: 4, borderRadius: 2, backgroundColor: colors.accent }} />
    </div>
  );
};

/**
 * 横画面の左。章を縦に並べ、丸の横に名前を置き、丸と丸を縦線でつなぐ。
 * 線は章の中の進みに合わせて、次の丸へ向けて緑に伸びる
 */
const ActStepper: React.FC = () => {
  const { steps } = useLayout().header;
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (steps.kind !== "stepper") return null;
  const { left, top, gap, dot, fontSize } = steps;
  const { current, within } = actProgress(frame);
  const lineX = left + dot / 2 - 3;
  const filled = gap * current + gap * within;
  // 章に入ると名前が膨らみ、抜けると戻る
  const grow = (i: number) => {
    const span = actSpans[i];
    const into = spring({ frame: frame - span.start, fps, config: { damping: 16, mass: 0.6 } });
    const out = i + 1 < actSpans.length ? spring({ frame: frame - span.end, fps, config: { damping: 16, mass: 0.6 } }) : 0;
    return into * (1 - out);
  };
  return (
    <>
      {/* 線（下地と、伸びる緑） */}
      <div
        style={{
          position: "absolute",
          left: lineX,
          top: top + dot / 2,
          width: 6,
          height: gap * (actNames.length - 1),
          borderRadius: 3,
          backgroundColor: "rgba(0,0,0,0.1)",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: lineX,
          top: top + dot / 2,
          width: 6,
          height: Math.min(filled, gap * (actNames.length - 1)),
          borderRadius: 3,
          backgroundColor: colors.accent,
        }}
      />
      {actNames.map((name, i) => {
        const reached = i <= current;
        const on = i === current;
        // いまの章の丸は、入った瞬間に少し膨らむ
        const pulse = on ? spring({ frame: frame - actSpans[i].start, fps, config: { damping: 10, mass: 0.5 } }) : 1;
        const size = on ? dot * (1.1 + 0.25 * (1 - Math.abs(1 - pulse))) : dot;
        return (
          <div key={name}>
            <div
              style={{
                position: "absolute",
                left: left + dot / 2 - size / 2,
                top: top + gap * i + dot / 2 - size / 2,
                width: size,
                height: size,
                borderRadius: "50%",
                boxSizing: "border-box",
                backgroundColor: reached ? colors.accent : colors.background,
                border: `5px solid ${reached ? colors.accent : "rgba(0,0,0,0.18)"}`,
                boxShadow: on ? "0 0 0 8px rgba(52, 199, 89, 0.18)" : "none",
              }}
            />
            <div
              style={{
                position: "absolute",
                left: left + dot + 28,
                top: top + gap * i + dot / 2 - fontSize * 0.68,
                fontSize,
                // いまの章の名前は大きく見せる。塊の大きさは変えず、文字だけを膨らませる
                transform: `scale(${1 + 0.35 * grow(i)})`,
                transformOrigin: "left center",
                fontWeight: on ? 800 : 600,
                letterSpacing: 3,
                color: on ? colors.accentDeep : reached ? colors.text : colors.subtle,
                opacity: on || reached ? 1 : 0.7,
                whiteSpace: "nowrap",
              }}
            >
              {name}
            </div>
          </div>
        );
      })}
    </>
  );
};

/**
 * 同じ一言が続いている区間の始まり。**語り手とキャラクターで別々に数える。**
 * 語り手が同じまま、キャラクターだけが話し始めることがある
 */
function runOf(frame: number, pick: (clip: PlacedClip) => string | undefined) {
  const current = clipAt(frame);
  const text = pick(current);
  const index = placed.indexOf(current);
  let since = current.start;
  for (let i = index - 1; i >= 0 && pick(placed[i]) === text; i--) since = placed[i].start;
  return { text, since };
}

/** 語り手の一言（使い方の説明）。縦画面は上の中央、横画面は左の列 */
const Narration: React.FC = () => {
  const { narration } = useLayout().header;
  const frame = useCurrentFrame();
  const { text, since } = runOf(frame, (clip) => clip.narration);
  const shadowed = narration.shadow === true;
  const local = frame - since;
  const opacity = interpolate(local, [0, 9], [0, 1], clamp);
  const rise = interpolate(local, [0, 12], [18, 0], { ...clamp, easing: Easing.out(Easing.cubic) });
  return (
    <div
      lang="ja"
      style={{
        position: "absolute",
        top: narration.top,
        left: narration.left,
        width: narration.width,
        textAlign: narration.align,
        // 文節で折り返す（「迎えまし／ょう。」のような途中の折り返しを避ける）
        wordBreak: "auto-phrase" as React.CSSProperties["wordBreak"],
        fontSize: narration.fontSize,
        lineHeight: 1.4,
        fontWeight: 700,
        letterSpacing: 2,
        color: colors.text,
        opacity,
        transform: `translateY(${rise}px)`,
      }}
    >
      {shadowed ? (
        // 端末に少し重なっても読めるよう、文字の後ろにうっすら影を敷く
        <span
          style={{
            display: "inline-block",
            padding: "10px 22px",
            borderRadius: 18,
            backgroundColor: "rgba(242, 245, 239, 0.72)",
            boxShadow: "0 10px 30px rgba(20, 40, 25, 0.16)",
            backdropFilter: "blur(6px)",
          }}
        >
          {text}
        </span>
      ) : (
        text
      )}
    </div>
  );
};

/** 案内役。キャラクターの一言があるあいだだけ吹き出しで話し、無いときは黙って立っている */
const Presenter: React.FC = () => {
  const { presenter, bubble } = useLayout().header;
  const frame = useCurrentFrame();
  const { text, since } = runOf(frame, (clip) => clip.comment);
  return (
    <>
      <div style={{ position: "absolute", left: presenter.left, top: presenter.top }}>
        <PresenterCharacter width={presenter.width} talkingSince={text ? since : -1000} />
      </div>
      {text && (
        <div style={{ position: "absolute", left: bubble.left, right: bubble.right, top: bubble.top, bottom: bubble.bottom }}>
          <PresenterBubble
            text={text}
            since={since}
            maxWidth={bubble.maxWidth}
            minWidth={bubble.minWidth}
            fontSize={bubble.fontSize}
            tail={bubble.tail}
            tailOffset={bubble.tailOffset}
          />
        </div>
      )}
    </>
  );
};

/** カメラの場面は作り物の映像（デモカメラ）なので、そう断っておく */
const CameraNote: React.FC = () => {
  const { note } = useLayout();
  const frame = useCurrentFrame();
  const current = clipAt(frame);
  const cameraShown = current.source === "camera" && frame >= INTRO_END - 12 && frame < clipsEnd;
  if (!cameraShown) return null;
  return (
    <div
      style={{
        position: "absolute",
        bottom: note.bottom,
        left: note.centerX - 400,
        width: 800,
        display: "flex",
        justifyContent: "center",
      }}
    >
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

// MARK: - 画面を並べる

const Overview: React.FC = () => {
  const layout = useLayout();
  const { columns, rows, miniWidth, bezel, gap, captionTop, captionSize, gridTop } = layout.overview;
  const miniHeight = screenHeightOf(miniWidth);
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (frame < OVERVIEW_START - 6 || frame > OUTRO_START + 20) return null;
  const local = frame - OVERVIEW_START;
  // 全体をゆっくり引く
  const pullBack = interpolate(local, [0, OUTRO_START - OVERVIEW_START], [1.08, 1], clamp);
  const leave = interpolate(frame, [OUTRO_START - 4, OUTRO_START + 14], [1, 0], clamp);
  const gridWidth = (miniWidth + bezel * 2) * columns + gap * (columns - 1);
  const gridHeight = (miniHeight + bezel * 2) * rows + gap * (rows - 1);
  const captionIn = interpolate(local, [4, 14], [0, 1], clamp);

  return (
    <AbsoluteFill style={{ opacity: leave }}>
      <div
        style={{
          position: "absolute",
          top: captionTop,
          width: "100%",
          textAlign: "center",
          fontSize: captionSize,
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
          left: (layout.width - gridWidth) / 2,
          top: gridTop,
          width: gridWidth,
          height: gridHeight,
          display: "grid",
          gridTemplateColumns: `repeat(${columns}, 1fr)`,
          gap,
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
                padding: bezel,
                borderRadius: miniWidth * (55 / 402) + bezel,
                backgroundColor: colors.bezel,
                boxShadow: "0 24px 50px rgba(20, 60, 30, 0.2)",
                opacity: appear,
                transform: `translateY(${(1 - appear) * 60}px) scale(${0.92 + appear * 0.08})`,
              }}
            >
              <div
                style={{
                  width: miniWidth,
                  height: miniHeight,
                  borderRadius: miniWidth * (55 / 402),
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
