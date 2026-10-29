"""仅修订用户本轮标出的19张地图；原地图/碰撞/事件与其他场景贴图引用不变。"""
from pathlib import Path
import json,math
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageOps
ROOT=Path(__file__).resolve().parents[1];ART=ROOT/'assets/fmj/modern';SOURCES=ROOT/'tool/art_sources/partial-review-v11';R=Image.Resampling.LANCZOS
TERRAIN_MAPS=['1:3','1:4','1:5','1:6','1:8','1:11',*[f'1:{i}'for i in range(13,20)]]
REVISED=['1:1',*TERRAIN_MAPS,'1:9','1:20','1:23','1:25','1:30']


def sprite(hd,key):
    t,x,y,w,h=hd['frames'][key]
    with Image.open(ART/hd['textures'][t])as im:return im.convert('RGBA').crop((x,y,x+w,y+h))


def native_tile(tileset,tile):
    raw=(ROOT/'assets/fmj/game/DAT.LIB').read_bytes()
    for h in range(16,8192,3):
        if raw[h]==255:break
        if tuple(raw[h:h+3])==(7,1,tileset):
            p=8192+h-16;o=raw[p]*16384+raw[p+1]+raw[p+2]*256;break
    w,h,count,bits=raw[o+2:o+6];stride=((w+7)//8)*bits;offset=o+6+tile*stride*h
    arr=np.zeros((h,w),dtype='uint8')
    for y in range(h):
        for x in range(w):
            bit=x*bits;v=raw[offset+y*stride+bit//8]>>(8-bits-bit%8)&((1<<bits)-1);arr[y,x]=255 if v&1 else 0
    return Image.fromarray(arr)


def edge_tile(tile,rock):
    # 填平原16像素石壁内部的点阵孔隙，保留轮廓/转角；不再把石壁直接铺成矩形石板。
    mask=native_tile(2,tile).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3)).resize((64,64),R)
    texture=rock.crop((0,0,64,64)).convert('RGBA')
    pixels=np.array(texture);yy,xx=np.mgrid[:64,:64];light=.74+.29*(1-xx/64)+.08*(1-yy/64);pixels[:,:,:3]=(pixels[:,:,:3]*light[:,:,None]).clip(0,255).astype('uint8');pixels[:,:,3]=np.array(mask)
    result=Image.fromarray(pixels)
    # 暗边与局部高光强调石壁体积，像素轮廓来自原图，留白显示同一泥土地。
    rim=Image.fromarray(np.maximum(0,np.array(mask,dtype='int16')-np.array(mask.filter(ImageFilter.MinFilter(3)),dtype='int16')).astype('uint8'))
    line=Image.new('RGBA',(64,64),'#354c42');line.putalpha(rim.point(lambda a:round(a*.6)));result.alpha_composite(line)
    return result


def wood_tile(tile):
    w=h=64;yy,xx=np.mgrid[:h,:w];grain=np.sin(xx*.9+np.sin(yy*.13))*3+np.sin(yy*.25)*1.6
    base=np.array([138,111,75]);colors=(base+grain[:,:,None]+(1-yy[:,:,None]/64)*10).clip(0,255).astype('uint8');im=Image.fromarray(colors).convert('RGBA');d=ImageDraw.Draw(im)
    vertical=tile in[79,83,84,85]
    for line in range(0,65,8):
        points=(line,0,line,63)if vertical else(0,line,63,line);d.line(points,fill='#514c37',width=1)
        for step in [10,46]:
            if vertical:d.ellipse((line+2,step,line+3,step+1),fill='#4f4a36')
            else:d.ellipse((step,line+2,step+1,line+3),fill='#4f4a36')
    if tile in[80,81,83,85]:
        if tile in[80,81]:
            x=8 if tile==80 else 54;d.rectangle((x-3,0,x+3,63),fill='#745b3d',outline='#3d4535');d.line((x-2,0,x-2,63),fill='#cfb78b',width=2)
        else:
            y=10 if tile==85 else 54;d.rectangle((0,y-4,63,y+4),fill='#6f583d',outline='#384735');d.line((0,y-3,63,y-3),fill='#d8bd8b',width=2)
            for x in[5,46]:d.rectangle((x,y-10,x+7,y+10),fill='#89704b',outline='#3b4738')
    return im


def stone_tile(tile):
    c=Image.new('RGBA',(64,64),'#9da99a');d=ImageDraw.Draw(c)
    if tile in[112,113]:
        d.rectangle((0,16,63,31),fill='#b6c1ac',outline='#4e6657',width=2);d.rectangle((0,48,63,57),fill='#7c907d',outline='#4e6657',width=2)
        for x in[3,45]:d.rectangle((x,12,x+10,56),fill='#a1b399',outline='#4b6556',width=2)
        for x in[20,31]:d.line((x,33,x+6,42,x,46),fill='#d3d6b7',width=2)
    else:
        for y in range(0,64,16):
            d.rectangle((0,y,63,y+10),fill='#b7c1ac');d.rectangle((0,y+11,63,y+15),fill='#657d70');d.line((0,y,63,y),fill='#e0debf')
        if tile in[29,30]:
            x=4 if tile==29 else 50;d.rectangle((x,0,x+9,63),fill='#aab89f',outline='#4f695b',width=2);d.line((x+2,0,x+2,63),fill='#dce0bf',width=2)
    return c


def fitted(name,size):
    with Image.open(SOURCES/name)as im:im=im.convert('RGBA')
    bbox=im.getchannel('A').point(lambda a:255 if a>16 else 0).getbbox()
    if bbox:im=im.crop(bbox)
    im.thumbnail((size[0]-8,size[1]-8),R);out=Image.new('RGBA',size);out.alpha_composite(im,((size[0]-im.width)//2,size[1]-im.height-4));return out


def main():
    hd=json.loads((ART/'enhanced-art.json').read_text());sources=json.loads((ART/'enhanced-art-sources.json').read_text());guide=json.loads((ROOT/'assets/fmj/game/FmjGuideData.json').read_text());maps={m['id']:m for m in guide['maps']}
    file='partial-review-v11.png'
    if file not in hd['textures']:hd['textures'].append(file)
    texture=hd['textures'].index(file);page=Image.new('RGBA',(768,768));pieces=[]
    props=[('water-jar',(128,160)),('temple-censer',(192,192)),('potted-shrub',(128,160)),('lotus',(128,96)),('signpost',(128,128)),('granary',(192,192)),*[(f'guardian-{b}',(128,192))for b in['dragon','tiger','bird','tortoise']]]
    for name,size in props:pieces.append((f'review-v11:{name}/0',fitted(name+'.png',size)))
    rock_texture=Image.open(ART/hd['groundTextures']['mountain-wall']).convert('RGBA').resize((128,128),R)
    for tile in[38,*range(43,66),*range(72,79),92,93]:pieces.append((f'review-v11:edge-{tile}/0',edge_tile(tile,rock_texture)))
    rocks=Image.new('RGBA',(192,128));original=sprite(hd,'plant:rock/0');original.thumbnail((192,128),R);rocks.alpha_composite(original,((192-original.width)//2,128-original.height))
    for tile in range(86,92):
        x=(tile-86)%3;y=(tile-86)//3;pieces.append((f'review-v11:edge-{tile}/0',rocks.crop((x*64,y*64,x*64+64,y*64+64))))
    for tile in range(79,86):pieces.append((f'review-v11:wood-{tile}/0',wood_tile(tile)))
    for tile in[29,30,112,113,114]:pieces.append((f'review-v11:stone-{tile}/0',stone_tile(tile)))
    # 高个物件先装箱；2像素边距避免相邻帧采样串色。
    x=y=rowh=0
    for key,im in sorted(pieces,key=lambda p:-p[1].height):
        if x+im.width+4>768:x=0;y+=rowh+4;rowh=0
        assert y+im.height+4<=768,(key,y,im.size)
        page.alpha_composite(im,(x+2,y+2));hd['frames'][key]=[texture,x+2,y+2,im.width,im.height];sources['frames'][key]={'source':'tool/fmj_partial_review_v11.py','scope':'仅用户本轮19张已批注地图'};x+=im.width+4;rowh=max(rowh,im.height)
    used_bottom=max(f[2]+f[4]for f in hd['frames'].values()if f[0]==texture)
    page.crop((0,0,768,min(768,used_bottom+4))).save(ART/file,optimize=True)
    for mid in REVISED:
        rows=hd['decorations'].get(mid,[])
        rows[:]=[b for b in rows if not b['key'].startswith('review-v11:')]
    overrides=hd.setdefault('tileOverrides',{})
    for mid in TERRAIN_MAPS:
        rules={}
        for t in[15,16,18,19]:rules[str(t)]=['bamboo-forest','floor',None]
        for t in[32,37]:rules[str(t)]=['earth','floor',None]
        for t in[38,*range(43,66),*range(72,79),*range(86,94)]:rules[str(t)]=['earth','cliff-edge',f'review-v11:edge-{t}/0']
        for t in range(79,86):rules[str(t)]=['earth','bridge',f'review-v11:wood-{t}/0']
        for t in[29,30,112,113,114]:rules[str(t)]=['earth','steps-rail',f'review-v11:stone-{t}/0']
        overrides[mid]=rules
    def add(mid,key,x,y,w,h,cells,visual=None):
        rows=hd['decorations'].setdefault(mid,[]);rows[:]=[b for b in rows if not(b['key']==key and b['x']==x and b['y']==y)]
        b={'key':key,'x':x,'y':y,'width':w,'height':h,'cells':cells}
        if visual:b['visualHeight']=visual
        rows.append(b)
    for mid in ['1:1','1:20','1:25','1:30']:
        m=maps[mid];w=m['width']
        for i,value in enumerate(m['cells']):
            t=value&127;x=i%w;y=i//w
            key='review-v11:water-jar'if mid=='1:1'and t==39 else'review-v11:potted-shrub'if mid=='1:1'and t==50 else'review-v11:lotus'if mid=='1:1'and t==94 else'review-v11:signpost'if mid!='1:1'and t==50 else None
            if key:add(mid,key,x,y,1,1,[i],1.4 if 'signpost'in key else 1.05)
            if mid=='1:1'and (x,y)in[(18,20),(26,20)]and t==104 and x+1<w and y+1<m['height']and [m['cells'][i+1]&127,m['cells'][i+w]&127,m['cells'][i+w+1]&127]==[105,106,107]:
                add(mid,'review-v11:temple-censer',x,y,2,2,[i,i+1,i+w,i+w+1],2.3)
    for mid in ['1:23','1:30']:
        m=maps[mid];w=m['width'];seen=set()
        # 部分谷仓用左/右片直接相邻组成两格宽，不能按缺失中片反推成两座重叠谷仓。
        candidates={i for i,v in enumerate(m['cells'])if v&127 in range(32,38)}
        for start in sorted(candidates):
            if start in seen:continue
            todo=[start];component=[];seen.add(start)
            while todo:
                cell=todo.pop();component.append(cell);xx=cell%w;yy=cell//w
                for nx,ny in[(xx-1,yy),(xx+1,yy),(xx,yy-1),(xx,yy+1)]:
                    nxt=ny*w+nx
                    if 0<=nx<w and 0<=ny<m['height']and nxt in candidates and nxt not in seen:seen.add(nxt);todo.append(nxt)
            xx=min(c%w for c in component);yy=min(c//w for c in component)
            span=max(c%w for c in component)-xx+1;height=max(c//w for c in component)-yy+1
            add(mid,'review-v11:granary',xx,yy,span,height,component,2.6)
    # 仅裁掉没有任何现存帧引用的外沿，坐标与帧内像素逐字节保留，留4像素采样边距。
    saved=0
    for t,name in enumerate(hd['textures']):
        if name==file:continue
        frames=[f for f in hd['frames'].values()if f[0]==t]
        if not frames:continue
        with Image.open(ART/name)as source:
            width=min(source.width,max(f[1]+f[3]for f in frames)+4);height=min(source.height,max(f[2]+f[4]for f in frames)+4)
            if (width,height)!=source.size:
                saved+=(source.width*source.height-width*height)*4;source.crop((0,0,width,height)).save(ART/name,optimize=True)
    hd['partialReviewV11']={'maps':sorted(set(REVISED)),'terrainMaps':TERRAIN_MAPS}
    for name,obj in[('enhanced-art.json',hd),('enhanced-art-sources.json',sources)]:
        (ART/name).write_text(json.dumps(obj,ensure_ascii=False,separators=(',',':')))
    print('Updated',len(set(REVISED)),'reviewed maps, packed',len(pieces),'frames, removed unused atlas margins MiB',round(saved/1048576,3))


if __name__=='__main__':main()
