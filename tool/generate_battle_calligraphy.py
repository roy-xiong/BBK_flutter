"""从OFL字体抽取本轮已确认的战斗书法字轮廓；输出矢量美术，不替换游戏菜单字体。"""
from pathlib import Path
import hashlib,json,shutil
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.qu2cuPen import Qu2CuPen

root=Path(__file__).resolve().parents[1]
source=root/'build/battle-calligraphy/MaShanZheng-Regular.ttf'
assert hashlib.sha256(source.read_bytes()).hexdigest()=='6d2546bb189c732a8ca29af9e22457b152387d158aa459e4ac2ce1e51788b7fb'
font=TTFont(source);glyphs=font.getGlyphSet();cmap=font.getBestCmap();units=font['head'].unitsPerEm
characters='攻防速毒乱封眠休生伤杜景死惊开降魔'
lines=["import 'dart:ui';",'', '/// 马善政书法字体的战斗专用矢量字形；SIL OFL 1.1，授权见licenses/fonts。', '/// 由tool/generate_battle_calligraphy.py生成，不依赖系统回退，也不改变菜单字体。', 'abstract final class BattleCalligraphy {', '  static final Map<String, Path> glyphs = {']
for char in characters:
 pen=RecordingPen();glyphs[cmap[ord(char)]].draw(Qu2CuPen(pen,max_err=1,all_cubic=True))
 lines.append(f"    '{char}': Path()")
 for operation,points in pen.value:
  numbers=[coordinate/units*(1 if axis==0 else -1)for point in points for axis,coordinate in enumerate(point)]
  args=', '.join(f'{n:.5f}'for n in numbers)
  method={'moveTo':'moveTo','lineTo':'lineTo','curveTo':'cubicTo','closePath':'close'}[operation]
  lines.append(f'      ..{method}({args})')
 lines[-1]+=','
lines+=['  };','}','']
(root/'lib/games/fmj/ui/battle_calligraphy.dart').write_text('\n'.join(lines))
shutil.copy2(root/'build/battle-calligraphy/OFL.txt',root/'licenses/fonts/MaShanZheng-OFL.txt')
(root/'licenses/fonts/MaShanZheng-source.json').write_text(json.dumps({'source':'https://github.com/google/fonts/tree/main/ofl/mashanzheng','file':'MaShanZheng-Regular.ttf','sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'use':'战斗字形矢量轮廓','characters':characters,'license':'SIL OFL 1.1'},ensure_ascii=False,indent=2)+'\n')
print('generated',len(characters),'battle-only calligraphy glyphs')
