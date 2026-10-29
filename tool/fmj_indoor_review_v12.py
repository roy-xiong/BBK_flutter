"""补齐全部室内地图的旧点阵陈设，保留原始地图、碰撞、事件和已完成家具布局。

图块组合来自 DAT.LIB 的原画，不按编号猜测运行时对象。新图放入旧图集的空闲
区域，所有既有帧的坐标和像素保持不变，不增加运行时图片解码预算。
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/fmj/modern'
SOURCES = ROOT / 'tool/art_sources/indoor-v12'
PREFIX = 'interior-v12:'
R = Image.Resampling.LANCZOS


def components(cells, width, height):
    """仅合并同类相邻原图块；跨行索引不能错误地连接房间两侧。"""
    pending = set(cells)
    while pending:
        start = min(pending)
        pending.remove(start)
        found, todo = [], [start]
        while todo:
            i = todo.pop()
            found.append(i)
            x, y = i % width, i // width
            for xx, yy in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
                j = yy * width + xx
                if 0 <= xx < width and 0 <= yy < height and j in pending:
                    pending.remove(j)
                    todo.append(j)
        yield sorted(found)


def main():
    hd = json.loads((ART / 'enhanced-art.json').read_text())
    provenance = json.loads((ART / 'enhanced-art-sources.json').read_text())
    maps = json.loads((ROOT / 'assets/fmj/game/FmjGuideData.json').read_text())['maps']
    pages = {}

    def sprite(key):
        t,x,y,w,h = hd['frames'][key]
        return Image.open(ART / hd['textures'][t]).convert('RGBA').crop((x,y,x+w,y+h))

    def insert(key, image):
        """在实际未引用区域放置带2像素透明边距的新帧，绝不覆盖既有采样区。"""
        fullkey = PREFIX + key + '/0'
        if fullkey in hd['frames']:
            t,x,y,w,h = hd['frames'][fullkey]
            assert image.size == (w,h)
        else:
            chosen = None
            for t,name in enumerate(hd['textures'][:11]):
                page = pages.setdefault(t, Image.open(ART/name).convert('RGBA'))
                mask = Image.new('L', page.size)
                draw = ImageDraw.Draw(mask)
                for frame in hd['frames'].values():
                    if frame[0] != t:
                        continue
                    _,xx,yy,ww,hh = frame
                    draw.rectangle((xx-2,yy-2,xx+ww+1,yy+hh+1),fill=255)
                # 候选只需原帧右侧/下侧边界；候选失败时继续下一张图集。
                xs = {2, *[f[1]+f[3]+4 for f in hd['frames'].values() if f[0]==t]}
                ys = {2, *[f[2]+f[4]+4 for f in hd['frames'].values() if f[0]==t]}
                for yy in sorted(ys):
                    for xx in sorted(xs):
                        if xx+image.width+2>page.width or yy+image.height+2>page.height:
                            continue
                        if mask.crop((xx-2,yy-2,xx+image.width+2,yy+image.height+2)).getbbox() is None:
                            chosen = t,xx,yy
                            break
                    if chosen:
                        break
                if chosen:
                    break
            assert chosen is not None, ('图集空闲空间不足',key)
            t,x,y = chosen
            hd['frames'][fullkey] = [t,x,y,image.width,image.height]
        page = pages.setdefault(t, Image.open(ART/hd['textures'][t]).convert('RGBA'))
        page.paste((0,0,0,0),(x,y,x+image.width,y+image.height))
        page.alpha_composite(image,(x,y))
        provenance['frames'][fullkey] = {'source':'tool/fmj_indoor_review_v12.py','master':'tool/art_sources/indoor-v12/'+key+'.png'}

    sizes = {'sealed-jar':(96,112),'storage-sack':(96,96),'herb-pot':(96,96),
             'pottery-bowl':(96,72),'herb-rack':(128,192),'kitchen-counter':(192,128),
             'vase-stand':(96,160),'weapon-rack':(160,192),'round-stool':(96,96),'bronze-scale':(96,112)}
    for key,size in sizes.items():
        im = Image.open(SOURCES/(key+'.png')).convert('RGBA')
        bounds = im.getchannel('A').point(lambda a:255 if a>16 else 0).getbbox()
        assert bounds, key
        im = im.crop(bounds)
        im.thumbnail((size[0]-4,size[1]-4),R)
        target = Image.new('RGBA',size)
        target.alpha_composite(im,((size[0]-im.width)//2,size[1]-im.height-2))
        insert(key,target)

    # 木柜外沿继续使用现有柜台原画，完整替代7号图块集上残留的旧格栅纹理。
    counter = sprite('furniture:shop-counter/0')
    insert('counter-top',counter.crop((0,0,counter.width,round(counter.height*.4))).resize((128,64),R))
    insert('counter-front',counter.crop((0,round(counter.height*.36),counter.width,counter.height)).resize((128,64),R))
    side = Image.new('RGBA',(64,64),'#826744')
    d = ImageDraw.Draw(side)
    for x in range(0,64,16):
        d.rectangle((x,0,x+13,63),fill='#aa8b5d',outline='#604e37',width=2)
        d.line((x+3,0,x+3,63),fill='#c5ac7c',width=1)
    insert('counter-side',side)

    aliases = {'bookcase':'furniture:bookshelf/0','screen-side':'furniture:screen-side/0',
               'screen-front':'furniture:screen-front/0','cabinet':'furniture:cabinet/0',
               'bench':'furniture:long-bench-3/0','tea-table':'furniture:tea-table/0',
               'window':'furniture:window/0',
               'cave-mouth':'building:cave-mouth/0'}
    for name,source in aliases.items():
        hd['frames'][PREFIX+name+'/0'] = hd['frames'][source]
        provenance['frames'][PREFIX+name+'/0'] = {'alias':source,'details':'复用已绘制完整物件，替换漏配旧图'}

    changed, audit = [], {}
    for m in maps:
        if not m['id'].startswith('2:'):
            continue
        mid,w,h = m['id'],m['width'],m['height']
        rows = hd['decorations'].setdefault(mid,[])
        for b in rows:
            if mid=='2:8' and b['key']==PREFIX+'cave-mouth':
                b['key']='furniture:hidden-passage'
        rows[:] = [b for b in rows if not b['key'].startswith(PREFIX)]
        # 前轮把部分酒坛上半片(50/51)误当作重复人像清空。只有下方确有坛身
        # (52/53)时才撤销该清空规则，不能把真实柜台掌柜的旧头像重新画回来。
        if m['tiles']==7:
            def jar_lid_erased(b):
                cells=b.get('cells',[])
                return b['key']=='furniture:erased-duplicate' and cells and all(
                    (m['cells'][i]&127)in {50,51} and i+w<len(m['cells']) and
                    (m['cells'][i+w]&127)in {52,53} for i in cells)
            rows[:] = [b for b in rows if not jar_lid_erased(b)]
        covered = {i for b in rows for i in b.get('cells',[])}
        count = 0

        def add(name,cells,visual=None):
            nonlocal count
            if not cells:
                return
            xx=min(i%w for i in cells); yy=min(i//w for i in cells)
            width=max(i%w for i in cells)-xx+1; height=max(i//w for i in cells)-yy+1
            item={'key':PREFIX+name,'x':xx,'y':yy,'width':width,'height':height,'cells':cells}
            if visual:
                item['visualHeight']=visual
            rows.append(item)
            covered.update(cells)
            count+=1

        def group(name,tiles,visual=None):
            candidates={i for i,v in enumerate(m['cells']) if (v&127)in tiles and i not in covered}
            for cells in components(candidates,w,h):
                add(name,cells,visual)

        def singles(name,tiles,visual=1.05):
            for i,v in enumerate(m['cells']):
                if v&127 in tiles and i not in covered:
                    add(name,[i],visual)

        if m['tiles']==3:
            group('window',{33,34})
            group('vase-stand',{28,29},2)
            group('bookcase',set(range(49,58)))
            group('screen-side',{58,59,60,61,62,63})
            group('screen-front',set(range(64,72)))
            group('tea-table',set(range(79,84)))
            group('screen-side',{84,85,86,87,88})
            # 厨房先识别完整的三格案台，再识别上方的竖向碗架，避免连成巨大杂物块。
            group('kitchen-counter',set(range(108,114)))
            group('herb-rack',{118,119,120,121})
            group('pottery-bowl',{104,105,106,107})
            group('pottery-bowl',{114,115,116,117})
            singles('pottery-bowl',{122})
            singles('herb-pot',{99})
            group('storage-sack',{124,125,126})
            # 分隔墙/柜脚的结构片保留原占地，统一为完整木柱表面。
            rules=hd.setdefault('tileOverrides',{}).setdefault(mid,{})
            for tile in [63,72]:
                if any(v&127==tile for v in m['cells']):
                    rules[str(tile)]=['wood-cross','wood-panel',PREFIX+'counter-side/0']
        elif m['tiles']==7:
            group('herb-rack',{10,11,14,15,34,35})
            group('sealed-jar',{50,51,52,53},2)
            group('bronze-scale',{54,55},1.7)
            group('weapon-rack'if mid=='2:17'else'herb-rack',set(range(37,39))|{40,41,42,43,44,45,46,47,48,49})
            # 81/82/83是客栈楼梯，沿用已绘制的台阶，不能套成长凳。
            group('bench',{79,80})
            singles('storage-sack',{16,56})
            singles('sealed-jar',{17,57})
            singles('pottery-bowl',{22,23})
            singles('round-stool',{39,58,59,61})
            group('cabinet',{18,19,20,21,64,65})
            rules=hd.setdefault('tileOverrides',{}).setdefault(mid,{})
            for tile,name in {2:'counter-top',3:'counter-top',4:'counter-front',5:'counter-side',36:'counter-top'}.items():
                if any(v&127==tile for v in m['cells']):
                    rules[str(tile)]=['indoor-stone','wood-counter',PREFIX+name+'/0']
        if mid=='2:8':
            # 隐藏洞口继续只出现在剧情揭开后的地图；沿用相同入口格和下沿。
            passage=next((b for b in rows if b['key']=='furniture:hidden-passage'),None)
            if passage:
                hd['frames']['furniture:hidden-passage/0']=hd['frames']['building:cave-mouth/0']
                provenance['frames']['furniture:hidden-passage/0']={'alias':'building:cave-mouth/0','details':'用户要求隐藏入口使用完整岩石山洞造型'}
                count+=1
        # 这些柜体切片已由原有高清木柜绘制，属于保留项；其余物件必须有完整接管。
        existing_cabinets={3:{89,90},5:{31,32},7:{8,9}}.get(m['tiles'],set())
        rules=hd.get('tileOverrides',{}).get(mid,{})
        if not rules:
            hd.get('tileOverrides',{}).pop(mid,None)
        audit[mid]={'newObjects':count,'remainingPropTiles':sorted({v&127 for i,v in enumerate(m['cells']) if i not in covered and (v&127)not in existing_cabinets and str(v&127)not in rules and hd['tileCatalog'][str(m['tiles'])][v&127][1] in ['wood-object','household']})}
        if count or hd.get('tileOverrides',{}).get(mid):
            changed.append(mid)
    hd['interiorReviewV12']={'maps':changed,'auditedMaps':[m['id']for m in maps if m['id'].startswith('2:')],'audit':audit}
    for t,page in pages.items():
        page.save(ART/hd['textures'][t],optimize=True)
    for name,value in [('enhanced-art.json',hd),('enhanced-art-sources.json',provenance)]:
        (ART/name).write_text(json.dumps(value,ensure_ascii=False,separators=(',',':')))
    labels={'sealed-jar':'封口陶坛','storage-sack':'麻布储物袋','herb-pot':'带盖药罐','pottery-bowl':'陶制碗盆','herb-rack':'器物储存架','kitchen-counter':'厨房案台','vase-stand':'花瓶与木花几','weapon-rack':'兵器陈列架','round-stool':'竹面木凳','bronze-scale':'铜制药秤','bookcase':'书架','screen-side':'纵向木屏风','screen-front':'横向木屏风','tea-table':'木茶案','cabinet':'储物柜','bench':'木长凳','window':'木格纸窗'}
    fixes={}
    for mid in changed:
        names=sorted({labels.get(b['key'][len(PREFIX):],b['key'][len(PREFIX):])for b in hd['decorations'][mid]if b['key'].startswith(PREFIX)})
        notes=[]
        if names:notes.append('补齐本场景残留旧图：'+'、'.join(names)+'。')
        if hd.get('tileOverrides',{}).get(mid):notes.append('补绘柜台侧板、面板与木作边沿，去除原点阵格栅和碎片。')
        notes.append('原地图、碰撞、交互格及已有家具布局保留。')
        fixes[mid]=notes
    fixes['2:8']=['揭开后的隐藏入口改用与其他洞口一致的完整岩石洞口，保留原入口和剧情显隐规则。']
    (ROOT/'tool/indoor_review_v12_fixes.json').write_text(json.dumps(fixes,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'audited':len(audit),'changed':len(changed),'objects':sum(a['newObjects']for a in audit.values()),'audit':audit},ensure_ascii=False))


if __name__=='__main__':
    main()
