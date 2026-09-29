import { Easing, interpolate } from "remotion";
import { acts, type ActName, type Clip, type SfxName, type Zoom } from "./cuts";

export const FPS = 30;
export const WIDTH = 1080;
export const HEIGHT = 1920;
export const TOTAL = 60 * FPS;

// BGM「Morning」（しゃろう・OpenTracks）の拍。約118 BPM、最初の拍は 0.031 秒。
// 録音を測って決めた。曲を替えたら測り直す
const BEAT = 0.5095;
const FIRST_BEAT = 0.031;
const BAR = BEAT * 4;

/** その小節の頭のフレーム */
export const barFrame = (bar: number) => Math.round((FIRST_BEAT + BAR * bar) * FPS);

export const INTRO_END = barFrame(2);
export const OVERVIEW_START = barFrame(25);
export const OUTRO_START = barFrame(27);

export type PlacedClip = Clip & { act: ActName; start: number; length: number };

/**
 * 切り出しを章ごとに並べる。章は小節の頭から始め、足りなければ章の最後の切り出しを
 * 録画の先まで伸ばして埋める。はみ出したら、次の章を後ろへずらす（小節からは外れる）
 */
export const placed: PlacedClip[] = (() => {
  const list: PlacedClip[] = [];
  acts.forEach((act, i) => {
    const previousEnd = list.length ? list[list.length - 1].start + list[list.length - 1].length : 0;
    let cursor = Math.max(barFrame(act.bar), previousEnd);
    const actEnd = i + 1 < acts.length ? barFrame(acts[i + 1].bar) : OVERVIEW_START;
    act.clips.forEach((clip, j) => {
      const rate = clip.rate ?? 1;
      let length = Math.round(((clip.to - clip.from) * FPS) / rate);
      const isLast = j === act.clips.length - 1;
      if (isLast && cursor + length < actEnd) {
        length = actEnd - cursor;
      }
      list.push({ ...clip, to: clip.from + (length / FPS) * rate, act: act.name, start: cursor, length });
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

/** 寄る・引くのにかける時間。短いと二段に動いて見える */
const ZOOM_FRAMES = 28;
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
