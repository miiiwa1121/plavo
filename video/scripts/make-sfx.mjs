// 効果音を作る。外部の素材は使わず、波形を計算して WAV に書き出す。
//
// 使い方: npm run sfx → public/sfx/*.wav
//
// どれも**控えめに**作る。BGM の下で「触った」「撮れた」が分かれば足りる。
// 音色を変えたら書き出し直すだけでよい（動画の側は名前で呼んでいる）

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const outDir = join(dirname(fileURLToPath(import.meta.url)), "../public/sfx");
const RATE = 44100;

/** 秒数ぶんの無音 */
const silence = (seconds) => new Float32Array(Math.round(seconds * RATE));

/** 決まった種から作る雑音。書き出すたびに音が変わらないように */
function noise(seed = 1) {
  let s = seed;
  return () => {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    return (s / 0x7fffffff) * 2 - 1;
  };
}

/** 指数で減っていく包絡。attack は立ち上がりの秒数 */
const envelope = (t, attack, decay) => (t < attack ? t / attack : Math.exp(-(t - attack) / decay));

/** 周波数が from から to へ滑る正弦波 */
function sweep(buffer, start, duration, from, to, decay, gain) {
  let phase = 0;
  const n = Math.round(duration * RATE);
  for (let i = 0; i < n; i++) {
    const t = i / RATE;
    const f = from + (to - from) * Math.min(1, t / duration);
    phase += (2 * Math.PI * f) / RATE;
    const at = Math.round(start * RATE) + i;
    if (at < buffer.length) buffer[at] += Math.sin(phase) * envelope(t, 0.003, decay) * gain;
  }
}

/** 鈴のような音。倍音を少し足す */
function bell(buffer, start, freq, decay, gain) {
  const n = Math.round(decay * 6 * RATE);
  for (let i = 0; i < n; i++) {
    const t = i / RATE;
    const at = Math.round(start * RATE) + i;
    if (at >= buffer.length) break;
    const e = envelope(t, 0.004, decay);
    buffer[at] +=
      (Math.sin(2 * Math.PI * freq * t) + 0.35 * Math.sin(2 * Math.PI * freq * 2.76 * t) * Math.exp(-t / 0.08)) *
      e * gain;
  }
}

/** 雑音に一次の低域通過を掛けた短い塊。cutoff は 0〜1（大きいほど明るい） */
function burst(buffer, start, duration, decay, cutoff, gain, seed) {
  const rand = noise(seed);
  let y = 0;
  const n = Math.round(duration * RATE);
  for (let i = 0; i < n; i++) {
    const t = i / RATE;
    y += cutoff * (rand() - y);
    const at = Math.round(start * RATE) + i;
    if (at < buffer.length) buffer[at] += y * envelope(t, 0.001, decay) * gain;
  }
}

const sounds = {
  // 触った。短く軽い「コッ」
  tap: () => {
    const b = silence(0.12);
    sweep(b, 0, 0.05, 1900, 1300, 0.012, 0.35);
    burst(b, 0, 0.02, 0.004, 0.6, 0.25, 7);
    return b;
  },
  // シャッター。2つの小さな機械音
  shutter: () => {
    const b = silence(0.35);
    burst(b, 0, 0.06, 0.012, 0.5, 0.7, 3);
    sweep(b, 0, 0.05, 220, 120, 0.02, 0.3);
    burst(b, 0.075, 0.08, 0.018, 0.35, 0.55, 11);
    return b;
  },
  // スタンプ・ハート。ぽん、と上がる
  pop: () => {
    const b = silence(0.3);
    sweep(b, 0, 0.12, 520, 1150, 0.06, 0.5);
    return b;
  },
  // 送信。短く上がる風の音
  send: () => {
    const b = silence(0.4);
    const rand = noise(5);
    let y = 0;
    const n = Math.round(0.32 * RATE);
    for (let i = 0; i < n; i++) {
      const t = i / RATE;
      const cutoff = 0.05 + 0.4 * (t / 0.32);
      y += cutoff * (rand() - y);
      b[i] += y * Math.sin((Math.PI * t) / 0.32) * 0.5;
    }
    sweep(b, 0.2, 0.08, 900, 1500, 0.04, 0.2);
    return b;
  },
  // 水。しずくが3つ落ちる
  water: () => {
    const b = silence(0.7);
    [0, 0.14, 0.3].forEach((at, i) => sweep(b, at, 0.06, 500 + i * 80, 1300 + i * 120, 0.035, 0.45));
    return b;
  },
  // センサーを土に刺す。やわらかく低い「とすっ」
  insert: () => {
    const b = silence(0.3);
    sweep(b, 0, 0.1, 260, 110, 0.035, 0.6);
    burst(b, 0, 0.06, 0.014, 0.12, 0.35, 13);
    return b;
  },
  // 日向。明るい鈴が上へ4つ
  sun: () => {
    const b = silence(1.6);
    [1046.5, 1318.5, 1568, 2093].forEach((f, i) => bell(b, i * 0.07, f, 0.3, 0.16));
    return b;
  },
  // 出会い・名前が決まった。鈴を2つ
  chime: () => {
    const b = silence(1.8);
    bell(b, 0, 1318.5, 0.35, 0.28);
    bell(b, 0.12, 1975.5, 0.4, 0.22);
    return b;
  },
};

function wav(samples) {
  const data = Buffer.alloc(samples.length * 2);
  samples.forEach((v, i) => data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, v)) * 32767), i * 2));
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + data.length, 4);
  header.write("WAVE", 8);
  header.write("fmt ", 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(RATE, 24);
  header.writeUInt32LE(RATE * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write("data", 36);
  header.writeUInt32LE(data.length, 40);
  return Buffer.concat([header, data]);
}

mkdirSync(outDir, { recursive: true });
for (const [name, make] of Object.entries(sounds)) {
  writeFileSync(join(outDir, `${name}.wav`), wav(make()));
}
console.log(`できました: public/sfx/（${Object.keys(sounds).join(" / ")}）`);
