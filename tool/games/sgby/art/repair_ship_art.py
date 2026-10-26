"""以同一完整船体和已核对弓兵合成小比例船员，拒绝巨人船员和随机变形的船帧。"""
from pathlib import Path
import argparse
import hashlib
import json

import cv2
import numpy as np
from PIL import Image, ImageOps

from handpainted_matting import cutout
from pack_handpainted import standalone


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True)
    root=parser.parse_args().root;raw=root/'generated'
    base=cutout(Image.open(raw/'unit-3-base.png'))
    rgb=np.asarray(Image.open(raw/'unit-3-base.png').convert('RGB'))
    if rgb.shape[:2]!=(640,512):raise ValueError('船体原稿改变，需重新核对船员和船舷遮罩')
    mask=np.zeros(rgb.shape[:2],np.uint8)
    cv2.fillPoly(mask,[np.array([(312,369),(347,369),(354,450),(306,452)],np.int32)],255)
    empty=cutout(Image.fromarray(cv2.inpaint(rgb,mask,5,cv2.INPAINT_TELEA)))
    # 船员在甲板后层，近侧船舷在前层，脚不会悬在船外或覆盖木质船身。
    foreground=np.zeros(rgb.shape[:2],np.uint8)
    cv2.fillPoly(foreground,[np.array([(278,456),(452,371),(512,371),(512,640),(278,640)],np.int32)],255)
    front=empty.copy();front.putalpha(Image.fromarray(np.minimum(np.asarray(empty.getchannel('A')),foreground)))

    def save(name,image,refs,transform):
        path=raw/(name+'.png');image.save(path)
        record=dict(id=name,model='derived composition of verified local MFLUX artwork',refs=['generated/'+ref+'.png' for ref in refs],transform=transform,sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        path.with_suffix('.provenance.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
    for pose,source in [('windup','unit-2-windup-single'),('attack','unit-2-attack-release')]:
        crew=ImageOps.contain(standalone(raw/(source+'.png'),True),(100,100),Image.Resampling.LANCZOS)
        image=empty.copy();image.alpha_composite(crew,(287,455-crew.height));image.alpha_composite(front)
        save('unit-3-'+pose+'-layered',image,['unit-3-base',source],
             'remove original tiny crew within polygon; one archer at 100px maximum body/bow height; original near gunwale occludes legs')
    for angle in [0,3,7,12]:
        image=base.rotate(-angle,resample=Image.Resampling.BICUBIC,expand=True)
        save('unit-3-list-'+str(angle),image,['unit-3-base'],f'rigid complete boat lists {angle} degrees; exact same mast, sail, hull, oars and tiny crew; runtime waterline controls sinking')
    selection=json.loads((root/'selection.json').read_text());actions=selection['singleActions']['3']
    actions['windup']='unit-3-windup-layered';actions['attack']='unit-3-attack-layered'
    actions['hit']='unit-3-list-3';actions['down']='unit-3-list-12'
    selection['singleDefeat']['3']=['unit-3-list-'+str(a) for a in [0,0,3,7,12,12]]
    (root/'selection.json').write_text(json.dumps(selection,ensure_ascii=False,indent=2)+'\n')
    print('水军复用完整船体、小比例船员和船舷遮挡；退场倾侧由原帧驱动。')


if __name__=='__main__':main()
