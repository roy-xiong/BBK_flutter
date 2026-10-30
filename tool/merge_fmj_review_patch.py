"""把本轮有字的10组48案例叠加到上轮原文件，逐文件证明通过的案例没有变化。"""
from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[1]

def records(folder,pattern):
    result={}
    for p in sorted(folder.glob(pattern)):
        for row in json.loads(p.read_text()):
            assert row['id']not in result,('重复案例',row['id'])
            result[row['id']]=row
    return result

def selections(feedback):
    rows=feedback['groupReviews']
    return {id for r in rows.values()if str(r.get('comment')or'').strip()or any(str(m.get('comment')or'').strip()for m in r.get('markers',[]))for id in r['caseIds']}

def assets(folder):
    return {p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in folder.iterdir()if p.suffix in('.gif','.webp')and '-classic'not in p.name}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--record-base',action='store_true');parser.add_argument('--input',type=Path,default=ROOT/'build/battle-review');args=parser.parse_args()
    folder=args.input;before=folder/'base-assets.json'
    if args.record_base:
        data=assets(folder);assert len(records(folder,'shard-*.json'))==712
        before.write_text(json.dumps(data));print('记录上轮彩色资源',len(data));return
    source=json.loads(before.read_text());current=assets(folder)
    feedback=json.loads((ROOT/'tool/fmj_battle_review_feedback_round2.json').read_text())
    selected=selections(feedback);assert len(selected)==48
    base=records(folder,'shard-*.json');patch=records(folder,'patch-shard-*.json');assert set(patch)==selected
    for id,entry in base.items():
        entry['assetRenderRevision']='a255ab13b0b9cdcec59ec5b650d31b3309353c8f'
        if id in selected:
            replacement=patch[id]
            for key in('id','actorType','actor','kind','resource','movie','all','mask','equipment','durationMs','simulationFrames','loopGapMs'):
                assert entry.get(key)==replacement.get(key),(id,key,'原案例身份或时序变化')
            replacement['assetRenderRevision']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
            extension='.webp'if replacement.get('webpFrames')else'.gif'
            assert(folder/(id+extension)).is_file(),(id,'本轮动图文件缺失')
            # 编码器可能把完全静止的WebP改为带时长GIF；不能误读上轮残留的另一格式。
            (folder/(id+('.gif'if extension=='.webp'else'.webp'))).unlink(missing_ok=True)
            base[id]=replacement
        else:
            for ext in('.webp','.gif'):
                name=id+ext
                if name in source:assert current.get(name)==source[name],(id,'已通过的文件被改动')
    ids=list(base)
    for shard in range(4):
        (folder/f'shard-{shard}.json').write_text(json.dumps([base[id]for id in ids if (int(id.split('-')[1])-1)%4==shard],ensure_ascii=False))
    report={'sourceCases':712,'rerenderedCases':len(selected),'reusedCases':712-len(selected),'approvedAssetHashesUnchanged':True,'rerenderedIds':sorted(selected)}
    (folder/'patch-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False))
if __name__=='__main__':main()
