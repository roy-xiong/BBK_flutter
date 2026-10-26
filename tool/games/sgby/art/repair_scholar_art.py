"""保持玄兵每个动作，纠正生成器误加的甲片、刀和缺失的文士帽。"""
from pathlib import Path
import argparse
import json


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True)
    root=parser.parse_args().root;jobs=json.loads((root/'requests.json').read_text())
    known={j['id'] for j in jobs};plan=[]
    for index,pose in enumerate(['windup','attack','hit','kneel','fall','ground']):
        name='unit-5-'+pose+'-cloth';plan.append(name)
        if name in known:continue
        prompt=('Keep the EXACT CURRENT BODY POSE, camera, face and hand positions. Edit ONLY the outfit and the handheld object of this exact man: '
                'REMOVE ALL METAL ARMOR, shoulder plates, scales, helmets, wrist guards and cuirass. '
                'Replace them with soft dark red layered SCHOLAR ROBES, deep red cloth cloak, ivory under-collar and a wide plain fabric sash. '
                'Add the same tall rectangular BLACK SCHOLAR CAP, worn on his head even in a falling or lying pose. '
                'Keep the mature narrow black beard, modest facial features and cloth shoes. '
                'He holds ONLY a WHITE FEATHER FAN; replace any sword, spear, staff or other weapon entirely with a white feather fan. '
                'Whole outfit is flowing FABRIC, not armor, with long loose sleeves and soft continuous cloth folds. '
                'Same fine hand-painted line art and exact current pose: '+
                {'windup':'raising his feather fan','attack':'gesturing his feather fan forward','hit':'recoiling with knees bent',
                 'kneel':'lowered onto one knee with the other knee bent','fall':'collapsed low onto his side with one hand braced on the floor',
                 'ground':'lying settled on his side, fully clothed with connected natural anatomy'}[pose]+
                '. Do not turn the pose back into standing. Keep the whole man and fan complete inside the image with generous margin. '
                'Uniform flat bright green background, no text, no floor, no additional people.')
        jobs.append(dict(id=name,refs=['generated/unit-5-'+pose+'-single.png'],prompt=prompt,kind='sprite',type=5,pose=pose,width=512,height=640,seed=254400+index*41))
    (root/'requests.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2)+'\n')
    (root/'scholar_jobs.json').write_text(json.dumps(plan,indent=2)+'\n')
    selection=json.loads((root/'selection.json').read_text());actions=selection['singleActions']['5']
    for pose in ['windup','attack','hit']:actions[pose]='unit-5-'+pose+'-cloth'
    actions['down']='unit-5-ground-cloth'
    selection['singleDefeat']['5']=['unit-5-'+pose+'-cloth' for pose in ['hit','hit','kneel','fall','ground','ground']]
    (root/'selection.json').write_text(json.dumps(selection,ensure_ascii=False,indent=2)+'\n')
    print('玄兵六动作只纠正布袍、文士帽与羽扇；终稿不绑定错误甲兵原图。')


if __name__=='__main__':main()
