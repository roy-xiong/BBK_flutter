"""验证共享动效分组和浏览器审核规则；无需运行 Flutter。"""

import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / 'tool/fmj_battle_review_groups.py'
FEEDBACK_PATH = ROOT / 'tool/fmj_battle_review_feedback_round1.json'


class BattleReviewGroupsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if MODULE_PATH.exists():
            spec = importlib.util.spec_from_file_location('review_groups', MODULE_PATH)
            cls.module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(cls.module)

    def require_module(self):
        self.assertTrue(MODULE_PATH.exists(), '缺少可独立验证的共享动效分组模块')
        return self.module

    def test_primary_srs_merges_aliases_and_keeps_status_variants(self):
        module = self.require_module()
        cases = [
            dict(id='a', title='柳清风 · 御魔诀', actorName='柳清风', kind='magic',
                 group='我方技能', movie=16, resource='1:10', skill='御魔诀',
                 observedMovies=['2:16'], all=False),
            dict(id='b', title='慕容小梅 · 苦口婆心', actorName='慕容小梅', kind='magic',
                 group='我方技能', movie=16, resource='1:65', skill='苦口婆心',
                 observedMovies=['2:16', '1:245'], all=True),
            dict(id='c', title='眠', actorName='柳清风', kind='status', group='状态特效',
                 mask=1, observedMovies=['1:246']),
            dict(id='d', title='普通攻击', actorName='柳清风', kind='attack', group='普通攻击'),
            dict(id='e', title='普通攻击', actorName='朱雀', kind='attack', group='普通攻击'),
        ]
        groups = module.build_review_groups(cases, {'reviews': {}})
        self.assertEqual(len(groups), 3)
        shared = next(g for g in groups if g['primarySrs'] == '2:16')
        self.assertEqual(shared['caseIds'], ['a', 'b'])
        self.assertEqual(set(shared['aliases']), {'御魔诀', '苦口婆心'})
        self.assertEqual(shared['observedMovies'], ['2:16', '1:245'])
        self.assertEqual(next(g for g in groups if g['primarySrs'] == '1:246')['caseIds'], ['c'])
        self.assertEqual(next(g for g in groups if g.get('actionKind') == 'attack')['caseIds'], ['d', 'e'])

    def test_history_beats_an_alias_approval_without_becoming_current_feedback(self):
        module = self.require_module()
        cases = [dict(id='a', title='御风行', actorName='小梅', kind='help', group='我方技能', movie=5),
                 dict(id='b', title='疾风步', actorName='萍芷', kind='help', group='我方技能', movie=5)]
        groups = module.build_review_groups(cases, {'reviews': {
            'a': dict(status='未审核', comment='最后是速字', markers=[]),
            'b': dict(status='通过', comment='', markers=[]),
        }})
        self.assertEqual(groups[0]['initialStatus'], '已修改待复审')
        self.assertEqual(groups[0]['historyReviews'][0]['caseId'], 'a')
        self.assertNotIn('comment', groups[0])

    def test_real_catalog_preserves_all_712_cases_and_28_comments(self):
        module = self.require_module()
        requested = os.environ.get('FMJ_REVIEW_CATALOG')
        candidates = [Path(requested)] if requested else [
            ROOT / 'build/battle-review/previous-catalog.json', ROOT / 'build/battle-review/catalog.json']
        catalog_path = next((p for p in candidates if p.exists()), None)
        if catalog_path is None:
            self.skipTest('本地未提供渲染 catalog；可设置 FMJ_REVIEW_CATALOG')
        catalog = json.loads(catalog_path.read_text())
        feedback = json.loads(FEEDBACK_PATH.read_text())
        groups = module.build_review_groups(catalog['cases'], feedback)
        case_ids = [case_id for group in groups for case_id in group['caseIds']]
        self.assertEqual(len(case_ids), 712)
        self.assertEqual(len(set(case_ids)), 712)
        self.assertEqual(set(case_ids), {c['id'] for c in catalog['cases']})
        history = [review for group in groups for review in group['historyReviews']]
        comments = [r for r in history if r['comment'].strip()]
        self.assertEqual(len(comments), 28)
        self.assertIn('case-0056', [r['caseId'] for r in comments])
        for group in groups:
            if group['historyReviews']:
                self.assertEqual(group['initialStatus'], '已修改待复审')
        by_case = {case_id: group for group in groups for case_id in group['caseIds']}
        self.assertIs(by_case['case-0014'], by_case['case-0024'])
        self.assertEqual(by_case['case-0014']['primarySrs'], '2:16')
        self.assertIs(by_case['case-0028'], by_case['case-0058'])
        self.assertEqual(by_case['case-0028']['primarySrs'], '2:5')
        print(f'真实目录：{len(groups)}组 / {len(case_ids)}案例 / {len(comments)}历史文字意见')

    def test_browser_rules_cover_legacy_import_and_text_overrides_approval(self):
        html = (ROOT / 'tool/fmj_battle_review_template.html').read_text()
        match = re.search(r'<script id="review-logic">(.*?)</script>', html, re.S)
        self.assertIsNotNone(match, '缺少可在 Node 中独立执行的审核规则')
        script = match.group(1) + r'''
const assert = require('node:assert/strict');
const group = {id:'srs-2-20',primarySrs:'2:20',caseIds:['case-0021','case-0056'],
  initialStatus:'已修改待复审',historyReviews:[{caseId:'case-0021',comment:'旧意见',markers:[]}]};
assert.equal(ReviewLogic.effectiveStatus({approved:true,comment:'仍需调整',markers:[]},group),'需修改');
assert.equal(ReviewLogic.effectiveStatus({approved:true,status:'通过',comment:'',markers:[{comment:'这里不对'}]},group),'需修改');
assert.equal(ReviewLogic.effectiveStatus({approved:true,comment:'  ',markers:[]},group),'通过');
assert.equal(ReviewLogic.effectiveStatus({approved:false,comment:'',markers:[]},group),'已修改待复审');
const legacy = {documentType:'fmj-color-battle-review',reviews:{
  'case-0021':{status:'通过',comment:'',markers:[]},
  'case-0056':{status:'未审核',comment:'同柳清风的修改意见',markers:[{x:33,y:44,comment:'手的位置'}]}}};
const imported = ReviewLogic.importReviews(legacy,[group]);
const current = imported.reviews[group.id];
assert.equal(ReviewLogic.effectiveStatus(current,group),'需修改');
assert.match(current.comment,/case-0056/);
assert.match(current.comment,/同柳清风/);
assert.equal(current.markers[0].caseId,'case-0056');
const initial=ReviewLogic.normalizeReview(null,group);
assert.equal(initial.comment,'');
assert.equal(initial.markers.length,0);
assert.equal(ReviewLogic.effectiveStatus(initial,group),'已修改待复审');
const exported=ReviewLogic.exportReviews({version:'x',revision:'r'},[group],{[group.id]:current},{});
assert.equal(exported.groupReviews[group.id].groupId,group.id);
assert.deepEqual(exported.groupReviews[group.id].caseIds,group.caseIds);
assert.equal(exported.groupReviews[group.id].primarySrs,'2:20');
assert.equal(exported.groupReviews[group.id].historyReviews.length,1);
assert.equal(exported.groupReviews[group.id].status,'需修改');
const again=ReviewLogic.importReviews(exported,[group]);
assert.equal(again.reviews[group.id].comment,current.comment);
assert.equal(again.histories[group.id].length,1);
assert.equal(ReviewLogic.effectiveStatus(again.reviews[group.id],group),'需修改');
assert.throws(()=>ReviewLogic.importReviews({documentType:'wrong'},[group]));
console.log('浏览器规则：文字/坐标优先、case-0056旧导入、分组导出往返均通过');
'''
        result = subprocess.run(['node', '-'], input=script, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        print(result.stdout.strip())

    def test_builder_validates_real_image_frames_and_embeds_group_history(self):
        """使用真正的黑白／彩色 WebP 验证打包链，避免仅验证字典转换。"""
        from PIL import Image
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            cases = [dict(id=f'case-{index:04d}', title=f'人物{index} · 共用技能',
                          actorType=1, actor=index, actorName=f'人物{index}', group='我方技能',
                          kind='magic', resource=f'1:{index}', movie=16, all=False)
                     for index in (1, 2)]
            catalog = dict(cases=cases, speed=1, stepMs=40, heroes=[], enemies=[],
                           skills=[], movies=[], notes=[])
            (folder / 'catalog.json').write_text(json.dumps(catalog))
            feedback = dict(documentType='fmj-color-battle-review', reviews={
                'case-0001': dict(status='未审核', comment='共用动画需要太极图', markers=[])})
            feedback_path = folder / 'feedback.json'
            feedback_path.write_text(json.dumps(feedback))
            records = [dict(**case, simulationFrames=1, durationMs=40, loopGapMs=600,
                            webpFrames=2, observedMovies=['2:16']) for case in cases]
            for prefix, suffix, colors in [('shard-', '', ('red', 'blue')),
                                            ('classic-shard-', '-classic', ('black', 'white'))]:
                (folder / f'{prefix}0.json').write_text(json.dumps(records))
                for case in cases:
                    frames = [Image.new('RGB', (640, 384), color) for color in colors]
                    frames[0].save(folder / (case['id'] + suffix + '.webp'), format='WEBP',
                                   save_all=True, append_images=frames[1:], duration=[40, 600],
                                   lossless=True, loop=0)
            output = folder / 'review.html'
            command = [sys.executable, str(ROOT / 'tool/build_fmj_battle_review.py'),
                       '--input', str(folder), '--output', str(output), '--feedback', str(feedback_path),
                       '--require-classic', '--render-revision', 'color-sha',
                       '--classic-render-revision', 'classic-sha']
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            manifest = json.loads(output.with_suffix('.manifest.json').read_text())
            self.assertEqual(manifest['cases'], 2)
            self.assertEqual(manifest['classicCases'], 2)
            self.assertEqual(manifest['reviewGroups'], 1)
            self.assertEqual(manifest['historicalReviews'], 1)
            self.assertEqual(manifest['classicRenderRevision'], 'classic-sha')
            html = output.read_text()
            self.assertIn('共用动画需要太极图', html)
            self.assertEqual(html.count('<script type="text/plain" id="fmj-animation-'), 2)
            self.assertNotIn('/*__DATA__*/', html)
            self.assertNotIn('<!--__ANIMATION_ASSETS__-->', html)
            payload = json.loads(re.search(r'<script>const DATA=(.*?);</script>', html).group(1))
            self.assertEqual(payload['reviewGroups'][0]['caseIds'], ['case-0001', 'case-0002'])
            self.assertEqual(payload['reviewGroups'][0]['initialStatus'], '已修改待复审')
            # 同帧数但时长错误仍必须拒绝，避免“1×”仅有标签而未校验实际素材。
            frames = [Image.new('RGB', (640, 384), color) for color in ('red', 'blue')]
            frames[0].save(folder / 'case-0001.webp', format='WEBP', save_all=True,
                           append_images=frames[1:], duration=[80, 600], lossless=True, loop=0)
            invalid = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(invalid.returncode, 0, '时长错误的素材不应通过校验')
            self.assertIn('case-0001', invalid.stderr)

    def test_all_template_scripts_have_valid_javascript_syntax(self):
        html = (ROOT / 'tool/fmj_battle_review_template.html').read_text()
        scripts = re.findall(r'<script(?: [^>]*)?>(.*?)</script>', html, re.S)
        self.assertEqual(len(scripts), 3)
        for script in scripts:
            result = subprocess.run(['node', '--check', '-'], input=script, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
