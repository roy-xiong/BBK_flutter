"""第三轮逐项审核修订：场景语义与墙地底材独立，不动已通过场景及原游戏数据。"""
from pathlib import Path
import copy,json
from PIL import Image,ImageDraw,ImageFilter
from fmj_indoor_review_v12 import components

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'assets/fmj/modern'
SOURCES=ROOT/'tool/art_sources/review-v14'
PREFIX='review-v14:'
R=Image.Resampling.LANCZOS


def main():
    hd=json.loads((ART/'enhanced-art.json').read_text())
    provenance=json.loads((ART/'enhanced-art-sources.json').read_text())
    baseline=json.loads((SOURCES/'baseline-layout.json').read_text())
    scope=json.loads((SOURCES/'scope.json').read_text())
    maps={m['id']:m for m in json.loads((ROOT/'assets/fmj/game/FmjGuideData.json').read_text())['maps']}
    pages={}
    def sprite(key):
        t,x,y,w,h=hd['frames'][key]
        return Image.open(ART/hd['textures'][t]).convert('RGBA').crop((x,y,x+w,y+h))
    def insert(name,im):
        key=PREFIX+name+'/0'
        if key in hd['frames']:
            t,x,y,w,h=hd['frames'][key]
            assert im.size==(w,h)
        else:
            found=None
            for t,file in enumerate(hd['textures']):
                page=pages.setdefault(t,Image.open(ART/file).convert('RGBA'))
                mask=Image.new('L',page.size);d=ImageDraw.Draw(mask)
                frames=[f for f in hd['frames'].values()if f[0]==t]
                for _,xx,yy,w,h in frames:d.rectangle((xx-2,yy-2,xx+w+1,yy+h+1),fill=255)
                xs={2,*[f[1]+f[3]+4 for f in frames]};ys={2,*[f[2]+f[4]+4 for f in frames]}
                for yy in sorted(ys):
                    for xx in sorted(xs):
                        if xx+im.width+2>page.width or yy+im.height+2>page.height:continue
                        if mask.crop((xx-2,yy-2,xx+im.width+2,yy+im.height+2)).getbbox()is None:
                            found=(t,xx,yy);break
                    if found:break
                if found:break
            assert found is not None,('图集空闲位置不足',name)
            t,x,y=found;hd['frames'][key]=[t,x,y,im.width,im.height]
        page=pages.setdefault(t,Image.open(ART/hd['textures'][t]).convert('RGBA'))
        page.paste(im,(x,y,x+im.width,y+im.height))
        provenance['frames'][key]={'source':'tool/fmj_review_v14.py','master':'tool/art_sources/review-v14/'+name+'.png'}
    sizes={**{f'pillar-{k}':(128,256)for k in ['dragon','tiger','bird','tortoise']},
           'stone-lantern':(128,224),'well':(192,144),'chest':(128,96),
           'garment-rack':(160,192),'cave-stairs':(128,128),'seated-guest-bench':(128,192)}
    for name,size in sizes.items():
        im=Image.open(SOURCES/(name+'.png')).convert('RGBA');bounds=im.getchannel('A').point(lambda a:255 if a>16 else 0).getbbox();assert bounds
        im=im.crop(bounds);im.thumbnail((size[0]-6,size[1]-6),R);out=Image.new('RGBA',size);out.alpha_composite(im,((size[0]-im.width)//2,size[1]-im.height-3));insert(name,out)
    for guardian in ['dragon','tiger','bird','tortoise']:
        old='review-v11:guardian-'+guardian+'/0';hd['frames'][old]=hd['frames'][PREFIX+'pillar-'+guardian+'/0']
        provenance['frames'][old]={'alias':PREFIX+'pillar-'+guardian+'/0','details':'用户要求四象保留各自身份，但必须是柱式机关'}

    # 原山道20/21/22是土路边缘，不能用纯色石阶条替代。此处只修本轮三张山道。
    earth=Image.open(ART/hd['groundTextures']['earth']).convert('RGBA')
    stair=earth.resize((128,128),R);d=ImageDraw.Draw(stair)
    for y in range(0,128,32):
        d.line((0,y+1,127,y+1),fill='#ead4a3',width=2)
        d.line((0,y+27,127,y+27),fill='#987e55',width=2)
        d.line((0,y+30,127,y+30),fill='#a98b60',width=2)
    insert('earth-steps',stair)

    fixes={}
    grounds=hd.setdefault('groundOverrides',{})
    for mid in scope['maps']:
        m=maps[mid];w=m['width'];height=m['height']
        hd['buildings'][mid]=copy.deepcopy(baseline['buildings'].get(mid,[]))
        hd['decorations'][mid]=copy.deepcopy(baseline['decorations'].get(mid,[]))
        original_rules=baseline['tileOverrides'].get(mid)
        if original_rules is None:hd['tileOverrides'].pop(mid,None)
        else:hd['tileOverrides'][mid]=copy.deepcopy(original_rules)
        grounds.pop(mid,None)
        rows=hd['decorations'][mid];buildings=hd['buildings'][mid]
        notes=[]
        def ground(cells,material):
            for i in cells:grounds.setdefault(mid,{})[str(i)]=material
        def add(key,cells,visual=None,visualwidth=None):
            cells=sorted(set(cells));assert cells
            x=min(i%w for i in cells);y=min(i//w for i in cells)
            width=max(i%w for i in cells)-x+1;h=max(i//w for i in cells)-y+1
            item={'key':key,'x':x,'y':y,'width':width,'height':h,'cells':cells}
            if visual:item['visualHeight']=visual
            if visualwidth:item['visualWidth']=visualwidth
            rows.append(item);return item
        def grouped(key,tiles,visual=None):
            found={i for i,v in enumerate(m['cells'])if v&127 in tiles}
            return [add(key,cells,visual)for cells in components(found,w,height)]
        if mid in ['1:3','1:5','1:6']:
            rules=hd['tileOverrides'].setdefault(mid,{})
            for tile in [38,*range(43,53),*range(72,79)]:rules[str(tile)]=['earth','floor',None]
            for tile in range(20,29):rules[str(tile)]=['earth','floor',None]
            if mid=='1:5':
                for tile in [20,21,22]:rules[str(tile)]=['earth','earth-steps',PREFIX+'earth-steps/0']
                notes.append('土阶改为与泥土地一致的细致踏面，移除粗糙的纯色横条。')
            if mid=='1:6':rules['50']=['mountain-wall','floor',None]
            for b in buildings:
                if b['key']=='building:cave-mouth':
                    ground(b['cells'],'mountain-wall')
            notes.append('清理山道拐角的异色平面，洞口背后补连续岩壁，岩石与路面保持原占格。')
        if mid=='1:35':
            for b in buildings:
                if b['key'].startswith('building:pavilion'):
                    ground([i for i in b['cells']if i//w<=2],'mountain-wall')
            notes.append('庙顶上方的黄色底图改为与相邻山壁连续的岩壁材质。')
        if mid=='1:36':
            grouped(PREFIX+'well',{124},1.3)
            notes.append('原井口换为完整精绘石井，井沿、石块和内部深度均清晰可见。')
        if mid=='1:9':notes.append('四象改为青龙、白虎、朱雀、玄武各自浮雕石柱，保留立柱、柱头及石座。')
        if mid=='1:39':
            grouped(PREFIX+'stone-lantern',{104,105,106,107},3.0)
            for i,v in enumerate(m['cells']):
                if v&127==50:add('review-v11:potted-shrub',[i],1.2)
            notes.append('十二组旧图块恢复为高石灯：灯座、立柱、灯室和檐顶完整；其余小盆景补精绘。')
        if mid in ['1:40','1:41','1:42']:
            for i,v in enumerate(m['cells']):
                if v&127==50:add('review-v11:signpost',[i],1.4)
            notes.append('原路口提示格恢复完整木路牌，保留原坐标和脚本。')
        if mid=='1:41':
            # 两座上下相邻的谷仓会共边，不能用连通域把它们合成一座高仓。
            for i,v in enumerate(m['cells']):
                if v&127==120 and i+w+1<len(m['cells']):
                    assert [m['cells'][i+1]&127,m['cells'][i+w]&127,m['cells'][i+w+1]&127]==[121,122,123]
                    add('review-v11:granary',[i,i+1,i+w,i+w+1],2.6)
            notes.append('六组仓身旧图恢复竹编茅草谷仓，覆盖完整顶盖与仓身。')
        if mid in ['1:43','1:44']:
            for i,v in enumerate(m['cells']):
                if v&127==50:add('plant:camphor'if mid=='1:44'else'review-v11:potted-shrub',[i],2.2 if mid=='1:44'else 1.2,1.6 if mid=='1:44'else 1.1)
            notes.append('钟山道院零散植被改为完整树木；同类旧盆景补齐彩绘。')
        if mid=='1:45':
            seen=set();clean=[]
            for b in buildings:
                identity=(b['key'],tuple(sorted(b.get('cells',[]))))
                if identity not in seen:clean.append(b);seen.add(identity)
            buildings[:]=clean
            hd['tileOverrides'].setdefault(mid,{})['114']=['earth','floor',None]
            notes.append('合并北海重复树冠，清除脱离树身的旧切片，保持完整树形和原碰撞。')
        if m['tiles']==3:
            # 厨房空地与房间统一为木地板。墙边器物背后按格补墙，不能因物件
            # 使用另一种tile而把墙擦成黄色空洞；过渡不影响任何已通过房间。
            if mid in ['2:5','2:10','2:11','2:12','2:13','2:14','2:23','2:24']:
                floor=[i for i,v in enumerate(m['cells'])if v&127==93]
                ground(floor,'wood-cross')
                notes.append('厨房和过道空白处铺连续木地板，消除与主房不一致的石地补丁。')
            for b in rows:
                if b['key'].startswith(('furniture:stove','furniture:jars','interior-v12:kitchen-counter','interior-v12:herb-rack'))and b['y']<=2:
                    ground([i for i in b['cells']if i//w<=max(2,b['y'])],'wall-plaster')
            if mid in ['2:5','2:14']:notes.append('灶台、案台后方恢复墙面，下方继续使用地板，不把陈设底色当墙色。')
            for i,v in enumerate(m['cells']):
                if v&127==15:add(PREFIX+'chest',[i],1.15)
            if any(v&127==15 for v in m['cells']):notes.append('15号原静态箱子补齐完整木箱与锁扣，开箱互动继续由原事件控制。')
            if mid=='2:25':
                grouped(PREFIX+'garment-rack',{31},2.0)
                notes.append('卧室两组挂衣架恢复横杆、立柱和挂衣，保留原箱子位置。')
        if mid in ['2:17','2:18']:
            cells={i for b in rows if b['key'].startswith(('interior-v12:weapon-rack','interior-v12:herb-rack'))and b['y']<=2 for i in b['cells']}
            ground(cells,'wall-plaster')
            notes.append('墙上兵器/药架后方补完整墙面，不再露出地板或异色方块。')
        if mid in ['2:21','2:22','2:26']:
            for b in list(rows):
                if b['key']=='interior-v12:seated-guest':
                    # 凳子与人物分层，凳子直接复用对侧同款长凳，人物原姿态保留。
                    bench={k:copy.deepcopy(v)for k,v in b.items()if k not in ['visualWidth','visualHeight']}
                    bench['key']='furniture:long-bench-'+str(b['height'])
                    rows.insert(rows.index(b),bench)
                    b['key']=PREFIX+'seated-guest-bench';b['visualWidth']=1.7;b['visualHeight']=2.7
            notes.append('保留坐客，将其下方小斜凳换成长直木凳，与桌子另一侧的凳子风格一致。')
        if mid=='3:2':notes.append('迷宫楼梯机关使用精绘石阶和出口暗部，原出口坐标、碰撞及触发规则保留。')
        if not notes:raise AssertionError(('遗漏的审核地图',mid))
        fixes[mid]=notes
    hd['reviewRound3']={'maps':scope['maps'],'approved':scope['approved']}
    for t,page in pages.items():
        # 只保存真正修改的页；图片尺寸保持不变，旧帧占用区域不受新帧覆盖。
        original=Image.open(ART/hd['textures'][t]).convert('RGBA')
        if original.tobytes()!=page.tobytes():page.save(ART/hd['textures'][t],optimize=True)
    for name,value in [('enhanced-art.json',hd),('enhanced-art-sources.json',provenance)]:
        (ART/name).write_text(json.dumps(value,ensure_ascii=False,separators=(',',':')))
    (ROOT/'tool/review_v14_fixes.json').write_text(json.dumps(fixes,ensure_ascii=False,indent=2)+'\n')
    print('Updated',len(scope['maps']),'maps; preserved',len(scope['approved']),'approved entries')


if __name__=='__main__':main()
