import { Composition } from "remotion";
import { FPS, HEIGHT, WIDTH, totalFrames } from "./timeline";
import { Tour } from "./Tour";
import { TOTAL } from "./long/timeline";
import { TourLong, TourLongWide } from "./long/TourLong";

export const Root: React.FC = () => (
  <>
    {/* 30秒版。各タブの操作だけ */}
    <Composition id="Tour" component={Tour} durationInFrames={totalFrames} fps={FPS} width={WIDTH} height={HEIGHT} />
    {/* 約64秒版。カメラから始め、出会う → 話す → 記録する → 共有する の流れで見せる。BGM と効果音つき */}
    <Composition id="TourLong" component={TourLong} durationInFrames={TOTAL} fps={FPS} width={1080} height={1920} />
    {/* 約64秒版の横画面。構成・時間・寄り先は縦画面と同じで、置き場所だけが違う（long/layout.ts） */}
    <Composition id="TourLongWide" component={TourLongWide} durationInFrames={TOTAL} fps={FPS} width={1920} height={1080} />
  </>
);
