import { clips, type Clip } from "./cuts";

export const FPS = 30;
export const WIDTH = 1080;
export const HEIGHT = 1920;

/** はじめの「plavo」だけの間 */
export const INTRO = 42;
/** 終わりの「plavo」の間 */
export const OUTRO = 54;

export type PlacedClip = Clip & {
  /** 動画の中で始まるフレーム */
  start: number;
  /** 動画の中での長さ（フレーム） */
  length: number;
};

/** 切り出しを動画の時間に並べる。速さを変えた切り出しは、そのぶん短く（長く）なる */
export const placed: PlacedClip[] = clips.reduce<PlacedClip[]>((list, clip) => {
  const previous = list.at(-1);
  const start = previous ? previous.start + previous.length : INTRO;
  const length = Math.round(((clip.to - clip.from) * FPS) / (clip.rate ?? 1));
  return [...list, { ...clip, start, length }];
}, []);

const last = placed.at(-1)!;
export const clipsEnd = last.start + last.length;
export const totalFrames = clipsEnd + OUTRO;
