# -*- coding: utf-8 -*-
"""导出已确认的卡通写实素材。仅生成资产，不编译或运行平台应用。"""
from pathlib import Path
from PIL import Image, ImageOps, ImageFilter, ImageDraw
import hashlib, json, struct, shutil, subprocess
import re
import illustrations as art
from native_matrix_land import export_background, grid_positions

ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/'.dart_tool/art_export';WORK.mkdir(parents=True,exist_ok=True)
OUT=ROOT/'assets/art';OUT.mkdir(parents=True,exist_ok=True)

for side,light,mid,dark in [('friendly','#dc9580','#b44337','#652e2c'),('enemy','#83bbc0','#237985','#173f4a')]:
    for i,fn in enumerate(art.UNIT_FNS):
        body=fn(mid)
        defs=f'<defs><linearGradient id="teamArmor" x2=".8" y2="1"><stop stop-color="{light}"/><stop offset=".4" stop-color="{mid}"/><stop offset="1" stop-color="{dark}"/></linearGradient></defs>'
        # 主盔、胸甲、腿甲和披风采用大面积阵营色；保留银刃、金属高光与甲片细节。
        body=body.replace('url(#iron)','url(#teamArmor)').replace('url(#cloth)','url(#teamArmor)')
        if i==2:body=body.replace('url(#wood)','url(#teamArmor)')
        if i==3:body=body.replace('url(#wood)','url(#teamArmor)')
        if i==5:body=body.replace('url(#robe)','url(#teamArmor)')
        if i==5:body=re.sub(r'(<path d="M265 227[^>]+fill=")url\(#teamArmor\)',r'\1url(#robe)',body)
        (WORK/f'unit_{i}_{side}.svg').write_text(art.svg(defs+body))

for name,capital,harbor in [('capital',True,False),('fort',False,False),('harbor',False,True)]:
    (WORK/f'city_{name}.svg').write_text(art.svg(art.city(capital,harbor),320,270))
for spec in art.HEROS:(WORK/f'hero_{spec[1]}.svg').write_text(art.svg(art.portrait(spec),512,640))
(WORK/'terrain_tree.svg').write_text(art.svg(art.tree(64,116,2.6),128,150))
mountain=art.ellipse(82,106,72,9,'#43564d',extra='opacity=".2"')
mountain+=art.path('M6 108L44 42L65 66L99 10L154 109Z','#7d8974',sw=1)
mountain+=art.path('M44 42L54 99L25 109L65 66M99 10L87 99L151 109Z','#4f665e',sw=0)
mountain+=art.path('M83 37L99 10L118 45L106 39L97 29L91 45Z','#d8d4b7',sw=0)
(WORK/'terrain_mountain.svg').write_text(art.svg(mountain,160,120))
village=''
for x,y in [(12,49),(61,37),(99,61)]:
 village+=art.rect(x,y,42,32,'url(#stone)',2)+art.path(f'M{x-5} {y}L{x+21} {y-20}L{x+47} {y}Z','url(#iron)',sw=1)+art.rect(x+17,y+14,10,18,'#3c4946',1)
(WORK/'terrain_village.svg').write_text(art.svg(village,155,110))
camp=art.path('M18 92L53 18L112 94Z','url(#robe)',sw=2)+art.path('M53 18L59 92L112 94Z','url(#jade)',sw=1)+art.path('M45 92L53 64L62 93Z','#293b3b',sw=1)
camp+=art.path('M9 87L130 87M15 77V102M39 77V102M91 77V102M119 77V102','none','#816c4d',4)
(WORK/'terrain_camp.svg').write_text(art.svg(camp,140,112))
for name in ['strategy_terrain.svg','battle_terrain.svg']:
    shutil.copyfile(Path(__file__).parent/name,WORK/name)

script=WORK/'render.cjs'
script.write_text('''const fs=require('node:fs/promises'),path=require('node:path');
const sharp=require(process.env.SGBY_SHARP_MODULE||'sharp');
(async()=>{for(const name of await fs.readdir(__dirname)){if(!name.endsWith('.svg'))continue;await sharp(path.join(__dirname,name)).png().toFile(path.join(__dirname,name.replace('.svg','.png')));}console.log('SVG illustrations rendered.');})();''')
import os
env=dict(os.environ)
runtime=Path('/Users/xiongjian/.cache/codex-runtimes/codex-primary-runtime/dependencies/node')
node=shutil.which('node') or str(runtime/'bin/node')
if (runtime/'node_modules/sharp').exists():env['SGBY_SHARP_MODULE']=str(runtime/'node_modules/sharp')
subprocess.run([node,str(script)],env=env,check=True)

archive=(ROOT/'assets/game/SGBY-Reset-4X.lib').read_bytes()
def item(resource,index=1):
    offset=struct.unpack_from('<I',archive,(resource-1)*4)[0]
    _,_,count,length,key=struct.unpack_from('<IHHIB',archive,offset)
    start,size=(14+(index-1)*length,length) if length else struct.unpack_from('<II',archive,offset+14+(index-1)*8)
    return bytes((v-key)&255 for v in archive[offset+start:offset+start+size])
def original_head(period,index):
    raw=item(47+period);w,h,count,flags=struct.unpack_from('<HHHB',raw)
    if index>=count:return None
    stride=(w+7)//8;plane=stride*h;offset=7+index*plane*((flags&1)+1)+(plane if flags&1 else 0)
    data=raw[offset:offset+plane];im=Image.new('L',(w,h),232);p=im.load()
    for y in range(h):
        for x in range(w):
            if data[y*stride+x//8]>>(7-x%8)&1:p[x,y]=35
    # 保留原头像的五官、发型、胡须和服饰轮廓，以平滑彩色线稿替代重复模板脸。
    im=im.filter(ImageFilter.GaussianBlur(.45))
    tint=ImageOps.colorize(im,(32,48,51),(218,191,154)).convert('RGBA')
    steel=ImageOps.colorize(im,(27,43,48),(155,176,173)).convert('RGBA')
    robe=ImageOps.colorize(im,(25,43,43),(106,139,122)).convert('RGBA')
    mask=Image.new('L',(w,h));m=ImageDraw.Draw(mask);m.rectangle((0,0,w,h*.23),fill=255)
    mask=mask.filter(ImageFilter.GaussianBlur(h*.045));tint=Image.composite(steel,tint,mask)
    mask=Image.new('L',(w,h));m=ImageDraw.Draw(mask);m.rectangle((0,h*.76,w,h),fill=255)
    mask=mask.filter(ImageFilter.GaussianBlur(h*.06));return Image.composite(robe,tint,mask)

sprites={}
for side in ['friendly','enemy']:
    for i in range(6):sprites[f'unit/{side}/{i}']=Image.open(WORK/f'unit_{i}_{side}.png').convert('RGBA').resize((160,160),Image.Resampling.LANCZOS)
for name in ['capital','fort','harbor']:sprites[f'city/{name}']=Image.open(WORK/f'city_{name}.png').convert('RGBA').resize((160,135),Image.Resampling.LANCZOS)
for name in ['tree','mountain','village','camp']:sprites[f'terrain/{name}']=Image.open(WORK/f'terrain_{name}.png').convert('RGBA').resize((112,112),Image.Resampling.LANCZOS)
hero_map={spec[0]:spec[1] for spec in art.HEROS}
vector_faces={}
for period,resource in enumerate([62,70,71,72],1):
    offset=struct.unpack_from('<I',archive,(resource-1)*4)[0];count=struct.unpack_from('<H',archive,offset+6)[0]
    raw_people=item(61,period)
    for index in range(max(count,200)):
        name=item(resource,index+1).split(b'\0')[0].decode('gbk',errors='replace').strip() if index<count else ''
        if not name:name=f'时期{period}保留武将{index+1}'
        if name in hero_map or name in vector_faces:continue
        fingerprint=hashlib.sha256(name.encode()).hexdigest();seed=int(fingerprint[:8],16)
        original=original_head(period,index)
        beard_density=0
        if original is not None:
            zone=original.convert('L').crop((int(original.width*.23),int(original.height*.5),int(original.width*.8),int(original.height*.78)))
            beard_density=sum(v<100 for v in zone.getdata())/max(1,zone.width*zone.height)
        beards=['bushy','long'] if beard_density>.3 else ['goatee','copper','short'] if beard_density>.16 else ['none','thin','short']
        force=raw_people[index*19+5] if index*19+6<len(raw_people) else seed%100
        iq=raw_people[index*19+6] if index*19+6<len(raw_people) else (seed//7)%100
        hats=['scholar','crown','wrap'] if iq>force+15 else ['silver','band','plumes','gold'] if force>iq+15 else ['crown','wrap','gold','band']
        spec=(name,'person_'+fingerprint[:12],['#d2ae86','#d7b68d','#b99070','#d8bca0','#c19473','#bca384'][seed%6],
            ['long','round','square','slim','narrow'][(seed//13)%5],beards[(seed//37)%len(beards)],hats[(seed//71)%len(hats)],
            ['#557c68','#354e65','#776d42','#895c4f','#657e86','#6d665b'][(seed//97)%6])
        sx=.88+(seed%27)/100;sy=.94+((seed//31)%13)/100
        body=art.rect(0,0,512,640,'#d7d7c1')+art.group(art.portrait(spec),f'translate(256 0) scale({sx} {sy}) translate(-256 0)')
        file=WORK/f'person_{fingerprint[:12]}.svg';file.write_text(art.svg(body,512,640));vector_faces[name]=file.with_suffix('.png')
for period,resource in enumerate([62,70,71,72],1):
    offset=struct.unpack_from('<I',archive,(resource-1)*4)[0];name_count=struct.unpack_from('<H',archive,offset+6)[0]
    head_count=struct.unpack_from('<H',item(47+period),4)[0]
    for index in range(head_count,max(200,name_count)):
        # 精修追加/保留槽没有原图，按稳定ID单独绘制，不借用同一张通用头像。
        seed=period*200+index
        spec=('特殊武将',f'extra_{period}_{index}', ['#d2ae86','#d7b68d','#b99070','#d8bca0'][seed%4],
            ['long','round','square','slim'][seed%4],['goatee','bushy','none','thin','short'][seed%5],
            ['crown','band','silver','scholar','wrap','plumes'][seed%6],['#557c68','#354e65','#776d42','#895c4f'][seed%4])
        (WORK/f'extra_{period}_{index}.svg').write_text(art.svg(art.portrait(spec),512,640))
subprocess.run([node,str(script)],env=env,check=True)
portrait_ids={};portraits={}
for period,resource in enumerate([62,70,71,72],1):
    off=struct.unpack_from('<I',archive,(resource-1)*4)[0];count=struct.unpack_from('<H',archive,off+6)[0]
    for index in range(max(count,200)):
        name=item(resource,index+1).split(b'\0')[0].decode('gbk',errors='replace').strip() if index<count else ''
        if not name:name=f'时期{period}保留武将{index+1}'
        key=f'portrait/{period}/{index}'
        if name in portraits:portrait_ids[key]=portraits[name];continue
        if name in hero_map:im=Image.open(WORK/f'hero_{hero_map[name]}.png').convert('RGBA')
        else:im=Image.open(vector_faces[name]).convert('RGBA')
        image_key='face/'+str(len(portraits));portraits[name]=image_key;portrait_ids[key]=image_key
        sprites[image_key]=im.resize((96,120),Image.Resampling.LANCZOS)
for name,key in hero_map.items():
    if name not in portraits:
        image_key='face/'+str(len(portraits));portraits[name]=image_key
        sprites[image_key]=Image.open(WORK/f'hero_{key}.png').convert('RGBA').resize((96,120),Image.Resampling.LANCZOS)

atlas=Image.new('RGBA',(2048,3072));rects={};x=y=row_h=0
for key,im in sprites.items():
    if x+im.width+2>2048:x=0;y+=row_h+2;row_h=0
    if y+im.height+2>3072:raise ValueError('Atlas capacity exceeded')
    atlas.alpha_composite(im,(x,y));rects[key]=[x,y,im.width,im.height]
    x+=im.width+2;row_h=max(row_h,im.height)
used_h=y+row_h+2
atlas.crop((0,0,2048,used_h)).save(OUT/'atlas.png',optimize=True)
export_background(ROOT, OUT/'strategy_map.png')
import random
noise=Image.new('RGB',(640,425),'#adb28a');d=ImageDraw.Draw(noise);rng=random.Random(328)
for i in range(1800):
 x=rng.randrange(640);y=rng.randrange(425);rx=rng.randrange(2,26);ry=rng.randrange(1,12)
 d.ellipse((x-rx,y-ry,x+rx,y+ry),fill=rng.choice(['#aab089','#a6ad84','#b0b68d','#b3b58e']))
noise=noise.filter(ImageFilter.GaussianBlur(2));d=ImageDraw.Draw(noise)
for i in range(900):
 x=rng.randrange(640);y=rng.randrange(425);d.line((x,y,x+1,y-2),fill='#8e9e78',width=1)
noise.save(OUT/'battle_texture.png',optimize=True)
locations=json.loads((Path(__file__).parent/'city_locations.json').read_text())
positions=grid_positions(ROOT)
cities=[{'id':index,'name':city['name'],'grid':list(positions[index]),'on_land':True,'symbol_on_land':True}
        for index,city in enumerate(locations['cities'])]
manifest={'version':2,'teamColors':{'friendly':'#b44337','enemy':'#237985'},'sprites':rects,
          'portraitIds':portrait_ids,'portraitNames':portraits,'cities':cities,'mapSize':[1280,960],
          'strategyLayout':{'type':'original-matrix','columns':12,'rows':9,'cell':16},
          'portraitPolicy':'Eight dedicated approved illustrations; other identities use fixed per-name vector portraits.',
          'source':'Original LIB C_CITYPOS/C_MAP matrix; artist-designed terrain and units'}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,separators=(',',':')))
proof={'atlasSize':[2048,used_h],'portraitNames':len(portraits),'portraitBindings':len(portrait_ids),'landCities':len(cities),'unitColorCoverage':{},'files':{}}
for side in ['friendly','enemy']:
    counts=[]
    for i in range(6):
        im=sprites[f'unit/{side}/{i}'];opaque=colored=0
        for r,g,b,a in im.getdata():
            if a<100:continue
            opaque+=1
            if side=='friendly' and r>g*1.22 and r>b*1.22:colored+=1
            if side=='enemy' and g>r*1.17 and b>r*1.17:colored+=1
        counts.append(round(colored/max(1,opaque),3))
    proof['unitColorCoverage'][side]=counts
for p in OUT.iterdir():proof['files'][p.name]=hashlib.sha256(p.read_bytes()).hexdigest()
(ROOT/'tool/baseline/realistic_art_assets.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in proof.items() if k!='files'},ensure_ascii=False))
