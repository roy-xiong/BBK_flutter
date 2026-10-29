"""柳清风成年比例：保留角色身份、空手地图四向和持剑战斗动作的原资源键。"""
from pathlib import Path
import json
from PIL import Image,ImageOps,ImageDraw
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'assets/fmj/modern';SOURCES=ROOT/'tool/art_sources/hero-v10'
R=Image.Resampling.LANCZOS


def figures(sheet, count):
    """按透明轮廓切出完整人物，不能用等宽列裁切越过列边界的袖子或剑尖。"""
    alpha=np.array(sheet.getchannel('A'))
    mask=Image.fromarray(np.where(alpha>48,255,0).astype('uint8')).copy()
    result=[]
    while True:
        values=np.array(mask);ys,xs=np.where(values==255)
        if not len(xs):break
        ImageDraw.floodfill(mask,(int(xs[0]),int(ys[0])),128)
        component=np.array(mask)==128
        if int(component.sum())>1200:
            yy,xx=np.where(component);box=(int(xx.min()),int(yy.min()),int(xx.max()+1),int(yy.max()+1))
            im=sheet.copy();im.putalpha(Image.fromarray(np.where(component,alpha,0).astype('uint8')))
            result.append((box[0],im.crop(box)))
        values=np.array(mask);values[component]=0;mask=Image.fromarray(values).copy()
    result.sort(key=lambda pair:pair[0])
    assert len(result)==count,[(x,im.size)for x,im in result]
    return [im for _,im in result]


def fitted(source,w,h):
    im=source.convert('RGBA');a=im.getchannel('A');bbox=a.point(lambda v:255 if v>24 else 0).getbbox()
    if bbox:im=im.crop(bbox)
    im.thumbnail((w-4,h-4),R);out=Image.new('RGBA',(w,h));out.alpha_composite(im,((w-im.width)//2,h-im.height-2));return out


def main():
    hd=json.loads((ART/'enhanced-art.json').read_text());sources=json.loads((ART/'enhanced-art-sources.json').read_text())
    filename='hero-v10.png'
    if filename not in hd['textures']:hd['textures'].append(filename)
    index=hd['textures'].index(filename);page=Image.new('RGBA',(512,272))
    world=Image.open(SOURCES/'hero-world.png').convert('RGBA');battle=Image.open(SOURCES/'hero-battle.png').convert('RGBA')
    world_figures=figures(world,4);battle_figures=figures(battle,3)
    # 原方向编号1背、2右、3正、4左；统一完整身高，不把小头重新放大到旧大头框内。
    for direction,column in enumerate([1,3,0,2],1):
        im=fitted(world_figures[column],96,136);x=(direction-1)*96;page.alpha_composite(im,(x,0))
        for phase in range(3):
            key=f'world:hero:1:{direction}/{phase}';hd['frames'][key]=[index,x,0,96,136]
            sources['frames'][key]={'source':'tool/art_sources/hero-v10/hero-world.png','direction':direction,'adultProportions':True,'emptyHands':True}
    # 战斗三张同身份原画：站姿、蓄力、横斩，按原12帧动作阶段复用。
    pieces=[(384,0,96,136),(0,136,200,136),(204,136,200,136)]
    frames=[]
    for figure,(x,y,w,h)in zip(battle_figures,pieces):
        page.alpha_composite(fitted(figure,w,h),(x,y));frames.append([index,x,y,w,h])
    for key in list(hd['frames']):
        if not key.startswith('battle:hero:1/'):continue
        phase=int(key.split('/')[-1]);pose=1 if phase in[1,2] else 2 if phase in[3,4] else 0
        hd['frames'][key]=frames[pose]
        sources['frames'][key]={'source':'tool/art_sources/hero-v10/hero-battle.png','pose':pose,'originalPhase':phase,'adultProportions':True}
    page.save(ART/filename,optimize=True)
    for n,o in [('enhanced-art.json',hd),('enhanced-art-sources.json',sources)]:
        (ART/n).write_text(json.dumps(o,ensure_ascii=False,separators=(',',':')))
    print('Updated 4 empty-hand views and 12 battle phases; unchanged logical identity.')


if __name__=='__main__':main()
