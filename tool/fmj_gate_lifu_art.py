"""山门及李府陈设修订：在原占地内换绘美术，不修改地图、碰撞、事件或剧情资源。"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/fmj/modern'
SOURCES = ROOT / 'tool/art_sources/lifu-v8'
R = Image.Resampling.LANCZOS
S = 2
INK = '#35473f'
GOLD = '#c4ac73'


class Drawing:
    """两倍坐标绘制，缩采样保留檐口、木作和器皿的细线。"""
    def __init__(self, w, h):
        self.im = Image.new('RGBA', (w*S, h*S))

    def xy(self, box):return tuple(round(v*S) for v in box)
    def polygon(self, points, fill, outline=INK, width=1):
        pts=[self.xy(p) for p in points];d=ImageDraw.Draw(self.im)
        d.polygon(pts, fill=fill)
        if outline:d.line(pts+[pts[0]], fill=outline, width=width*S, joint='curve')
    def line(self, points, fill, width=1):ImageDraw.Draw(self.im).line([self.xy(p)for p in points],fill=fill,width=width*S,joint='curve')
    def rect(self, box, fill, outline=None, width=1):ImageDraw.Draw(self.im).rectangle(self.xy(box),fill=fill,outline=outline,width=width*S)
    def oval(self, box, fill, outline=None, width=1):ImageDraw.Draw(self.im).ellipse(self.xy(box),fill=fill,outline=outline,width=width*S)
    def paste(self, im, box):
        x,y,w,h=box;self.im.alpha_composite(im.resize((round(w*S),round(h*S)),R),(round(x*S),round(y*S)))
    def text(self, point, text, size, fill):
        font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Songti.ttc',size*S)
        ImageDraw.Draw(self.im).text(self.xy(point),text,font=font,fill=fill,anchor='mm',stroke_width=0)
    def finish(self):return self.im.resize((self.im.width//S,self.im.height//S),R)


def sprite(hd, key):
    t,x,y,w,h=hd['frames'][key]
    return Image.open(ART/hd['textures'][t]).convert('RGBA').crop((x,y,x+w,y+h))


def gate_part(part):
    """把完整四柱三间牌楼按原机关边界切分，三段共用同一比例和同一条基线。

    原图分为256/512/256三个宽度；统一构图后再切片，避免独立画柱、边墙和
    中楼导致檐口、横梁或颜色衔接不一致。只替换纹理，机关坐标和通行规则不变。
    """
    whole=Image.new('RGBA',(1024,640));image=source_image('sanqing-reference-gate.png')
    image.thumbnail((1024,632),R)
    whole.alpha_composite(image,((1024-image.width)//2,632-image.height))
    left,right=[(0,256),(256,768),(768,1024)][part]
    return whole.crop((left,0,right,640))


def gate(hd):
    return gate_part(1)


def gate_wing(hd, right=False):
    return gate_part(2 if right else 0)


def source_image(name):
    """读取已审看并去色键的手绘源图；等比缩放，避免再次把方座扶手椅拉成长椅。"""
    with Image.open(SOURCES/name) as source:
        return source.convert('RGBA')


def side_group():
    """每组两把朝内扶手椅夹一张茶几；等比放大并紧邻排列，不让三件家具散开。

    三件沿南北排列，桌面采用与椅座一致的视角。先画后排椅，再画茶几，最后画
    前排椅，保持轻微重叠处的正确遮挡；另一侧整组镜像，四组原占地保持一致。
    """
    c=Drawing(128,192)
    chair=source_image('ming-chair-right.png');chair.thumbnail((82,84),R)
    table=source_image('ming-tea-table-aligned.png');table.thumbnail((78,64),R)
    chair_x=(128-chair.width)/2;table_x=(128-table.width)/2
    for bottom in [84,190]:c.oval((42,bottom-7,91,bottom+1),'#15322a44')
    c.oval((29,115,102,125),'#18362b44')
    c.paste(chair,(chair_x,0,chair.width,chair.height))
    c.paste(table,(table_x,62,table.width,table.height))
    c.paste(chair,(chair_x,108,chair.width,chair.height))
    return c.finish()


def head_table(hd):
    c=Drawing(192,128);table=sprite(hd,'furniture:tea-table/0')
    c.paste(table,(0,14,192,110))
    c.rect((0,0,192,40),(0,0,0,0))
    # 覆盖旧图中堆叠的茶碗，重绘清晰可数的壶与左右各一只茶碗。
    c.polygon([(19,27),(174,27),(181,61),(11,61)],'#c1a376',width=1)
    for y in [37,48,57]:c.line([(22,y),(171,y)],'#ac8b5e',1)
    c.oval((77,39,116,53),'#5c6a5744')
    c.oval((79,25,111,49),'#dce5d6',INK,1)
    c.line([(108,29),(120,27),(122,37),(113,40)],'#b6cdc7',4)
    c.polygon([(81,30),(67,25),(72,37),(81,40)],'#c3d7cc')
    c.oval((79,22,110,31),'#edf0da',INK,1);c.oval((92,17,101,24),'#8ca99e',INK,1)
    c.line([(88,34),(93,40),(103,34)],'#548c94',2)
    for x in [48,145]:
        c.oval((x-16,41,x+16,52),'#b5c5b1',INK,1)
        c.polygon([(x-11,39),(x+11,39),(x+7,48),(x-7,48)],'#dce6d2')
        c.oval((x-11,35,x+11,43),'#eef1db',INK,1);c.oval((x-7,37,x+7,41),'#9e885e')
    return c.finish()


def bucket():
    c=Drawing(96,128);c.oval((8,107,89,125),'#18332b44')
    c.polygon([(15,34),(81,34),(76,107),(65,118),(31,118),(20,107)],'#97744b',width=2)
    for x in [23,34,46,58,70]:c.line([(x,43),(x+(-2 if x<45 else 2),110)],'#5d4931',2)
    for x in [26,38,51,64]:c.line([(x,45),(x,105)],'#c1a06d',1)
    c.oval((14,24,82,47),'#b9a177',INK,2);c.oval((21,29,75,42),'#423e2c',INK,1)
    for y in [54,92]:c.polygon([(17,y),(79,y),(78,y+7),(18,y+7)],'#59645a',width=1);c.line([(23,y+1),(73,y+1)],'#b4b698',1)
    c.line([(21,36),(17,15),(30,5),(64,5),(78,15),(75,36)],'#5b6558',5)
    c.line([(30,7),(62,7)],'#b2b59b',2)
    return c.finish()


def stairs():
    c=Drawing(512,64);c.rect((0,0,511,13),'#b0baa5');c.rect((0,13,511,60),'#627a6b')
    c.line([(0,13),(511,13)],'#e2dfbb',3);c.line([(0,58),(511,58)],'#344f43',3)
    for x in range(0,512,55):c.line([(x,18),(x,56)],'#52695b',1)
    # 两侧原踏步之间同样铺两级整段石阶，不能留下两段梯子夹一堵立墙。
    left=(7+.5)/21*512;right=(13+.5)/21*512
    c.polygon([(left-13,0),(right+13,0),(right+18,27),(left-18,27)],'#bdc6ad')
    c.rect((left-18,27,right+18,34),'#657d6b')
    c.polygon([(left-18,34),(right+18,34),(right+23,55),(left-23,55)],'#a2b39a')
    c.rect((left-23,55,right+23,63),'#4f6959')
    c.line([(left-19,37),(right+19,37)],'#e1dfbd',2)
    for x in range(round(left),round(right)+1,28):
        c.line([(x,2),(x,25)],'#93a28b',1)
        c.line([(x+8,39),(x+8,53)],'#819680',1)
    return c.finish()


def north_house(hd):
    """按最新反馈沿用黑白版的整片屋顶，不在北侧另造门窗；入口由上半部名牌表达。"""
    c=Drawing(128,128)
    house=sprite(hd,'building:house/0')
    roof=house.crop((0,0,house.width,round(house.height*.42)))
    c.oval((5,115,123,127),'#142c2544')
    c.rect((13,96,115,122),'#a6ad94',INK,1)
    c.line([(15,120),(113,120)],'#596d5b',2)
    for x in [30,53,78,100]:c.line([(x,116),(x,122)],'#697d68',1)
    c.paste(roof,(0,2,128,116))
    return c.finish()


def main():
    hd=json.loads((ART/'enhanced-art.json').read_text());sources=json.loads((ART/'enhanced-art-sources.json').read_text())
    guide=json.loads((ROOT/'assets/fmj/game/FmjGuideData.json').read_text());maps={m['id']:m for m in guide['maps']}
    for mid,rows in hd['buildings'].items():
        rows[:]=[b for b in rows if not b.get('northGenerated')]
        for b in rows:
            if 'northOriginalKey'in b:b['key']=b.pop('northOriginalKey')
    key='mechanism:gate:2/0';pages={}
    for n,image in [(1,gate_wing(hd)),(2,gate(hd)),(3,gate_wing(hd,True))]:
        t,x,y,w,h=hd['frames'][f'mechanism:gate:{n}/0']
        if t not in pages:pages[t]=Image.open(ART/hd['textures'][t]).convert('RGBA')
        pages[t].paste(image.resize((w,h),R),(x,y))
        sources['frames'][f'mechanism:gate:{n}/0']={'source':'tool/art_sources/lifu-v8/sanqing-reference-gate.png','originalSprite':n,'details':'one coherent four-column three-bay paifang, split at original mechanism boundaries'}
    # 中式石狮与须弥座来自同一张完整原画，不能分离缩放造成脚掌悬空。
    # right沿用旧摆放键名，原画朝左；left为镜像，用于其他原本朝右的位置。
    lion=source_image('chinese-guardian-lion.png')
    for side,image in [('right',lion),('left',ImageOps.mirror(lion))]:
        lion_key=f'scenery:stone-lion-{side}/0';t,x,y,w,h=hd['frames'][lion_key]
        if t not in pages:pages[t]=Image.open(ART/hd['textures'][t]).convert('RGBA')
        fitted=Image.new('RGBA',(w,h));image=image.copy();image.thumbnail((w-8,h-8),R)
        fitted.alpha_composite(image,((w-image.width)//2,h-image.height-4))
        pages[t].paste(fitted,(x,y))
        sources['frames'][lion_key]={'source':'tool/art_sources/lifu-v8/chinese-guardian-lion.png','derived':'Chinese seated guardian lion with attached plinth','mirrored':side=='left'}
    for t,page in pages.items():page.save(ART/hd['textures'][t],optimize=True)
    sources['frames'][key]={'source':'tool/art_sources/lifu-v8/sanqing-reference-gate.png','details':'reference-based four-column paifang, unified vermilion and gold, no lanterns; unchanged original footprint'}
    filename='lifu-furniture-v7.png'
    if filename not in hd['textures']:hd['textures'].append(filename)
    index=hd['textures'].index(filename);page=Image.new('RGBA',(512,512))
    chair=sprite(hd,'furniture:chair/0');chair.thumbnail((128,160),R)
    top=Image.new('RGBA',(128,160));top.alpha_composite(chair,((128-chair.width)//2,160-chair.height))
    group=side_group();pieces=[('furniture:lifu-chair-table-left',group,0,0),('furniture:lifu-chair-table-right',ImageOps.mirror(group),132,0),('furniture:lifu-head-chair',top,264,0),('furniture:lifu-head-table',head_table(hd),0,196),('furniture:wooden-bucket',bucket(),400,0),('furniture:lifu-two-step-platform',stairs(),0,332),('building:house-north',north_house(hd),196,196)]
    for name,image,px,py in pieces:
        page.alpha_composite(image,(px,py));hd['frames'][name+'/0']=[index,px,py,image.width,image.height]
        sources['frames'][name+'/0']={'source':'tool/fmj_gate_lifu_art.py','details':name}
    page.save(ART/filename,optimize=True)
    for b in hd['buildings']['1:37']:
        if b['x']==28 and b['y']in[8,12] and b['key']in['furniture:grave-18','scenery:stone-lion-left','scenery:stone-lion-right']:
            # 图集的right指摆放位置；该原画的狮头朝左，两尊均按最新反馈统一。
            b['key']='scenery:stone-lion-right'
    # 原64号图是木桶；旧通用修订误把它当木椅，统一纠正所有复用该图块的位置。
    buckets=0
    for mid,m in maps.items():
        if m['tiles']!=9:continue
        rows=hd['decorations'].setdefault(mid,[])
        cells={i for i,v in enumerate(m['cells'])if v&127==64}
        rows[:]=[b for b in rows if not (b['key']=='furniture:chair' and set(b.get('cells',[]))&cells)]
        for i in sorted(cells):
            if any(i in b.get('cells',[]) and b['key']=='furniture:wooden-bucket' for b in rows):continue
            rows.append({'key':'furniture:wooden-bucket','x':i%m['width'],'y':i//m['width'],'width':1,'height':1,'cells':[i],'visualHeight':1.3});buckets+=1
    hd['tileCatalog']['9'][64]=['earth','wooden-bucket','furniture:wooden-bucket/0']
    wells=[]
    for mid,m in maps.items():
        if m['tiles']!=9:continue
        w=m['width'];rows=hd['decorations'].setdefault(mid,[])
        rows[:]=[b for b in rows if not(b['key']=='furniture:well' and any(
            old['key']=='furniture:well' and old['x']==b['x'] and old['y']==b['y']
            for old in hd['buildings'].get(mid,[])))]
        for i,value in enumerate(m['cells'][:-1]):
            if value&127!=68 or (i+1)%w==0 or m['cells'][i+1]&127!=69:continue
            if not any(b['key']=='furniture:well' and b['x']==i%w and b['y']==i//w
                for b in rows+hd['buildings'].get(mid,[])):
                rows.append({'key':'furniture:well','x':i%w,'y':i//w,'width':2,'height':1,'cells':[i,i+1],'visualHeight':1.6})
            wells.append({'map':mid,'x':i%w,'y':i//w})
    rows=hd['decorations']['2:20']
    for b in rows:
        if b['key']=='furniture:round-stool':b['key']='furniture:lifu-head-chair'
        elif b['key']=='furniture:offering-table-3':b['key']='furniture:lifu-head-table'
        elif b['key']=='furniture:chair':b['key']='furniture:lifu-chair-table-left' if b['x']==6 else 'furniture:lifu-chair-table-right'
    if not any(b['key']=='furniture:lifu-two-step-platform' for b in rows):
        m=maps['2:20'];cells=[i for i,v in enumerate(m['cells'])if v&127 in[98,99]]
        rows.append({'key':'furniture:lifu-two-step-platform','x':0,'y':5,'width':m['width'],'height':1,'floor':True,'cells':cells})
    # 原北门图块120(城镇)和80(原野城镇)由ROM固定定义；不能按房屋所在屏幕半边猜方向。
    # 部分旧组合只识别到背靠背房屋的南半部，北门要补齐原三行占地。
    north=[]
    for mid,m in maps.items():
        if m['tiles']not in[1,9]:continue
        entries={42,120,125} if m['tiles']==1 else {61,80,85}
        handled=set()
        for i,value in enumerate(m['cells']):
            if i in handled or value&127 not in entries or value>>8&255==0:continue
            x=i%m['width'];y=i//m['width'];w=m['width']
            right=x
            while right+1<w and m['cells'][y*w+right+1]&127 in entries and m['cells'][y*w+right+1]>>8&255==value>>8&255:
                right+=1
            handled.update(y*w+xx for xx in range(x,right+1))
            left=x-1;width=right-x+3;height=3
            # 连续三格入口属于一栋五格宽房屋，不得生成三栋重叠小屋。
            if width>3 and y+2<m['height'] and any(m['cells'][(y+2)*w+xx]&127 in[86,87,88,89,90]for xx in range(left,left+width)):
                height=2
            objects=hd['buildings'].setdefault(mid,[])
            b=next((b for b in objects if b['x']==left and b['y']==y and b['width']==width and b['height']==height),None)
            if b is None:
                b={'key':'building:house-north','x':left,'y':y,'width':width,'height':height,'northGenerated':True,
                   'cells':[(y+dy)*w+left+dx for dy in range(height)for dx in range(width)]}
                objects.append(b)
            else:b['northOriginalKey']=b['key'];b['key']='building:house-north'
            north.append({'map':mid,'x':(x+right)//2,'y':y,'event':value>>8&255,'width':width,'height':height})
    for filename,j in [('enhanced-art.json',hd),('enhanced-art-sources.json',sources)]:
        (ART/filename).write_text(json.dumps(j,ensure_ascii=False,separators=(',',':')))
    bucket_count=sum(b['key']=='furniture:wooden-bucket' for rows in hd['decorations'].values()for b in rows)
    (ROOT/'tool/fmj_scene_audit_v7.json').write_text(json.dumps({'mapsChecked':len(maps),'northEntrances':north,'bucketPlacements':bucket_count,'wells':wells},ensure_ascii=False,indent=2)+'\n')
    print('Updated Sanqing gate, Lifu lions and hall; checked',len(maps),'maps,',len(north),'north entrances and',bucket_count,'bucket positions')


if __name__=='__main__':main()
