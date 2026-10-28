"""按原ROM物品身份绘制彩色图标，并修订加宽建筑立面与山壁材质。

所有形状在256坐标空间绘制，缩采样后放入96像素图集；不在游戏帧内生成图片。
不改物品数值、原地图、碰撞或入口。可重复执行，旧图集中的其余切片保持不变。
"""
from pathlib import Path
import hashlib
import json
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/fmj/modern'
R = Image.Resampling.LANCZOS
INK = '#263735'
GOLD = '#d1ad65'
PALETTE = ['#547d83', '#799268', '#965954', '#716088', '#9d804c', '#426b60', '#667792']


def tint(color, factor):
    from PIL import ImageColor
    return tuple(min(255, max(0, round(c * factor))) for c in ImageColor.getrgb(color))


class Drawing:
    """带统一轮廓、局部渐变和抗锯齿的离线矢量式笔刷。"""
    def __init__(self):
        self.im = Image.new('RGBA', (256, 256))

    @property
    def d(self):
        return ImageDraw.Draw(self.im)

    def shape(self, points, color, outline=INK, width=3):
        mask = Image.new('L', (256, 256)); ImageDraw.Draw(mask).polygon(points, fill=255)
        self.fill(mask, color)
        if outline:
            self.d.line(points + [points[0]], fill=outline, width=width, joint='curve')

    def fill(self, mask, color):
        yy, xx = np.mgrid[:256, :256]
        # 顶部左侧受光，保留明显的金属/织物体积，不用纯色剪影。
        factor = .77 + .34 * (1 - yy / 256) + .12 * (1 - xx / 256)
        rgb = np.array(tint(color, 1), dtype=float)
        pixels = np.zeros((256, 256, 4), dtype=np.uint8)
        pixels[:, :, :3] = (factor[:, :, None] * rgb).clip(0, 255).astype('uint8')
        pixels[:, :, 3] = np.array(mask)
        self.im.alpha_composite(Image.fromarray(pixels))

    def oval(self, box, color, outline=INK, width=3):
        mask = Image.new('L', (256, 256)); ImageDraw.Draw(mask).ellipse(box, fill=255)
        self.fill(mask, color)
        if outline:self.d.ellipse(box, outline=outline, width=width)

    def box(self, box, color, radius=3, outline=INK, width=3):
        mask = Image.new('L', (256, 256)); ImageDraw.Draw(mask).rounded_rectangle(box, radius, fill=255)
        self.fill(mask, color)
        if outline:self.d.rounded_rectangle(box, radius, outline=outline, width=width)

    def line(self, points, color=GOLD, width=3):
        self.d.line(points, fill=color, width=width, joint='curve')

    def gem(self, x, y, color, r=10):
        self.shape([(x, y-r), (x+r, y), (x, y+r), (x-r, y)], color)
        self.line([(x-r+3, y), (x, y-r+3), (x, y+r-3)], '#e0ead1', 2)

    def shadow(self):self.d.ellipse((32, 215, 224, 239), fill='#091d1b44')


def leaf(c, x, y, angle, color, length=48):
    points=[]
    for u,v in [(0,0),(-13,-length*.35),(-9,-length*.75),(0,-length),(11,-length*.65),(12,-length*.25)]:
        a=math.radians(angle);points.append((x+u*math.cos(a)-v*math.sin(a),y+u*math.sin(a)+v*math.cos(a)))
    c.shape(points,color,width=2)
    c.line([points[0],points[3]],'#c0c591',2)


def weapon(color, index, knife=False, wood=False):
    c=Drawing();c.shadow()
    if knife:
        c.shape([(110,23),(134,40),(150,80),(147,132),(128,178),(111,177),(128,126),(126,67)],color)
        c.line([(134,48),(142,94),(136,139),(124,164)],'#e0e8d6',3)
    else:
        breadth=10+index%4*2
        c.shape([(128,15),(128+breadth,47),(138,174),(118,174),(128-breadth,47)],color)
        c.shape([(128,18),(128,172),(119,172),(128-breadth,47)],tint_hex(color,.7),outline=None)
        c.line([(128,38),(128,165)],'#d9e5d9' if not wood else '#ceb78e',2)
    c.shape([(88,175),(109,164),(147,164),(169,175),(164,183),(139,178),(117,178),(92,184)],GOLD)
    c.box((119,179,137,222),'#624a36' if wood else '#374c51',4)
    for y in range(186,218,7):c.line([(121,y),(135,y-3)],'#bca378',2)
    c.oval((116,218,140,237),GOLD)
    c.gem(128,172,PALETTE[index%7],7)
    for y in range(65,145,16+index%7):
        if index>4:c.gem(128,y,PALETTE[index%7],3+index%3)
    return c.im


def tint_hex(color, factor):return '#%02x%02x%02x'%tint(color,factor)


def icon(item):
    t,i,n=item['type'],item['index'],item['name'];c=Drawing();c.shadow()
    color=PALETTE[(i-1)%7]
    for word,value in [('金','#b5934e'),('银','#b4c7c9'),('玉','#4b9d89'),('青','#547e78'),('蓝','#577fba'),('紫','#946c9d'),('红','#af584b'),('赤','#b75b43'),('白','#d5d7be'),('黑','#455454'),('火','#bc6339'),('冰','#91c7c9')]:
        if word in n:color=value;break
    color=tint_hex(color,.91+i*.007)
    if t==1:
        if any(k in n for k in ['簪','饰','毛']):
            c.line([(61,207),(181,48)],'#334b46',13);c.line([(62,205),(181,48)],'#d3bf83',7)
            if '毛' in n:
                for a in range(-35,46,20):leaf(c,159,99,a,color,78)
            else:
                for a in range(5):
                    x=165+math.cos(a*math.tau/5)*28;y=72+math.sin(a*math.tau/5)*28;c.oval((x-13,y-13,x+13,y+13),color)
                c.gem(165,72,GOLD,13)
        elif any(k in n for k in ['带','巾']):
            c.shape([(50,93),(207,88),(196,127),(61,133)],color)
            c.shape([(175,121),(210,121),(227,208),(198,195),(181,219)],color)
            c.shape([(169,121),(187,133),(167,201),(144,191)],tint_hex(color,.85))
            c.line([(62,103),(196,99)],'#d4c593',3);c.gem(126,111,GOLD,11)
        elif '面罩' in n:
            c.oval((50,57,207,212),'#718785');c.oval((73,97,111,138),'#20383a');c.oval((145,97,183,138),'#20383a');c.box((97,147,159,194),'#455e59',8)
        else:
            crown='冠' in n
            if crown:c.shape([(57,156),(51,71),(86,105),(126,44),(165,105),(206,70),(197,156)],color)
            else:c.oval((60,61,196,182),color);c.box((86,43,170,86),color,12)
            c.box((47,149,209,181),color,8);c.line([(55,158),(201,158)],GOLD,4);c.gem(128,151,'#79bfc1',18)
            if '盔' in n:c.shape([(62,162),(84,176),(82,217),(52,201)],color);c.shape([(194,162),(174,176),(174,217),(204,201)],color)
    elif t==2:
        c.shape([(93,48),(75,53),(25,91),(47,133),(77,114),(65,219),(191,219),(179,114),(209,133),(231,91),(181,53),(162,48),(128,75)],color)
        c.shape([(94,47),(128,75),(159,48),(151,84),(128,113),(101,85)],'#e0d9b5')
        c.line([(128,80),(110,151),(108,215)],GOLD,4);c.line([(77,114),(84,90)],tint_hex(color,.6),3)
        c.box((73,144,183,159),'#513f31',3);c.gem(126,151,GOLD,10)
        armored=any(s in n for s in ['甲','胃','锁','缕'])
        for y in range(103,210,21):
            for x in range(89,175,19):
                if 139<y<164:continue
                if armored:c.d.arc((x-7,y-5,x+8,y+8),0,180,fill=GOLD,width=2)
                elif i>7:c.line([(x,y),(x+5,y-5),(x+10,y)],tint_hex(color,1.4),2)
    elif t==3:
        for dx,dy in [(0,-17),(71,12)]:
            x=48+dx;y=56+dy
            c.shape([(x,y),(x+56,y),(x+54,y+91),(x+74,y+109),(x+74,y+137),(x-17,y+137),(x-24,y+122),(x-17,y+102),(x+4,y+89)],color)
            c.line([(x+3,y+7),(x+47,y+7)],GOLD,6);c.line([(x-16,y+129),(x+66,y+129)],'#d1c49e',5)
            for yy in range(y+23,y+81,15):c.line([(x+14,yy),(x+42,yy-5)],GOLD,2)
            if '草鞋' in n:
                for xx in range(x-8,x+68,10):c.line([(xx,y+111),(xx+12,y+130)],'#e3cd8b',3)
    elif t==4:
        c.shape([(100,51),(72,62),(39,120),(65,129),(50,219),(128,233),(207,219),(192,129),(218,120),(185,62),(155,51),(128,79)],color)
        c.line([(100,53),(128,80),(156,53)],GOLD,6)
        for x in [78,104,151,178]:c.line([(128+(x-128)*.55,95),(x,212)],tint_hex(color,.66),4)
        if any(k in n for k in ['甲','肌','铠']):
            for y in [101,128,155,182]:c.shape([(75,y),(128,y+11),(181,y),(175,y+15),(128,y+27),(81,y+15)],tint_hex(color,1.12))
        else:
            for a in range(5):leaf(c,128,161,a*72,GOLD,28)
        if '芦藤' in n:
            for x in range(76,184,17):c.line([(x,96),(x+9,210)],'#a9b17a',3)
    elif t==5:
        for dx,dy in [(0,0),(72,39)]:
            c.shape([(44+dx,57+dy),(107+dx,44+dy),(121+dx,156+dy),(56+dx,172+dy)],color)
            c.oval((44+dx,40+dy,109+dx,72+dy),'#d8c79b');c.oval((53+dx,46+dy,100+dx,63+dy),'#3e534e')
            c.line([(56+dx,81+dy),(109+dx,70+dy)],GOLD,5);c.line([(60+dx,150+dy),(113+dx,138+dy)],GOLD,5);c.gem(82+dx,110+dy,'#87b49d',15)
    elif t==7 or (t==14 and i==12):
        metal=tint_hex('#b6cbcd' if i%4!=0 else '#607b83',.84+i*.006)
        if '木' in n:metal='#b99564'
        if any(k in n for k in ['玉','碧']):metal='#7eb7a8'
        im=weapon(metal,i,knife='刀' in n,wood='木' in n)
        if '双' in n or '姐妹' in n:
            im=Image.new('RGBA',(256,256));a=weapon(metal,i).resize((165,224),R);im.alpha_composite(a.rotate(-22,resample=Image.Resampling.BICUBIC,expand=False),(5,9));im.alpha_composite(a.rotate(22,resample=Image.Resampling.BICUBIC,expand=False),(84,9))
        if t==14:
            overlay=ImageDraw.Draw(im);overlay.ellipse((108,157,148,180),outline='#bce3cb',width=3)
        return im
    elif (t==14 and '钥匙' in n):
        metal=GOLD if '金色' in n else '#b9d0c2'
        c.oval((49,31,126,107),metal);c.oval((70,52,105,87),'#24443f');c.shape([(108,90),(125,80),(214,182),(197,196),(181,177),(167,191),(152,174),(166,159)],metal);c.line([(116,93),(197,184)],'#f0dfa9',3)
    elif t==14 and '信' in n or t==14 and '情书' in n:
        c.shape([(36,65),(214,52),(226,193),(48,207)],'#d6c49a' if i==1 else '#bdb99c');c.line([(38,69),(130,134),(213,55)],'#9c8556',4);c.line([(49,203),(103,135)],'#a58c5c',3);c.oval((112,119,148,151),'#a14c41');c.gem(130,135,'#e7c48d',5 if i==1 else 9)
    elif t==14 and '卡片' in n:
        c.box((60,29,195,223),'#b2a47e',10);c.box((70,40,185,212),['#51775e','#666494','#985954'][i-5],6);c.box((80,51,175,201),color,4,outline=GOLD,width=3)
        if i==5:
            for y in [102,120,138,156]:c.oval((110,y-10,143,y+19),'#c2b778');c.line([(109,119),(91,107),(87,117)],GOLD,4);c.line([(141,119),(159,107),(162,117)],GOLD,4)
        elif i==6:
            c.oval((99,86,155,155),'#c4c9c0');c.shape([(98,118),(155,118),(160,163),(148,154),(134,166),(121,156),(101,166)],'#c4c9c0');c.oval((111,111,119,122),INK);c.oval((137,111,145,122),INK)
        else:
            for x,y in [(112,104),(143,104),(112,145),(143,145)]:c.oval((x-9,y-9,x+9,y+9),'#edd8a0')
        for y in [62,189]:c.line([(95,y),(160,y)],GOLD,3)
    elif t==14 and 8<=i<=11:
        c.oval((40,39,216,216),'#385851');c.oval((52,51,204,204),['#5d9476','#bab79a','#ba6651','#698d9c'][i-8]);c.d.ellipse((58,57,198,198),outline=GOLD,width=4)
        if i==8:
            c.line([(88,170),(146,159),(154,127),(109,115),(100,91),(141,77),(167,97)],'#36534b',22);c.shape([(153,102),(155,69),(175,77),(182,94),(169,109)],GOLD);c.line([(159,76),(151,58)],GOLD,5)
        elif i==9:
            c.shape([(82,108),(77,76),(102,89),(128,80),(154,89),(180,76),(174,111),(160,162),(128,178),(96,161)],'#e2ddbc');c.line([(100,118),(114,128),(104,148)],INK,5);c.line([(155,118),(142,128),(153,148)],INK,5);c.shape([(115,145),(141,145),(128,158)],INK)
        elif i==10:
            c.shape([(128,103),(93,80),(66,108),(98,122),(72,145),(111,137),(128,185),(143,135),(181,145),(158,121),(191,104),(163,80),(136,105),(145,63),(127,76)],'#e4bf73');c.gem(130,113,'#b44e39',11)
        else:
            c.oval((88,80,168,179),'#3a6462');c.gem(128,129,GOLD,30)
            for x,y in [(91,92),(164,92),(90,163),(165,163),(128,73)]:c.oval((x-9,y-9,x+9,y+9),'#bad0ae')
    elif '灯' in n or (t==6 and '钟' in n) or (t==14 and i==13):
        if '钟' in n:
            c.shape([(93,53),(164,53),(175,158),(195,192),(61,192),(81,158)],GOLD);c.oval((102,32,154,68),GOLD);c.oval((113,39,143,58),'#263c33');c.line([(76,174),(181,174)],'#e8d294',5)
        elif t==14:
            c.shape([(64,87),(191,87),(179,181),(76,181)],GOLD);c.oval((51,68,205,103),GOLD);c.oval((64,77,192,94),'#5a613e');c.shape([(82,176),(103,176),(94,216),(75,216)],GOLD);c.shape([(154,176),(175,176),(183,216),(164,216)],GOLD)
        else:
            flame='#b196dc' if '紫瞳' in n else '#84c3b0' if '幽灵' in n else '#edc26e'
            c.box((94,171,163,186),GOLD);c.shape([(112,167),(141,167),(135,93),(119,93)],GOLD);c.oval((71,76,183,109),GOLD);c.oval((81,79,172,98),'#425947');c.shape([(124,84),(110,64),(129,30),(140,61),(134,84)],flame);c.line([(128,78),(128,52)],'#f6e5a0',5);c.oval((85,193,172,215),GOLD)
            if '七星' in n:
                for x,y in [(65,130),(188,130),(74,161),(180,161),(128,126)]:c.oval((x-8,y-5,x+8,y+5),GOLD);c.line([(x,y),(x,y-17)],'#dab965',3)
    elif '符' in n or '旗' in n or (t==6 and i==18):
        c.shape([(77,31),(181,39),(175,222),(68,210)],'#d3ba72');c.line([(86,44),(170,50),(165,205),(80,199),(86,44)],'#9b573e',3)
        c.line([(104,64),(151,67),(123,94),(151,113),(106,119),(141,143),(105,167),(149,187)],'#974d3b',6);c.line([(121,57),(119,197)],'#974d3b',3)
        for k in range(i%5+1):c.gem(93+k*14,184,PALETTE[(i+t)%7],3)
        for k in range(t%3):c.line([(88,75+k*19),(103,79+k*19)],'#974d3b',2)
        c.d.arc((101,87+i%12,148,136+i%12),20+i*7,180+i*7,fill=PALETTE[(t+i)%7],width=3)
    elif '镜' in n:
        c.oval((42,36,214,208),GOLD);c.oval((57,51,199,193),'#708f88');c.oval((71,64,186,177),'#bbd2c7');c.d.arc((80,76,175,166),180,270,fill='#e3e9d4',width=7);c.gem(128,201,color,12)
    elif t==6:
        if '笛' in n:
            c.shape([(62,199),(49,186),(186,38),(200,53)],'#a28a54')
            for x in range(81,174,18):c.oval((x-4,225-x-4,x+4,225-x+4),'#354b3b')
        elif '袋' in n:
            c.shape([(90,68),(166,68),(156,94),(185,149),(176,200),(128,218),(78,200),(69,149),(101,95)],color);c.line([(91,80),(166,80)],GOLD,7);c.gem(128,153,GOLD,25)
        else:
            c.d.arc((65,34,191,163),0,180,fill=GOLD,width=6);c.gem(128,157,color,44);c.line([(128,194),(128,230)],GOLD,6);c.line([(117,216),(112,238)],GOLD,3);c.line([(137,216),(145,237)],GOLD,3)
    elif any(k in n for k in ['草','叶','针树','两面针','青阴','魔王须','田七','紫荦','根','延命香']) and '蛋' not in n:
        if '延命香' in n:
            for x in [98,128,158]:c.line([(x,196),(x-12,47)],'#bba26b',7);c.oval((x-16,35,x-9,47),'#c76549')
            c.box((70,183,185,205),'#7e6a4a');c.line([(88,214),(168,214)],GOLD,5)
        else:
            c.line([(127,213),(114,140),(144,68)],'#537a4c',7)
            for x,y,a0 in [(122,184,-65),(120,155,50),(126,130,-50),(133,111,48),(141,85,-20)]:leaf(c,x,y,a0,color if '珠仙' in n or '玄冥' in n else tint_hex('#729260',.88+i*.009),43+i%6*4)
            c.line([(127,209),(102,229)],'#b29c6a',6);c.line([(127,209),(148,229)],'#b29c6a',6)
    elif '果' in n or '菩提' in n or '杏' in n:
        for x,y in [(98,152),(159,151),(129,104)]:c.oval((x-35,y-36,x+35,y+37),color);c.d.arc((x-24,y-25,x+20,y+22),195,275,fill='#efd6a1',width=3)
        leaf(c,136,77,55,'#6f975c',48);c.line([(128,91),(137,55)],'#796544',5)
    elif '虫' in n or n in ['魔王甲','黑狐甲'] or '蝎卵' in n or '蜘蛛卵' in n:
        c.oval((88,84,170,201),color);c.oval((103,54,155,100),color)
        for y in [102,129,155,181]:c.line([(91,y),(65,y-11),(51,y+6)],GOLD,4);c.line([(167,y),(191,y-11),(205,y+6)],GOLD,4)
        c.line([(128,98),(128,189)],'#d3c9a3',3);c.oval((112,67,119,74),'#e4d6a0');c.oval((137,67,144,74),'#e4d6a0')
    elif '石' in n or '珠' in n or t==13:
        color=tint_hex(color,.85+t*.012)
        c.shape([(67,182),(44,106),(97,43),(170,53),(210,133),(176,207),(98,221)],color);c.shape([(97,44),(123,131),(44,107)],tint_hex(color,1.4));c.shape([(123,131),(171,54),(210,133),(176,207)],tint_hex(color,.72));c.line([(97,44),(123,131),(98,219)],GOLD,3)
        if t==13:c.gem(128,133,'#f0d9a0',24)
    elif '镖' in n or '袖里剑' in n or '钉' in n or '毒铁' in n or '针' in n:
        count=5 if '梅花' in n else 4
        points=[]
        for a in range(count*2):
            theta=a*math.pi/count;r=101 if a%2==0 else 29;points.append((128+math.sin(theta)*r,128+math.cos(theta)*r))
        c.shape(points,'#9caeb2');c.oval((112,112,144,144),color);c.oval((121,121,135,135),'#213d38')
    elif '花' in n and '酒' not in n:
        for a in range(8):
            x=128+math.cos(a*math.tau/8)*48;y=123+math.sin(a*math.tau/8)*48;c.oval((x-28,y-34,x+28,y+34),color)
        c.oval((104,99,152,147),GOLD);c.line([(126,176),(130,222)],'#6a8b54',7);leaf(c,130,209,60,'#708b55',43)
    elif '蛋' in n or '卵' in n:
        c.oval((68,49,185,218),'#a1bd94' if '蛇' in n else '#cab484');c.d.arc((83,67,170,199),190,265,fill='#e6dbb6',width=6)
        for x,y in [(110,100),(146,135),(104,171)]:c.d.arc((x-18,y-12,x+18,y+12),0,145,fill='#876442',width=3)
    elif '鹿肉' in n or '尸肉' in n:
        c.line([(61,202),(200,51)],'#bba372',11);c.shape([(69,128),(107,69),(150,60),(182,100),(179,141),(127,187)],'#a8754e' if '鹿' in n else '#777a62');c.line([(89,125),(134,80)],'#deb77c',6);c.line([(112,151),(158,102)],'#633f2c',5)
    elif '蛙' in n:
        c.oval((79,90,182,191),'#78a99e');c.oval((71,72,116,119),'#a0c6b2');c.oval((149,72,194,119),'#a0c6b2');c.oval((86,82,99,96),INK);c.oval((163,82,176,96),INK);c.line([(90,177),(48,206),(82,212)],'#94ba96',14);c.line([(168,177),(208,206),(174,212)],'#94ba96',14)
    else:
        # 药膏、药酒、散剂、丹药的容器由名称区分，刻纹和标签随原物品身份绑定。
        bowl=any(k in n for k in ['汤','散','糯','盐','粉','砂'])
        if bowl:
            c.shape([(54,119),(202,119),(186,190),(154,213),(101,213),(70,191)],color);c.oval((51,100,205,140),'#c9c19a');c.oval((65,109,192,129),'#53664b')
        else:
            c.box((97,39,160,70),'#725b37',5);c.shape([(100,71),(156,71),(155,91),(184,115),(193,192),(175,217),(80,217),(61,191),(71,115),(101,91)],color);c.line([(82,117),(78,181)],tint_hex(color,1.5),6);c.box((94,122,163,184),'#d4c194',6);c.line([(107,139),(151,139),(120,156),(147,168)],'#8b573e',4)
        for k in range(i%3+1):c.gem(110+k*16,175 if bowl else 203,'#dbbb72',5)
    # 同类物品有各自的材质色阶，草叶、丹瓶等既保持家族辨识，也不共享占位位图。
    values=np.array(c.im);mask=values[:,:,3]>0
    factor=.97+(t*37+i)%9*.007
    values[mask,:3]=(values[mask,:3].astype(float)*factor).clip(0,255).astype('uint8')
    return Image.fromarray(values)


def items_from_rom():
    raw=(ROOT/'assets/fmj/game/DAT.LIB').read_bytes();items=[]
    for h in range(16,8192,3):
        if raw[h]==255:break
        if raw[h]!=6:continue
        kind,t,i=raw[h:h+3];p=8192+h-16;off=raw[p]*16384+raw[p+1]+raw[p+2]*256
        text=lambda at:raw[off+at:raw.index(0,off+at)].decode('gbk',errors='strict')
        items.append(dict(id=f'{t}:{i}',type=t,index=i,name=text(6)))
    return sorted(items,key=lambda a:(a['type'],a['index']))


def main():
    hd=json.loads((ART/'enhanced-art.json').read_text());sources=json.loads((ART/'enhanced-art-sources.json').read_text());items=items_from_rom()
    assert len(items)==216
    filename='goods-icons-v6.png';page=Image.new('RGBA',(14*96,16*96))
    if filename not in hd['textures']:hd['textures'].append(filename)
    texture=hd['textures'].index(filename)
    for k,item in enumerate(items):
        im=icon(item).resize((88,88),R);x=k%14*96+4;y=k//14*96+4;page.alpha_composite(im,(x,y));key=f"goods:{item['id']}/0"
        hd['frames'][key]=[texture,x,y,88,88];sources['frames'][key]=dict(source='tool/fmj_art_v6.py',originalItem=item['id'],name=item['name'],method='offline vector shapes; shaded materials; supersampled RGBA')
    page.save(ART/filename,optimize=True)
    # 复用已认可屋顶的瓦片细节，重绘加宽立面：木梁、格窗、门框、打开的双门和石阶。
    old=hd['frames']['building:hall/0'];roof=Image.open(ART/hd['textures'][old[0]]).crop((old[1],old[2],old[1]+old[3],old[2]+round(old[4]*.49)))
    building_page=Image.new('RGBA',(2048,1024));yy=0;xx=0;rowh=0
    bfile='building-frontages-v6.png'
    if bfile not in hd['textures']:hd['textures'].append(bfile)
    bt=hd['textures'].index(bfile)
    for span in range(3,11):
        w=span*64;h=192;im=Image.new('RGBA',(w,h));d=ImageDraw.Draw(im)
        # 窗与门的位置始终对应原宽建筑中心的出入口，纯色暗区只存在于真正的门洞。
        d.rectangle((19,66,w-20,181),fill='#c0b695',outline='#544c37',width=3)
        plaster=Image.open(ART/'surface-wall-plaster.png').convert('RGBA').resize((w-40,112),R)
        im.alpha_composite(plaster,(20,68));d=ImageDraw.Draw(im)
        d.rectangle((24,173,w-25,184),fill='#7d8371',outline='#3f534b',width=2)
        for x in [23,w-34]:
            d.rectangle((x,94,x+11,175),fill='#775339',outline='#382f27',width=2);d.line((x+4,101,x+4,168),fill='#b99261',width=2)
        opening=max(34,min(78,w//6));cx=w//2
        d.rectangle((cx-opening//2-6,92,cx+opening//2+6,179),fill='#77593a',outline='#3b3a2c',width=3)
        d.rectangle((cx-opening//2,100,cx+opening//2,173),fill='#172a25')
        for sign in [-1,1]:
            edge=cx+sign*opening//2
            d.polygon([(edge,100),(edge-sign*opening*.23,109),(edge-sign*opening*.23,172),(edge,173)],fill='#9d794c',outline='#4c402c')
            for y in [115,143,160]:d.line((edge,y,edge-sign*opening*.2,y+3),fill='#d0b77c',width=2)
            wx=cx+sign*(opening//2+(w//2-opening//2-30)//2)
            ww=max(20,min(56,(w-opening-70)//3));d.rectangle((wx-ww//2-4,108,wx+ww//2+4,157),fill='#af9361',outline='#4a4d39',width=2);d.rectangle((wx-ww//2,113,wx+ww//2,153),fill='#36534d')
            for dx in range(-ww//2+7,ww//2,9):d.line((wx+dx,114,wx+dx,151),fill='#c2b783',width=2)
            d.line((wx-ww//2,133,wx+ww//2,133),fill='#c2b783',width=2)
        d.rectangle((26,84,w-27,99),fill='#76583b',outline='#c1a374',width=2)
        for x in range(40,w-36,24):d.line((x,88,x+12,93),fill='#ad8959',width=1)
        d.polygon([(cx-opening//2-9,173),(cx+opening//2+9,173),(cx+opening//2+15,188),(cx-opening//2-15,188)],fill='#9ca58e',outline='#475e55')
        d.line((cx-opening//2-10,181,cx+opening//2+10,181),fill='#cbd0b5',width=2)
        cover=roof.resize((w,100),R);im.alpha_composite(cover,(0,0))
        if xx+w+8>2048:xx=0;yy+=rowh+8;rowh=0
        building_page.alpha_composite(im,(xx+4,yy+4));key=f'building:hall-wide-{span}/0';hd['frames'][key]=[bt,xx+4,yy+4,w,h];sources['frames'][key]=dict(source='tool/fmj_art_v6.py',derivedFrom='building:hall/0',details='timber facade; latticed windows; open doors; stone doorstep; original entrance unchanged');xx+=w+8;rowh=max(rowh,h)
    building_page.crop((0,0,2048,yy+rowh+8)).save(ART/bfile,optimize=True)
    # 连续山壁沿原始山壁格铺设，有层理、嵌缝和明暗；不再出现逐格云纹块。
    w=h=512;yy,xx=np.mgrid[:h,:w]
    # 复用游戏既有的手绘灰岩质感与青苔，而不是把墙壁画成几条平面色带。
    # 横向的周期变形打散方砖感，连续采样仍严格以512为周期，接缝不会跳色。
    rock=np.array(Image.open(ART/'surface-rock-ground.png').convert('RGB').resize((w,h),R)).astype(float)
    shift=np.round(13*np.sin(yy*math.tau/h)+5*np.sin(yy*math.tau*3/h)).astype(int)
    rock=rock[yy,(xx+shift)%w]
    light=.81+.07*np.cos(yy*math.tau/h)+.045*np.sin(xx*math.tau/h)
    rock=(rock*light[:,:,None]*np.array([.94,1.0,.96])).clip(0,255).astype('uint8')
    wall=Image.fromarray(rock).convert('RGBA')
    wall.save(ART/'surface-mountain-wall-v6.png',optimize=True);hd['groundTextures']['mountain-wall']='surface-mountain-wall-v6.png'
    marks=json.loads((ART/'scene-landmarks.json').read_text())
    for mid,rows in marks.items():
        caves=[b for b in hd['buildings'].get(mid,[])if b['key']=='building:cave-mouth']
        marks[mid]=[m for m in rows if not any(b['x']<=m['x']<=b['x']+b['width'] and b['y']<=m['y']<=b['y']+b['height'] for b in caves)]
    for name,value in [('enhanced-art.json',hd),('enhanced-art-sources.json',sources),('scene-landmarks.json',marks)]:
        (ART/name).write_text(json.dumps(value,ensure_ascii=False,separators=(',',':')))
    (ROOT/'tool/fmj_item_catalog.json').write_text(json.dumps(items,ensure_ascii=False,indent=2)+'\n')
    print('Updated:',len(items),'item icons; 8 complete frontages; continuous mountain wall; cave labels removed')


if __name__=='__main__':main()
