"""用逐动作单图替代已淘汰的混乱图集；生成后统一归一化、分色与组帧。"""
from pathlib import Path
import argparse,json
from prepare_handpainted import STYLE


def main():
 p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);args=p.parse_args();root=args.root
 jobs=json.loads((root/'requests.json').read_text());known={j['id'] for j in jobs};selection=json.loads((root/'selection.json').read_text())
 def add(id,prompt,ref,width=512,height=640,**extra):
  if id not in known:
   jobs.append(dict(id=id,prompt=prompt,refs=[ref] if ref else [],kind='sprite',width=width,height=height,seed=248100+len(jobs)*37,**extra));known.add(id)
 add('unit-4-halberd','Edit this exact heavy soldier. ADD ONE SMALL CURVED CRESCENT SILVER SIDE BLADE attached to the TOP spear head immediately below the existing straight silver point. The result is a traditional Chinese ji HALBERD with one straight point and one curved side blade. Keep the plain rounded WOODEN lower shaft with absolutely no lower metal blade. Keep the face, broad bronze shoulder guards, deep red armor, correct hands, boots, camera and uniform green background exactly. No axe at the bottom, no second weapon.', 'generated/unit-4-final.png',type=4)
 masters={0:'unit-0-corrected',1:'unit-1-corrected',2:'unit-2-base',3:'unit-3-base',4:'unit-4-halberd',5:'unit-5-corrected'}
 directions={
 0:['the rider draws his long spear back in his RIGHT HAND, preparing a thrust, his left hand holding the reins of the single complete horse', 'the rider thrusts his ONE long spear horizontally toward screen RIGHT while mounted on the single brown horse. ONE silver spearhead at the far right, a plain wooden butt at the other end. Left hand on reins', 'horse and rider recoil slightly from an impact, the rider leans backward, both stay together with intact correct anatomy'],
 1:['he draws his ONE spear back with the shield raised on his other forearm, preparing to thrust', 'he thrusts his ONE spear toward screen RIGHT. Exactly ONE SILVER SPEARHEAD at the rightmost tip, a plain wood butt at the other end. Shield remains strapped to his left forearm. Two correct hands, no second spear, no sword', 'he recoils from impact, knees bent, shield lowered, still holding his one spear'],
 2:['he draws ONE arrow to his cheek on the taut bowstring with correct two hands and a visible arrow nock, bow aimed screen RIGHT', 'he releases ONE arrow from his recurved bow toward screen RIGHT, correct complete bow and two arms, quiver retained on his back', 'he recoils slightly, knees bent and bow lowered, complete clothed body and intact bow'],
 3:['the one red-armored sailor stands within this ONE intact wooden warship and aims a small bow over the right gunwale, complete red sail and mast retained', 'the one red-armored sailor fires one arrow toward screen RIGHT from the same single intact wooden warship, complete red sail, mast, hull and oars retained', 'the ONE complete ship lists slightly from an impact, red sail leaning, hull remains connected, same tiny red sailor, no water'],
 4:['he braces his wide heavily armored stance and draws his ONE halberd back, keeping the silver point plus curved side blade at its TOP and the plain wooden butt below his hands', 'he swings or thrusts his ONE long halberd toward screen RIGHT from a stable wide stance. ONE point and crescent side blade at its front, plain wood butt at the other end, correct two hands and complete shoulders', 'he recoils, knees bent, broad heavy armor and the ONE correct halberd retained'],
 5:['he raises a BROAD WHITE FEATHER FAN with at least six separate white feather tips, preparing a command, soft red robes and tall black scholar cap retained', 'he gestures his broad WHITE FEATHER FAN toward screen RIGHT, robe sleeves and cloth folds following the arm, calm commanding pose, no weapons and no armor', 'he recoils slightly with knees bent, fan held near his clothed chest, tall black scholar cap and soft red robes retained, no armor'],
 }
 single_actions={};single_defeat={};final_jobs=[]
 for kind,master in masters.items():
  # 文士提示词不携带通用的“层叠金属甲片”，避免模型忽略布袍而把玄兵变成甲兵。
  style=STYLE.replace('layered lamellar armor, ','') if kind==5 else STYLE
  materials='deep RED flowing cloth robes' if kind==5 else 'deep RED clothing and RED armor or sail'
  actions={'idle':master,'stride':master}
  for pose,prompt in zip(['windup','attack','hit'],directions[kind]):
   id=f'unit-{kind}-{pose}-single';actions[pose]=id
   full=style+'Edit the EXACT SAME subject in the reference to show ONLY THIS ONE POSE: '+prompt+'. Exactly ONE SINGLE complete subject, NOT a sprite sheet, NOT a collage, no panels, no duplicated bodies. Keep the exact same identity, headwear, '+materials+', materials, body proportions and camera. Keep natural anatomy. All feet, weapon tips and the entire subject must fit within the frame with wide green margin. Uniform bright green #00ff00 background, no ground, no cast shadow, no text, no labels, no UI. No extra people, no extra horses, no dismemberment, no gore.'
   add(id,full,'generated/'+master+'.png',type=kind,pose=pose)
  death=[]
  for stage in ['kneel','fall','ground']:
   if kind==0:
    pose={'kneel':'the ONE horse is lowering onto its bent knees while its ONE red armored rider loses balance but remains fully visible beside the saddle, all horse and rider anatomy intact','fall':'the ONE horse and its ONE rider are collapsing together onto their side near the ground, rider is completely visible in red armor beside the saddle, NO second horse, no merged bodies','ground':'ONE complete brown horse lies on its SIDE, with its ONE complete red-armored rider lying clearly beside the saddle. The rider has a visible human helmeted head, two arms and two legs. Keep the same red caparison and spear nearby. No other horse, no extra human, no human-horse fusion'}[stage]
   elif kind==3:
    pose={'kneel':'the ONE complete wooden ship lists moderately to its right side, mast and red sail leaning, hull intact','fall':'the ONE wooden ship is tilted low and its mast is leaning sharply, the red canvas sail is loosening and folding down, same intact hull','ground':'the ONE wooden ship rests very low and heavily tilted to its side, its red sail folded and mast leaning, hull still recognizable and connected. No water, no waves, no extra boat'}[stage]
   else:
    pose={'kneel':'the ONE clothed character has buckled onto ONE KNEE with the other knee bent, his upper body leaning forward and his weapon lowered, exactly two arms and two legs, no exposed skin except face and hands','fall':'the ONE clothed character is falling toward his SIDE, one hand braced on the ground and upper body low, with the same complete outfit, headwear and weapon. Exactly two arms and two legs, no extra joints, no exposed knees','ground':'the ONE complete clothed character lies settled on his SIDE at ground level with his head, torso, two arms and two legs connected naturally. His headwear and full red outfit are retained; his ONE original weapon lies beside him. No second body, no extra limbs, no floating objects, no exposed knees'}[stage]
   id=f'unit-{kind}-{stage}-single';death.append(id)
   full=style+'Create ONLY ONE SINGLE defeat pose of the EXACT SAME subject in the reference: '+pose+'. Preserve the exact face, weapon identity, red outfit, original proportions and materials, the same camera, fine hand-painted outlines and soft volume. ONE complete single subject, NOT a sheet, NOT a collage, no panels. Keep the whole subject including weapon within the image, generous margin. Completely flat bright green #00ff00 backdrop, no floor or background objects, no text or labels. No smiles, no nudity, no gore, no blood, no extra figures.'
   add(id,full,'generated/'+master+'.png',type=kind,stage=stage)
  actions['down']=death[-1];single_actions[str(kind)]=actions
  single_defeat[str(kind)]=[actions['hit'],actions['hit'],death[0],death[1],death[2],death[2]]
  final_jobs += [master,*[actions[p] for p in ['windup','attack','hit']],*death]
 selection['masters']={str(k):v for k,v in masters.items()};selection['singleActions']=single_actions;selection['singleDefeat']=single_defeat
 final_jobs+=list(selection['cities'].values())+list(selection['terrains'].values())+list(selection['icons'].values())+list(selection['grounds'].values())+['effects-sheet','ui-paper','strategy-land']+['scene-'+n for n in ['field','river','forest','siege','victory','defeat']]
 (root/'requests.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2)+'\n');(root/'selection.json').write_text(json.dumps(selection,ensure_ascii=False,indent=2)+'\n');(root/'final_jobs.json').write_text(json.dumps(sorted(set(final_jobs),key=final_jobs.index),ensure_ascii=False,indent=2)+'\n')
 print('Final verified plan',len(set(final_jobs)),'sources; new single pose jobs',36)

if __name__=='__main__':main()
