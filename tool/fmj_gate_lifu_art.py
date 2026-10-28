"""山门及李府陈设修订：在原占地内换绘美术，不修改地图、碰撞、事件或剧情资源。"""
from pathlib import Path
import copy
import json
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/fmj/modern'
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


def gate(hd):
    c=Drawing(512,640)
    c.oval((14,597,498,633),'#152e2944')
    # 雕刻石座与朱漆柱用渐变而非平面色块，门中通道保持透明。
    for cx in [70,442]:
        c.polygon([(cx-37,582),(cx+37,582),(cx+51,608),(cx-51,608)],'#7b8c80',width=2)
        c.rect((cx-35,560,cx+35,585),'#a9b39b',INK,2)
        c.rect((cx-28,531,cx+28,563),'#bbc2a8',INK,2)
        c.line([(cx-33,567),(cx+33,567)],'#d9d5b5',2)
        c.oval((cx-24,550,cx+24,571),'#7b8f7b','#405c4d',2)
        c.oval((cx-30,530,cx+30,548),'#c5ccb2',INK,2)
        for y in [540,573]:
            c.line([(cx-18,y+5),(cx-8,y),(cx,y+5),(cx+8,y),(cx+18,y+5)],'#647d68',2)
        mask=Image.new('L',(512*S,640*S));ImageDraw.Draw(mask).rounded_rectangle(c.xy((cx-19,258,cx+19,536)),radius=10*S,fill=255)
        yy,xx=np.mgrid[:640*S,:512*S];shade=np.maximum(0,np.cos((xx-cx*S)/(20*S)*math.pi/2))
        rgb=np.stack([109+shade*59,38+shade*38,31+shade*31],axis=2).clip(0,255).astype('uint8')
        layer=Image.fromarray(rgb).convert('RGBA');layer.putalpha(mask);c.im.alpha_composite(layer)
        c.line([(cx-17,264),(cx-17,528)],'#61352c',2);c.line([(cx-8,268),(cx-8,525)],'#d59b67',2)
        for y in [278,512]:c.rect((cx-21,y,cx+21,y+9),'#a17f48',INK,2);c.line([(cx-16,y+2),(cx+16,y+2)],'#ead3a0',1)
    # 双层斗拱：挑梁、拱臂与承托木件一一相连，不悬空贴金条。
    for cx in [70,442]:
        for y,reach in [(264,34),(250,48),(236,62)]:
            c.polygon([(cx-reach,y-9),(cx+reach,y-9),(cx+reach-8,y+4),(cx+16,y+7),(cx+12,y+16),(cx-12,y+16),(cx-16,y+7),(cx-reach+8,y+4)],'#637b6c',width=2)
            c.line([(cx-reach+7,y-5),(cx+reach-7,y-5)],GOLD,2)
    c.rect((51,236,461,276),'#4b675c',INK,2)
    for y in [240,269]:c.line([(57,y),(455,y)],GOLD,3)
    for x in range(87,432,34):
        c.line([(x,249),(x+10,244),(x+20,249),(x+10,255),(x,249)],'#afaa75',2)
    # 复用当前殿宇的手绘瓦片，使新门楼与其余建筑保持同一笔触。
    roof=sprite(hd,'building:palace/0');roof=roof.crop((0,0,roof.width,round(roof.height*.5)))
    c.rect((123,126,389,192),'#77543a',INK,2)
    for x in range(136,386,22):c.rect((x,137,x+12,176),'#314f48',GOLD,1)
    c.paste(roof,(0,141,512,116))
    c.paste(roof,(55,4,402,151))
    # 镇脊宝珠和吻兽，低饱和金属色仅用于结构边缘和纹样。
    c.oval((243,1,269,26),'#b6a066',INK,2);c.oval((248,3,261,12),'#e8dcb0')
    c.polygon([(129,266),(383,266),(378,325),(134,325)],'#294a45',GOLD,3)
    c.rect((141,277,371,313),'#28463f','#887f57',1)
    for x in [144,368]:
        c.line([(x,283),(x+(-8 if x==144 else 8),296),(x,307)],'#d3b579',2)
    c.text((256,295),'三清宫',37,'#ecda9e')
    # 灯笼由横梁悬挂，保留层叠轮廓、铜顶、束腰与流苏。
    for x in [111,401]:
        c.line([(x,287),(x,326)],GOLD,2)
        c.rect((x-17,325,x+17,332),'#b39761',INK,1)
        c.oval((x-20,330,x+20,383),'#a24633',INK,2)
        c.oval((x-12,332,x+12,380),'#c66b45','#8d3d2e',1)
        c.line([(x-1,336),(x-1,376)],'#dba66c',2)
        c.rect((x-13,380,x+13,386),'#ac915b',INK,1)
        for dx in [-4,0,4]:c.line([(x+dx,386),(x+dx,409)],'#c9aa66',1)
    return c.finish()


def gate_wing(hd, right=False):
    """左右门楼同绘，替换旧放大的点阵侧柱，与中央朱柱、檐色和石座衔接。"""
    c=Drawing(256,640)
    c.oval((16,588,256,622),'#173b2e44')
    c.rect((69,347,255,545),'#b1b99e',INK,2)
    c.rect((81,370,255,502),'#5d7662',INK,2)
    for y in [380,490]:c.line([(89,y),(255,y)],'#c6b079',2)
    for x in range(105,255,46):
        c.line([(x,405),(x-14,424),(x+10,431),(x+20,414)],'#aab795',3)
        c.line([(x-8,460),(x+10,446),(x+22,460)],'#aab795',2)
    for y in [521,537]:c.line([(76,y),(255,y)],'#6e8269',2)
    c.polygon([(21,578),(87,578),(101,606),(7,606)],'#7c9080',width=2)
    c.rect((18,550,89,583),'#b4c0a5',INK,2)
    c.rect((29,276,79,552),'#bbc5aa',INK,2)
    c.rect((37,285,69,541),'#809984',INK,1)
    for y in range(315,524,37):
        c.line([(45,y+14),(40,y+4),(53,y),(62,y+12),(54,y+24)],'#bfc9aa',2)
    c.rect((18,267,90,285),'#738d77',INK,2)
    c.polygon([(14,256),(94,256),(102,270),(7,270)],'#bcc6a8',width=2)
    roof=sprite(hd,'building:house/0');roof=roof.crop((0,0,roof.width,round(roof.height*.55)))
    c.paste(roof,(0,212,256,137))
    c.rect((72,344,255,356),'#54715f',INK,1);c.line([(75,346),(255,346)],GOLD,2)
    image=c.finish()
    return ImageOps.mirror(image) if right else image


def side_chair():
    c=Drawing(128,64);c.oval((12,52,117,64),'#15322a44')
    c.polygon([(28,35),(99,37),(110,45),(33,46)],'#9b7755',width=2)
    c.polygon([(33,46),(110,45),(107,53),(32,53)],'#674931',width=2)
    for x in [29,95]:c.polygon([(x,45),(x+8,45),(x+6,62),(x-1,62)],'#6b5139')
    c.polygon([(15,5),(31,9),(33,45),(17,39)],'#96714c',width=2)
    c.polygon([(19,10),(27,13),(29,34),(20,30)],'#4f3d2b')
    c.line([(19,9),(18,36)],'#cbb181',2)
    for y in range(15,31,5):c.line([(21,y),(28,y+3)],'#a8895a',1)
    c.line([(26,27),(95,30),(102,37)],'#bd9b6a',4)
    c.line([(26,29),(95,32)],'#604b35',1)
    for x in [45,68,91]:c.rect((x,32,x+3,39),'#6a4c31')
    c.line([(39,49),(97,49)],'#c2a06b',1)
    return c.finish()


def side_group():
    im=Image.new('RGBA',(128,192));chair=side_chair();im.alpha_composite(chair,(0,0));im.alpha_composite(chair,(0,128))
    c=Drawing(128,64);c.oval((15,44,118,63),'#18362b44')
    for x in [25,94]:c.polygon([(x,26),(x+7,26),(x+5,59),(x-2,59)],'#775438')
    c.polygon([(15,13),(105,19),(119,32),(28,27)],'#b18f5f',width=2)
    c.polygon([(28,27),(119,32),(117,39),(27,34)],'#785638',width=2)
    c.line([(22,15),(103,21)],'#dcc395',2);c.line([(36,34),(106,38)],'#c3a16a',1)
    im.alpha_composite(c.finish(),(0,64));return im


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
    # 对齐原99号台阶列x7及x13：每个出入口保留两级踏面。
    for x in [7,13]:
        center=(x+.5)/21*512
        c.polygon([(center-13,0),(center+13,0),(center+18,27),(center-18,27)],'#bdc6ad')
        c.rect((center-18,27,center+18,34),'#657d6b')
        c.polygon([(center-18,34),(center+18,34),(center+23,55),(center-23,55)],'#a2b39a')
        c.rect((center-23,55,center+23,63),'#4f6959');c.line([(center-19,37),(center+19,37)],'#e1dfbd',2)
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
        if n!=2:sources['frames'][f'mechanism:gate:{n}/0']={'source':'tool/fmj_gate_lifu_art.py','originalSprite':n,'details':'coordinated side wing roof, carved stone pier and inset cloud panel'}
    for t,page in pages.items():page.save(ART/hd['textures'][t],optimize=True)
    sources['frames'][key]={'source':'tool/fmj_gate_lifu_art.py','derivedFrom':'building:palace/0','details':'double eaves, vermilion columns, dougong, bronze plaque, carved stone bases; unchanged original footprint'}
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
