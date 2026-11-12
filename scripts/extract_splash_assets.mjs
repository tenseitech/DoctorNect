/**
 * Extract splash assets from design/Splash Screen.svg
 * Usage: node scripts/extract_splash_assets.mjs
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { Resvg } from '@resvg/resvg-js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');
const svgPath = path.join(repoRoot, 'design', 'Splash Screen.svg');
const outDir = path.join(repoRoot, 'frontend', 'assets', 'splash');
const designOut = path.join(repoRoot, 'design', 'splash_reference.png');

const W = 1242;
const H = 2208;

const gradientOnlySvg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}">
  <defs>
    <linearGradient id="linear-gradient" x1="34.25" y1="25.33" x2="1165.68" y2="2105.33" gradientUnits="userSpaceOnUse">
      <stop offset="0.10" stop-color="#32A5FE"/>
      <stop offset="0.31" stop-color="#166EFC"/>
      <stop offset="0.50" stop-color="#0A51EC"/>
      <stop offset="0.95" stop-color="#001FB3"/>
    </linearGradient>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#linear-gradient)"/>
</svg>`;

function extractBase64Png(svgText) {
  const m = svgText.match(
    /xlink:href="data:image\/png;base64,([^"]+)"/,
  );
  if (!m) throw new Error('embedded PNG not found in SVG');
  return Buffer.from(m[1], 'base64');
}

async function main() {
  fs.mkdirSync(outDir, { recursive: true });
  fs.mkdirSync(path.dirname(designOut), { recursive: true });

  const svgText = fs.readFileSync(svgPath, 'utf8');
  const srcPng = extractBase64Png(svgText);
  const srcPath = path.join(outDir, 'splash_logo_src.png');
  fs.writeFileSync(srcPath, srcPng);

  const srcMeta = await sharp(srcPng).metadata();
  const hasAlpha = srcMeta.hasAlpha === true;
  console.log(
    `splash_logo_src.png: ${srcMeta.width}x${srcMeta.height}, hasAlpha=${hasAlpha}`,
  );

  const logoW = 612;
  const logoH = 596;
  const logoPath = path.join(outDir, 'splash_logo.png');
  await sharp(srcPng)
    .resize(logoW, logoH, {
      kernel: sharp.kernel.lanczos3,
      fit: 'fill',
    })
    .png()
    .toFile(logoPath);
  console.log(`wrote ${logoPath} (${logoW}x${logoH}, non-uniform scale 1.18x1.24)`);

  if (srcMeta.width >= logoW * 2 && srcMeta.height >= logoH * 2) {
    await sharp(srcPng)
      .resize(logoW * 2, logoH * 2, { kernel: sharp.kernel.lanczos3, fit: 'fill' })
      .png()
      .toFile(path.join(outDir, '2.0x', 'splash_logo.png'));
    fs.mkdirSync(path.join(outDir, '2.0x'), { recursive: true });
    console.log('wrote 2.0x/splash_logo.png');
  } else {
    console.log(
      'SKIP 2x/3x: source 519x481 is too small for crisp @2x/@3x; ask designer for vector or >=1224px logo',
    );
  }

  const bgResvg = new Resvg(gradientOnlySvg, { fitTo: { mode: 'original' } });
  const bgPng = bgResvg.render().asPng();
  const bgPath = path.join(outDir, 'splash_background.png');
  fs.writeFileSync(bgPath, bgPng);
  console.log(`wrote ${bgPath} (${W}x${H}) via @resvg/resvg-js gradient SVG`);

  const fullResvg = new Resvg(svgText, { fitTo: { mode: 'original' } });
  const refPng = fullResvg.render().asPng();
  fs.writeFileSync(designOut, refPng);
  console.log(`wrote ${designOut} (${W}x${H}) via @resvg/resvg-js full SVG`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
