"""从项目已经采用的OFL书法字体提取片尾矢量字形，避免系统字体或低分辨率位图。"""
from pathlib import Path
import hashlib,json
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.qu2cuPen import Qu2CuPen
root=Path(__file__).resolve().parents[1]
p=root/'build/battle-calligraphy/MaShanZheng-Regular.ttf'
assert hashlib.sha256(p.read_bytes()).hexdigest()=='6d2546bb189c732a8ca29af9e22457b152387d158aa459e4ac2ce1e51788b7fb'
font=TTFont(p);units=font['head'].unitsPerEm;glyphs=font.getGlyphSet();cmap=font.getBestCmap()
pen=RecordingPen();glyphs[cmap[ord('完')]].draw(Qu2CuPen(pen,max_err=1,all_cubic=True))
lines=["import 'dart:ui';",'', '/// 马善政书法字体的片尾矢量字形；SIL OFL 1.1，授权见licenses/fonts。','/// 由tool/generate_ending_calligraphy.py生成，游戏运行时无需加载另一份字体。','abstract final class EndingCalligraphy {','  static final Path glyph = Path()']
for op,points in pen.value:
 method={'moveTo':'moveTo','lineTo':'lineTo','curveTo':'cubicTo','closePath':'close'}[op]
 values=[n/units*(1 if axis==0 else -1) for point in points for axis,n in enumerate(point)]
 lines.append('    ..'+method+'('+', '.join(f'{n:.5f}' for n in values)+')')
lines[-1]+=';';lines+=['}',''];(root/'lib/games/fmj/ui/ending_calligraphy.dart').write_text('\n'.join(lines))
p=root/'licenses/fonts/MaShanZheng-source.json';x=json.loads(p.read_text());x['additionalUse']={'characters':'完','use':'片尾专用矢量轮廓','generator':'tool/generate_ending_calligraphy.py'};p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n')
print('generated ending vector glyph')
