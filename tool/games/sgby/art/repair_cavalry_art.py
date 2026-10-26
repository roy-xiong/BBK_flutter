"""将骑手、倒地马匹分别生成和核对后合成，避免模型在双主体中混合人体与马体。"""
from pathlib import Path
import argparse
import hashlib
import json

import cv2
import numpy as np
from PIL import Image, ImageOps

from pack_handpainted import standalone


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--compose',action='store_true')
    args=parser.parse_args();root=args.root;raw=root/'generated'
    if not args.compose:
        jobs=json.loads((root/'requests.json').read_text());known={j['id'] for j in jobs}
        entries=[
            ('cavalry-horse-alone','generated/unit-0-corrected.png',
             'REMOVE the human rider completely. Show ONLY the ONE complete brown horse from this picture, with its same red caparison, saddle and reins, standing alone. No human being and no human body parts. Keep all FOUR horse legs, whole animal body, horse head and tail, same exact fine hand-painted Chinese game style and soft volume. Uniform bright green background. No ground or text.'),
            ('cavalry-horse-falling','generated/cavalry-horse-alone.png',
             'The ONE horse has COLLAPSED ONTO ITS RIGHT SIDE, with its WHOLE BODY LOW ON THE GROUND. Show a real complete horse body lying down, FOUR horse legs tucked naturally beside its belly, head near the ground, red caparison and saddle on the back. The horse is NOT standing and NOT sitting upright. No rider, no people, no human parts. Same hand-painted horse identity, proportions and camera. Entire animal fits with green margin. Flat bright green backdrop, no floor, no text.'),
            ('cavalry-horse-settled','generated/cavalry-horse-falling.png',
             'Keep ONLY this one complete horse lying on its SIDE. Lower its muzzle to rest on the ground and relax its tucked four legs. Its whole belly stays low; preserve the same brown body, red caparison, saddle, tail and the exact same hand-painted outline. No humans, no rider, no blood. Entire animal fits inside a plain bright green background with generous margin. No ground, no text.'),
            ('cavalry-rider-alone','generated/unit-0-corrected.png',
             'REMOVE the horse entirely. Show ONLY the SAME red-armored cavalryman DISMOUNTED and standing ON FOOT. ONE complete human man with a red helmet, same face, dark red lamellar armor and cape, red skirt over dark trousers, two hands, two legs and dark boots. He holds one long spear. Same slightly stylized three-and-a-half head proportions, fine Chinese hand-painted lines and soft volume. No horse, no animal parts, no other person. Whole body and spear fit with generous green margin. Uniform bright green background, no floor, no text.'),
            ('cavalry-rider-falling','generated/cavalry-rider-alone.png',
             'This SAME ONE cavalryman has fallen LOW onto his RIGHT SIDE, his left hand braced on the ground, his upper body near the floor, two complete bent legs together to the side, exactly two arms. He is NOT standing. Same red helmet, red armor, cape, dark trousers and boots. Keep whole human anatomy connected, no horse and no animal parts. His one spear is beside him, never through his body. Same fine hand-painted style and identity. Entire figure fits with wide margin on a bright green background, no ground, no text, no blood.'),
            ('cavalry-rider-settled','generated/cavalry-rider-alone.png',
             'This SAME ONE complete cavalryman lies SETTLED ON HIS RIGHT SIDE with his helmeted head low and eyes closed. The red armored torso, two arms and two clothed legs connect naturally. Both legs lie to one side; no crouching, no standing. Keep the same red helmet, red armor and cape, dark trousers and boots, one spear lying BESIDE the body. No horse, no animal parts, no second body. Same fine hand-painted identity. Entire body and spear fit with wide green margin. Bright green backdrop, no floor, no text, no blood.'),
            ('cavalry-horse-falling-red','generated/cavalry-horse-falling.png',
             'Add a LARGE DEEP RED EMBROIDERED HORSE BLANKET under the saddle, draping over this lying horse back and upper side. The blanket has a thin gold embroidered edge like traditional Chinese cavalry caparison. Keep the exact complete brown horse, all its four tucked legs, lowered head, tail, saddle and collapsed pose unchanged. No humans, no rider, no face except the horse head. Fine hand-painted game style, same uniform green background, no ground or text.'),
            ('cavalry-horse-settled-red','generated/cavalry-horse-settled.png',
             'Add a LARGE DEEP RED EMBROIDERED HORSE BLANKET under the saddle, draping over this lying horse back and upper side. The blanket has a thin gold embroidered edge like traditional Chinese cavalry caparison. Keep the exact complete brown horse, all its four tucked legs, lowered head, tail, saddle and settled pose unchanged. No humans, no rider, no face except the horse head. Fine hand-painted game style, same uniform green background, no ground or text.'),
            ('cavalry-dropped-spear',None,
             'ONE isolated complete ancient Chinese long cavalry spear lying horizontally. A straight long slender brown wooden shaft, a single small silver triangular spearhead at the RIGHT tip, a plain rounded wooden butt at the LEFT end. Fine hand-painted Chinese game art, dark clean contour, visible wood grain, silver painted highlights, soft dimensional shading. ONLY THE SPEAR, no human, no hand, no horse, no creature, no holder, no decoration, no second weapon, no shadow, no floor, no writing. Plain uniform bright green background. Full spear fits inside with generous empty margin.'),
        ]
        plan=[]
        for index,(name,ref,prompt) in enumerate(entries):
            plan.append(name)
            if name not in known:
                jobs.append(dict(id=name,refs=[ref] if ref else [],prompt=prompt,kind='sprite',width=512,height=256 if ref is None else 640,seed=251900+index*53))
        (root/'requests.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2)+'\n')
        (root/'cavalry_jobs.json').write_text(json.dumps(plan,indent=2)+'\n')
        return
    for pose,horse,rider in [
        ('fall','cavalry-horse-falling-red','cavalry-rider-falling'),
        ('ground','cavalry-horse-settled-red','cavalry-rider-settled'),
    ]:
        animal=standalone(raw/(horse+'.png'),True)
        # 去掉原稿中悬空斜举的长枪，再按人体本身而非枪尖外包框确定人马比例。
        # 遮罩仅沿枪杆，不经过头脸；握枪手的轮廓留作受伤后自然收拢的手势。
        rgb=np.asarray(Image.open(raw/(rider+'.png')).convert('RGB'))
        mask=np.zeros(rgb.shape[:2],np.uint8)
        start,end,hand=((454,110),(189,500),(311,333)) if pose=='fall' else ((44,20),(495,546),(319,333))
        cv2.line(mask,start,end,255,24);cv2.circle(mask,hand,18,0,-1)
        cleaned=Image.fromarray(cv2.inpaint(rgb,mask,5,cv2.INPAINT_TELEA))
        cleaned_name=rider+'-unarmed';cleaned_path=raw/(cleaned_name+'.png');cleaned.save(cleaned_path)
        human=standalone(cleaned_path,True)
        # 同一地面上，马在后层、骑手在近侧；两套完整解剖均保留，不把两者互相截肢。
        # 人的头到脚长度约为马身长的六成，符合军人和坐骑的相对尺度。
        canvas=Image.new('RGBA',(640,400))
        animal=ImageOps.contain(animal,(520,245),Image.Resampling.LANCZOS)
        human=ImageOps.contain(human,(345,230),Image.Resampling.LANCZOS)
        canvas.alpha_composite(animal,(55,340-animal.height))
        canvas.alpha_composite(human,(210,385-human.height))
        spear=ImageOps.contain(standalone(raw/'cavalry-dropped-spear.png',True),(310,35),Image.Resampling.LANCZOS)
        canvas.alpha_composite(spear,(75,390-spear.height))
        name='unit-0-'+pose+'-composite';path=raw/(name+'.png');canvas.save(path)
        provenance=dict(id=name,model='composition of separately verified MFLUX horse and rider',
                        refs=['generated/'+horse+'.png','generated/'+rider+'.png','generated/cavalry-dropped-spear.png'],
                        transform='remove floating spear with narrow inpaint mask excluding hand and face; scale full human body to horse; horse behind rider; spear on ground; transparent PNG',
                        weaponMask=dict(start=start,end=end,width=24,protectedHand=hand),
                        inputs=[json.loads((raw/(source+'.provenance.json')).read_text()) for source in [horse,rider,'cavalry-dropped-spear']],
                        sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        path.with_suffix('.provenance.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n')
    selection=json.loads((root/'selection.json').read_text())
    selection['singleActions']['0']['down']='unit-0-ground-composite'
    selection['singleDefeat']['0'][3]='unit-0-fall-composite'
    selection['singleDefeat']['0'][4:]=['unit-0-ground-composite']*2
    (root/'selection.json').write_text(json.dumps(selection,ensure_ascii=False,indent=2)+'\n')
    print('骑兵侧倒与接地已从两套完整解剖合成；请检查后再进入候选图集。')


if __name__=='__main__':
    main()
