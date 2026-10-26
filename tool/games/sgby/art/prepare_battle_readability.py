"""为16点战场补充可辨认的盾矛、长弓箭筒与近景城门，沿用已确认角色与画风。"""
from pathlib import Path
import argparse,json


def main():
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);root=p.parse_args().root
    jobs=json.loads((root/'requests.json').read_text());known={j['id'] for j in jobs};plan=[]
    entries=[
        ('field-infantry-v2','generated/unit-1-corrected.png',512,640,
         'Edit this EXACT same infantryman for readability as a SMALL tactical-map sprite. Keep his exact face, red helmet, red clothing, body proportions and whole standing ready pose. Make his oval shield MUCH LARGER, a broad oval reaching from chest to shin, with a clearly visible thick BRONZE RIM and dark RED lacquered wooden center. The shield occupies nearly half the body silhouette on his shield arm. The other hand holds ONE long straight spear with ONE silver point and a plain wooden butt. No bow, no arrows, no additional weapon. Fine hand-painted outlines, metal highlights and detailed wood, soft dimensional shading, same three-quarter camera and face toward screen RIGHT. Whole complete person, feet and spear fit with large margin on perfectly uniform bright green #00ff00 backdrop. No floor, no text, no extra people.'),
        ('field-archer-v2','generated/unit-2-base.png',512,640,
         'Edit this EXACT same archer for readability as a SMALL tactical-map sprite. Keep his exact face, red helmet, red light clothing, body proportions and complete standing ready pose. Make his recurved BOW much larger and visually stronger, a clearly open curved C silhouette with thick golden-brown polished wooden limbs in front of his left side. Enlarge the arrow QUIVER on his back, with FIVE distinct WHITE feather arrow tails clearly projecting above his shoulder. His ready bow is lowered and not drawn, one correct hand grips it. No shield, no spear, no extra weapon, no extra hands. Preserve the fine hand-painted lines, carved wood details, red cloth folds and soft dimensional shading, same three-quarter view toward screen RIGHT. Complete body, boots, bow tips and arrows fit with wide margin on perfectly uniform bright green #00ff00 backdrop. No floor, no text, no additional people.'),
        ('battle-city-gate-v2','generated/city-fort-final.png',512,512,
         'Create a CLOSE VIEW game icon of ONLY the FRONT FORTIFIED GATE of this exact Chinese walled town. A large central gray-brick arched gate tower, a single prominent blue-gray tiled roof with upturned eaves, red timber supports, two short flanking crenellated stone walls, and a broad light-gray paved stone foundation. The large DARK OPEN ARCH starts at ground level and is very clearly visible from outside. Complete compact icon, same elevated three-quarter camera, detailed fine hand-painted stone, tiles and wood with soft dimensional shading. Main gate fills most of the icon, no courtyard buildings and no sprawling city complex. No people, no flags, no letters, no symbols. Entire gate, walls and foundation fit inside the canvas with generous margin. Perfectly uniform flat bright green #00ff00 background, no surrounding terrain, no scenery.'),
    ]
    for i,(id,ref,w,h,prompt) in enumerate(entries):
        plan.append(id)
        if id not in known:jobs.append(dict(id=id,prompt=prompt,refs=[ref],kind='sprite',width=w,height=h,seed=257300+i*47))
    (root/'requests.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2)+'\n')
    (root/'readability_jobs.json').write_text(json.dumps(plan,indent=2)+'\n')
    selected=json.loads((root/'selection.json').read_text());selected['battleUnits']={'1':'field-infantry-v2','2':'field-archer-v2'};selected['battleCity']='battle-city-gate-v2'
    # 此套重装兵原稿除出刺帧外均朝左，离线归一化为朝右；阵营镜像仍由运行时完成。
    selected.setdefault('facingCorrections',{'normal':{'4':['idle','stride','windup','hit','down']},'defeat':['4']})
    (root/'selection.json').write_text(json.dumps(selected,ensure_ascii=False,indent=2)+'\n')


if __name__=='__main__':main()
