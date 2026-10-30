"""从当前ROM与脚本枚举战斗美术审核案例，不修改任何游戏运行逻辑。"""
from pathlib import Path
import argparse,json
ROOT=Path(__file__).resolve().parents[1]

def catalog():
    raw=(ROOT/'assets/fmj/game/DAT.LIB').read_bytes();offsets={}
    for h in range(16,8192,3):
        if raw[h]==255:break
        p=8192+h-16;offsets[tuple(raw[h:h+3])]=raw[p]*16384+raw[p+1]+raw[p+2]*256
    def row(key):return raw[offsets[key]:]
    def text(v,i):return v[i:v.index(0,i)].decode('gbk',errors='replace')
    def chain(number,learned=None):
        if (12,1,number)not in offsets:return []
        v=row((12,1,number));return [f'{v[3+i*2]}:{v[4+i*2]}'for i in range(v[2]if learned is None else min(v[2],learned))]
    skills={f'{k[1]}:{k[2]}':{'id':f'{k[1]}:{k[2]}','name':text(row(k),6),'type':row(k)[0],'all':bool(row(k)[3]&128),'movie':row(k)[5],'mp':row(k)[4],'status':row(k)[24]&15,'hp':int.from_bytes(row(k)[18:20],'little'),'detail':text(row(k),26)}for k in offsets if k[0]==4}
    heroes=[{'index':k[2],'name':text(row(k),10),'skills':chain(row(k)[23]),'side':'我方'}for k in offsets if k[:2]==(3,1)]
    enemies=[{'index':k[2],'name':text(row(k),6),'sprite':row(k)[46],'maxMp':min(999,int.from_bytes(row(k)[28:30],'little')),'skills':chain(row(k)[47],row(k)[2]),'side':'敌方'}for k in offsets if k[:2]==(3,3)]
    guide=json.loads((ROOT/'assets/fmj/game/FmjGuideData.json').read_text())
    for script in guide['scripts']:
        for command in script['commands']:
            if command['op']!=44:continue
            args=command['a'];hero=next((h for h in heroes if h['index']==args[0]),None)
            mid=f'{args[1]}:{args[2]}'
            if hero and mid in skills and mid not in hero['skills']:hero['skills'].append(mid)
    cases=[]
    def add(group,name,actor_type=1,actor=1,**values):
        cases.append({'id':f'case-{len(cases)+1:04d}','group':group,'title':name,'actorType':actor_type,'actor':actor,**values})
    for hero in heroes:
        for mid in hero['skills']:
            m=skills[mid];add('我方技能',f"{hero['name']} · {m['name']}",actor=hero['index'],kind='help'if m['type']not in(1,5)else'magic',resource=mid,movie=m['movie'],all=m['all'],actorName=hero['name'],availability='角色技能表／剧情学习',skill=m['name'])
    for enemy in enemies:
        automatic={next((mid for mid in enemy['skills']if skills[mid]['type']==ty and skills[mid]['mp']<mp),None)for ty in(1,3)for mp in range(1,enemy['maxMp']+1)}-{None}
        for mid in enemy['skills']:
            m=skills[mid];add('敌方技能',f"{enemy['name']}〔{enemy['index']}〕 · {m['name']}",actor_type=3,actor=enemy['index'],kind='help'if m['type']not in(1,5)else'magic',resource=mid,movie=m['movie'],all=m['all'],actorName=enemy['name'],availability='当前AI可选（真气筛选后的首个同类技能，另受血量/概率条件限制）'if mid in automatic else'资源定义预览：当前AI不主动选用这项',skill=m['name'])
    assigned={c['resource']for c in cases}
    for mid,m in skills.items():
        if mid not in assigned:add('未分配技能',f"未分配技能 · {m['name']}",kind='help'if m['type']not in(1,5)else'magic',resource=mid,movie=m['movie'],all=m['all'],actorName='柳清风（预览载体）',availability='当前角色/敌人技能表及学习脚本未分配；只展示资源',skill=m['name'])
    for actor in [*heroes,*enemies]:
        ty=1 if actor['side']=='我方'else 3
        add('普通攻击',f"{actor['name']}〔{actor['index']}〕 · 普通攻击",ty,actor['index'],kind='attack',actorName=actor['name'],availability='正常攻击动作')
    for hero in heroes:
        for variant,title in [('hit','受击'),('weak','虚弱待机'),('death','倒地'),('self','混乱自伤'),('defend','防御'),('flee-fail','逃跑失败'),('flee-success','逃跑成功'),('poison','毒伤结算')]:
            add('我方状态与动作',f"{hero['name']} · {title}",actor=hero['index'],kind=variant,actorName=hero['name'],availability='当前状态机表现')
        for mask,title in [(1,'眠'),(2,'封'),(4,'乱'),(8,'毒'),(32,'攻击变化'),(64,'防御变化'),(128,'速度变化')]:
            add('状态特效',f"{hero['name']} · {title}",actor=hero['index'],kind='status',mask=mask,actorName=hero['name'],availability='受击上浮后的原SRS状态效果')
    for enemy in enemies:
        add('敌方受击与退场',f"{enemy['name']}〔{enemy['index']}〕 · 受击与死亡退场",3,enemy['index'],kind='death',actorName=enemy['name'],availability='正常受击、死亡后隐藏')
    for mask,title in [(1,'眠'),(2,'封'),(4,'乱'),(8,'毒'),(32,'攻击变化'),(64,'防御变化'),(128,'速度变化')]:
        add('状态特效',f'敌方 · {title}',3,44,kind='status',mask=mask,actorName='天道（敌方示例）',availability='敌方状态效果，使用敌方坐标锚点')
    for k in offsets:
        if k[0]!=6 or k[1]not in(7,8,9,10,11,12):continue
        v=row(k);throw=k[1]in(7,8);name=text(v,6)
        add('投掷物与药品',f'{"投掷"if throw else"使用"} · {name}',kind='throw'if throw else'item',resource=f'{k[1]}:{k[2]}',movie=v[26],all=bool(v[28]&16),actorName='柳清风',availability='需允许投掷武器时可用'if k[1]==7 else'战斗物品入口',skill=name)
    for k in offsets:
        if k[:2]!=(6,6)or row(k)[28]==0:continue
        v=row(k);mid=f'1:{v[28]}';m=skills[mid]
        add('合击',f'三人合击 · {text(v,6)} / {m["name"]}',kind='coop',equipment=f'6:{k[2]}',resource=mid,movie=m['movie'],all=True,actorName='柳清风＋慕容小梅＋袁萍芷',availability='按当前第一位角色首个饰品所指定的合击技能',skill=m['name'])
    add('合击','三人合击 · 无指定饰品的默认效果',kind='coop',movie=240,all=True,actorName='三人队伍',availability='当前默认合击分支')
    # 原动画库单列，避免技能共用动画、未分配动画被误认为有遗漏。
    for k in offsets:
        if k[:2]!=(5,2):continue
        add('战斗动画库',f'SRS 2:{k[2]} · 原始战斗动画',kind='movie',movie=k[2],all=False,actorName='独立特效预览',availability='原始动画资源；命名与使用者见关联案例')
    for m in skills.values():
        m['cases']=[c['id']for c in cases if c.get('resource')==m['id']]
    movies=[{'id':k[2],'cases':[c['id']for c in cases if c.get('movie')==k[2]and c['kind']!='movie']}for k in offsets if k[:2]==(5,2)]
    return {'schema':1,'stepMs':40,'speed':1,'renderSize':[640,384],'heroes':heroes,'enemies':enemies,'skills':list(skills.values()),'movies':movies,'cases':cases,'notes':['所有动图来自当前正式Painter与原状态机，固定runSpeed=1，每个模拟步40ms。','每项覆盖完整施法/攻击过程；角色的攻击目标采用代表性对手，不展开所有目标排列组合。','敌方技能表中的未选用定义与未分配技能单独标记，不能据资源预览推断正常战斗会施放。','道具共享同一我方施法动作，逐个列出道具效果，不重复穷举三人对每个目标的组合。']}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=ROOT/'build/battle-review/catalog.json');args=parser.parse_args()
    data=catalog();args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    from collections import Counter
    print(json.dumps({'cases':len(data['cases']),'groups':dict(Counter(c['group']for c in data['cases'])),'skills':len(data['skills']),'movies':len(data['movies'])},ensure_ascii=False))
if __name__=='__main__':main()
