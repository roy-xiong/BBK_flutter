"""把逐张核对的手绘原稿转成正式图集；只做离线抠图、分色、裁剪与固定矩阵合成。"""
from pathlib import Path
import argparse,hashlib,json,math,random
import cv2
import numpy as np
from PIL import Image,ImageChops,ImageDraw,ImageFilter,ImageOps
from handpainted_matting import cutout
from portrait_assets import build_portraits
from native_matrix_land import export_mask,grid_positions

ROOT=Path(__file__).resolve().parents[2]
POSES=['idle','stride','windup','attack','hit','down']


def standalone(path,interior=False):
    image=cutout(Image.open(path),interior_holes=interior)
    alpha=np.asarray(image.getchannel('A'))
    n,labels,stats,_=cv2.connectedComponentsWithStats((alpha>20).astype(np.uint8),8)
    if n<2:raise ValueError('素材没有实体：'+str(path))
    maximum=max(stats[1:,4]);valid=[]
    for i in range(1,n):
        x,y,w,h,area=stats[i]
        if area<max(18,maximum*.0008):continue
        if (w<4 and h>image.height*.7) or (h<4 and w>image.width*.7):continue
        valid.append(i)
    selected=np.isin(labels,valid);alpha=np.where(selected,alpha,0).astype(np.uint8)
    image.putalpha(Image.fromarray(alpha));box=image.getbbox()
    if box is None:raise ValueError('抠图后为空：'+str(path))
    image=image.crop(box)
    if path.name.startswith('icon-'):
        # 天气与粮袋图案本身不含绿色；将白雾边缘混入的幕色中和，保留柔软透明边。
        a=np.asarray(image).copy();a[...,1]=np.minimum(a[...,1],np.maximum(a[...,0],a[...,2]));image=Image.fromarray(a,'RGBA')
    return image


def sheet(path,columns=3,rows=2):
    """按原稿等分格提取完整对象；接触相邻格边界时拒绝静默裁去兵器。"""
    image=Image.open(path);w,h=image.size
    if w%columns or h%rows:raise ValueError('原稿尺寸不能整分')
    frames=[]
    for row in range(rows):
        for col in range(columns):
            cell=image.crop((col*w//columns,row*h//rows,(col+1)*w//columns,(row+1)*h//rows))
            rgba=cutout(cell);alpha=np.asarray(rgba.getchannel('A')).copy()
            if path.name=='effects-sheet.png':
                # 此六种特效不含绿色实体；删除生成器把绿幕混进光晕的闭合孔洞及边缘。
                # 不用于树林、角色或材质，避免把正常绿色植被误当作背景。
                rgb=np.asarray(rgba)[...,:3].astype(float)
                spill=(rgb[...,1]>rgb[...,0]*1.12)&(rgb[...,1]>rgb[...,2]*1.12)
                alpha[spill]=0
            n,labels,stats,_=cv2.connectedComponentsWithStats((alpha>25).astype(np.uint8),8)
            if n<2:raise ValueError(f'{path.name}第{len(frames)+1}格为空')
            maximum=max(stats[1:,4]);components=[]
            for i in range(1,n):
                x,y,cw,ch,area=stats[i]
                if area<max(24,maximum*.001):continue
                if (cw<=5 and ch>cell.height*.7) or (ch<=5 and cw>cell.width*.7):continue
                components.append(i)
            rgba.putalpha(Image.fromarray(np.where(np.isin(labels,components),alpha,0).astype(np.uint8)))
            bounds=rgba.getbbox()
            if bounds is None or min(bounds[2]-bounds[0],bounds[3]-bounds[1])<28:raise ValueError('原稿对象不完整')
            if bounds[0]<2 or bounds[1]<2 or bounds[2]>cell.width-2 or bounds[3]>cell.height-2:
                raise ValueError(f'{path.name}第{len(frames)+1}格接触边缘，需检查是否裁断')
            frames.append(rgba.crop(bounds))
    return frames


def normalize_sequence(frames,size=192):
    """同一角色使用同一缩放比例和脚下位置，攻击、受击不按单帧重新放大。"""
    max_width=max(im.width for im in frames);max_height=max(im.height for im in frames)
    ratio=min((size-8)/max_width,(size-8)/max_height,1)
    result=[]
    for image in frames:
        image=image.resize((max(1,round(image.width*ratio)),max(1,round(image.height*ratio))),Image.Resampling.LANCZOS)
        canvas=Image.new('RGBA',(size,size));canvas.alpha_composite(image,((size-image.width)//2,size-image.height-4));result.append(canvas)
    first_height=frames[0].height*ratio
    anchor=[.5,(size-4)/size,round(17*size/max(1,first_height),6)]
    return result,anchor


def walking_pose(image,kind):
    """复用本人原稿的脚步/船体轻摆；上半身、脸和兵器不使用另一人的图替换。

    动画仍由原播放器交替 idle/stride。这里只离线移动衣摆、双脚或船身的像素，
    不改变运行时位置、朝向、步长和计时，也不将此派生图冒充模型独立生成的姿态。
    """
    a=np.asarray(image);height,width=a.shape[:2]
    yy,xx=np.mgrid[:height,:width].astype(np.float32)
    lower=np.clip((yy/height-.56)/.44,0,1)
    shift=(np.sin(xx/width*math.pi*2)*width*.016*lower)
    if kind==3:shift=np.sin(yy/height*math.pi)*width*.009
    return Image.fromarray(cv2.remap(a,xx-shift,yy,cv2.INTER_CUBIC,borderMode=cv2.BORDER_CONSTANT))


def clean_victory(path):
    """去掉旗面不成字的金色生成痕迹；原生标题由 Flutter 系统字体绘制。

    遮罩严格限制在这一张1280×768原稿的旗面内部，城墙、旗边、阴影均不参与。
    原始图与生成记录仍保留，处理方式进入最终素材来源清单。
    """
    rgb=np.asarray(Image.open(path).convert('RGB'))
    if rgb.shape[:2]!=(768,1280):raise ValueError('胜利原稿尺寸变化，需要重新检查旗面遮罩')
    polygon=np.zeros(rgb.shape[:2],np.uint8)
    cv2.fillPoly(polygon,[np.array([(931,238),(956,233),(956,284),(930,288)],np.int32)],255)
    hsv=cv2.cvtColor(rgb.astype(np.float32)/255,cv2.COLOR_RGB2HSV)
    gold=((hsv[...,0]>24)&(hsv[...,0]<75)&(hsv[...,1]>.25)&(hsv[...,2]>.42)).astype(np.uint8)*255
    mask=cv2.bitwise_and(cv2.dilate(gold,np.ones((3,3),np.uint8)),polygon)
    return Image.fromarray(cv2.inpaint(rgb,mask,4,cv2.INPAINT_TELEA)).convert('RGBA')


def team(image,enemy=False):
    """仅将红色衣甲、披风和船帆转为青色，肤色、木材、银刃与铜饰保持原稿。"""
    if not enemy:return image.copy()
    rgba=np.asarray(image).copy();rgb=rgba[...,:3].astype(np.float32)/255
    hsv=cv2.cvtColor(rgb,cv2.COLOR_RGB2HSV)
    hue,saturation,value=hsv[...,0],hsv[...,1],hsv[...,2]
    selected=(((hue<16)|(hue>342))&(saturation>.27)&(value>.09)&(rgba[...,3]>0))
    hsv[...,0]=np.where(selected,185,hue)
    hsv[...,1]=np.where(selected,np.minimum(1,saturation*.96),saturation)
    converted=cv2.cvtColor(hsv,cv2.COLOR_HSV2RGB)
    rgba[...,:3]=np.where(selected[...,None],np.clip(converted*255,0,255),rgba[...,:3]).astype(np.uint8)
    return Image.fromarray(rgba,'RGBA')


def fitted(image,size):
    image=ImageOps.contain(image,(size[0]-6,size[1]-6),Image.Resampling.LANCZOS)
    result=Image.new('RGBA',size);result.alpha_composite(image,((size[0]-image.width)//2,size[1]-image.height-3));return result


def seamless(path,size):
    im=Image.open(path).convert('RGB');result=Image.new('RGB',(im.width*2,im.height*2))
    for image,at in [(im,(0,0)),(ImageOps.mirror(im),(im.width,0)),(ImageOps.flip(im),(0,im.height)),(ImageOps.flip(ImageOps.mirror(im)),(im.width,im.height))]:result.paste(image,at)
    result=result.resize(size,Image.Resampling.LANCZOS)
    if path.name.startswith('ground-water'):
        # 降低水面焦散的高频对比，避免在小战场上像网格，也让青色部队更易辨认。
        average=tuple(int(v) for v in np.asarray(im).mean(axis=(0,1)))
        result=Image.blend(result,Image.new('RGB',size,average),.35)
    return result


def strategy_map(root,out,review):
    """原矩阵陆地遮罩拥有海岸；生成的画风不参与城市坐标、道路或寻路。"""
    mask=export_mask(ROOT,review/'original_matrix_mask.png')
    land=Image.open(root/'generated/strategy-land.png').convert('RGB')
    land=land.crop((40,40,land.width-40,land.height-40)).resize(mask.size,Image.Resampling.LANCZOS)
    selection=json.loads((root/'selection.json').read_text())
    water=seamless(root/'generated'/(selection['grounds']['water']+'.png'),mask.size)
    outer=ImageChops.subtract(mask.filter(ImageFilter.MaxFilter(15)),mask)
    water.paste((166,183,161),(0,0,mask.width,mask.height),outer.filter(ImageFilter.GaussianBlur(1.2)))
    result=Image.composite(land,water,mask.filter(ImageFilter.GaussianBlur(.65))).convert('RGBA')
    # 两条绘画河流沿矩阵城池之间的空隙连续流动，禁止用大块地基把河水截断。
    # 只改变背景像素：原城池矩阵、道路、点击与寻路数据都不参与本导出函数。
    rivers=Image.new('RGBA',mask.size);draw=ImageDraw.Draw(rivers)
    for controls in [[(19,27),(32,35),(48,46),(69,46),(84,49),(96,58),(108,50),(117,46),(143,45.5),(160,46),(178,46)],[(24,78),(45,77.5),(62,78),(77,88),(93,94),(112,94),(127,94),(135,101),(144,94),(157,94),(176,94)]]:
        extended=[controls[0],*controls,controls[-1]];points=[]
        for i in range(1,len(extended)-2):
            a,b,c,d=extended[i-1:i+3]
            for step in range(32):
                t=step/32
                points.append(tuple(.5*((2*b[k])+(-a[k]+c[k])*t+(2*a[k]-5*b[k]+4*c[k]-d[k])*t*t+(-a[k]+3*b[k]-3*c[k]+d[k])*t*t*t)*(mask.width/192 if k==0 else mask.height/144) for k in (0,1)))
        for x,y in grid_positions(ROOT):
            if any(x*16+2.2<px/mask.width*192<x*16+13.8 and y*16+.2<py/mask.height*144<y*16+10.8 for px,py in points):
                raise ValueError(f'背景河道碰到原矩阵城池图标：{x},{y}')
        draw.line(points,fill=(134,153,122,160),width=13,joint='curve');draw.line(points,fill=(94,137,145,255),width=7,joint='curve')
    rivers.putalpha(ImageChops.multiply(rivers.getchannel('A'),mask))
    result.alpha_composite(rivers)
    result.convert('RGB').save(out/'strategy_map.png',optimize=True)
    return mask


def pack(root,out):
    out.mkdir(parents=True,exist_ok=True);review=root/'review';review.mkdir(exist_ok=True)
    jobs=json.loads((root/'requests.json').read_text());selection=json.loads((root/'selection.json').read_text())
    originals=root/'generated';sprites={};aliases={};origins={};anchors={};checks={}
    required=[source for poses in selection['singleActions'].values() for source in poses.values()]
    required+=[source for frames in selection['singleDefeat'].values() for source in frames]
    required+=list(selection['cities'].values())+list(selection['terrains'].values())+list(selection['icons'].values())+['scene-'+n for n in ['field','river','forest','siege','victory','defeat']]+list(selection['grounds'].values())+['ui-paper','effects-sheet','strategy-land']
    required+=list(selection['skillEffects'].values())
    required+=list(selection.get('battleUnits',{}).values())
    if selection.get('battleCity'):required.append(selection['battleCity'])
    missing=[name for name in required if not (originals/(name+'.png')).exists()]
    if missing:raise ValueError('完整原稿缺失：'+','.join(missing))
    for kind in range(6):
        action_sources=selection['singleActions'][str(kind)];death_sources=selection['singleDefeat'][str(kind)]
        original_poses=[standalone(originals/(action_sources[pose]+'.png'),True) for pose in POSES]
        original_poses[1]=walking_pose(original_poses[0],kind)
        mirrored_poses=selection.get('facingCorrections',{}).get('normal',{}).get(str(kind),[])
        original_poses=[ImageOps.mirror(image) if pose in mirrored_poses else image for pose,image in zip(POSES,original_poses)]
        poses,anchor=normalize_sequence(original_poses,192)
        # 四个独立姿态跨原有六时隙：受击、跪倒、侧倒、接地；首尾保留短暂停留。
        death_sources_images=[standalone(originals/(name+'.png'),True) for name in death_sources]
        mirrored_death=str(kind) in selection.get('facingCorrections',{}).get('defeat',[])
        if mirrored_death:death_sources_images=[ImageOps.mirror(image) for image in death_sources_images]
        death,death_anchor=normalize_sequence(death_sources_images,128)
        checks[kind]={'poses':[hashlib.sha256(im.tobytes()).hexdigest() for im in poses],'defeat':[hashlib.sha256(im.tobytes()).hexdigest() for im in death]}
        for side in ['friendly','enemy']:
            base=f'unit/{side}/{kind}'
            for name,image in zip(POSES,poses):
                sprites[base+'/'+name]=team(image,side=='enemy');origins[base+'/'+name]={'source':action_sources[name]+'.png','pose':name,'team':side}
                if name=='stride':origins[base+'/'+name]['derived']='subtle lower-body cloth/footstep mesh; original movement clock'
                if name in mirrored_poses:origins[base+'/'+name]['sourceMirror']=True
            aliases[base]=base+'/idle';anchors[f'{side}/{kind}']=death_anchor
            for frame,image in enumerate(death):
                key=f'defeat/{side}/{kind}/{frame}';sprites[key]=team(image,side=='enemy');origins[key]={'source':death_sources[frame]+'.png','frame':frame,'team':side,'hold':frame in [1,5]}
                if mirrored_death:origins[key]['sourceMirror']=True
    for name,source in selection['cities'].items():
        key='city/'+name;sprites[key]=fitted(standalone(originals/(source+'.png'),True),(224,192));origins[key]={'source':source+'.png'}
    for kind,source in selection.get('battleUnits',{}).items():
        base=standalone(originals/(source+'.png'),True)
        frames,_=normalize_sequence([base,walking_pose(base,int(kind))],128)
        for side in ['friendly','enemy']:
            for pose,image in zip(['idle','stride'],frames):
                key=f'unit/{side}/{kind}/field_{pose}';sprites[key]=team(image,side=='enemy');origins[key]={'source':source+'.png','pose':pose,'team':side,'usage':'battlefield silhouette; same costume with emphasized equipment'}
    if selection.get('battleCity'):
        source=selection['battleCity'];sprites['city/battle']=fitted(standalone(originals/(source+'.png'),True),(192,192));origins['city/battle']={'source':source+'.png'}
    for name in ['mountain','tree','village','camp']:
        source=selection['terrains'][name];key='terrain/'+name;sprites[key]=fitted(standalone(originals/(source+'.png'),True),(192,192));origins[key]={'source':source+'.png'}
    for name,source in selection['icons'].items():
        key='icon/'+name;sprites[key]=fitted(standalone(originals/(source+'.png'),True),(96,96));origins[key]={'source':source+'.png','transform':'chroma matte; neutralize green spill in non-green icon'}
    for name in ['field','river','forest','siege','victory','defeat']:
        key='scene/'+name
        scene=clean_victory(originals/'scene-victory.png') if name=='victory' else Image.open(originals/('scene-'+name+'.png')).convert('RGBA')
        sprites[key]=scene.resize((640,384),Image.Resampling.LANCZOS);origins[key]={'source':'scene-'+name+'.png'}
        if name=='victory':origins[key]['transform']='remove non-text gold marks inside flag polygon; cv2 inpaint radius 4'
        if name in ['victory','defeat']:
            sprites[key+'/enemy']=team(sprites[key],True);origins[key+'/enemy']={'source':'scene-'+name+'.png','team':'enemy'}
    for name in ['dirt','water']:
        source=selection['grounds'][name];key='ground/'+name;sprites[key]=seamless(originals/(source+'.png'),(512,512)).convert('RGBA');origins[key]={'source':source+'.png','transform':'mirrored seamless surface'}
    sprites['ui/paper']=Image.open(originals/'ui-paper.png').convert('RGBA').resize((256,256),Image.Resampling.LANCZOS);origins['ui/paper']={'source':'ui-paper.png'}
    for name,image in zip(['slash','impact','fire','water','mist','level'],sheet(originals/'effects-sheet.png')):
        sprites['effect/'+name]=fitted(image,(192,192));origins['effect/'+name]={'source':'effects-sheet.png','effect':name,'transform':'cell crop; remove green mixed into effect glow; transparent matte'}
    for name,source in selection['skillEffects'].items():
        key='effect/'+name;sprites[key]=fitted(standalone(originals/(source+'.png'),True),(192,192));origins[key]={'source':source+'.png'}
    portrait_sprites,portrait_ids,portrait_names,people=build_portraits();sprites.update(portrait_sprites)
    previous=json.loads((ROOT/'assets/art/manifest.json').read_text())
    atlas=Image.new('RGBA',(4096,4096));rectangles={};x=y=row=0;padding=3
    for key,image in sorted(sprites.items(),key=lambda item:-item[1].height):
        if x+image.width+padding*2>atlas.width:x=0;y+=row+padding*2;row=0
        if y+image.height+padding*2>atlas.height:raise ValueError('图集超过4096，需调整原生切片尺寸后重排')
        px,py=x+padding,y+padding;atlas.alpha_composite(image,(px,py));rectangles[key]=[px,py,image.width,image.height]
        # 为双线性采样留透明间隔，避免采到邻居的红甲、青甲或头像。
        x+=image.width+padding*2;row=max(row,image.height)
    atlas=atlas.crop((0,0,4096,y+row+padding*2));atlas.save(out/'atlas.png',optimize=True)
    for key,value in aliases.items():rectangles[key]=rectangles[value];origins[key]=dict(origins[value],alias=value)
    land_mask=strategy_map(root,out,review)
    seamless(originals/'ground-grass.png',(1024,1024)).save(out/'battle_texture.png',optimize=True)
    manifest={'version':4,'style':'hand-painted Chinese 2.5D','teamColors':{'friendly':'#b44337','enemy':'#237985'},'sprites':rectangles,'portraitIds':portrait_ids,'portraitNames':portrait_names,'cities':previous['cities'],'strategyLayout':previous['strategyLayout'],'mapSize':[1280,960],'unitPoses':POSES,'defeatAnchors':anchors,'defeatFrames':6,'defeatSinks':True,'portraitPolicy':previous['portraitPolicy'],'generator':'tool/art/pack_handpainted.py','rendering':'Offline local MFLUX generation; Flutter only draws cached PNG images','spriteSources':origins}
    (out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,separators=(',',':')))
    proof={'atlasSize':list(atlas.size),'portraitNames':len(portrait_names),'portraitBindings':len(portrait_ids),'landCities':38,'photoPeople':len({p['name'] for p in people if p['key'].startswith('photo1994/')}),'photoBindings':sum(p['key'].startswith('photo1994/') for p in people),'originalBindings':sum(p['key'].startswith('original/') for p in people),'defeatFrames':72,'unitPoses':POSES,'matrixLayout':manifest['strategyLayout'],'unitColorCoverage':{},'style':manifest['style'],'decodedImageBytes':(atlas.width*atlas.height+1280*960+1024*1024)*4,'files':{},'poseChecks':checks}
    if proof['decodedImageBytes']>64*1024*1024:raise ValueError('图片解码总内存超过64MiB预算')
    for side in ['friendly','enemy']:
        ratios=[]
        for kind in range(6):
            a=np.asarray(sprites[f'unit/{side}/{kind}/idle']);opaque=a[...,3]>100;r,g,b=[a[...,i].astype(float) for i in range(3)]
            colored=((r>g*1.22)&(r>b*1.22)) if side=='friendly' else ((g>r*1.17)&(b>r*1.17))
            ratio=float(np.count_nonzero(colored&opaque)/max(1,np.count_nonzero(opaque)));ratios.append(round(ratio,4))
            if ratio<=.35:raise ValueError(f'{side}兵种{kind}分色不足：{ratio:.3f}')
        proof['unitColorCoverage'][side]=ratios
    for name in ['atlas.png','strategy_map.png','battle_texture.png','manifest.json']:
        proof['files'][name]=hashlib.sha256((out/name).read_bytes()).hexdigest()
    (review/'art_proof.json').write_text(json.dumps(proof,ensure_ascii=False,indent=2)+'\n')
    sources={};references={}
    def record_source(name):
        if name in sources:return
        file=originals/(name+'.png');record=json.loads(file.with_suffix('.provenance.json').read_text())
        if hashlib.sha256(file.read_bytes()).hexdigest()!=record['sha256']:raise ValueError('原稿与生成来源校验不一致：'+name)
        record['file']=name+'.png';sources[name]=record
        for ref in record.get('refs',[]):
            path=Path(ref)
            if path.parts[0]=='generated':record_source(path.stem)
            elif path.parts[0]=='reference':references[ref]=hashlib.sha256((root/path).read_bytes()).hexdigest()
    for name in sorted(set(required)):record_source(name)
    selected={key:value for key,value in selection.items() if key not in ['actions','defeat']}
    (review/'sources.json').write_text(json.dumps({'style':manifest['style'],'selection':selected,'referenceFiles':references,'sources':list(sources.values())},ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in proof.items() if k not in ['poseChecks','files']},ensure_ascii=False),flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--out',type=Path,default=ROOT/'.dart_tool/handpainted_candidate');args=p.parse_args();pack(args.root,args.out)
