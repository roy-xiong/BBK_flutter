"""生成立体素材配置与正式图集。只在离线美术阶段运行，不进入Flutter运行时。"""
from pathlib import Path
import argparse
import hashlib
import json

from PIL import Image, ImageOps, ImageChops
import math
from portrait_assets import build_portraits

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / '.dart_tool/production_art'
OUT = ROOT / 'assets/art'
WORK.mkdir(parents=True, exist_ok=True)


def profiles():
    """导出原矩阵与身份索引；头像由真实剧照和原黑白资源单独生成。"""
    manifest = json.loads((OUT / 'manifest.json').read_text())
    config = {'version': 3, 'cities': manifest['cities'], 'strategyLayout': manifest['strategyLayout'],
              'people': [{'name': name, 'key': key} for name,key in manifest['portraitNames'].items()]}
    (WORK / 'profiles.json').write_text(json.dumps(config, ensure_ascii=False, indent=2))
    print('Original matrix cities:', len(config['cities']), flush=True)


def illustration(path, size, portrait=False):
    """透明角色按实体裁剪，去掉阴影画布造成的巨幅留白；肖像保持统一胸像构图。"""
    image = Image.open(path).convert('RGBA')
    if portrait:
        return ImageOps.fit(image, size, Image.Resampling.LANCZOS)
    alpha = image.getchannel('A').point(lambda v: 0 if v < 190 else int((v - 190) * 255 / 65))
    image.putalpha(alpha)
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError('Rendered asset is empty: ' + str(path))
    image = image.crop(bounds)
    result = Image.new('RGBA', size)
    image = ImageOps.contain(image, (size[0] - 4, size[1] - 4), Image.Resampling.LANCZOS)
    result.alpha_composite(image, ((size[0] - image.width) // 2, size[1] - image.height - 2))
    return result


def seamless(path, size):
    """镜像相邻边缘，使烘焙纹理的光照、颗粒在重复边界连续。"""
    source=Image.open(path).convert('RGB')
    result=Image.new('RGB',(source.width*2,source.height*2))
    result.paste(source,(0,0));result.paste(ImageOps.mirror(source),(source.width,0))
    result.paste(ImageOps.flip(source),(0,source.height));result.paste(ImageOps.flip(ImageOps.mirror(source)),(source.width,source.height))
    return result.resize(size,Image.Resampling.LANCZOS)


def pack():
    config = json.loads((WORK / 'profiles.json').read_text())
    renders = WORK / 'renders'
    sprites, aliases = {}, {}
    poses = ['idle', 'stride', 'windup', 'attack', 'hit', 'down']
    for side in ['friendly', 'enemy']:
        for kind in range(6):
            base = f'unit/{side}/{kind}'
            for pose in poses:
                key = base + '/' + pose
                sprites[key] = illustration(renders / f'unit_{kind}_{side}_{pose}.png', (160, 160))
            aliases[base] = base + '/idle'
    defeat_anchors = {}
    # 同一角色六帧使用联合包围盒，统一裁剪和缩放，倒地时脚下锚点不变。
    for side in ['friendly','enemy']:
        for kind in range(6):
            frames = []
            for phase in range(6):
                image = Image.open(renders/f'fall_{kind}_{side}_{phase}.png').convert('RGBA')
                image.putalpha(image.getchannel('A').point(lambda v: 0 if v<190 else int((v-190)*255/65)))
                frames.append(image)
            union = frames[0].getchannel('A')
            for image in frames[1:]:union=ImageChops.lighter(union,image.getchannel('A'))
            bounds=union.getbbox()
            if bounds is None:raise ValueError('Empty defeat sequence')
            span=max(bounds[2]-bounds[0],bounds[3]-bounds[1])+4
            box=(int((bounds[0]+bounds[2]-span)/2),int((bounds[1]+bounds[3]-span)/2))
            box=(*box,box[0]+span,box[1]+span)
            for phase,image in enumerate(frames):
                sprites[f'defeat/{side}/{kind}/{phase}']=image.crop(box).resize((112,112),Image.Resampling.LANCZOS)
            # 正交相机朝向固定；用原点的投影坐标计算地面锚点。
            direction=(4.85,-8,3.4);n=math.sqrt(sum(v*v for v in direction));d=tuple(v/n for v in direction)
            right=(8/math.hypot(8,4.85),4.85/math.hypot(8,4.85),0)
            up=(-d[2]*right[1],d[2]*right[0],d[0]*right[1]-d[1]*right[0])
            delta=(-.15,0,-1.1);scale=5.0 if kind==0 else 4.2
            ax=.5+sum(a*b for a,b in zip(delta,right))/scale
            ay=.5-sum(a*b for a,b in zip(delta,up))/scale
            initial=frames[0].getchannel('A').getbbox()
            length=17*span/(initial[3]-initial[1])
            defeat_anchors[f'{side}/{kind}']=[round((ax*320-box[0])/span,6),round((ay*320-box[1])/span,6),round(length,6)]
    for name in ['capital', 'fort', 'harbor']:
        sprites['city/' + name] = illustration(renders / ('city_' + name + '.png'), (160, 135))
    for name in ['mountain', 'tree', 'village', 'camp']:
        sprites['terrain/' + name] = illustration(renders / ('terrain_' + name + '.png'), (128, 128))
    for name in ['supplies', 'sun', 'cloud', 'wind', 'rain', 'fog']:
        sprites['icon/' + name] = illustration(renders / ('icon_' + name + '.png'), (96, 96))
    for name in ['dirt', 'water']:
        sprites['ground/' + name] = seamless(renders / ('ground_' + name + '.png'),(256,256)).convert('RGBA')
    for name in ['field', 'river', 'forest', 'siege']:
        sprites['scene/' + name] = Image.open(renders / ('scene_' + name + '.png')).convert('RGBA').resize((512, 256), Image.Resampling.LANCZOS)
    portrait_sprites, portrait_ids, portrait_names, people = build_portraits()
    sprites.update(portrait_sprites)
    atlas = Image.new('RGBA', (2048, 4096))
    rectangles, x, y, row_height = {}, 0, 0, 0
    for key, image in sorted(sprites.items(),key=lambda item: -item[1].height):
        if x + image.width + 2 > atlas.width:
            x, y, row_height = 0, y + row_height + 2, 0
        if y + image.height + 2 > atlas.height:
            raise ValueError('3D atlas exceeds 4096px; split the atlas before adding assets')
        atlas.alpha_composite(image, (x, y))
        rectangles[key] = [x, y, image.width, image.height]
        x, row_height = x + image.width + 2, max(row_height, image.height)
    for key, target in aliases.items():
        rectangles[key] = rectangles[target]
    atlas = atlas.crop((0, 0, atlas.width, y + row_height + 2))
    atlas.save(OUT / 'atlas.png', optimize=True)
    Image.open(renders / 'matrix_terrain.png').convert('RGB').save(OUT / 'strategy_map.png', optimize=True)
    seamless(renders / 'ground_grass.png',(1024,1024)).save(OUT / 'battle_texture.png', optimize=True)
    manifest = {'version': 3, 'style': '3D pre-rendered realism',
                'teamColors': {'friendly': '#b44337', 'enemy': '#237985'},
                'sprites': rectangles, 'portraitIds': portrait_ids,
                'portraitNames': portrait_names, 'cities': config['cities'],
                'strategyLayout': config['strategyLayout'], 'mapSize': [1280, 960],
                'unitPoses': poses, 'defeatAnchors': defeat_anchors, 'defeatFrames': 6, 'portraitPolicy': 'Verified 1994 TV character stills; otherwise original monochrome portrait by period and person ID',
                'generator': 'tool/art/render_production_3d.py',
                'rendering': 'Offline Blender Cycles; Flutter runtime draws cached images only'}
    (OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')))
    proof = {'atlasSize': list(atlas.size), 'portraitNames': len(portrait_names),
             'portraitBindings': len(portrait_ids), 'landCities': 38,
             'photoPeople': len({p['name'] for p in people if p['key'].startswith('photo1994/')}),
             'photoBindings': sum(p['key'].startswith('photo1994/') for p in people),
             'originalBindings': sum(p['key'].startswith('original/') for p in people),
             'defeatFrames': sum(key.startswith('defeat/') for key in sprites), 'unitPoses': poses, 'matrixLayout': config['strategyLayout'],
             'unitColorCoverage': {}, 'files': {}}
    for side in ['friendly', 'enemy']:
        values = []
        for kind in range(6):
            colored = opaque = 0
            for r, g, b, a in sprites[f'unit/{side}/{kind}/idle'].getdata():
                if a < 100:
                    continue
                opaque += 1
                if (r > g * 1.22 and r > b * 1.22) if side == 'friendly' else (g > r * 1.17 and b > r * 1.17):
                    colored += 1
            values.append(round(colored / max(1, opaque), 3))
        proof['unitColorCoverage'][side] = values
    proof['decodedImageBytes'] = (atlas.width * atlas.height + 1280 * 960 + 1024 * 1024) * 4
    for file in OUT.iterdir():
        if file.is_file():
            proof['files'][file.name] = hashlib.sha256(file.read_bytes()).hexdigest()
    (ROOT / 'tool/baseline/realistic_art_assets.json').write_text(json.dumps(proof, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in proof.items() if k != 'files'}, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--profiles-only', action='store_true')
    args = parser.parse_args()
    if args.profiles_only:
        profiles()
    else:
        pack()
