import { Easing, interpolate } from "remotion";
import { acts, type ActName, type Clip, type SfxName, type Zoom } from "./cuts";

export const FPS = 30;
export const WIDTH = 1080;
export const HEIGHT = 1920;

// BGM「Morning」（しゃろう・OpenTracks）の拍。約118 BPM、最初の拍は 0.031 秒。
// 録音を測って決めた。曲を替えたら測り直す
const BEAT = 0.5095;
const FIRST_BEAT = 0.031;
const BAR = BEAT * 4;

/** その小節の頭のフレーム */
export const barFrame = (bar: number) => Math.round((FIRST_BEAT + BAR * bar) * FPS);

/** 全体の長さ。見ている人の目線が追いつくよう1分30秒にし、センサーの場面を足して1分40秒にした */
export const TOTAL = 100 * FPS;
/** はじめのタイトル（約4秒・小節の頭まで） */
export const INTRO_END = barFrame(2);
/** 画面を並べる場面。最後の章（共有する）のあと */
export const OVERVIEW_START = barFrame(44);
/** 終わりのタイトルは4秒 */
export const OUTRO_START = TOTAL - 4 * FPS;

export type PlacedClip = Clip & {
  act: ActName;
  start: number;
  /** 動画の中での長さ（フレーム）。hold を含む */
  length: number;
  /** 最後のコマで止めておく長さ（フレーム） */
  hold: number;
};

/**
 * 切り出しを章ごとに並べる。章は小節の頭から始める。
 *
 * **章の長さに足りないぶんは、切り出しを伸ばして埋める。**まず、次の切り出しとのあいだ
 * （録画から切り取っていた待ち時間や文字の入力）を戻す。録画のとおりに続くので、つなぎ目は増えない。
 * それでも足りなければ、各切り出しの最後のコマで少しずつ止める。
 * はみ出したら、次の章を後ろへずらす（小節からは外れる）
 */
export const placed: PlacedClip[] = (() => {
  const flat = acts.flatMap((act) => act.clips);
  const list: PlacedClip[] = [];
  let index = 0;
  acts.forEach((act, i) => {
    const previousEnd = list.length ? list[list.length - 1].start + list[list.length - 1].length : 0;
    const actStart = Math.max(barFrame(act.bar), previousEnd);
    const actEnd = i + 1 < acts.length ? barFrame(acts[i + 1].bar) : OVERVIEW_START;
    const clips = act.clips.map((clip) => {
      const rate = clip.rate ?? 1;
      const next = flat[++index];
      // 次の切り出しが同じ録画の続きなら、そのあいだを戻せる
      const gap = next && next.source === clip.source && next.from >= clip.to ? next.from - clip.to : 0;
      return {
        clip,
        rate,
        base: Math.round(((clip.to - clip.from) * FPS) / rate),
        capacity: Math.floor((gap * FPS) / rate),
      };
    });
    const extra = Math.max(0, actEnd - actStart - clips.reduce((sum, c) => sum + c.base, 0));
    const capacity = clips.reduce((sum, c) => sum + c.capacity, 0);
    const fromGaps = Math.min(extra, capacity);
    const grown = clips.map((c) => (capacity ? Math.floor((fromGaps * c.capacity) / capacity) : 0));
    const holdTotal = extra - grown.reduce((sum, g) => sum + g, 0);
    let cursor = actStart;
    clips.forEach((c, j) => {
      const hold = Math.floor(holdTotal / clips.length) + (j === clips.length - 1 ? holdTotal % clips.length : 0);
      const length = c.base + grown[j] + hold;
      list.push({
        ...c.clip,
        to: c.clip.from + ((c.base + grown[j]) / FPS) * c.rate,
        act: act.name,
        start: cursor,
        length,
        hold,
      });
      cursor += length;
    });
  });
  return list;
})();

export const clipsEnd = placed[placed.length - 1].start + placed[placed.length - 1].length;

/** 録画の秒を、動画のフレームに移す（その切り出しの中で） */
export const frameOf = (clip: PlacedClip, sourceSeconds: number) =>
  clip.start + Math.round(((sourceSeconds - clip.from) * FPS) / (clip.rate ?? 1));

// MARK: - 寄り

export type ZoomTarget = Required<Omit<Zoom, "at">>;

/** 端末の見え方。拡大の倍率と、キャンバス上での平行移動（拡大の原点は端末の左上） */
export type Camera = { scale: number; x: number; y: number };

export const NEUTRAL_CAMERA: Camera = { scale: 1, x: 0, y: 0 };

/** 寄る・引くのにかける時間（約1.3秒）。短いと二段に動いて見え、目線が追いつかない */
const ZOOM_FRAMES = 40;
/** ゆるい加減速（ease-in-out） */
const ZOOM_EASE = Easing.bezier(0.42, 0, 0.58, 1);

const keyframes: { frame: number; target: ZoomTarget }[] = placed.flatMap((clip) =>
  (clip.zoom ?? []).map((z) => ({
    frame: frameOf(clip, z.at ?? clip.from),
    target: { x: z.x, y: z.y, scale: z.scale },
  })),
);
keyframes.sort((a, b) => a.frame - b.frame);

/**
 * 2つの見え方のあいだ。**倍率は比で補間する**（1→2 の途中を 1.5 ではなく √2 にする）。
 * 差で補間すると、寄り始めは遅く、寄り終わりは速く感じる
 */
function blend(from: Camera, to: Camera, progress: number): Camera {
  return {
    scale: from.scale * Math.pow(to.scale / from.scale, progress),
    x: from.x + (to.x - from.x) * progress,
    y: from.y + (to.y - from.y) * progress,
  };
}

/**
 * そのフレームでの見え方。寄り先ごとの見え方（toCamera で決める）へ、なめらかに移る。
 * **拡大と平行移動を同じ進み方で動かす。**別々に動かすと、途中で動きの向きが変わって見える
 */
export function cameraAt(frame: number, toCamera: (target: ZoomTarget) => Camera): Camera {
  let current = NEUTRAL_CAMERA;
  for (const key of keyframes) {
    if (key.frame > frame) break;
    const progress = interpolate(frame, [key.frame, key.frame + ZOOM_FRAMES], [0, 1], {
      easing: ZOOM_EASE,
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
    current = blend(current, toCamera(key.target), progress);
  }
  // 端末が出ていくときは寄りを戻す
  const release = interpolate(frame, [clipsEnd - ZOOM_FRAMES, clipsEnd], [0, 1], {
    easing: ZOOM_EASE,
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return blend(current, NEUTRAL_CAMERA, release);
}

// MARK: - 音

export const sfxEvents: { frame: number; name: SfxName; volume: number }[] = placed.flatMap((clip) =>
  (clip.sfx ?? [])
    .filter((s) => s.at >= clip.from && s.at < clip.to)
    .map((s) => ({ frame: frameOf(clip, s.at), name: s.name, volume: s.volume ?? 1 })),
);
