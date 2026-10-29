"""全量检查后的续审：继承原批注，重新列入明确报错的水池，并增加实际开场帧。"""
from pathlib import Path
from collections import Counter
import argparse,copy,json,subprocess
from PIL import Image,ImageDraw,ImageFont
from continue_fmj_review import payload
from build_fmj_review import encoded

ROOT=Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser()
    for option in ['previous','patch','frames','output']:parser.add_argument('--'+option,type=Path,required=True)
    args=parser.parse_args();old=payload(args.previous);patch=json.loads(args.patch.read_text())
    replacement={e['id']:e for e in patch['entries']}
    archive=copy.deepcopy(old['approvedReviews']);reviews=copy.deepcopy(old['initialReviews']);entries=[]
    revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    for entry in old['entries']:
        key=entry['id'];review=reviews[key]
        if review['status']=='通过':archive[key]=review;continue
        if key in replacement:
            fresh=copy.deepcopy(replacement[key]);assert fresh['cells']==entry['cells']
            assert(fresh['width'],fresh['height'])==(entry['width'],entry['height'])
            entry=fresh;review['status']='待复审'
        else:entry=copy.deepcopy(entry)
        review['documentRevision']=revision;entries.append(entry)
    # 三清宫此前通过，但用户在本轮明确指出池内仍有低清片，重新列为待复审。
    pool=copy.deepcopy(replacement['1:1']);review=archive.pop('1:1')
    review['status']='待复审';review['documentRevision']=revision;reviews['1:1']=review;entries.insert(0,pool)
    art=ROOT/'assets/fmj/modern';hd=json.loads((art/'enhanced-art.json').read_text())
    # 让文档也同步此前用户指定的旧地图四方向、新战斗攻击组合。
    hero=next(e for e in entries if e['id']=='hero:liuqingfeng')
    canvas=Image.new('RGBA',(hero['width'],hero['height']),'#193136');d=ImageDraw.Draw(canvas)
    font_path=Path('/System/Library/Fonts/STHeiti Medium.ttc')
    font=ImageFont.truetype(str(font_path),18)if font_path.exists()else ImageFont.load_default()
    keys=['world:hero:1:3/0','world:hero:1:1/0','world:hero:1:4/0','world:hero:1:2/0','battle:hero:1/3']
    labels=['正面（旧版）','背面（旧版）','左侧（旧版）','右侧（旧版）','攻击（新版）']
    for i,(key,label)in enumerate(zip(keys,labels)):
        t,x,y,w,h=hd['frames'][key]
        with Image.open(art/hd['textures'][t])as page:im=page.convert('RGBA').crop((x,y,x+w,y+h))
        im=im.crop(im.getchannel('A').getbbox());im.thumbnail((180,330),Image.Resampling.LANCZOS)
        canvas.alpha_composite(im,(i*200+(200-im.width)//2,370-im.height));d.text((i*200+12,374),label,font=font,fill='#e5d0a5')
    hero['image']=encoded(canvas);hero['name']='柳清风 · 旧版地图形象与新版攻击'
    hero['revisionSummary']=['同步此前指定的旧地图四方向和新版攻击动作，本轮没有重画柳清风形象。']
    reviews[hero['id']]['status']='待复审'
    for index in range(3):
        path=args.frames/f'opening-{index}.png'
        with Image.open(path)as im:
            key=f'effect:opening-{index}'
            entries.append({'id':key,'name':f'重制开场追蝶 · 关键帧{index+1}','kind':'人物/动效','width':im.width,'height':im.height,'tileSize':0,'image':encoded(im),'revisionSummary':['来自正式Flutter绘制器，原SRS时序与剧情不变；角色和蝴蝶采用彩绘图像，不放大旧黑白轮廓。']})
        reviews[key]={'status':'待复审','comment':'','markers':[],'documentRevision':revision}
    active={e['id']for e in entries};reviews={k:v for k,v in reviews.items()if k in active}
    for key,r in reviews.items():
        before=old['initialReviews'].get(key)or old['approvedReviews'].get(key)
        if before:assert r['comment']==before['comment']and r['markers']==before['markers']
    data={'revision':revision,'renderRevision':patch['revision'],'date':'2026-10-29','entries':entries,'initialReviews':reviews,'approvedReviews':archive,'mapCount':sum(bool(e['tileSize'])for e in entries),'totalCatalogCount':len(entries)+len(archive),'reviewRoundLabel':'全量美术与开场修订 · 三清宫水池重新待复审','exportFilename':'伏魔记-全地图审核意见-续审4-20261029.json'}
    template=(ROOT/'tool/fmj_review_template.html').read_text();script=json.dumps(data,ensure_ascii=False,separators=(',',':')).replace('</','<\\/')
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(template.replace('/*__REVIEW_DATA__*/','const DATA='+script+';'))
    manifest={'revision':revision,'renderRevision':patch['revision'],'updatedMaps':len(replacement),'openingSamples':3,'approvedHidden':len(archive),'visibleEntries':len(entries),'statuses':dict(Counter(r['status']for r in reviews.values()))}
    args.output.with_suffix('.manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');print(json.dumps(manifest,ensure_ascii=False))


if __name__=='__main__':main()
