import { Composition } from "remotion";
import { FPS, HEIGHT, WIDTH, totalFrames } from "./timeline";
import { Tour } from "./Tour";

export const Root: React.FC = () => (
  <Composition
    id="Tour"
    component={Tour}
    durationInFrames={totalFrames}
    fps={FPS}
    width={WIDTH}
    height={HEIGHT}
  />
);
