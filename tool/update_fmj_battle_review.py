"""原位更新离线战斗审核页，保留文件URL、案例身份、时长及浏览器审核存储键。"""
from pathlib import Path
import argparse,hashlib,json,os,re,shutil,subprocess,tempfile,zipfile

STORAGE_KEY='fmj-battle-review-v1'

def payload(path):
    source=path.read_text()
    data,_=json.JSONDecoder().raw_decode(source.split('const DATA=',1)[1])
    script=source.rsplit('<script>',1)[1].split('</script>',1)[0]
    match=re.search(r"KEY='([^']+)'",script)
    assert match and match[1]==STORAGE_KEY,'审核记录存储键发生变化，拒绝覆盖'
    return data,script

def identity(case):
    return tuple(case.get(k)for k in('id','group','title','actorType','actor','kind','resource'))

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--artifact',type=Path,required=True)
    parser.add_argument('--sha256',required=True)
    parser.add_argument('--destination',type=Path,required=True)
    parser.add_argument('--render-revision',required=True)
    parser.add_argument('--mirror',type=Path)
    parser.add_argument('--require-classic',action='store_true')
    args=parser.parse_args()
    assert hashlib.sha256(args.artifact.read_bytes()).hexdigest()==args.sha256,'云端产物摘要不匹配'
    before,_=payload(args.destination)
    previous={c['id']:c for c in before['cases']}
    descriptor,filename=tempfile.mkstemp(prefix='.'+args.destination.stem+'-',suffix='.tmp',dir=args.destination.parent)
    os.close(descriptor)
    staged=Path(filename)
    try:
        with zipfile.ZipFile(args.artifact)as archive:
            assert archive.testzip()is None,'压缩包校验失败'
            name=next(n for n in archive.namelist()if n.endswith('.html'))
            with archive.open(name)as source,staged.open('wb')as target:shutil.copyfileobj(source,target)
            manifest=json.loads(archive.read(next(n for n in archive.namelist()if n.endswith('.manifest.json'))))
        data,script=payload(staged)
        assert data['renderRevision']==args.render_revision,'绘制来源不是本轮最新提交'
        assert data['stepMs']==40 and data['speed']==1
        assert len(data['cases'])==len(previous) and len({c['id']for c in data['cases']})==len(previous),'案例数量或唯一编号发生变化'
        assert {c['id']for c in data['cases']}==set(previous),'案例编号有增删'
        if args.require_classic:
            assert data['summary'].get('classicCases')==len(previous),'黑白对照案例未完整导出'
        for case in data['cases']:
            old=previous[case['id']]
            assert identity(case)==identity(old),(case['id'],'案例身份发生变化')
            assert(case['durationMs'],case['simulationFrames'],case['loopGapMs'])==(old['durationMs'],old['simulationFrames'],old['loopGapMs']),(case['id'],'原动作时长发生变化')
            assert case['gifDurationMs']==case['durationMs']+case['loopGapMs']
            if args.require_classic:
                classic=case.get('classic',{})
                assert classic.get('gif')in data['gifs'],(case['id'],'黑白动图缺失')
                for field in('durationMs','simulationFrames','loopGapMs'):
                    assert classic.get(field)==case[field],(case['id'],field,'黑白彩色时长不一致')
        descriptor,js_filename=tempfile.mkstemp(prefix='fmj-battle-review-',suffix='.js')
        os.close(descriptor)
        javascript=Path(js_filename)
        try:
            javascript.write_text(script)
            subprocess.run(['node','--check',str(javascript)],check=True)
        finally:javascript.unlink(missing_ok=True)
        # 验证完成后原子替换，刷新不能读到写到一半的DATA；不读取或写入浏览器存储。
        staged.replace(args.destination)
        manifest.update(previousRenderRevision=before.get('renderRevision'),localHtml=str(args.destination),reviewStorageKey=STORAGE_KEY,caseIdsPreserved=True,caseIdentitiesPreserved=True,timingsPreserved=True)
        args.destination.with_suffix('.manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
        if args.mirror:
            args.mirror.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(args.destination,args.mirror)
            shutil.copy2(args.destination.with_suffix('.manifest.json'),args.mirror.with_suffix('.manifest.json'))
            assert hashlib.sha256(args.destination.read_bytes()).digest()==hashlib.sha256(args.mirror.read_bytes()).digest()
        print(json.dumps(manifest,ensure_ascii=False))
    finally:staged.unlink(missing_ok=True)

if __name__=='__main__':main()
