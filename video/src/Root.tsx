import { Composition } from "remotion";
import { FPS, HEIGHT, WIDTH, totalFrames } from "./timeline";
import { Tour } from "./Tour";
import { TOTAL } from "./long/timeline";
import { TourLong } from "./long/TourLong";

export const Root: React.FC = () => (
  <>
    {/* 30秒版。各タブの操作だけ */}
    <Composition id="Tour" component={Tour} durationInFrames={totalFrames} fps={FPS} width={WIDTH} height={HEIGHT} />
    {/* 60秒版。カメラから始め、出会う → 話す → 残す → 分かち合う の流れで見せる。BGM と効果音つき */}
    <Composition id="TourLong" component={TourLong} durationInFrames={TOTAL} fps={FPS} width={WIDTH} height={HEIGHT} />
  </>
);
