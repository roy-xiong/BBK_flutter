// 只负责把设计 SVG 光栅化；运行时不依赖本工具或 sharp。
const fs = require('node:fs');
const path = require('node:path');
const sharp = require(process.env.BBK_SHARP_MODULE || 'sharp');
(async () => {
  for (const theme of ['light', 'dark']) {
    for (const kind of ['icon', 'console']) {
      const base = path.join('assets', 'branding', `${kind}-${theme}`);
      await sharp(`${base}.svg`, {density:144}).resize(1024,1024).png().toFile(`${base}.png`);
    }
  }
})().catch(error => { console.error(error); process.exit(1); });
