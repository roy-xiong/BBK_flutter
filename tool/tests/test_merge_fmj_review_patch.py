from pathlib import Path
import importlib.util,json,subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location('merge_patch',ROOT/'tool/merge_fmj_review_patch.py')
MODULE=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(MODULE)

class PatchMergeTest(unittest.TestCase):
    def setup_files(self,folder):
        feedback=json.loads((ROOT/'tool/fmj_battle_review_feedback_round2.json').read_text())
        selected=MODULE.selections(feedback);self.assertEqual(len(selected),48)
        entries=[]
        for index in range(1,713):
            id=f'case-{index:04d}'
            entries.append(dict(id=id,actorType=1,actor=1,kind='magic',resource='1:1',movie=1,all=False,durationMs=80,simulationFrames=2,loopGapMs=600,webpFrames=2))
            (folder/(id+'.webp')).write_bytes(('old:'+id).encode())
        for shard in range(4):(folder/f'shard-{shard}.json').write_text(json.dumps(entries[shard::4]))
        self.run_command(folder,'--record-base',success=True)
        patch=[e.copy()for e in entries if e['id']in selected]
        for e in patch:(folder/(e['id']+'.webp')).write_bytes(('new:'+e['id']).encode())
        for shard in range(4):(folder/f'patch-shard-{shard}.json').write_text(json.dumps(patch[shard::4]))
        return selected,patch
    def run_command(self,folder,*args,success):
        result=subprocess.run(['python3',str(ROOT/'tool/merge_fmj_review_patch.py'),'--input',str(folder),'--feedback',str(ROOT/'tool/fmj_battle_review_feedback_round2.json'),*args],cwd=ROOT,capture_output=True,text=True)
        self.assertEqual(result.returncode==0,success,result.stderr)
        return result
    def test_only_48_written_cases_replace_and_other_664_keep_bytes(self):
        with tempfile.TemporaryDirectory()as tmp:
            folder=Path(tmp);selected,_=self.setup_files(folder)
            self.run_command(folder,success=True)
            report=json.loads((folder/'patch-verification.json').read_text())
            self.assertEqual(report['reusedCases'],664);self.assertEqual(set(report['rerenderedIds']),selected)
            merged=MODULE.records(folder,'shard-*.json');self.assertEqual(len(merged),712)
            for id in merged:
                self.assertEqual((folder/(id+'.webp')).read_bytes(),(('new:'if id in selected else'old:')+id).encode())
    def test_changed_approved_file_rejected(self):
        with tempfile.TemporaryDirectory()as tmp:
            folder=Path(tmp);self.setup_files(folder)
            (folder/'case-0001.webp').write_bytes(b'not authorized')
            result=self.run_command(folder,success=False)
            self.assertIn('已通过的文件被改动',result.stderr)
    def test_changed_timing_rejected(self):
        with tempfile.TemporaryDirectory()as tmp:
            folder=Path(tmp);_,patch=self.setup_files(folder)
            row=patch[0];row['durationMs']=120
            shard=0;p=folder/f'patch-shard-{shard}.json';rows=json.loads(p.read_text());rows[0]=row;p.write_text(json.dumps(rows))
            result=self.run_command(folder,success=False)
            self.assertIn('原案例身份或时序变化',result.stderr)
    def test_next_round_preserves_previously_approved_patch_and_revision(self):
        with tempfile.TemporaryDirectory()as tmp:
            folder=Path(tmp);previous,_=self.setup_files(folder)
            self.run_command(folder,'--render-revision','previous-approved-render',success=True)
            self.run_command(folder,'--record-base',success=True)
            base=MODULE.records(folder,'shard-*.json')
            for path in folder.glob('patch-shard-*.json'):path.unlink()
            selected='case-0002';scope=folder/'scope.json';scope.write_text(json.dumps({'caseIds':[selected]}))
            (folder/(selected+'.webp')).write_bytes(b'new sword appearance')
            (folder/'patch-shard-0.json').write_text(json.dumps([base[selected]]))
            self.run_command(folder,'--scope',str(scope),'--render-revision','current-sword-render',success=True)
            merged=MODULE.records(folder,'shard-*.json')
            for id in previous:
                self.assertEqual(merged[id]['assetRenderRevision'],'previous-approved-render')
                self.assertEqual((folder/(id+'.webp')).read_bytes(),('new:'+id).encode())
            self.assertEqual(merged[selected]['assetRenderRevision'],'current-sword-render')
            self.assertEqual(json.loads((folder/'patch-verification.json').read_text())['reusedCases'],711)
if __name__=='__main__':unittest.main()
