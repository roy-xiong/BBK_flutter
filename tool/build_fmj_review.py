"""把正式Flutter导出的全部地图、地表材质和修订图打成单文件离线审核网页。"""
from pathlib import Path
import argparse,base64,io,json,subprocess
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'assets/fmj/modern'


def encoded(im):
    # 保留48像素/格的全图尺寸，JPEG只压缩颜色，不缩小坐标或丢失可点击位置。
    background=Image.new('RGB',im.size,'#183033')
    if im.mode=='RGBA':background.paste(im,mask=im.getchannel('A'))
    else:background.paste(im)
    buf=io.BytesIO();background.save(buf,'JPEG',quality=88,optimize=True)
    return 'data:image/jpeg;base64,'+base64.b64encode(buf.getvalue()).decode()


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--input',type=Path,default=ROOT/'build/validation/approved-art');parser.add_argument('--output',type=Path,default=ROOT/'build/validation/review/伏魔记全地图交互审核-20261029.html');parser.add_argument('--patch',action='store_true');args=parser.parse_args()
    guide=json.loads((ROOT/'assets/fmj/game/FmjGuideData.json').read_text());hd=json.loads((ART/'enhanced-art.json').read_text());entries=[]
    scripts={s['id']:s for s in guide['scripts']};aliases={}
    for script in guide['scripts']:
        commands=script['commands']
        for i,c in enumerate(commands):
            if c['op']!=1:continue
            target=f"{c['a'][0]}:{c['a'][1]}"
            for following in commands[i+1:i+4]:
                if following['op']==14:
                    sid=f"{following['a'][0]}:{following['a'][1]}"
                    if sid in scripts:aliases.setdefault(target,set()).add(scripts[sid]['name'].replace('李俯','李府'))
                    break
    aliases.setdefault('1:37',set()).add('李府');aliases.setdefault('2:20',set()).add('李府客厅')

    fixes_path=ROOT/'tool/partial_review_v11_fixes.json'
    fixes=json.loads(fixes_path.read_text())if fixes_path.exists()else {}
    interior=hd.get('interiorReviewV12')
    if interior:
        fixes=json.loads((ROOT/'tool/indoor_review_v12_fixes.json').read_text())
    third=hd.get('reviewRound3')
    if third:
        fixes=json.loads((ROOT/'tool/review_v14_fixes.json').read_text())
    revised=set((third or interior or hd.get('partialReviewV11',{})).get('maps',[]))
    sweep=hd.get('artSweepV15')
    if sweep:
        revised=set(sweep.get('reviewMaps',sweep['maps']))
        fixes=json.loads((ROOT/'tool/art_sweep_v15_fixes.json').read_text())
    for m in guide['maps']:
        if args.patch and m['id']not in revised:continue
        path=args.input/('map-'+m['id'].replace(':','-')+'.png')
        with Image.open(path)as im:
            assert im.size==(m['width']*48,m['height']*48),(m['id'],im.size)
            entry={'id':m['id'],'name':m['name'],'kind':'道路/室外'if m['id'].startswith('1:')else'室内/洞府','width':im.width,'height':im.height,'tileSize':48,'mapWidth':m['width'],'mapHeight':m['height'],'tileset':m['tiles'],'cells':m['cells'],'image':encoded(im)}
        if m['id']in fixes:entry['revisionSummary']=fixes[m['id']]
        entry['aliases']=sorted(aliases.get(m['id'],set()))
        entry['road']=any(s in m['name']for s in ['路','阡','原野','小径','入口','山道'])
        entries.append(entry)
    if args.patch:
        assert len(entries)==len(revised)>0
        revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps({'revision':revision,'entries':entries},ensure_ascii=False,separators=(',',':')))
        print('Updated-map patch:',len(entries),'maps, bytes',args.output.stat().st_size)
        return
    labels={'wood':'木地板','wood-cross':'横向木板','cave':'洞窟地面','cave-wall':'洞窟墙壁','rock-ground':'岩石地面','wood-post':'木柱','wall-plaster':'灰泥墙面','abyss':'深渊','earth':'泥土地','grass':'草地','stone':'石路','city-stone':'城镇石地','brick-road':'砖道','indoor-stone':'室内石地','hall-floor':'殿堂地砖','hall-wall':'殿堂墙面','mountain-wall':'山洞山壁','water':'水面','bamboo-forest':'竹林'}
    materials={**hd['groundTextures']}
    for key,value in materials.items():
        with Image.open(ART/value)as im:
            entries.append({'id':'material:'+key,'name':labels.get(key,key),'kind':'地表材质','width':im.width,'height':im.height,'tileSize':0,'image':encoded(im),'source':value})
    # 原画切片直接从实际图集取出，审核看到的形象与游戏使用的帧一致。
    frame_keys=[('柳清风正面','world:hero:1:3/0'),('柳清风背面','world:hero:1:1/0'),('柳清风左侧','world:hero:1:4/0'),('柳清风右侧','world:hero:1:2/0'),('柳清风战斗','battle:hero:1/0')]
    canvas=Image.new('RGBA',(1000,400),'#193136')
    for i,(label,key)in enumerate(frame_keys):
        t,x,y,w,h=hd['frames'][key]
        with Image.open(ART/hd['textures'][t])as page:im=page.convert('RGBA').crop((x,y,x+w,y+h))
        im=im.resize((round(im.width*2.3),round(im.height*2.3)),Image.Resampling.LANCZOS)
        im.thumbnail((180,350),Image.Resampling.LANCZOS);canvas.alpha_composite(im,(i*200+(200-im.width)//2,370-im.height))
    entries.append({'id':'hero:liuqingfeng','name':'柳清风 · 四方向与战斗比例','kind':'人物/动效','width':canvas.width,'height':canvas.height,'tileSize':0,'image':encoded(canvas)})
    fall=ROOT/'build/validation/review-v23'
    for frame_index,path in enumerate(sorted(fall.glob('fall-*.png')),1):
        with Image.open(path)as im:
            entries.append({'id':'effect:'+path.stem,'name':'取伏魔剑后的落石 · 画面'+str(frame_index),'kind':'人物/动效','width':im.width,'height':im.height,'tileSize':0,'image':encoded(im)})
    revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    data=json.dumps({'revision':revision,'date':'2026-10-29','mapCount':len(guide['maps']),'entries':entries},ensure_ascii=False,separators=(',',':')).replace('</','<\\/')
    template=(ROOT/'tool/fmj_review_template.html').read_text()
    html=template.replace('/*__REVIEW_DATA__*/', 'const DATA='+data+';')
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(html)
    (args.output.parent/'manifest.json').write_text(json.dumps({'revision':revision,'maps':len(guide['maps']),'materials':len(materials),'entries':len(entries),'bytes':len(html.encode())},ensure_ascii=False,indent=2)+'\n')
    print('Review created:',args.output,'maps',len(guide['maps']),'entries',len(entries),'MiB',round(len(html.encode())/1024/1024,2))


if __name__=='__main__':main()
