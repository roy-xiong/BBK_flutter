"""整套立体素材的离线生产工具：兵种动作、地形、道具和场景（武将头像由真实剧照单独导出）。

Blender --background --factory-startup --python-exit-code 1 --python 本文件 -- --batch all
渲染结果缓存于.dart_tool，打包工具将PNG压入图集；应用不依赖Blender或三维引擎。
"""
import argparse
import math
from pathlib import Path
import random
import sys

import bpy
from mathutils import Matrix, Vector, noise

sys.path.insert(0, str(Path(__file__).resolve().parent))
import render_3d_study as art

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / '.dart_tool/production_art'
OUT = WORK / 'renders'
OUT.mkdir(parents=True, exist_ok=True)


def setup(team='#a83b30', resolution=(512, 512), samples=24):
    """每张图清理上轮孤立网格和材质，避免数百张肖像批处理时积累内存。"""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for collection in [bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                       bpy.data.cameras, bpy.data.lights]:
        for block in list(collection):
            if block.users == 0:
                collection.remove(block)
    materials = art.setup()
    materials['team_metal'] = art.material('阵营漆甲', team, .62, .58, 42)
    materials['team_cloth'] = art.material('阵营织物', team, rough=.87, grain=90)
    scene = bpy.context.scene
    scene.cycles.samples = samples
    scene.render.resolution_x, scene.render.resolution_y = resolution
    return materials


def save(name):
    bpy.context.scene.render.filepath = str(OUT / (name + '.png'))
    bpy.ops.render.render(write_still=True)
    print('PRODUCTION_RENDERED', name, flush=True)


def transform(objects, pivot, rotation):
    # 先同步位置/缩放再读取matrix_world，防止最后创建的盾饰退回单位球体。
    bpy.context.view_layer.update()
    at = Vector(pivot)
    matrix = Matrix.Translation(at) @ rotation.to_4x4() @ Matrix.Translation(-at)
    for obj in objects:
        obj.matrix_world = matrix @ obj.matrix_world


def units(side_filter=None):
    builders = [art.horse, art.infantry, art.archer, art.navy,
                lambda m: art.infantry(m, True), art.scholar]
    for side, tint in [('friendly', '#ab3a30'), ('enemy', '#227c88')]:
        if side_filter and side!=side_filter:continue
        for kind, build in enumerate(builders):
            for pose in ['idle', 'stride', 'windup', 'attack', 'hit', 'down']:
                name = f'unit_{kind}_{side}_{pose}'
                if (OUT / (name + '.png')).exists():
                    continue
                m = setup(tint)
                build(m)
                if kind == 3:
                    bpy.data.objects['鼓风帆'].data.materials[0] = m['team_cloth']
                if kind == 0:
                    # 马裙与骑手盔甲采用同阵营色，骑兵在原战场尺寸下也能明确分红青。
                    for side_x in [-1, 1]:
                        vertices = []
                        for row in range(10):
                            t = row / 9
                            for col in range(12):
                                u = col / 11
                                vertices.append((side_x*(.40+.045*math.sin(t*math.pi)),
                                                 -.55+u*1.18, 1.57-t*.75+.025*math.sin(u*math.pi*8)*t))
                        faces = []
                        for row in range(9):
                            for col in range(11):
                                a = row*12+col
                                faces.append((a,a+1,a+13,a+12))
                        art.mesh('阵营马裙',vertices,faces,m['team_cloth'],smooth=True)
                if kind == 4:
                    for sx in [-1, 1]:
                        art.ellipsoid('重甲肩吞',(sx*.33,0,1.80),(.21,.20,.10),m['gold'])
                        art.rod('重甲肩棱',(sx*.35,0,1.82),(sx*.43,0,2.02),.045,m['steel'],.005)
                objects = [o for o in bpy.context.scene.objects if o.type in {'MESH','CURVE'}]
                if pose == 'stride':
                    for obj in objects:
                        if obj.name.startswith(('袴腿','胫甲','战靴','马胫','马蹄')):
                            sign = 1 if obj.location.x > 0 else -1
                            obj.location.y += sign*.11
                elif pose in ['windup','attack']:
                    weapons = [o for o in objects if o.name.startswith(
                        ('兵器木杆','双刃枪锋','戟月刃','骑枪','骑枪锋','反曲弓','弓弦','已搭弦箭','羽扇'))]
                    angle = -.30 if pose == 'windup' else .72
                    transform(weapons, (.40,-.20,1.70), Matrix.Rotation(angle,3,'Y'))
                    transform(objects, (0,0,.3), Matrix.Rotation(.025 if pose=='windup' else -.07,3,'X'))
                elif pose == 'hit':
                    transform(objects,(0,0,.15),Matrix.Rotation(-.18,3,'Y'))
                elif pose == 'down':
                    transform(objects,(0,0,.12),Matrix.Rotation(-1.22,3,'Y'))
                target=(0,0,.7 if pose=='down' else 1.9 if kind==0 else 1.35)
                scale=5.8 if kind==0 else 4.4 if pose=='down' else 3.7
                art.shadow_ground(m)
                art.camera(target,scale,(5,-8,4.5))
                save(name)


def tree(m):
    rng=random.Random(510)
    leaves=[art.material('树叶'+str(i),c,rough=.9,grain=80)
            for i,c in enumerate(['#48653b','#618046','#7c8e50','#345844'])]
    art.rod('树干',(0,0,.04),(0,0,1.55),.10,m['wood'],.055)
    vertices,faces=[],[]
    for branch in range(9):
        angle=branch*2.399;z=.65+branch*.10
        end=(math.cos(angle)*.55,math.sin(angle)*.55,z+.25)
        art.rod('分枝',(0,0,z),end,.035,m['wood'],.012)
        for leaf in range(105):
            a=rng.random()*math.tau;r=.40*math.sqrt(rng.random())
            x,y=end[0]+math.cos(a)*r,end[1]+math.sin(a)*r
            zz=end[2]+rng.uniform(-.16,.35)
            length=rng.uniform(.035,.085);width=length*.45;n=len(vertices)
            for dx,dy,dz in [(0,-length,0),(width,0,.012),(0,length,.018),(-width,0,-.009)]:
                vertices.append((x+math.cos(a)*dx-math.sin(a)*dy,y+math.sin(a)*dx+math.cos(a)*dy,zz+dz))
            faces.append((n,n+1,n+2,n+3))
    obj=art.mesh('细叶树冠',vertices,faces,leaves[0])
    for mat in leaves[1:]:obj.data.materials.append(mat)
    for poly in obj.data.polygons:poly.material_index=rng.randrange(4)


def mountain(m):
    rng=random.Random(82)
    rock=art.material('岩层','#777c70',rough=.93,grain=48)
    for x,y,h in [(-.45,.18,1.1),(.20,.32,1.65),(.50,-.25,.85),(-.40,-.37,.65)]:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=48,ring_count=32,location=(x,y,h*.44))
        obj=bpy.context.object;obj.name='侵蚀岩层';obj.scale=(.52,.48,h*.62)
        obj.data.materials.append(rock)
        for v in obj.data.vertices:
            f=noise.noise(v.co*3.7)*.16+noise.noise(v.co*8.2)*.06
            v.co*=1+f
        for p in obj.data.polygons:p.use_smooth=True


def camp(m):
    for x,y in [(-.65,.15),(.45,.25),(0,-.45)]:
        vertices=[(x-.43,y-.42,.02),(x+.43,y-.42,.02),(x,y-.42,.72),
                  (x-.43,y+.42,.02),(x+.43,y+.42,.02),(x,y+.42,.72)]
        art.mesh('布帐',vertices,[(0,1,2),(3,5,4),(0,2,5,3),(1,4,5,2)],m['linen'])
        art.mesh('帐门',[(x-.13,y-.432,.02),(x+.13,y-.432,.02),(x,y-.432,.42)],[(0,1,2)],m['leather'])
    for side in [-1,1]:
        for i in range(11):
            x=(i-5)*.23;art.rod('围栅',(x,side*.92,0),(x,side*.92,.35),.035,m['wood'])
    art.rod('军旗杆',(.9,0,0),(.9,0,1.5),.025,m['wood_light'])
    art.mesh('军旗',[(.9,0,1.5),(1.35,.05,1.45),(1.3,.02,1.1),(.9,0,1.13)],[(0,1,2,3)],m['team_cloth'])


def village(m):
    for x,y,w in [(-.65,.35,.9),(.48,.25,.8),(0,-.5,1.0)]:
        art.pavilion(m,x,y,.05,w,w*.75,.6)


def harbor(m):
    art.castle(m,False)
    for i in range(13):
        art.box('码头木板',(1.7,-2.2-i*.13,.13),(.9,.12,.12),m['wood_light'],.012)
    for x in [1.25,2.15]:
        for y in [-2.4,-3.1,-3.7]:art.rod('码头木桩',(x,y,-.1),(x,y,.35),.05,m['wood'])


def supplies(m):
    vertices,faces=[],[]
    for row in range(20):
        t=row/19;radius=.35*math.sin(t*math.pi)**.4+.06
        for col in range(48):
            a=col/48*math.tau;r=radius*(1+.035*math.sin(a*9))
            vertices.append((math.cos(a)*r,math.sin(a)*r,t*.9))
    for row in range(19):
        for col in range(48):
            a=row*48+col;b=row*48+(col+1)%48;faces.append((a,b,b+48,a+48))
    art.mesh('粮袋',vertices,faces,m['linen'],smooth=True)
    art.curve('扎绳',[(.075*math.cos(i*.2),.075*math.sin(i*.2),.82) for i in range(33)],.018,m['wood'])
    for x in [-.15,0,.15]:
        art.rod('稻秆',(x,0,.8),(x+.10,0,1.22),.009,m['gold'])
        for i in range(5):art.ellipsoid('稻穗',(x+.06+i*.01,-.02,1.0+i*.04),(.05,.02,.025),m['gold'])


def weather(m,kind):
    white=art.material('云层','#d9e0df',rough=.8,grain=60)
    sun=art.material('太阳','#dfb45b',.25,.45,40)
    if kind=='sun':
        art.ellipsoid('日轮',(0,0,.45),(.40,.18,.40),sun)
        for i in range(12):
            a=i*math.tau/12;art.rod('日芒',(math.cos(a)*.5,0,.45+math.sin(a)*.5),
                                   (math.cos(a)*.67,0,.45+math.sin(a)*.67),.026,sun)
    elif kind in ['cloud','rain']:
        for x,y,z,r in [(-.35,0,.5,.30),(0,.02,.7,.39),(.36,0,.5,.29),(0,-.04,.4,.32)]:
            art.ellipsoid('积云',(x,y,z),(r,r*.6,r*.8),white)
        if kind=='rain':
            for x in [-.4,0,.4]:art.rod('雨滴',(x,-.02,.18),(x-.1,-.02,-.18),.027,m['team_metal'])
    else:
        for row in range(3):
            z=.15+row*.25
            art.curve('风雾', [(-.65,0,z),(-.1,0,z),(.5,0,z),(.65,0,z+.12 if kind=='wind' else z)],.035,white)


def surface_material(name):
    """地表保留土壤、碎石与草丛的多尺度起伏，避免缩小后只剩一块单色面。"""
    mat=art.material('自然地表_'+name, '#657f45' if name=='grass' else '#8d7655' if name=='dirt' else '#3c7685',
                     rough=.24 if name=='water' else .95, grain=90)
    nodes,links=mat.node_tree.nodes,mat.node_tree.links
    shader=nodes.get('Principled BSDF');coords=nodes.new('ShaderNodeTexCoord')
    noise_node=nodes.new('ShaderNodeTexNoise');noise_node.inputs['Scale'].default_value=8
    noise_node.inputs['Detail'].default_value=5;noise_node.inputs['Roughness'].default_value=.78
    links.new(coords.outputs['Generated'],noise_node.inputs['Vector'])
    ramp=nodes.new('ShaderNodeValToRGB')
    colors={'grass':['#53683a','#859761'],'dirt':['#655943','#b39b75'],'water':['#356773','#5a91a0']}[name]
    for element,color in zip(ramp.color_ramp.elements,colors):element.color=art.rgb(color)
    ramp.color_ramp.elements[0].position=.18;ramp.color_ramp.elements[1].position=.82
    links.new(noise_node.outputs['Fac'],ramp.inputs['Fac']);links.new(ramp.outputs['Color'],shader.inputs['Base Color'])
    return mat


def ground(name):
    if (OUT/('ground_'+name+'.png')).exists():return
    m=setup(resolution=(1024,1024),samples=28)
    mat=surface_material(name)
    art.box('地面',(0,0,-.03),(8.2,8.2,.06),mat,0)
    if name=='grass':
        rng=random.Random(28);verts,faces=[],[]
        for i in range(16000):
            x,y=rng.uniform(-4,4),rng.uniform(-4,4);h=rng.uniform(.04,.10);a=len(verts)
            verts.extend([(x-.012,y,0),(x+.012,y,0),(x+.025,y+.018,h)]);faces.append((a,a+1,a+2))
        art.mesh('细草',verts,faces,art.material('草尖','#5a7540',rough=.98))
    art.camera((0,0,0),8,(0,0,12));save('ground_'+name)


def arena(name):
    if (OUT/('scene_'+name+'.png')).exists():return
    m=setup(resolution=(1024,512),samples=24)
    art.box('战斗地面',(0,0,-.08),(40,40,.12),surface_material('grass'),0)
    for x,y in [(-4,2.5),(3.6,3.3),(-3.6,3.9)]:
        before=set(bpy.context.scene.objects);mountain(m)
        for obj in set(bpy.context.scene.objects)-before:obj.location+=Vector((x,y,0))
    if name in ['forest','field']:
        for x,y in [(-3.4,1.7),(3.5,2),(-2.8,3.4)]:
            before=set(bpy.context.scene.objects);tree(m)
            for obj in set(bpy.context.scene.objects)-before:obj.location+=Vector((x,y,0))
    if name=='river':
        water=art.material('河面','#4f8794',rough=.2,grain=80)
        art.box('战斗河流',(0,.8,.015),(14,1.2,.03),water,.04)
    if name=='siege':
        before=set(bpy.context.scene.objects);art.castle(m,False)
        for obj in set(bpy.context.scene.objects)-before:
            obj.scale*=.6;obj.location=obj.location*.6+Vector((0,2.7,0))
    art.camera((0,0,.4),9,(7,-10,6));save('scene_'+name)


def environment():
    builders={'city_capital':lambda m:art.castle(m,True),'city_fort':lambda m:art.castle(m,False),
              'city_harbor':harbor,'terrain_tree':tree,'terrain_mountain':mountain,
              'terrain_village':village,'terrain_camp':camp,'icon_supplies':supplies}
    for name,build in builders.items():
        if (OUT/(name+'.png')).exists():continue
        m=setup();build(m);art.shadow_ground(m)
        art.camera((0,0,1.2 if name.startswith('city') else .75),
                   9.4 if name.startswith('city') else 3.4,(6,-8,6));save(name)
    for kind in ['sun','cloud','wind','rain','fog']:
        if (OUT/('icon_'+kind+'.png')).exists():continue
        m=setup();weather(m,kind);art.camera((0,0,.45),1.85,(1,-8,2));save('icon_'+kind)
    for name in ['grass','dirt','water']:ground(name)
    for name in ['field','river','forest','siege']:arena(name)
    if not (OUT/'matrix_terrain.png').exists():
        art.terrain(OUT,ROOT/'.dart_tool/art_export/native_matrix_mask.png')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--batch',choices=['all','units','environment'],default='all')
    parser.add_argument('--side',choices=['friendly','enemy']);args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    if args.batch in ['all','environment']:environment()
    if args.batch in ['all','units']:units(args.side)
