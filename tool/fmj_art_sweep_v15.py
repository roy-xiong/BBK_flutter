"""全量清理彩色地图旧点阵轮廓；规则建筑使用高倍离线绘制，不改原版黑白资源。

只重绘没有完整彩绘别名的旧结构切片。现有角色、怪物、家具原画保持像素不变。
图集10重新装箱去掉空闲区域，为开场插画留出解码预算，运行时不生成位图。
"""
from pathlib import Path
from collections import Counter
import hashlib,json,math,random
from PIL import Image,ImageDraw,ImageFilter,ImageOps

ROOT=Path(__file__).resolve().parents[1];ART=ROOT/'assets/fmj/modern'
SOURCES=ROOT/'tool/art_sources/art-sweep-v15';R=Image.Resampling.LANCZOS


def clean_tile(tileset,index,role,size):
    """在256坐标空间画连续材质和器物结构，避免沿16像素点阵再着色。"""
    im=Image.new('RGBA',(256,256));d=ImageDraw.Draw(im);rng=random.Random(tileset*1000+index)
    if role=='rug' and index==39 or tileset==6 and index in[22,23]:return im.resize(size,R)
    if role in['wall-panel','wall-cap','roof','wood-object','stone-object','stone-steps','stone-rail','pond-rail','rug','source-detail']:
        if role=='roof' or role=='wall-cap':
            d.rectangle((0,0,255,255),fill='#666c68')
            for x in range(-20,280,32):
                d.rounded_rectangle((x,0,x+27,255),radius=11,fill='#727b77',outline='#3e4c4c',width=4)
                d.line((x+6,0,x+6,255),fill='#9aa49a',width=3)
            for y in range(15,270,45):d.line((0,y,255,y),fill='#4d5b58',width=2)
        elif role=='wall-panel':
            post=tileset in[3,5,7]and index in[7,8,28,29,31,32]
            if post:
                d.rectangle((0,0,255,255),fill='#a28760')
                for x in range(0,257,32):
                    d.line((x,0,x,255),fill='#746047',width=4);d.line((x+5,0,x+5,255),fill='#c8ae7e',width=3)
            else:
                d.rectangle((0,0,255,255),fill='#c4c2a8')
                for row,y in enumerate(range(0,257,48)):
                    d.line((0,y,255,y),fill='#8b9582',width=3)
                    for x in range(-64+(row%2)*64,300,128):d.line((x,y,x,y+48),fill='#929b87',width=2)
                if index in[3,4,5,6,9,10,24,25,26,27,30,31,97,98]:
                    d.rectangle((0,0,255,13),fill='#e1d8b5');d.line((0,15,255,15),fill='#7e866e',width=3)
        elif role=='wood-object':
            d.rectangle((0,0,255,255),fill='#8c714e')
            for y in range(5,256,82):
                for x in range(5,256,126):
                    d.rounded_rectangle((x,y,x+119,y+74),radius=5,fill='#b19768',outline='#574d38',width=4)
                    d.line((x+8,y+8,x+110,y+8),fill='#d8c295',width=3)
                    d.rounded_rectangle((x+49,y+34,x+69,y+40),radius=3,fill='#4e4e39')
        elif role=='rug':
            d.rectangle((0,0,255,255),fill='#7d4039')
            for p in[7,16,25]:d.rectangle((p,p,255-p,255-p),outline='#c3a46b',width=4)
            for y in range(36,235,28):
                for x in range(36,235,28):d.line((x-5,y,x,y-5,x+5,y,x,y+5,x-5,y),fill='#aa7954',width=2)
        elif role in['stone-steps','stone-rail','pond-rail','stone-object','source-detail']:
            rail=role in['stone-rail','pond-rail']
            if rail:
                for y in[35,175]:d.rounded_rectangle((0,y,255,y+32),radius=5,fill='#aab6a3',outline='#4e675c',width=4)
                for x in[22,208]:d.rounded_rectangle((x,23,x+25,231),radius=4,fill='#b7c1ac',outline='#536e60',width=4)
                d.line((0,38,255,38),fill='#e0dfc0',width=4)
            else:
                d.rectangle((0,0,255,255),fill='#82988c')
                for y in range(0,256,51):
                    d.rectangle((0,y,255,y+35),fill='#b2bda8');d.line((0,y+2,255,y+2),fill='#e0dfc6',width=3)
                    d.line((0,y+37,255,y+37),fill='#4c675b',width=5)
    elif role in['fence-h','fence-v']:
        vertical=role=='fence-v'
        def box(rect):
            if vertical:rect=(rect[1],rect[0],rect[3],rect[2])
            d.rounded_rectangle(rect,radius=4,fill='#a68b5c',outline='#526044',width=4)
        for y in[90,153]:box((0,y,255,y+18))
        for x in[24,193]:box((x,48,x+21,215))
    elif role in['flowerbed','foliage','herb','bamboo','hay','rock','trail-edge','cloud']:
        if role=='cloud':
            for n in range(6):
                x=rng.randint(-70,180);y=rng.randint(35,210)
                d.ellipse((x,y,x+150,y+45),fill=(147,175,179,90))
            im=im.filter(ImageFilter.GaussianBlur(10))
        elif role=='trail-edge':
            d.line([(0,28),(55,36),(98,21),(151,31),(206,19),(255,27)],fill='#ab8b5e88',width=8)
            for n in range(10):
                x=rng.randint(0,255);y=rng.randint(22,58);d.ellipse((x,y,x+4,y+3),fill='#d0bb8b99')
        elif role=='hay':
            for n in range(28):
                x=rng.randint(15,235);d.line((x,230,x+rng.randint(-15,15),rng.randint(70,155)),fill=rng.choice(['#b9a36c','#c9b77e','#8c8850']),width=4)
        elif role=='rock':
            d.polygon([(18,219),(39,115),(111,40),(191,65),(242,160),(224,222)],fill='#83968b',outline='#435c53',width=5)
            d.polygon([(39,115),(111,40),(146,132),(92,185)],fill='#b4bda7')
            d.line((111,40,146,132,224,222),fill='#455e57',width=4)
        else:
            bamboo=role=='bamboo'
            for n in range(5 if bamboo else 10):
                x=rng.randint(14,240);y=rng.randint(175,250);top=rng.randint(15,105)
                d.line((x,y,x+rng.randint(-18,18),top),fill='#486f49',width=3)
                for side in[-1,1]:
                    for j in range(3):
                        yy=top+25+j*38;length=rng.randint(24,55)
                        d.polygon([(x,yy+16),(x+side*length,yy-15),(x+side*length*.7,yy+7)],fill=rng.choice(['#69905c','#8ba36c','#4f7d50']))
            if role=='flowerbed'and tileset==1:
                for n in range(3):
                    x=rng.randint(20,230);y=rng.randint(60,150)
                    for a in range(5):
                        xx=x+math.cos(a*math.tau/5)*10;yy=y+math.sin(a*math.tau/5)*10;d.ellipse((xx-6,yy-6,xx+6,yy+6),fill='#e4d9b7')
                    d.ellipse((x-4,y-4,x+4,y+4),fill='#c6ae67')
    return im.resize(size,R)


def main():
    hd=json.loads((ART/'enhanced-art.json').read_text());source=json.loads((ART/'enhanced-art-sources.json').read_text())
    guide=json.loads((ROOT/'assets/fmj/game/FmjGuideData.json').read_text());maps={m['id']:m for m in guide['maps']}
    pages={};aliases={tuple(f)for k,f in hd['frames'].items()if not k.startswith('structure:')}
    original=[]
    for key,record in source['frames'].items():
        f=hd['frames'].get(key)
        if record.get('transform')=='original-contour-native-material'and f and tuple(f)not in aliases:
            original.append(key)
    # 一个帧可能有多个结构别名，按实际矩形只重绘一次。
    done=set()
    for key in original:
        t,x,y,w,h=hd['frames'][key];tileset,index=map(int,key.split('/')[0].split(':')[1:]);role=source['frames'][key]['semantic']
        page=pages.setdefault(t,Image.open(ART/hd['textures'][t]).convert('RGBA'))
        if (t,x,y,w,h)not in done:page.paste(clean_tile(tileset,index,role,(w,h)),(x,y,x+w,y+h));done.add((t,x,y,w,h))
        source['frames'][key]={**source['frames'][key],'transform':'offline-clean-vector-material','source':'tool/fmj_art_sweep_v15.py','originalContourUsed':False}
    for key,record in source['frames'].items():
        if record.get('transform')=='original-contour-native-material' and tuple(hd['frames'].get(key,[])) in aliases:
            record['transform']='complete-illustration-alias'
            record['originalContourUsed']=False
    # 地图中真正的柜体和石灯采用已有完整原画，不能把小切片误画成泛用装饰。
    for key,target in [('structure:3:15/0','review-v14:chest/0')]:
        hd['frames'][key]=hd['frames'][target];source['frames'][key]={'alias':target,'source':'tool/fmj_art_sweep_v15.py'}
    for tile in range(94,102):
        key=f'structure:1:{tile}/0';hd['frames'][key]=hd['frames']['review-v11:lotus/0'];source['frames'][key]={'alias':'review-v11:lotus/0','source':'tool/fmj_art_sweep_v15.py'}
    for name,target in [('lantern','review-v14:stone-lantern/0'),('incense','review-v11:temple-censer/0'),('signpost','review-v11:signpost/0')]:
        key='sweep-v15:'+name+'/0';hd['frames'][key]=hd['frames'][target];source['frames'][key]={'alias':target,'source':'tool/fmj_art_sweep_v15.py'}
    for mid,rows in hd['decorations'].items():
        rows[:]=[b for b in rows if not b['key'].startswith('sweep-v15:')]
        m=maps[mid];w=m['width'];covered={i for b in [*hd['buildings'].get(mid,[]),*rows]for i in b.get('cells',[])}
        for i,v in enumerate(m['cells']):
            tile=v&127
            if i in covered:continue
            name='lantern'if m['tiles']==9 and tile==116 else'signpost'if m['tiles']==9 and tile==50 else'something'
            if name!='something':
                rows.append({'key':'sweep-v15:'+name,'x':i%w,'y':i//w,'width':1,'height':1,'cells':[i],'visualHeight':1.8 if name=='lantern'else 1.4})
            if m['tiles']==1 and tile==104 and i+w+1<len(m['cells']):
                if [m['cells'][i+1]&127,m['cells'][i+w]&127,m['cells'][i+w+1]&127]==[105,106,107]:
                    rows.append({'key':'sweep-v15:incense','x':i%w,'y':i//w,'width':2,'height':2,'cells':[i,i+1,i+w,i+w+1],'visualHeight':2.3})
        for b in rows:
            if b['key']in['interior-v12:seated-guest','review-v14:seated-guest-bench']:
                b['visualHeight']=1.4;b['visualWidth']=1.1
    # 旧图集中同样的干净瓦片、墙片可共享切片；裁掉装箱留下的大块空白。
    t=10;old=pages.get(t)or Image.open(ART/hd['textures'][t]).convert('RGBA');items={}
    for key,f in hd['frames'].items():
        if f[0]!=t or key=='opening:butterfly/0':continue
        _,x,y,w,h=f;im=old.crop((x,y,x+w,y+h));identity=(w,h,hashlib.sha256(im.tobytes()).digest());items.setdefault(identity,{'image':im,'keys':[]})['keys'].append(key)
    page=Image.new('RGBA',(2048,2048));x=y=rowh=0
    for item in sorted(items.values(),key=lambda item:-item['image'].height):
        im=item['image']
        if x+im.width+4>2048:x=0;y+=rowh+4;rowh=0
        assert y+im.height+4<=2048,'装箱超出原图集'
        page.paste(im,(x+2,y+2))
        for key in item['keys']:hd['frames'][key]=[t,x+2,y+2,im.width,im.height]
        x+=im.width+4;rowh=max(rowh,im.height)
    page=page.crop((0,0,2048,y+rowh+4));pages[t]=page
    for t,page in pages.items():page.save(ART/hd['textures'][t],optimize=True)
    # 蝴蝶小图装进空闲切片；开场插画独立加载一次。
    filename='opening-v15.png';background=Image.open(SOURCES/'opening-meadow.png').convert('RGB');background=ImageOps.fit(background,(960,576),method=R);background.save(ART/filename,optimize=True)
    hd['backgrounds']['opening']=filename
    butterfly=Image.open(SOURCES/'butterfly.png').convert('RGBA');butterfly=butterfly.crop(butterfly.getchannel('A').getbbox());butterfly.thumbnail((96,64),R)
    # 图集10的新底部空闲行容纳蝴蝶，不另建整页纹理。
    t=10;page=pages[t];pos=(4,page.height-68)
    # 放在新独立的68像素底带，避免覆盖最后一排原帧。
    expanded=Image.new('RGBA',(page.width,page.height+68));expanded.paste(page,(0,0));expanded.alpha_composite(butterfly,(4,page.height+2));expanded.save(ART/hd['textures'][t],optimize=True)
    hd['frames']['opening:butterfly/0']=[t,4,page.height+2,butterfly.width,butterfly.height]
    source['frames']['opening:butterfly/0']={'source':'tool/art_sources/art-sweep-v15/butterfly.png'}
    definitions=list(dict.fromkeys([*hd.get('artSweepV15',{}).get('definitionKeys',[]),*original]))
    hd['artSweepV15']={**hd.get('artSweepV15',{}),'maps':list(maps),'legacyDefinitionsRedrawn':len(definitions),'definitionKeys':definitions,'openingMovies':['1:2','1:3']}
    for name,value in [('enhanced-art.json',hd),('enhanced-art-sources.json',source)]:
        (ART/name).write_text(json.dumps(value,ensure_ascii=False,separators=(',',':')))
    print('Redrawn legacy definitions',len(original),'atlas10 new height',expanded.height)


if __name__=='__main__':main()
