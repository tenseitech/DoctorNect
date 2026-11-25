#!/usr/bin/env node
'use strict';

/**
 * Generates every DoctorNect launcher-icon and splash raster from the vector master
 * assets/branding/doctornect_mark.svg, plus review previews in docs/branding_preview/.
 *
 *   node frontend/tools/generate_brand_assets.js            (from the repo root)
 *   cd frontend && dart run flutter_launcher_icons && dart run flutter_native_splash:create
 *
 * Uses sharp and @resvg/resvg-js from the repo-root node_modules (already installed).
 *
 * Geometry rules (Android / Material):
 *  - Adaptive icon: 108dp canvas, launcher masks show the centre 72dp, and only a 66dp
 *    circle is guaranteed visible. The whole mark (its bounding-box diagonal) is kept
 *    inside that circle with a small margin, so no mask can clip it.
 *  - Android 12+ splash icon without icon background: 288dp canvas, content must fit in
 *    a 192dp circle. Rendered at xxxhdpi (1152 px).
 *  - The pre-Android-12 / iOS splash image and the Flutter splash screen use the same
 *    1152 px composition and the same mark size (SPLASH_MARK_DP), so the hand-off from
 *    the native splash to Flutter does not move or resize the logo.
 */

const fs = require('fs');
const path = require('path');

const FRONTEND = path.resolve(__dirname, '..');
const REPO = path.resolve(FRONTEND, '..');
const sharp = require(path.join(REPO, 'node_modules/sharp'));
const { Resvg } = require(path.join(REPO, 'node_modules/@resvg/resvg-js'));

/** AppColors.doctorBlue (lib/core/theme/app_colors.dart). */
const BRAND_BLUE = '#1D4ED8';
const WHITE = '#FFFFFF';

const MASTER = path.join(FRONTEND, 'assets/branding/doctornect_mark.svg');
const master = fs.readFileSync(MASTER, 'utf8');
const inner = master.slice(master.indexOf('<g'), master.lastIndexOf('</g>') + 4);

// Bounding box of the mark inside the master's coordinate space (measured from the paths).
const MARK = { x0: 206.5, y0: 236, x1: 818.6, y1: 788.5 };
MARK.w = MARK.x1 - MARK.x0;
MARK.h = MARK.y1 - MARK.y0;
MARK.cx = (MARK.x0 + MARK.x1) / 2;
MARK.cy = (MARK.y0 + MARK.y1) / 2;
MARK.halfDiag = Math.hypot(MARK.w / 2, MARK.h / 2);

/** Mark width on the splash, in dp (native Android 12, pre-12, iOS and Flutter). */
const SPLASH_MARK_DP = 134;

function markSvg(size, { bg = null, color = WHITE, scale }) {
  const t = `translate(${size / 2} ${size / 2}) scale(${scale}) translate(${-MARK.cx} ${-MARK.cy})`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">` +
    (bg ? `<rect width="${size}" height="${size}" fill="${bg}"/>` : '') +
    `<g color="${color}" transform="${t}">${inner}</g></svg>`;
}

function render(svg) {
  return Buffer.from(new Resvg(svg, { shapeRendering: 2 }).render().asPng());
}

async function writePng(rel, svg, { flatten = false } = {}) {
  const out = path.join(FRONTEND, rel);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  let img = sharp(render(svg));
  if (flatten) img = img.flatten({ background: BRAND_BLUE }).removeAlpha();
  await img.png({ compressionLevel: 9 }).toFile(out);
  return out;
}

/** Scale so the mark's bounding-box diagonal fits a circle of `diameterFrac` of the canvas. */
const scaleForCircle = (size, diameterFrac, margin) => ((size * diameterFrac) / 2) * (1 - margin) / MARK.halfDiag;
/** Scale so the mark is `widthFrac` of the canvas wide. */
const scaleForWidth = (size, widthFrac) => (size * widthFrac) / MARK.w;

async function main() {
  const S = 1024;
  // Adaptive foreground / monochrome: inside the 66dp-of-108dp safe circle, 6% margin.
  const fgScale = scaleForCircle(S, 66 / 108, 0.06);
  // Legacy square icon (API < 26), iOS and web: mark 58% of the tile width.
  const fullScale = scaleForWidth(S, 0.58);

  await writePng('assets/icon/icon_foreground.png', markSvg(S, { scale: fgScale }));
  await writePng('assets/icon/icon_monochrome.png', markSvg(S, { scale: fgScale }));
  await writePng('assets/icon/icon_full.png', markSvg(S, { bg: BRAND_BLUE, scale: fullScale }), { flatten: true });
  fs.writeFileSync(path.join(FRONTEND, 'assets/branding/doctornect_app_icon.svg'),
    markSvg(S, { bg: BRAND_BLUE, scale: fullScale }) + '\n');

  // Legacy round launcher icons (API < 26 uses mipmap/ic_launcher_round directly).
  const roundSizes = { mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 };
  for (const [density, px] of Object.entries(roundSizes)) {
    const r = px / 2;
    const roundScale = scaleForCircle(px, 1, 0.24);
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${px}"><circle cx="${r}" cy="${r}" r="${r}" fill="${BRAND_BLUE}"/>` +
      `<g color="${WHITE}" transform="translate(${r} ${r}) scale(${roundScale}) translate(${-MARK.cx} ${-MARK.cy})">${inner}</g></svg>`;
    await writePng(`android/app/src/main/res/mipmap-${density}/ic_launcher_round.png`, svg);
  }

  // Splash: 1152 px = 288dp at xxxhdpi (4x). Mark width SPLASH_MARK_DP.
  const SP = 1152;
  const spScale = (SPLASH_MARK_DP * 4) / MARK.w;
  const spHalfDiagDp = (MARK.halfDiag * spScale) / 4;
  if (spHalfDiagDp * 2 > 192) throw new Error(`splash mark does not fit the 192dp circle (${spHalfDiagDp * 2}dp)`);
  await writePng('assets/splash/splash_android12.png', markSvg(SP, { scale: spScale }));
  await writePng('assets/splash/splash_logo.png', markSvg(SP, { scale: spScale }));

  // Flutter-side splash logo: tight crop of the same mark at 4x.
  const tight = `<svg xmlns="http://www.w3.org/2000/svg" width="${Math.round(MARK.w * spScale)}" height="${Math.round(MARK.h * spScale)}" viewBox="${MARK.x0} ${MARK.y0} ${MARK.w} ${MARK.h}"><g color="${WHITE}">${inner}</g></svg>`;
  await writePng('assets/splash/splash_mark.png', tight);

  console.log(JSON.stringify({
    adaptiveMarkWidthPx: Math.round(MARK.w * fgScale),
    legacyMarkWidthPx: Math.round(MARK.w * fullScale),
    splashMarkDp: SPLASH_MARK_DP,
    splashCircleDp: Math.round(spHalfDiagDp * 2),
    splashMarkAspect: +(MARK.w / MARK.h).toFixed(4),
  }));
}

main().catch((e) => { console.error(e); process.exit(1); });
