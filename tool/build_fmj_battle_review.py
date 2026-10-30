"""汇总真实战斗GIF及完整角色/技能索引，生成单文件深色审核文档。"""
from pathlib import Path
from collections import Counter
import argparse,base64,gzip,hashlib,json,subprocess
from datetime import datetime
from zoneinfo import ZoneInfo
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser();p.add_argument('--render-revision');p.add_argument('--input',type=Path,default=ROOT/'build/battle-review');p.add_argument('--output',type=Path,default=ROOT/'build/battle-review/伏魔记-彩色战斗全案例动图审核.html');a=p.parse_args()
    data=json.loads((a.input/'catalog.json').read_text());records={}
    for f in sorted(a.input.glob('shard-*.json')):
        for c in json.loads(f.read_text()):assert c['id']not in records;records[c['id']]=c
    assert set(records)=={c['id']for c in data['cases']},'案例缺失，不能生成不完整文档'
    gifs={};identities={};total_frames=0;total_duration=0
    for c in data['cases']:
        item={**records[c['id']],**c};records[c['id']]=item;raw=(a.input/(c['id']+'.gif')).read_bytes();digest=hashlib.sha256(raw).hexdigest()
        with Image.open(a.input/(c['id']+'.gif'))as im:
            assert im.size==(640,384)
            ms=0
            for frame in range(im.n_frames):im.seek(frame);ms+=im.info.get('duration',0)
            assert ms==item['durationMs']+item['loopGapMs'],c['id']
            assert im.n_frames==item['gifFrames']
        identity=identities.setdefault(digest,c['id'])
        if identity not in gifs:gifs[identity]=base64.b64encode(gzip.compress(raw,compresslevel=9,mtime=0)).decode()
        item['gif']=identity;item['sha256']=digest;total_frames+=item['simulationFrames'];total_duration+=item['durationMs']
    data['cases']=[records[c['id']]for c in data['cases']];data['gifs']=gifs;data['gifEncoding']='gzip-base64'
    data['revision']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    data['renderRevision']=a.render_revision or data['revision']
    data['version']=next(l.split(':',1)[1].strip()for l in(ROOT/'pubspec.yaml').read_text().splitlines()if l.startswith('version:'))
    data['createdAt']=datetime.now(ZoneInfo('Asia/Shanghai')).isoformat(timespec='seconds')
    data['summary']={'cases':len(records),'uniqueGifs':len(gifs),'heroes':len(data['heroes']),'enemyDefinitions':len(data['enemies']),'skills':len(data['skills']),'movies':len(data['movies']),'simulationFrames':total_frames,'durationMs':total_duration,'groups':dict(Counter(c['group']for c in data['cases']))}
    template=(ROOT/'tool/fmj_battle_review_template.html').read_text();payload=json.dumps(data,ensure_ascii=False,separators=(',',':')).replace('</','<\\/')
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(template.replace('/*__DATA__*/','const DATA='+payload+';'))
    manifest={**data['summary'],'revision':data['revision'],'renderRevision':data['renderRevision'],'version':data['version'],'createdAt':data['createdAt'],'htmlBytes':a.output.stat().st_size,'gifBytes':sum((a.input/(c['id']+'.gif')).stat().st_size for c in data['cases'])}
    a.output.with_suffix('.manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(manifest,ensure_ascii=False))
if __name__=='__main__':main()
