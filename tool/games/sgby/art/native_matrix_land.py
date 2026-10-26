"""原版矩阵地图的美术边界；城池始终使用LIB的格坐标，海岸围绕原布局绘制。"""
from pathlib import Path
import struct

from PIL import Image, ImageDraw, ImageFilter
import math
import random


def grid_positions(root):
    archive = (Path(root) / 'assets/game/SGBY-Reset-4X.lib').read_bytes()
    offset = struct.unpack_from('<I', archive, 4)[0]
    _, _, _, length, key = struct.unpack_from('<IHHIB', archive, offset)
    start, size = ((14 + 5 * length, length) if length else
                   struct.unpack_from('<II', archive, offset + 14 + 5 * 8))
    values = bytes((v - key) & 255 for v in archive[offset + start:offset + start + size])
    return list(zip(values[::2], values[1::2]))[:38]


def land_polygon():
    points = [(0, 0), (192, 0), (192, 18)]
    curves = [
        ((187, 18), (184, 20), (180, 24)),
        ((177, 27), (175, 31), (171, 32)),
        ((168, 34), (169, 37), (171, 39)),
        ((174, 40), (177, 38), (178, 43)),
        ((178, 46), (176, 49), (178, 52)),
        ((184, 61), (178, 74), (180, 83)),
        ((181, 94), (174, 99), (171, 104)),
        ((167, 111), (163, 116), (162, 123)),
        ((155, 130), (147, 132), (138, 134)),
        ((118, 139), (104, 136), (90, 138)),
        ((79, 141), (67, 137), (57, 140)),
        ((43, 144), (33, 135), (20, 138)),
        ((13, 138), (6, 137), (0, 137)),
    ]
    for first, second, end in curves:
        start = points[-1]
        for step in range(1, 21):
            t = step / 20
            points.append(tuple((1-t)**3 * start[i] + 3 * (1-t)**2 * t * first[i] +
                                3 * (1-t) * t*t * second[i] + t**3 * end[i] for i in (0, 1)))
    return points


def export_mask(root, target):
    image = Image.new('L', (1280, 960), 0)
    ImageDraw.Draw(image).polygon([(x / 192 * 1280, y / 144 * 960) for x, y in land_polygon()], fill=255)
    for index, (x, y) in enumerate(grid_positions(root)):
        box = ((x*16+3)/192*1280, (y*16+1)/144*960,
               (x*16+13)/192*1280, (y*16+10)/144*960)
        if image.crop(tuple(int(v) for v in box)).getextrema() != (255, 255):
            raise ValueError('原矩阵城池图标落海：' + str(index))
    Path(target).parent.mkdir(parents=True, exist_ok=True)
    image.convert('RGB').save(target)
    return image


def export_background(root, target):
    """布局修复包沿用既有二维素材；原矩阵陆地单独生成，三维方案保留在研究目录。"""
    mask = export_mask(root, Path(root) / '.dart_tool/art_export/native_matrix_mask.png')
    rng = random.Random(240)
    land = Image.new('RGB', mask.size)
    water = Image.new('RGB', mask.size)
    lp, wp = land.load(), water.load()
    for y in range(mask.height):
        for x in range(mask.width):
            grain = rng.uniform(-3, 3)
            tone = 4 * math.sin(x / 250) * math.cos(y / 280)
            lp[x, y] = tuple(int(v + grain + tone) for v in (163, 171, 134))
            wp[x, y] = tuple(int(v + grain * .5 + 3 * y / mask.height) for v in (105, 145, 155))
    land = land.filter(ImageFilter.GaussianBlur(.35))
    canvas = Image.composite(land, water, mask).convert('RGBA')
    draw = ImageDraw.Draw(canvas)
    coast = [(x / 192 * 1280, y / 144 * 960) for x,y in land_polygon()[2:]]
    draw.line(coast, fill=(214, 214, 179), width=3, joint='curve')
    # 河道只属于美术背景，不参与原版通路或寻路；曲线按原矩阵布局绘制。
    for control in [[(19,27),(42,31),(62,28),(79,34),(98,34),(117,44),(139,34),(175,36)],
                    [(24,80),(48,77),(76,83),(95,93),(123,94),(145,99),(177,93)]]:
        points=[]
        extended=[control[0],*control,control[-1]]
        for index in range(1,len(extended)-2):
            a,b,c,d=extended[index-1:index+3]
            for step in range(20):
                t=step/20
                points.append(tuple(.5*((2*b[i])+(-a[i]+c[i])*t+
                                     (2*a[i]-5*b[i]+4*c[i]-d[i])*t*t+
                                     (-a[i]+3*b[i]-3*c[i]+d[i])*t*t*t)
                                    * (1280/192 if i==0 else 960/144) for i in (0,1)))
        draw.line(points,fill=(115,131,106),width=10,joint='curve')
        draw.line(points,fill=(106,150,161),width=6,joint='curve')
    # 保留已有图集中山体的造型；新立体模型经过研究确认后再统一替换。
    import json
    manifest_path=Path(root)/'assets/art/manifest.json'
    if manifest_path.exists():
        data=json.loads(manifest_path.read_text())
        rect=data['sprites']['terrain/mountain']
        atlas=Image.open(Path(root)/'assets/art/atlas.png').convert('RGBA')
        sprite=atlas.crop((rect[0],rect[1],rect[0]+rect[2],rect[1]+rect[3])).resize((72,62),Image.Resampling.LANCZOS)
        cities=grid_positions(root)
        for x,y in [(0,1),(0,2),(1,3),(0,4),(1,5),(1,7),(2,7),(3,7),(4,0),(5,0),(6,0)]:
            if (x,y) in cities:continue
            canvas.alpha_composite(sprite,(int((x*16+2)/192*1280),int((y*16+2)/144*960)))
    canvas.convert('RGB').save(target,optimize=True)


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[2]
    export_mask(root, root / '.dart_tool/art_export/native_matrix_mask.png')
    export_background(root, root / 'assets/art/strategy_map.png')
    print('38座城池完整图标均在原矩阵陆地内')
