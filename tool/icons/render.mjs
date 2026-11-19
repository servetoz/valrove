// Renders every app icon from valrove-icon.svg (project root).
//
//   npm --prefix tool/icons install
//   node tool/icons/render.mjs && dart run flutter_launcher_icons
//
// Writes the artwork that flutter_launcher_icons turns into the Android and
// iOS launcher icons (assets/icon/), plus the in-app logo (assets/brand/).
// The monochrome icon is built from the SVG paths with the ids `puck-outline`,
// `v-outline` and `rim-sparkle`.
import { Resvg } from '@resvg/resvg-js';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const source = fs.readFileSync(path.join(root, 'valrove-icon.svg'), 'utf8');

/** Tile behind the puck: adaptive icon background and iOS icon. Keep in sync
 * with `adaptive_icon_background` in pubspec.yaml. */
const TILE = '#000429';

/** Puck diameter on the 108dp adaptive icon canvas. Launchers show the central
 * 72dp, cut to their icon shape, and always keep the central 66dp. */
const PUCK_DP = 56;

const [vx, vy, vw, vh] = source.match(/viewBox="([^"]+)"/)[1].trim().split(/[\s,]+/).map(Number);

const render = (svg, size, background) =>
  new Resvg(svg, { fitTo: { mode: 'width', value: size }, background }).render();

/** Same artwork, showing the square [cx ± side/2, cy ± side/2] of the canvas. */
const framed = (svg, cx, cy, side) =>
  svg.replace(/<svg\b[^>]*>/, (tag) =>
    tag
      .replace(/viewBox="[^"]*"/, `viewBox="${cx - side / 2} ${cy - side / 2} ${side} ${side}"`)
      .replace(/\swidth="[^"]*"/, ` width="${side}"`)
      .replace(/\sheight="[^"]*"/, ` height="${side}"`),
  );

/** Bounds of the visible pixels, in viewBox units. */
function bounds(svg) {
  const img = render(svg, Math.round(vw));
  const { width, height, pixels } = img;
  let x0 = width, y0 = height, x1 = -1, y1 = -1;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (pixels[(y * width + x) * 4 + 3] === 0) continue;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }
  }
  if (x1 < 0) throw new Error('nothing visible');
  const k = vw / width;
  const box = { x: vx + x0 * k, y: vy + y0 * k, w: (x1 + 1 - x0) * k, h: (y1 + 1 - y0) * k };
  return { ...box, cx: box.x + box.w / 2, cy: box.y + box.h / 2, side: Math.max(box.w, box.h) };
}

function write(file, image) {
  const out = path.join(root, file);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, image.asPng());
  console.log(`${file.padEnd(32)} ${image.width}x${image.height}`);
}

const art = bounds(source);

// Android adaptive foreground: the puck centred on the 108dp canvas, with the
// tile colour around it inside every launcher shape.
write('assets/icon/foreground.png', render(framed(source, art.cx, art.cy, (art.side * 108) / PUCK_DP), 1024));

// Android 7.x launcher icon (no masking there): the round puck itself, 44dp
// of a 48dp canvas like other round legacy icons.
write('assets/icon/android_legacy.png', render(framed(source, art.cx, art.cy, (art.side * 48) / 44), 1024));

// iOS: opaque tile, the puck at 80% of it; iOS rounds the corners itself.
write('assets/icon/ios.png', render(framed(source, art.cx, art.cy, art.side / 0.8), 1024, TILE));

// Google Play listing: the same tile at 512px; Play rounds the corners itself.
write('docs/play-store/icon-512.png', render(framed(source, art.cx, art.cy, art.side / 0.8), 512, TILE));

// Android 13+ themed icon: the V and the sparkle as a silhouette (the system
// tints it), 50dp wide on the 108dp canvas, centred.
const pathData = (id) => {
  const element = source.match(new RegExp(`<path\\b[^>]*\\bid="${id}"[^>]*>`, 's'));
  if (!element) throw new Error(`valrove-icon.svg has no <path id="${id}">`);
  return element[0].match(/\sd="([^"]+)"/)[1];
};
const glyph = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${vx} ${vy} ${vw} ${vh}" width="${vw}" height="${vh}">
  <clipPath id="puck"><path d="${pathData('puck-outline')}"/></clipPath>
  <path d="${pathData('v-outline')}" fill="#fff" fill-rule="evenodd" clip-path="url(#puck)"/>
  <path d="${pathData('rim-sparkle')}" fill="#fff"/>
</svg>`;
const mark = bounds(glyph);
write('assets/icon/monochrome.png', render(framed(glyph, mark.cx, mark.cy, (mark.w * 108) / 50), 1024));

// In-app logo (84dp at 1x), trimmed to the puck.
for (const [dir, scale] of [['', 1], ['2.0x/', 2], ['3.0x/', 3]]) {
  write(`assets/brand/${dir}logo.png`, render(framed(source, art.cx, art.cy, art.side * 1.02), 84 * scale));
}
