"""撤回未逐项审核的全量结构重绘，仅保留用户单独提出的定向修改。

素材以1.0.27+28提交为基线。图集10只做无损装箱以容纳已认可的开场背景，
每个既有帧逐像素验证相同；不重新生成墙、柱、花草等任何结构图像。
"""
from pathlib import Path
import copy,hashlib,io,json,subprocess
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'assets/fmj/modern'
BASE='8a930a02a6aef5c1e07724a3908da7b8f6cc57ee'

def baseline(name):
    return subprocess.check_output(['git','show',f'{BASE}:assets/fmj/modern/{name}'],cwd=ROOT)

def main():
    current=json.loads((ART/'enhanced-art.json').read_text())
    t,x,y,w,h=current['frames']['opening:butterfly/0']
    with Image.open(ART/current['textures'][t])as page:butterfly=page.convert('RGBA').crop((x,y,x+w,y+h))
    hd=json.loads(baseline('enhanced-art.json'));source=json.loads(baseline('enhanced-art-sources.json'))
    original=copy.deepcopy(hd)
    for filename in hd['textures']:(ART/filename).write_bytes(baseline(filename))
    # 只重新装箱，不改变像素；保存每个基线帧的摘要供范围核对。
    with Image.open(ART/hd['textures'][10])as page:old=page.convert('RGBA')
    items={}
    for key,(t,x,y,w,h)in hd['frames'].items():
        if t!=10:continue
        im=old.crop((x,y,x+w,y+h));identity=(w,h,hashlib.sha256(im.tobytes()).hexdigest())
        items.setdefault(identity,{'image':im,'keys':[]})['keys'].append(key)
    page=Image.new('RGBA',(2048,2048));x=y=rowh=0
    for item in sorted(items.values(),key=lambda item:-item['image'].height):
        im=item['image']
        if x+im.width+4>2048:x=0;y+=rowh+4;rowh=0
        assert y+im.height+4<=2048
        page.paste(im,(x+2,y+2))
        for key in item['keys']:hd['frames'][key]=[10,x+2,y+2,im.width,im.height]
        x+=im.width+4;rowh=max(rowh,im.height)
    page.crop((0,0,2048,y+rowh+4)).save(ART/hd['textures'][10],optimize=True)
    butterfly_name='opening-butterfly-v15.png';butterfly.save(ART/butterfly_name,optimize=True)
    hd['frames']['opening:butterfly/0']=[len(hd['textures']),0,0,butterfly.width,butterfly.height]
    hd['textures'].append(butterfly_name)
    hd['backgrounds']['opening']=current['backgrounds']['opening']
    source['frames']['opening:butterfly/0']={'source':'tool/art_sources/art-sweep-v15/butterfly.png'}
    exceptions={}
    for tile in range(94,102):
        key=f'structure:1:{tile}/0';hd['frames'][key]=hd['frames']['review-v11:lotus/0']
        source['frames'][key]={'alias':'review-v11:lotus/0','source':'user-directed pond lotus replacement'}
        exceptions[key]='review-v11:lotus/0'
    for rows in hd['decorations'].values():
        for decoration in rows:
            if decoration['key']in['interior-v12:seated-guest','review-v14:seated-guest-bench']:
                decoration['visualHeight']=1.4;decoration['visualWidth']=1.1
    hd['targetedArtV15']={'baseline':BASE,'globalSweepReverted':True,'structureExceptions':exceptions,'openingMovies':['1:2','1:3']}
    # 对所有既有图像逐像素核对，只有明确要求的8个睡莲别名允许不同。
    originals={};pages={};hashes={}
    for key,f in original['frames'].items():
        if key in exceptions:continue
        t,x,y,w,h=f
        if t not in originals:originals[t]=Image.open(io.BytesIO(baseline(original['textures'][t]))).convert('RGBA')
        wanted=originals[t].crop((x,y,x+w,y+h)).tobytes()
        t,x,y,w,h=hd['frames'][key]
        if t not in pages:pages[t]=Image.open(ART/hd['textures'][t]).convert('RGBA')
        actual=pages[t].crop((x,y,x+w,y+h)).tobytes()
        assert wanted==actual,key
        hashes[key]=hashlib.sha256(actual).hexdigest()
    for field in ['buildings','tileOverrides','groundOverrides','rooms']:
        assert hd.get(field)==original.get(field),field
    for mid,rows in hd['decorations'].items():
        for b,old_b in zip(rows,original['decorations'][mid]):
            expected=copy.deepcopy(old_b)
            if b['key']in['interior-v12:seated-guest','review-v14:seated-guest-bench']:expected.update(visualHeight=1.4,visualWidth=1.1)
            assert b==expected,(mid,b['key'])
    for name,value in [('enhanced-art.json',hd),('enhanced-art-sources.json',source)]:
        (ART/name).write_text(json.dumps(value,ensure_ascii=False,separators=(',',':')))
    names=[*hd['textures'],*hd['backgrounds'].values(),*hd['groundTextures'].values(),'world-atlas.png','battle-landscape.png']
    decoded=sum(Image.open(ART/name).width*Image.open(ART/name).height*4 for name in names)
    assert decoded<256*1024*1024,decoded
    manifest={'baseline':BASE,'unchangedFrameCount':len(hashes),'structureExceptions':exceptions,'decodedImageBytes':decoded,'frameSha256':hashes}
    folder=ROOT/'tool/art_sources/art-rollback-v16';folder.mkdir(parents=True,exist_ok=True)
    (folder/'baseline-verification.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in manifest.items()if k!='frameSha256'},ensure_ascii=False))

if __name__=='__main__':main()
