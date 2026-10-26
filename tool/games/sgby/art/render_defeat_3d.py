"""逐关节制作受击、跪倒、侧倒、落地六帧；统一相机和脚下锚点，不逐帧裁切。"""
from pathlib import Path
import argparse,math,sys
import bpy
from mathutils import Vector,Matrix
sys.path.insert(0,str(Path(__file__).resolve().parent))
import render_production_3d as production
import render_3d_study as art


def body(m,kind,phase):
    """上身保持成组，腿、手臂和掉落兵器分别按关节放置，避免整个人像木板翻倒。"""
    poses=[((0,0,1.05),(-.10,.02,1.76)),((0,.08,.67),(.19,-.05,1.34)),
           ((.08,0,.35),(.68,-.08,.63)),((.20,0,.23),(.89,-.07,.28))]
    index=min(2,int(phase));blend=phase-index
    hip,shoulder=[Vector(poses[index][j]).lerp(Vector(poses[index+1][j]),blend) for j in range(2)]
    original=Vector((0,0,1.05));q=Vector((0,0,1)).rotation_difference((shoulder-hip).normalized())
    matrix=Matrix.Translation(hip)@q.to_matrix().to_4x4()@Matrix.Translation(-original)
    art.human(m,pose='archer' if kind==2 else 'heavy' if kind==4 else 'infantry',armored=kind!=5)
    # 移除原直立四肢，按当前关节坐标重建，身体甲片和头部不会互相分离。
    prefixes=('袴腿','胫甲','战靴','上臂','护臂','护肩','手掌','握持手指')
    for obj in list(bpy.context.scene.objects):
        if obj.type in {'MESH','CURVE'} and obj.name.startswith(prefixes):bpy.data.objects.remove(obj,do_unlink=True)
    bpy.context.view_layer.update()
    for obj in list(bpy.context.scene.objects):
        if obj.type in {'MESH','CURVE'}:obj.matrix_world=matrix@obj.matrix_world
    for side in [-1,1]:
        pelvis=hip+q@Vector((side*.16,0,0))
        knee_poses=[(side*.18,-.10,.57),(side*.23,-.25,.20),(-.12,side*.20,.16),(-.22,side*.16,.12)]
        ankle_poses=[(side*.22,-.04,.15),(side*.25,.16,.10),(-.49,side*.23,.10),(-.68,side*.20,.08)]
        knee=Vector(knee_poses[index]).lerp(Vector(knee_poses[index+1]),blend)
        ankle=Vector(ankle_poses[index]).lerp(Vector(ankle_poses[index+1]),blend)
        art.rod('折膝袴腿',pelvis,knee,.125,m['team_cloth'],.10)
        art.rod('落地胫甲',knee,ankle,.105,m['team_metal'] if kind!=5 else m['leather'],.073)
        art.ellipsoid('落地战靴',ankle+Vector((0,-.06,-.025)),(.105,.17,.075),m['leather'])
        start=hip+q@Vector((side*.32,0,.72))
        if phase<2:hand=hip+q@Vector((side*.48,-.17,.18 if phase==1 else .33))
        else:hand=Vector((.93 if side<0 else .56,-.43 if side<0 else .22,.09))
        elbow=start*.5+hand*.5+Vector((0,-.10,.06))
        art.rod('屈臂',start,elbow,.105,m['team_cloth'],.085)
        art.rod('垂落护腕',elbow,hand,.09,m['team_metal'] if kind!=5 else m['leather'],.066)
        art.ellipsoid('着地手掌',hand,(.075,.065,.06),m['skin'])
        art.ellipsoid('屈肩甲',start,(.17,.17,.07),m['team_metal'])
    if kind==4:
        for side in [-1,1]:
            point=hip+q@Vector((side*.33,0,.77));art.ellipsoid('极兵肩吞',point,(.20,.17,.10),m['gold'])
    if kind==5:
        # 冠帽与羽扇保留玄兵身份，头部始终跟随上身。
        a=matrix@Vector((0,0,2.42));b=matrix@Vector((0,0,2.77));art.rod('玄兵冠',a,b,.11,m['hair'],.09)
    weapon_end=Vector((1.4,-.39,.07)) if phase>=2 else Vector((.78,-.38,.18))
    weapon_top=Vector((-.72,-.40,.10)) if phase>=2 else Vector((.70,-.38,2.6-phase*.9))
    if kind==2:
        center=Vector((.6,-.42,.10 if phase>=2 else .8))
        art.curve('落弓',[center+Vector((math.sin(t)*.4,0,math.cos(t)*(.04 if phase>=2 else .4))) for t in [i*math.pi/12 for i in range(13)]],.025,m['wood_light'])
    elif kind==5:
        art.rod('散落扇柄',weapon_end,weapon_end+Vector((-.3,0,.01)),.024,m['wood_light'])
        for i in range(7):
            angle=-.7+i*.22;art.rod('落地羽扇',weapon_end+Vector((-.25,0,0)),weapon_end+Vector((-.25+math.cos(angle)*.55,math.sin(angle)*.35,.02)),.035,m['linen'],.014)
    else:
        art.rod('掉落长兵器',weapon_end,weapon_top,.023,m['wood_light'])
        d=(weapon_top-weapon_end).normalized();art.rod('落刃',weapon_top,weapon_top+d*.3,.055,m['steel'],0)
        if kind==1:
            art.ellipsoid('掉落木盾',(.1,-.40,.13 if phase>=2 else .8),(.28,.32 if phase>=2 else .07,.06 if phase>=2 else .37),m['wood'])


def mounted(m,phase):
    """骑兵保留战马与骑手不同的运动；只表现失衡和倒地，不把整匹马凭空翻飞。"""
    art.horse(m);bpy.context.view_layer.update()
    objects=[o for o in bpy.context.scene.objects if o.type in {'MESH','CURVE'}]
    # 马体绕脚下重心降低，骑手随失衡方向偏离马鞍；最后阶段贴地。
    values=[.04,.24,.80,1.38];index=min(2,int(phase));angle=values[index]+(values[index+1]-values[index])*(phase-index);pivot=Vector((0,0,.28))
    rotation=Matrix.Rotation(angle,4,'Y')
    for obj in objects:obj.matrix_world=Matrix.Translation(pivot)@rotation@Matrix.Translation(-pivot)@obj.matrix_world
    bpy.context.view_layer.update()
    min_z=min((o.matrix_world@Vector(c)).z for o in objects for c in o.bound_box)
    for obj in objects:obj.location.z+=.025-min_z


def naval(m,phase):
    art.navy(m);bpy.context.view_layer.update()
    bpy.data.objects['鼓风帆'].data.materials[0]=m['team_cloth']
    objects=[o for o in bpy.context.scene.objects if o.type in {'MESH','CURVE'}]
    values=[.03,.12,.28,.48];index=min(2,int(phase));angle=values[index]+(values[index+1]-values[index])*(phase-index)
    production.transform(objects,(0,0,.2),Matrix.Rotation(angle,3,'Y'))
    depths=[0,.08,.22,.45];depth=depths[index]+(depths[index+1]-depths[index])*(phase-index)
    for obj in objects:obj.location.z-=depth


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--side',choices=['friendly','enemy'],required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    for kind in range(6):
        for phase in range(6):
            name=f'fall_{kind}_{args.side}_{phase}'
            if (production.OUT/(name+'.png')).exists():continue
            m=production.setup('#ab3a30' if args.side=='friendly' else '#227c88',resolution=(320,320),samples=24)
            if kind==0:mounted(m,phase*3/5)
            elif kind==3:naval(m,phase*3/5)
            else:body(m,kind,phase*3/5)
            art.shadow_ground(m)
            # 各帧共享相机、画幅和地面锚点；打包时也不按单帧包围盒重新放大。
            art.camera((.15,0,1.1),5.0 if kind==0 else 4.2,(5,-8,4.5))
            production.save(name)

if __name__=='__main__':main()
