"""准备已确认的国风手绘素材任务与风格参考；不修改参考项目。"""
from pathlib import Path
import argparse,json
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
STYLE=('Detailed hand-painted ancient Chinese Three Kingdoms strategy game illustration. '
       'Match the fine ink contours, fabric folds, layered lamellar armor, painted materials and soft dimensional shading of the reference. '
       'Natural modest facial features, slightly stylized three-and-a-half head proportions, readable silhouette, polished high resolution, harmonious restrained colors. ')
CUTOUT=(' Exactly ONE isolated complete subject, centered with wide empty margin around the whole subject including weapons and feet. '
        'Completely flat uniform bright green background #00ff00; no ground, no shadow on the background, no scenery, no text, no labels, no watermark, no border, no UI. ')
UNITS=[
 'a Chinese cavalry soldier mounted on a complete brown war horse with four correct legs and visible saddle, a long straight cavalry spear held diagonally to the right, dark red lacquered armor and helmet, a large deep red cape and red horse caparison, dark leather boots. Both the complete horse and rider must fit inside the image',
 'a Chinese infantry spearman, wearing dark red lacquered lamellar armor and helmet, red layered tunic and red cape, dark boots, holding a clearly separate large oval wooden shield in the LEFT hand and a long straight spear with silver spearhead in the RIGHT hand. An upright grounded ready stance',
 'a Chinese archer with dark red light lamellar armor, red helmet and red layered tunic, a clearly visible large recurved wooden bow in the left hand and a quiver of arrows on the back, holding a single arrow in the right hand, ready upright stance, no spear or shield',
 'a single complete small ancient Chinese river warship viewed from an elevated three-quarter angle, curved wooden hull with dark red gunwales and red trim, one large dark red rectangular canvas sail on a wooden mast, oars and a tiny sailor in red lamellar armor. This subject is a BOAT with a red sail, no human legs, no sea or water background',
 'an imposing Chinese elite heavy halberd infantryman with a wide sturdy silhouette, dark red thick overlapping lamellar armor, red iron helmet with a modest plume, reinforced broad bronze-edged shoulder guards, red armored skirt, a single large halberd with a clearly visible silver crescent side blade. No shield, no bow, broad heavy stance',
 'a mature Chinese military strategist with black scholar cap, neat moustache and short beard, a long layered deep red robe, deep red cloak, cloth belt and dark cloth shoes, holding a white feather fan at chest height. Slim calm silhouette, no metal helmet, no spear, no sword, no glowing magic orb',
]


def main():
 p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);args=p.parse_args();root=args.root
 (root/'reference').mkdir(parents=True,exist_ok=True);(root/'generated').mkdir(exist_ok=True)
 fm=Path('/Users/xiongjian/Downloads/changba/fmj_flutter/assets/modern');m=json.loads((fm/'enhanced-art.json').read_text())
 for key,name in [('world:archetype:guard:3/0','style-soldier.png'),('building:hall/0','style-building.png'),('plant:pine/0','style-tree.png')]:
  page,x,y,w,h=m['frames'][key];im=Image.open(fm/m['textures'][page]).convert('RGBA').crop((x,y,x+w,y+h));bg=Image.new('RGBA',im.size,(0,255,0,255));bg.alpha_composite(im);bg.convert('RGB').save(root/'reference'/name)
 jobs=[]
 def add(name,prompt,refs,kind='sprite',width=768,height=768,**extra):
  style=STYLE if name.startswith('unit-') else STYLE.replace('Natural modest facial features, slightly stylized three-and-a-half head proportions, ','')
  extra_constraint='' if name.startswith('unit-') else ' No people, no human figures, no creatures. '
  jobs.append(dict(id=name,prompt=style+prompt+extra_constraint+(CUTOUT if kind=='sprite' else ''),refs=refs,kind=kind,width=width,height=height,seed=241040+len(jobs)*37,**extra))
 for i,subject in enumerate(UNITS):
  add(f'unit-{i}-base',subject+'. Turned slightly three quarters toward the viewer, facing screen RIGHT. Large red surfaces on armor and clothing must occupy at least half the visible character.', ['reference/style-soldier.png'],width=512,height=640,type=i)
 add('city-capital','a fortified ancient Chinese capital city, enclosing gray brick walls, complete closed wall perimeter with a gate facing the viewer, several corner towers, a large central timber palace with layered blue-gray tile roofs, muted red timber posts, fine roof tile detail. Elevated orthographic three-quarter view. A single compact city complex, no terrain, no mountains, no streets outside the wall.', ['reference/style-building.png'],city='capital')
 add('city-fort','a compact ancient Chinese fortified walled town, complete low gray brick wall perimeter, one clearly visible central gate tower with blue-gray tiled roof and red timber posts, two smaller corner towers. Distinct from a palace capital, compact and easy to recognize as one city icon, elevated orthographic three-quarter view.', ['reference/style-building.png'],city='fort')
 add('city-harbor','a compact ancient Chinese river port fort, gray stone walls and gate tower with blue-gray tiled roofs, a short timber pier and a small moored wooden boat beside the wall, muted red timber pillars. Entire fort and pier visible, elevated orthographic three-quarter view, no water outside the subject.', ['reference/style-building.png'],city='harbor')
 add('terrain-mountain','a single compact cluster of weathered blue-gray rocky mountain peaks and pale exposed stone ledges, mossy olive slopes, several cracks and painted rock strata. Elevated three-quarter view, soft subtle shading, clear irregular natural silhouette, not sharp geometric polygons.', ['reference/style-building.png'],terrain='mountain')
 add('terrain-tree','a single compact grove of THREE mature ancient Chinese evergreen and deciduous trees with clearly visible gnarled trunks, dense olive green foliage clusters, fine painted leaves, soft layered light, elevated three-quarter view, complete canopy and trunks.', ['reference/style-tree.png'],terrain='tree')
 add('terrain-village','a small compact ancient Chinese village of THREE timber and plaster houses with blue-gray tiled roofs, red-brown beams, wooden doors and tiny windows, irregular grouping, all houses complete, elevated three-quarter view, no surrounding scenery.', ['reference/style-building.png'],terrain='village')
 add('terrain-camp','a compact ancient Chinese military encampment, three beige canvas tents with triangular silhouettes, low wooden palisade stakes, stacked supply boxes and one dark red military pennant with NO writing. Elevated three-quarter view, all poles and tents complete.', ['reference/style-building.png'],terrain='camp')
 add('icon-supplies','a single ancient military supply bundle: tied tan cloth grain sack with a few golden rice ears, one small wooden supply box beside it, hand painted fabric folds, no symbols or lettering.', ['reference/style-building.png'],icon='supplies')
 for name,subject in [('sun','one warm golden sun disk with short simple rays'),('cloud','one soft pale blue-gray layered rain cloud'),('wind','three clean curved wisps of moving pale air'),('rain','one dark blue-gray rain cloud and several clear blue falling raindrops'),('fog','three low layered soft gray fog banks')]:
  add('icon-'+name,subject+', a small clear painterly weather icon, bold simple silhouette with soft volume, fully separated from background.', ['reference/style-building.png'],width=512,height=512,icon=name)
 # 场景下方留出单位和动作的实际显示区域，装饰集中于远处边缘。
 for name,subject in [
  ('field','a broad empty natural grassland battlefield in ancient China, distant low olive hills and a sparse line of trees along the TOP edge, irregular earth and small grass clumps'),
  ('river','a broad empty riverbank battlefield in ancient China, soft curving blue-green river along the FAR UPPER edge, reeds and a small distant timber jetty, open packed earth foreground'),
  ('forest','an empty forest clearing battlefield in ancient China, mature pine and broadleaf trees framing the far TOP and side edges, distant mountains, broad empty earthy clearing'),
  ('siege','an empty ancient Chinese fortress approach, a complete gray stone wall with a timber gate tower in the FAR TOP background, red timber beams and blue-gray tile roof, broad open packed earth foreground'),
  ('victory','an empty peaceful ancient Chinese fortified city after a victorious defense, warm restrained golden afternoon light, red military banners on a distant gray stone gate tower, broad empty foreground with intact wooden shields and a lowered spear at the extreme side edge'),
  ('defeat','an empty ancient Chinese military encampment after a lost battle, muted blue-gray evening sky, a lowered tattered red pennant at the far edge, several abandoned supplies at the extreme side edge, quiet broad empty foreground, no gore'),
 ]:
  add('scene-'+name,subject+'. Painterly elevated camera about 25 degrees. The LOWER SEVENTY percent is open unobstructed ground for game units, all large buildings, trees and decorations stay at the far edges. No people, no creatures, no characters, no writing, no UI, no border, fill the entire canvas.', ['reference/style-building.png'],kind='scene',width=1280,height=768,scene=name)
 for name,subject in [('grass','muted olive grassland with small painted grass tufts and gentle mottled earth'),('dirt','warm beige-brown packed earth with subtle natural irregular pebbles and fine dry soil'),('water','muted blue-green river water, subtle softly painted ripples and small light reflections, no bank or objects')]:
  jobs.append(dict(id='ground-'+name,prompt='A seamless top down orthographic hand-painted ancient Chinese strategy game ground texture. '+subject+'. Soft detailed painted materials. Uniform neutral illumination, continuous natural surface filling the entire canvas edge to edge. No repeated square tiles, no grid, no border, no frame, no horizon, no cast shadow, no objects, no text, no people.',refs=[],kind='surface',width=768,height=768,seed=241113+len(jobs)*37,ground=name))
 (root/'requests.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2)+'\n');print('Prepared',len(jobs),'hand-painted jobs at',root)

if __name__=='__main__':main()
