"""按同一人物设计统一地图与战斗；保留原身份、战斗动画帧数及地图碰撞。"""
from pathlib import Path
import json
from PIL import Image, ImageOps

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'assets/fmj/modern'
SOURCES=ROOT/'tool/art_sources/identity-v9'
R=Image.Resampling.LANCZOS


def main():
    hd=json.loads((ART/'enhanced-art.json').read_text())
    sources=json.loads((ART/'enhanced-art-sources.json').read_text())
    filename='identity-v9.png'
    if filename not in hd['textures']:hd['textures'].append(filename)
    texture=hd['textures'].index(filename)
    atlas=Image.new('RGBA',(512,256))
    # 只需4方向静态切片，行走帧共用同一身份；脚步仍由原角色位置和动画时钟驱动。
    specs=[('tiandao',None,37,[1,2,0,3]),('chixue',27,18,[1,3,0,2]),('lihu',25,9,[1,2,0,2])]
    for row,(name,npc,monster,columns)in enumerate(specs):
        sheet=Image.open(SOURCES/(name+'-world.png')).convert('RGBA')
        frames=[]
        for direction,column in enumerate(columns,1):
            width=sheet.width/4
            im=sheet.crop((round(column*width),0,round((column+1)*width),sheet.height))
            bbox=im.getchannel('A').point(lambda a:255 if a>20 else 0).getbbox()
            if bbox:im=im.crop(bbox)
            if name=='lihu'and direction==4:im=ImageOps.mirror(im)
            im.thumbnail((110,80),R)
            x=(direction-1)*128;y=row*84
            atlas.alpha_composite(im,(x+(128-im.width)//2,y+82-im.height))
            frame=[texture,x,y,128,84];frames.append(frame)
            for phase in range(3):
                key=f'world:tiandao:{direction}/{phase}'if npc is None else f'world:npc:{npc}:{direction}/{phase}'
                hd['frames'][key]=frame
                sources['frames'][key]={'source':f'tool/art_sources/identity-v9/{name}-world.png','direction':direction,'canonicalBattleSprite':monster,'emptyHands':True,'noCrown':True}
        if name in ['tiandao','chixue']:
            # 战斗与地图直接使用同一侧身设计，消除原红黑换袍和冠帽、胡须的差异。
            for key in list(hd['frames']):
                if key.startswith(f'battle:monster:{monster}/'):
                    hd['frames'][key]=frames[3]
                    sources['frames'][key]={'alias':f'world:{"tiandao" if npc is None else "npc:"+str(npc)}:4/0','sameIdentity':True}
    atlas.save(ART/filename,optimize=True)
    for mechanism,monster in [(24,5),(28,29),(31,37),(36,38),(42,35)]:
        key=f'mechanism:{mechanism}/0';hd['frames'][key]=hd['frames'][f'battle:monster:{monster}/0']
        sources['frames'][key]={'alias':f'battle:monster:{monster}/0','reason':'同一剧情身份在地图及战斗使用相同形态，尺寸只由场景投影决定'}
    # 去除旧备用页从未被任何切片引用的底部空白，抵消新增身份页的解码占用。
    page=ART/'enhanced-surface-fallback-v5.png'
    last=max(f[2]+f[4]for f in hd['frames'].values()if hd['textures'][f[0]]==page.name)
    with Image.open(page)as im:
        if im.height>last:im.crop((0,0,im.width,last)).save(page,optimize=True)
    for name,obj in [('enhanced-art.json',hd),('enhanced-art-sources.json',sources)]:
        (ART/name).write_text(json.dumps(obj,ensure_ascii=False,separators=(',',':')))
    print('Unified Tiandao, Chixue, Lihu, snake/dragon forms, Zhuque and celestial soul.')


if __name__=='__main__':main()
