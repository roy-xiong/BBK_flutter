"""立体写实素材研究：离线 Blender 渲染，不改变 Flutter 运行时或游戏规则。

用法：Blender --background --factory-startup --python 本文件 -- --out 输出目录。
建筑、甲片、兵器均为可编辑几何；材质、灯光和相机固定，便于同倍率对照。
"""
import argparse
import math
from pathlib import Path
import random
import sys

import bpy
from mathutils import Vector


def rgb(word):
    values = [int(word.lstrip('#')[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in values) + (1,)


def material(name, tint, metal=0, rough=.7, grain=0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = rgb(tint)
    shader.inputs['Metallic'].default_value = metal
    shader.inputs['Roughness'].default_value = rough
    if grain:
        noise = nodes.new('ShaderNodeTexNoise')
        noise.inputs['Scale'].default_value = grain
        noise.inputs['Detail'].default_value = 5
        noise.inputs['Roughness'].default_value = .75
        coordinates = nodes.new('ShaderNodeTexCoord')
        links.new(coordinates.outputs['Object'], noise.inputs['Vector'])
        ramp = nodes.new('ShaderNodeValToRGB')
        base = rgb(tint)
        ramp.color_ramp.elements[0].position = .2
        low, high = (.90, 1.10) if '皮肤' in name else (.82, 1.18) if metal else (.72, 1.24)
        ramp.color_ramp.elements[0].color = tuple(c * low for c in base[:3]) + (1,)
        ramp.color_ramp.elements[1].position = .8
        ramp.color_ramp.elements[1].color = tuple(min(1, c * high) for c in base[:3]) + (1,)
        bump = nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = .18
        bump.inputs['Distance'].default_value = .0015 if '皮肤' in name else .005 if metal else .009
        links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
        links.new(ramp.outputs['Color'], shader.inputs['Base Color'])
        links.new(noise.outputs['Fac'], bump.inputs['Height'])
        links.new(bump.outputs['Normal'], shader.inputs['Normal'])
    return mat


def mesh(name, vertices, faces, mat, smooth=False, bevel=0):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    if mat:
        obj.data.materials.append(mat)
    for face in data.polygons:
        face.use_smooth = smooth
    if bevel:
        mod = obj.modifiers.new('磨损倒角', 'BEVEL')
        mod.width, mod.segments = bevel, 3
        obj.modifiers.new('立面法线', 'WEIGHTED_NORMAL')
    return obj


def box(name, at, size, mat, bevel=.025):
    w, d, h = [v / 2 for v in size]
    vertices = [(a * w, b * d, c * h)
                for a, b, c in [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
                                (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]]
    obj = mesh(name, vertices, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                                (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], mat, bevel=bevel)
    obj.location = at
    return obj


def ellipsoid(name, at, scale, mat, rotation=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16, location=at)
    obj = bpy.context.object
    obj.name, obj.scale = name, scale
    if rotation:
        obj.rotation_euler = rotation
    obj.data.materials.append(mat)
    for face in obj.data.polygons:
        face.use_smooth = True
    return obj


def rod(name, a, b, radius, mat, end_radius=None, sides=16):
    a, b = Vector(a), Vector(b)
    direction = b - a
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=radius,
                                   radius2=radius if end_radius is None else end_radius,
                                   depth=direction.length, location=(a + b) / 2)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = direction.to_track_quat('Z', 'Y').to_euler()
    obj.data.materials.append(mat)
    for face in obj.data.polygons:
        face.use_smooth = len(face.vertices) == 4
    return obj


def curve(name, points, radius, mat):
    data = bpy.data.curves.new(name, 'CURVE')
    data.dimensions, data.resolution_u, data.bevel_resolution = '3D', 16, 3
    data.bevel_depth = radius
    spline = data.splines.new('BEZIER')
    spline.bezier_points.add(len(points) - 1)
    for control, point in zip(spline.bezier_points, points):
        control.co, control.handle_left_type, control.handle_right_type = point, 'AUTO', 'AUTO'
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def setup():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.film_transparent = True
    scene.view_settings.view_transform = 'AgX'
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.55, .64, .76, 1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value = .45
    for name, at, energy, size, tint in [
        ('暖色主光', (-4, -6, 9), 1100, 5, (1, .87, .68)),
        ('天空填充', (5, -1, 6), 550, 5, (.65, .79, 1)),
        ('背部轮廓', (0, 5, 7), 900, 4, (1, .95, .82)),
    ]:
        data = bpy.data.lights.new(name, 'AREA')
        data.energy, data.shape, data.size, data.color = energy, 'DISK', size, tint
        obj = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(obj)
        obj.location = at
        obj.rotation_euler = (Vector((0, 0, 1)) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    return {
        'stone': material('风化青砖', '#8e8b79', grain=36),
        'stone_dark': material('湿润石缝', '#565c51', grain=45),
        'wood': material('旧木梁', '#72503a', rough=.73, grain=18),
        'wood_light': material('木纹亮面', '#a68155', rough=.73, grain=22),
        'roof': material('青瓦', '#45545a', rough=.54, grain=48),
        'roof_edge': material('瓦口', '#748086', rough=.6, grain=32),
        'red_roof': material('旧琉璃瓦', '#7e4b35', rough=.54, grain=28),
        'skin': material('皮肤', '#b88762', rough=.62, grain=75),
        'skin_light': material('鼻梁与指节', '#ce9d78', rough=.62, grain=75),
        'hair': material('发须', '#24251e', rough=.86, grain=12),
        'eye': material('眼白', '#d9cfb4', rough=.5),
        'pupil': material('瞳孔', '#191c19', rough=.3),
        'steel': material('磨损钢铁', '#aeb8b7', .88, .32, 65),
        'iron': material('黑铁', '#454b4a', .72, .5, 48),
        'gold': material('旧铜边', '#b19859', .68, .4, 40),
        'leather': material('皮革', '#4b3428', rough=.8, grain=22),
        'linen': material('旧麻布', '#d7cdb2', rough=.9, grain=90),
        'grass': material('地表', '#77846a', rough=.96, grain=50),
    }


def camera(target, scale, at=(6, -8, 6)):
    data = bpy.data.cameras.new('正交素材相机')
    data.type, data.ortho_scale = 'ORTHO', scale
    obj = bpy.data.objects.new('正交素材相机', data)
    bpy.context.collection.objects.link(obj)
    obj.location = Vector(target) + Vector(at)
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.camera = obj


def shadow_ground(m):
    obj = box('投影接收面', (0, 0, -.10), (200, 200, .1), m['grass'], bevel=0)
    obj.is_shadow_catcher = True


def roof(m, x, y, z, width, depth, height, red=False):
    """双坡曲面屋顶，逐条瓦垄与弯曲飞檐形成真实遮挡和高光。"""
    roof_mat = m['red_roof' if red else 'roof']
    for side in [-1, 1]:
        vertices, faces = [], []
        cols, rows = 36, 12
        for iy in range(rows + 1):
            t = iy / rows
            for ix in range(cols + 1):
                u = ix / cols
                xx = (u - .5) * width
                yy = side * t * depth / 2
                zz = height * (1 - t) + height * .16 * t ** 4
                zz += .018 * (math.cos(u * math.pi * 36) ** 2)
                zz += .10 * height * abs(2 * u - 1) ** 5 * t ** 3
                vertices.append((x + xx, y + yy, z + zz))
        for iy in range(rows):
            for ix in range(cols):
                a = iy * (cols + 1) + ix
                face = (a, a + 1, a + cols + 2, a + cols + 1)
                faces.append(face if side > 0 else tuple(reversed(face)))
        mesh('瓦垄屋面', vertices, faces, roof_mat, smooth=True)
        for ix in range(0, cols + 1, 2):
            u = ix / cols
            points = []
            for step in range(9):
                t = step / 8
                points.append((x + (u - .5) * width, y + side * t * depth / 2,
                               z + height * (1 - t) + height * .16 * t ** 4 +
                               .10 * height * abs(2 * u - 1) ** 5 * t ** 3 + .012))
            curve('筒瓦分缝', points, .009, m['roof_edge'])
        curve('飞檐', [(x - width / 2, y + side * depth / 2, z + .25 * height),
                       (x, y + side * depth / 2, z + .16 * height),
                       (x + width / 2, y + side * depth / 2, z + .25 * height)], .035, roof_mat)
    rod('屋脊', (x - width * .48, y, z + height + .02),
        (x + width * .48, y, z + height + .02), .045, m['roof_edge'])


def pavilion(m, x, y, bottom, width=1.4, depth=1.2, height=1.1, red=False):
    box('楼阁墙体', (x, y, bottom + height / 2), (width, depth, height), m['wood'], .02)
    for sx in [-1, 1]:
        for sy in [-1, 1]:
            rod('承重柱', (x + sx * width * .45, y + sy * depth * .45, bottom),
                (x + sx * width * .45, y + sy * depth * .45, bottom + height), .055, m['red_roof'])
    for i in range(5):
        xx = x + (i - 2) * width / 6
        box('窗洞', (xx, y - depth / 2 - .012, bottom + height * .64),
            (width / 9, .035, height * .42), m['iron'], .005)
        rod('窗棂', (xx, y - depth / 2 - .04, bottom + height * .44),
            (xx, y - depth / 2 - .04, bottom + height * .84), .012, m['gold'])
    roof(m, x, y, bottom + height, width * 1.3, depth * 1.32, height * .55, red)


def castle(m, capital=True):
    rng = random.Random(301)
    box('城基', (0, 0, .08), (5.7, 4.6, .16), m['stone_dark'], .10)
    box('夯土院地', (0, 0, .19), (5.15, 4.05, .16), m['grass'], .04)
    for x, y, width, depth in [(0, 1.9, 5.2, .40), (-2.4, 0, .4, 4.0), (2.4, 0, .4, 4.0),
                                (-1.55, -1.9, 1.85, .45), (1.55, -1.9, 1.85, .45)]:
        box('城墙主体', (x, y, .70), (width, depth, 1.0), m['stone'], .05)
        count = max(2, int(max(width, depth) / .25))
        for index in range(count):
            t = (index + .5) / count - .5
            xx, yy = (x + t * width, y) if width > depth else (x, y + t * depth)
            box('垛口', (xx, yy, 1.31), (.15 if width > depth else width, depth if width > depth else .15, .26), m['stone'], .018)
        # 石块接缝采用几何细线，让斜光真实投影，避免单纯大色块。
        if width > depth:
            for row in range(5):
                z = .28 + row * .17
                rod('砖水平缝', (x - width / 2, y - depth / 2 - .006, z),
                    (x + width / 2, y - depth / 2 - .006, z), .007, m['stone_dark'])
                for index in range(int(width / .32)):
                    xx = x - width / 2 + index * .32 + (row % 2) * .16
                    rod('错缝砖缝', (xx, y - depth / 2 - .008, z),
                        (xx, y - depth / 2 - .008, z + .16), .005, m['stone_dark'])
    for x in [-2.4, 2.4]:
        for y in [-1.9, 1.9]:
            box('角楼石台', (x, y, .9), (.85, .85, 1.5), m['stone'], .06)
            pavilion(m, x, y, 1.62, .82, .82, .6)
    box('城门门额', (0, -1.9, 1.08), (1.35, .8, .4), m['stone'], .05)
    for side in [-1, 1]:
        box('城门门扇', (side * .25, -2.13, .58), (.48, .13, .85), m['wood'], .02)
        for row in range(4):
            for col in range(3):
                ellipsoid('门钉', (side * .25 + (col - 1) * .12, -2.21, .30 + row * .17), (.022, .012, .022), m['gold'])
    pavilion(m, 0, -1.9, 1.35, 1.5, 1.0, .72, capital)
    if capital:
        pavilion(m, 0, -1.9, 2.34, 1.18, .83, .54, True)
    for x, y in [(-1.2, .45), (1.2, .45), (-1.2, 1.25), (1.2, 1.25)]:
        pavilion(m, x, y, .28, .85, .58, .46)
    pavilion(m, 0, .8, .25, 1.1, 1.1, .95, capital)
    for side in [-1, 1]:
        for index in range(4):
            at = (side * (1.75 + rng.random() * .12), -1.2 + index * .6, .35)
            ellipsoid('庭院灌木', at, (.15, .16, .14), m['grass'])
    rod('旗杆', (.95, -2, 1.5), (.95, -2, 3.5), .027, m['wood_light'])
    flag = mesh('迎风旗', [(.95, -2, 3.45), (1.6, -1.93, 3.38), (1.52, -2.03, 3.03), (.95, -2, 3.1)], [(0, 1, 2, 3)], m['team_cloth'])
    solid = flag.modifiers.new('旗布厚度', 'SOLIDIFY')
    solid.thickness = .012


def head(m, at, helmet=True, beard=False):
    x, y, z = at
    # 连续头部曲面雕出眼窝、眉弓、鼻梁和颧骨，避免把五官拼成球体玩偶。
    bpy.ops.mesh.primitive_uv_sphere_add(segments=96, ring_count=64, location=at)
    obj = bpy.context.object
    obj.name = '连续颅面雕塑'
    obj.data.materials.append(m['skin'])
    def gaussian(px, pz, cx, cz, sx, sz):
        return math.exp(-((px - cx) / sx) ** 2 - ((pz - cz) / sz) ** 2)
    for vertex in obj.data.vertices:
        px, py, pz = vertex.co
        px, py, pz = px * .18, py * .16, pz * .25
        if pz < -.11:
            px *= 1 - .21 * min(1, (-pz - .11) / .14)
        if py < 0:
            depth = -.065 * gaussian(px, pz, 0, -.005, .033, .10)
            depth -= .045 * gaussian(px, pz, 0, -.045, .038, .035)
            for side in [-1, 1]:
                depth += .025 * gaussian(px, pz, side * .075, .025, .049, .039)
                depth -= .023 * gaussian(px, pz, side * .075, .070, .060, .022)
                depth -= .016 * gaussian(px, pz, side * .105, -.050, .048, .065)
            depth -= .013 * gaussian(px, pz, 0, -.128, .08, .022)
            py += depth * min(1, abs(py) / .08)
        vertex.co = (px, py, pz)
    for face in obj.data.polygons:
        face.use_smooth = True
    for side in [-1, 1]:
        ellipsoid('耳', (x + side * .19, y, z - .015), (.044, .032, .08), m['skin'])
        ellipsoid('眼白', (x + side * .074, y - .149, z + .026), (.024, .009, .010), m['eye'])
        ellipsoid('瞳孔', (x + side * .071, y - .158, z + .026), (.009, .006, .010), m['pupil'])
        curve('眉', [(x + side * .033, y - .154, z + .065), (x + side * .077, y - .158, z + .075),
                     (x + side * .115, y - .132, z + .062)], .008, m['hair'])
    curve('唇线', [(x -.051, y -.135, z -.127), (x, y -.147, z -.132), (x +.051, y -.135, z -.127)], .004, m['leather'])
    if beard:
        ellipsoid('短须', (x, y -.075, z -.22), (.14, .12, .17), m['hair'])
    if helmet:
        rod('锥形盔盖', (x, y + .015, z + .11), (x, y + .015, z + .35), .205, m['team_metal'], .035, sides=48)
        curve('盔沿', [(x -.218, y -.01, z + .12), (x -.14, y -.18, z + .13),
                       (x, y -.20, z + .14), (x +.14, y -.18, z +.13), (x +.218, y -.01, z +.12)], .018, m['gold'])
        for side in [-1, 1]:
            points = [(x + side * .19, y -.06, z +.12), (x + side * .19, y +.12, z +.10),
                      (x + side * .16, y +.10, z -.18), (x + side * .15, y -.055, z -.14)]
            guard = mesh('垂片护颊', points, [(0, 1, 2, 3)], m['team_metal'], bevel=.008)
            guard.modifiers.new('护颊厚度', 'SOLIDIFY').thickness = .012
        rod('盔顶', (x, y, z +.28), (x, y, z +.38), .05, m['gold'], .013)
        for strand in range(11):
            dx = (strand - 5) * .006
            curve('盔缨细束', [(x + dx, y, z + .34), (x + dx, y +.08, z + .48),
                              (x + dx, y +.25, z +.43), (x + dx, y +.37, z +.21)], .010, m['team_cloth'])


def cloth(m, x, y, z, width=.65, length=.9):
    verts, faces = [], []
    cols, rows = 18, 20
    for row in range(rows + 1):
        t = row / rows
        for col in range(cols + 1):
            u = col / cols - .5
            verts.append((x + u * width * (1 + .6 * t),
                          y + .2 + t * .30 + .035 * math.sin(col * 1.6) * t,
                          z - t * length + .03 * math.sin(col * 1.6) * t))
    for row in range(rows):
        for col in range(cols):
            a = row * (cols + 1) + col
            faces.append((a, a + 1, a + cols + 2, a + cols + 1))
    obj = mesh('褶皱披风', verts, faces, m['team_cloth'], smooth=True)
    obj.modifiers.new('布料厚度', 'SOLIDIFY').thickness = .012


def human(m, at=(0, 0, 1.05), pose='infantry', armored=True):
    x, y, z = at
    chest = (x, y, z + .48)
    ellipsoid('衣袍躯干', chest, (.29, .19, .40), m['team_cloth'])
    if armored:
        ellipsoid('胸甲', (x, y -.025, z + .48), (.305, .205, .35), m['team_metal'])
        for row in range(6):
            for col in range(7):
                u = (col - 3) / 3
                xx = x + u * .25
                yy = y -.19 * math.sqrt(max(.1, 1 - u * u * .8)) -.04
                plate = box('叠压甲片', (xx, yy, z + .24 + row * .075), (.069, .024, .09), m['team_metal'], .009)
                plate.rotation_euler[2] = -u * .35
                plate.rotation_euler[0] = .16
                if row % 2 == 0 and col % 2 == 0:
                    ellipsoid('甲钉', (xx, yy -.018, z + .265 + row * .075), (.009, .006, .009), m['gold'])
    rod('腰带', (x -.31, y -.03, z +.10), (x +.31, y -.03, z +.10), .07, m['leather'])
    box('带扣', (x, y -.23, z +.10), (.13, .04, .11), m['gold'], .02)
    for side in [-1, 1]:
        hip = (x + side * .16, y, z)
        knee = (x + side * (.31 if pose == 'rider' else .18), y -.10, z -.48)
        ankle = (x + side * (.35 if pose == 'rider' else .22), y -.04, z -.90)
        rod('袴腿', hip, knee, .13, m['team_cloth'], .11)
        rod('胫甲', knee, ankle, .115, m['team_metal'] if armored else m['leather'], .075)
        ellipsoid('战靴', (ankle[0], ankle[1] -.06, ankle[2] -.035), (.105, .18, .09), m['leather'])
        shoulder = Vector((x + side * .32, y, z +.72))
        if pose == 'archer':
            elbow = Vector((x + side * .48, y -.17, z +.55))
            hand = Vector((x + (.64 if side > 0 else .18), y -.40, z +.66))
        else:
            elbow = Vector((x + side * .43, y -.10, z +.40))
            hand = Vector((x + side * .48, y -.24, z +.58))
        rod('上臂', shoulder, elbow, .11, m['team_cloth'], .095)
        rod('护臂', elbow, hand, .10, m['team_metal'] if armored else m['leather'], .075)
        ellipsoid('护肩', shoulder, (.17, .18, .065), m['team_metal'] if armored else m['team_cloth'])
        ellipsoid('手掌', hand, (.075, .055, .09), m['skin_light'])
        for finger in range(3):
            rod('握持手指', hand + Vector((-.04 + finger * .028, -.03, .02)),
                hand + Vector((-.04 + finger * .028, -.065, -.04)), .012, m['skin_light'], .010)
    rod('颈', (x, y, z +.75), (x, y, z +.93), .085, m['skin'])
    head(m, (x, y -.015, z +1.11), helmet=armored, beard=pose == 'heavy')
    cloth(m, x, y, z +.73, length=.9)


def spear(m, x=.53, y=-.32, heavy=False):
    rod('兵器木杆', (x, y, .22), (x + .10, y, 2.65), .023, m['wood_light'])
    tip = (x + .10, y, 2.65)
    mesh('双刃枪锋', [(tip[0] -.065, y, 2.63), (tip[0], y -.02, 3.04),
                       (tip[0] +.065, y, 2.63), (tip[0], y +.025, 2.70)],
         [(0, 1, 3), (1, 2, 3), (0, 3, 2)], m['steel'], bevel=.005)
    if heavy:
        mesh('戟月刃', [(x +.1, y, 2.65), (x +.35, y, 2.87), (x +.30, y, 2.59), (x +.1, y, 2.52)],
             [(0, 1, 2, 3)], m['steel'], bevel=.015)


def infantry(m, heavy=False):
    human(m, pose='heavy' if heavy else 'infantry')
    spear(m, heavy=heavy)
    if not heavy:
        ellipsoid('木盾', (-.48, -.36, 1.40), (.29, .065, .43), m['wood'])
        for i in range(6):
            x = -.48 + (i - 2.5) * .075
            height = .72 * math.sqrt(max(.1, 1 - ((i - 2.5) / 3.2) ** 2))
            rod('盾板缝', (x, -.424, 1.40 - height / 2), (x, -.424, 1.40 + height / 2), .007, m['leather'])
        for z in [1.15, 1.65]:
            rod('盾铁箍', (-.69, -.431, z), (-.27, -.431, z), .025, m['iron'])
        ellipsoid('盾心铁包', (-.48, -.44, 1.40), (.11, .045, .12), m['steel'])


def archer(m):
    human(m, pose='archer')
    curve('反曲弓', [(.69, -.39, 1.05), (.82, -.48, 1.26), (.70, -.51, 1.66),
                     (.82, -.48, 2.05), (.69, -.39, 2.25)], .026, m['wood_light'])
    curve('弓弦', [(.69, -.39, 1.05), (.17, -.43, 1.70), (.69, -.39, 2.25)], .004, m['linen'])
    rod('已搭弦箭', (.12, -.44, 1.70), (1.10, -.44, 1.70), .009, m['wood_light'])
    rod('箭袋', (-.20, .29, 1.30), (-.32, .31, 2.08), .11, m['leather'])
    for i in range(7):
        x = -.32 + (i % 3 - 1) * .045
        rod('备用箭', (x, .30, 1.5), (x -.05, .30, 2.34 + (i % 2) * .05), .007, m['wood_light'])
        ellipsoid('箭羽', (x -.05, .30, 2.28 + (i % 2) * .05), (.025, .012, .08), m['linen'])


def horse(m):
    coat = material('战马栗色', '#70503c', rough=.7, grain=33)
    mane = material('鬃毛', '#25251f', rough=.92, grain=18)
    ellipsoid('马躯', (0, 0, 1.17), (.43, .88, .48), coat)
    ellipsoid('马臀', (0, .58, 1.18), (.42, .40, .46), coat)
    ellipsoid('马颈', (0, -.66, 1.62), (.26, .35, .60), coat, (.35, 0, 0))
    ellipsoid('马首', (0, -.97, 2.04), (.22, .34, .28), coat, (-.35, 0, 0))
    ellipsoid('马鼻', (0, -1.19, 1.91), (.19, .22, .17), m['leather'])
    for side in [-1, 1]:
        ellipsoid('马耳', (side * .14, -.89, 2.34), (.055, .07, .18), coat)
        ellipsoid('马眼', (side * .205, -1.04, 2.10), (.025, .043, .035), m['pupil'])
        for front in [-1, 1]:
            y = front * .55
            hip, knee, foot = (side * .29, y, 1.13), (side * .28, y -.08, .55), (side * .29, y +.04, .16)
            rod('马股肌', hip, knee, .15, coat, .065)
            rod('马胫', knee, foot, .065, coat, .045)
            ellipsoid('马蹄', (foot[0], foot[1] -.02, .105), (.075, .11, .085), m['iron'])
        curve('缰绳', [(side * .18, -1.19, 1.96), (side * .26, -.8, 1.55), (side * .29, -.2, 2.0)], .012, m['leather'])
    for i in range(7):
        curve('马鬃', [((i - 3) * .025, -.75, 2.28), ((i - 3) * .025, -.45, 1.91),
                       ((i - 3) * .035, -.45, 1.45)], .035, mane)
    curve('马尾', [(0, .86, 1.45), (.08, 1.0, .94), (.12, 1.08, .45)], .085, mane)
    box('鞍毯', (0, .05, 1.60), (.76, .90, .10), m['team_cloth'], .08)
    ellipsoid('鞍', (0, .02, 1.70), (.28, .36, .13), m['leather'])
    human(m, (0, .04, 1.88), pose='rider')
    rod('骑枪', (.53, -.15, 2.0), (.69, -.65, 4.1), .027, m['wood_light'])
    mesh('骑枪锋', [(.63, -.65, 4.04), (.72, -.71, 4.49), (.76, -.65, 4.04)], [(0, 1, 2)], m['steel'])


def scholar(m):
    human(m, armored=False)
    rod('长袍', (0, 0, .15), (0, 0, 1.28), .46, m['team_cloth'], .25, sides=48)
    box('冠', (0, 0, 2.45), (.25, .23, .38), m['iron'], .025)
    box('冠玉', (0, -.13, 2.49), (.10, .025, .13), m['gold'], .02)
    for i in range(11):
        t = (i - 5) * .09
        curve('羽扇羽毛', [(.47, -.3, 1.45), (.54 + t, -.31, 1.73),
                          (.54 + t * 1.7, -.31, 1.95 - abs(t) * .4)], .028, m['linen'])


def navy(m):
    verts, faces = [], []
    sections = 16
    for i in range(sections + 1):
        y = -1.6 + i * 3.2 / sections
        w = .48 * max(.12, math.sin(math.pi * i / sections)) ** .55
        for x, z in [(-w, .45), (-w * .7, .05), (w * .7, .05), (w, .45)]:
            verts.append((x, y, z + abs(y / 1.6) ** 4 * .25))
    for i in range(sections):
        for k in range(3):
            a = i * 4 + k
            faces.append((a, a + 1, a + 5, a + 4))
    mesh('舢板船壳', verts, faces, m['team_metal'], smooth=True)
    for k in range(3):
        for side in [-1, 1]:
            curve('船舷木筋', [(side * .48 * max(.12, math.sin(math.pi * i / sections)) ** .55,
                               -1.6 + i * 3.2 / sections, .14 + k * .14 + abs((-1.6 + i * 3.2 / sections) / 1.6) ** 4 * .25)
                              for i in range(sections + 1)], .016, m['wood_light'])
    box('甲板', (0, 0, .43), (.67, 2.45, .06), m['wood_light'], .02)
    rod('桅杆', (0, -.1, .4), (0, -.1, 2.9), .043, m['wood'])
    verts = [(-.67, -.1, 2.7), (.67, -.1, 2.7), (.60, -.1, 1.0), (-.60, -.1, 1.0), (0, -.38, 1.85)]
    mesh('鼓风帆', verts, [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], m['linen'], smooth=True)
    for z in [1.1, 1.45, 1.8, 2.15, 2.55]:
        curve('帆竹骨', [(-.62, -.1, z), (0, -.38, z), (.62, -.1, z)], .012, m['wood_light'])
    # 操舟兵为缩小的人物模型，不使用一块无细节色片代替。
    before = set(bpy.data.objects)
    human(m, (0, .80, 1.05))
    for obj in set(bpy.data.objects) - before:
        obj.location *= .48
        obj.scale *= .48
        obj.location += Vector((0, .55, .43))
    for side in [-1, 1]:
        rod('长桨', (side * .18, .65, .7), (side * 1.05, 1.05, .06), .023, m['wood_light'])


def terrain(output, mask_path):
    """顶视渲染原矩阵地形；相机无透视、不旋转布局，城池预留平地与清晰边界。"""
    import numpy as np
    import struct
    from mathutils import noise as field
    m = setup()
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = 1280, 960
    scene.cycles.samples = 48
    image = bpy.data.images.load(str(mask_path))
    w, h = image.size
    mask = np.asarray(image.pixels[:], dtype=float).reshape(h, w, 4)[:, :, 0]
    root = Path(__file__).resolve().parents[2]
    archive = (root / 'assets/game/SGBY-Reset-4X.lib').read_bytes()
    offset = struct.unpack_from('<I', archive, 4)[0]
    _, _, _, length, key = struct.unpack_from('<IHHIB', archive, offset)
    start, size = ((14 + 5 * length, length) if length else struct.unpack_from('<II', archive, offset + 54))
    values = bytes((v-key)&255 for v in archive[offset+start:offset+start+size])
    cities = [((values[i*2]+.5)*2-12, 9-(values[i*2+1]+.5)*2) for i in range(38)]
    def is_land(x, y):
        ix, iy = int((x+12)/24*(w-1)), int((y+9)/18*(h-1))
        return 0 <= ix < w and 0 <= iy < h and mask[iy, ix] > .5
    def height(x, y):
        if not is_land(x, y):
            return -.16
        west = max(0, 1-(x+12)/20)
        ridge = max(0, field.noise(Vector((x*.46,y*.46,2.1)))*1.6+.12)
        detail = sum(abs(field.noise(Vector((x*frequency,y*frequency,3.7))))*weight
                     for frequency,weight in [(1.2,.20),(2.5,.09),(5,.035)])
        z = .14 + west*(1.7*ridge**1.8+detail) + .025*field.noise(Vector((x*2,y*2,0)))
        distance = min(math.hypot(x-cx,y-cy) for cx,cy in cities)
        blend = min(1, max(0, (distance-.30)/.35))
        return .14 + (z-.14)*blend
    verts, faces = [], []
    nx, ny = 512, 384
    for iy in range(ny+1):
        for ix in range(nx+1):
            x,y = -12+24*ix/nx, -9+18*iy/ny
            verts.append((x,y,height(x,y)))
    for iy in range(ny):
        for ix in range(nx):
            a = iy*(nx+1)+ix
            faces.append((a,a+1,a+nx+2,a+nx+1))
    mesh('连续山川地形',verts,faces,m['grass'],smooth=True)
    water = material('水面', '#426d78', rough=.20, grain=180)
    water.node_tree.nodes['Principled BSDF'].inputs['Coat Weight'].default_value = .35
    box('海水', (0,0,-.04), (24.5,18.5,.06), water, bevel=0)
    rng = random.Random(2401)
    leaves = [material('林冠'+str(i), c, rough=.93, grain=28)
              for i,c in enumerate(['#3f5742','#506b43','#687849','#415c4d'])]
    trunk = m['wood']
    for index in range(320):
        x,y = rng.uniform(-11.7,10.5),rng.uniform(-8,8.7)
        if not is_land(x,y) or min(math.hypot(x-cx,y-cy) for cx,cy in cities) < .92:
            continue
        z=height(x,y);size=rng.uniform(.15,.28)
        rod('林木枝干',(x,y,z),(x,y,z+size*2.9),size*.10,trunk)
        leaf_verts,leaf_faces=[],[]
        for leaf in range(220):
            angle=rng.random()*math.tau;radius=size*math.sqrt(rng.random())
            cx,cy=x+math.cos(angle)*radius,y+math.sin(angle)*radius
            cz=z+size*(1.8+1.6*rng.random())*(1-.12*radius/size)
            length=rng.uniform(.022,.05);width=length*.5;tilt=rng.uniform(-.6,.6)
            a=len(leaf_verts)
            for dx,dy,dz in [(0,-length,0),(width,0,tilt*width),(0,length,0),(-width,0,-tilt*width)]:
                leaf_verts.append((cx+math.cos(angle)*dx-math.sin(angle)*dy,
                                   cy+math.sin(angle)*dx+math.cos(angle)*dy,cz+dz))
            leaf_faces.append((a,a+1,a+2,a+3))
        canopy=mesh('独立叶片林冠',leaf_verts,leaf_faces,leaves[index%len(leaves)])
        for mat in leaves:canopy.data.materials.append(mat)
        for face in canopy.data.polygons:face.material_index=rng.randrange(len(leaves))
    rock=material('山石断层','#70776e',rough=.92,grain=32)
    for i in range(23):
        x,y=rng.uniform(-11.6,-4),rng.uniform(-7.5,8)
        if min(math.hypot(x-cx,y-cy) for cx,cy in cities)<.9:continue
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3,radius=1,location=(x,y,height(x,y)+.15))
        obj=bpy.context.object;obj.name='侵蚀岩峰';obj.scale=(rng.uniform(.25,.5),rng.uniform(.25,.5),rng.uniform(.4,.95))
        obj.data.materials.append(rock)
        for vertex in obj.data.vertices:vertex.co*=rng.uniform(.86,1.12)
    for points in [[(20,27),(40,31),(60,28),(76,34),(95,34),(116,44),(138,34),(174,36)],
                   [(25,80),(48,77),(76,83),(95,93),(123,94),(145,99),(177,93)]]:
        # 水系沿XY曲线密采样，再贴合真实高度，避免Bezier弦段潜入山体形成断流。
        converted=[]
        extended=[points[0],*points,points[-1]]
        for index in range(1,len(extended)-2):
            a,b,c,d=extended[index-1:index+3]
            for step in range(30):
                t=step/30
                xy=[.5*(2*b[i]+(-a[i]+c[i])*t+(2*a[i]-5*b[i]+4*c[i]-d[i])*t*t+
                         (-a[i]+3*b[i]-3*c[i]+d[i])*t*t*t) for i in (0,1)]
                x,y=xy[0]/8-12,9-xy[1]/8
                converted.append((x,y,height(x,y)+.028))
        curve('连续水系',converted,.042,water)
    camera((0,0,0),24,(0,0,30))
    scene.render.filepath=str(output/'matrix_terrain.png')
    bpy.ops.render.render(write_still=True)
    print('SGBY_RENDERED matrix_terrain',flush=True)


def render(output, name, build, target, scale, at=(6, -8, 6), team='#a63a30'):
    m = setup()
    m['team_metal'] = material('阵营漆甲', team, .62, .60, 42)
    m['team_cloth'] = material('阵营织物', team, rough=.88, grain=90)
    build(m)
    shadow_ground(m)
    camera(target, scale, at)
    bpy.context.scene.render.filepath = str(output / (name + '.png'))
    bpy.ops.render.render(write_still=True)
    print('SGBY_RENDERED', name, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', required=True)
    parser.add_argument('--subject', default='all')
    parser.add_argument('--only', type=int)
    parser.add_argument('--mask')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    output = Path(args.out)
    output.mkdir(parents=True, exist_ok=True)
    if args.subject == 'terrain':
        terrain(output, Path(args.mask))
    if args.subject in ['all', 'castle']:
        render(output, 'capital', lambda m: castle(m, True), (0, 0, 1.3), 8.4)
        render(output, 'fort', lambda m: castle(m, False), (0, 0, 1.1), 8.0)
    if args.subject in ['all', 'units']:
        types = [horse, infantry, archer, navy, lambda m: infantry(m, True), scholar]
        for side, tint in [('friendly', '#a83b30'), ('enemy', '#207e87')]:
            for index, build in enumerate(types):
                if args.only is not None and index != args.only:
                    continue
                render(output, f'unit_{index}_{side}', build,
                       (0, 0, 1.9 if index == 0 else 1.35), 4.8 if index == 0 else 3.7,
                       at=(5, -8, 4.5), team=tint)
