"""汇总同一战斗状态机的黑白/彩色无损动图，生成保留审核编号的单文件文档。"""
from pathlib import Path
from collections import Counter
import argparse
import base64
import gzip
import hashlib
import json
import subprocess
from datetime import datetime
from zoneinfo import ZoneInfo
from PIL import Image
from fmj_battle_review_groups import build_review_groups, build_review_scope, feedback_round

ROOT = Path(__file__).resolve().parents[1]


def read_records(folder, pattern):
    records = {}
    for path in sorted(folder.glob(pattern)):
        for case in json.loads(path.read_text()):
            assert case['id'] not in records, ('duplicate case', case['id'])
            records[case['id']] = case
    return records


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--render-revision')
    parser.add_argument('--classic-render-revision', help='复用原版黑白 raw 时记录其真实绘制提交')
    parser.add_argument('--feedback', type=Path, default=ROOT / 'tool/fmj_battle_review_feedback_round3.json',
                        help='内嵌上一轮共享组或逐案例反馈；默认使用仓库固定第三轮反馈')
    parser.add_argument('--scope', type=Path, default=ROOT / 'tool/fmj_battle_review_scope_round4.json',
                        help='补充统一要求；仅在绑定的feedbackExportedAt匹配时启用')
    parser.add_argument('--no-scope', action='store_true', help='不附加统一要求，仅按文字／坐标意见确定范围')
    parser.add_argument('--require-classic', action='store_true')
    parser.add_argument('--input', type=Path, default=ROOT / 'build/battle-review')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/battle-review/伏魔记-彩色战斗全案例动图审核.html')
    args = parser.parse_args()
    data = json.loads((args.input / 'catalog.json').read_text())
    feedback = json.loads(args.feedback.read_text())
    instruction = None if args.no_scope else json.loads(args.scope.read_text())
    assert feedback.get('documentType') in ('fmj-color-battle-review', 'fmj-color-battle-review-groups'), '历史意见文件类型不正确'
    assert data.get('speed') == 1 and data.get('stepMs') == 40, '审核仅接受原40ms时钟的1倍速raw'
    records = read_records(args.input, 'shard-*.json')
    originals = read_records(args.input, 'classic-shard-*.json')
    ids = {case['id'] for case in data['cases']}
    assert set(records) == ids, '彩色案例缺失，不能生成不完整文档'
    if args.require_classic or originals:
        assert set(originals) == ids, '黑白案例缺失，不能生成不完整对比文档'
    animations, identities = {}, {}

    def animation(case, suffix=''):
        name = case['id'] + suffix
        extension = 'webp' if (args.input / (name + '.webp')).exists() else 'gif'
        path = args.input / (name + '.' + extension)
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        frames = case.get('webpFrames') if extension == 'webp' else case.get('gifFrames')
        assert isinstance(frames, int) and frames > 0, (name, '缺少有效帧数')
        with Image.open(path) as image:
            assert image.size == (640, 384), name
            duration = 0
            for frame in range(image.n_frames):
                image.seek(frame)
                image.load()
                duration += image.info.get('duration', 0)
            assert duration == case['durationMs'] + case['loopGapMs'], name
            assert image.n_frames == frames, name
        identity = identities.setdefault(digest, name)
        if identity not in animations:
            animations[identity] = base64.b64encode(gzip.compress(raw, compresslevel=9, mtime=0)).decode()
        return dict(gif=identity, sha256=digest, imageExtension=extension,
                    imageMime='image/' + extension, imageBytes=len(raw), imageFrames=frames)

    for source in data['cases']:
        case = {**records[source['id']], **source}
        if records[source['id']].get('assetRenderRevision'):
            case['assetRenderRevision'] = records[source['id']]['assetRenderRevision']
        case.update(animation(case))
        if originals:
            original = originals[source['id']]
            for field in ('id', 'actorType', 'actor', 'kind', 'resource', 'movie', 'all', 'mask',
                          'equipment', 'durationMs', 'simulationFrames', 'loopGapMs'):
                assert original.get(field) == case.get(field), (case['id'], field, '黑白/彩色未对齐')
            case['classic'] = {**animation(original, '-classic'),
                               'assetRenderRevision': original.get('assetRenderRevision') or args.classic_render_revision,
                               'durationMs': original['durationMs'],
                               'simulationFrames': original['simulationFrames'],
                               'loopGapMs': original['loopGapMs']}
        records[source['id']] = case
    data['cases'] = [records[case['id']] for case in data['cases']]
    data['reviewSchema'] = 4
    data['reviewGroups'] = build_review_groups(data['cases'], feedback, instruction)
    data['feedbackRound'] = feedback_round(feedback)
    data['reviewScope'] = build_review_scope(data['reviewGroups'], feedback)
    data['reviewRoundId'] = data['reviewScope']['reviewRoundId']
    # 分块储存大体积动画，只解压当前一对，避免浏览器单段JS字符串超限。
    data.update(gifs={key: 'fmj-animation-' + key for key in animations},
                gifEncoding='gzip-base64', assetStorage='inert-script')
    data['revision'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    data['renderRevision'] = args.render_revision or data['revision']
    data['classicRenderRevision'] = (args.classic_render_revision or data['revision']) if originals else None
    data['version'] = next(line.split(':', 1)[1].strip() for line in (ROOT / 'pubspec.yaml').read_text().splitlines() if line.startswith('version:'))
    data['createdAt'] = datetime.now(ZoneInfo('Asia/Shanghai')).isoformat(timespec='seconds')
    data['summary'] = dict(cases=len(records), classicCases=len(originals), uniqueGifs=len(animations),
                           heroes=len(data['heroes']), enemyDefinitions=len(data['enemies']),
                           skills=len(data['skills']), movies=len(data['movies']),
                           simulationFrames=sum(case['simulationFrames'] for case in records.values()),
                           durationMs=sum(case['durationMs'] for case in records.values()),
                           groups=dict(Counter(case['group'] for case in data['cases'])),
                           reviewGroups=len(data['reviewGroups']),
                           writtenFeedbackGroups=len(data['reviewScope']['writtenFeedbackGroupIds']),
                           globalInstructionGroups=len(data['reviewScope']['globalInstructionGroupIds']),
                           globalInstructionCount=len(data['reviewScope']['globalInstructions']),
                           reviewGroupStates=dict(Counter(group['initialStatus'] for group in data['reviewGroups'])),
                           historicalReviews=sum(len(group['historyReviews']) for group in data['reviewGroups']),
                           latestFeedbackReviews=sum(row['roundId'] == data['feedbackRound']['id']
                                                     for group in data['reviewGroups'] for row in group['historyReviews']),
                           olderHistoricalReviews=sum(row['roundId'] != data['feedbackRound']['id']
                                                      for group in data['reviewGroups'] for row in group['historyReviews']))
    payload = json.dumps(data, ensure_ascii=False, separators=(',', ':')).replace('</', '<\\/')
    template = (ROOT / 'tool/fmj_battle_review_template.html').read_text()
    before, after = template.replace('/*__DATA__*/', 'const DATA=' + payload + ';').split('<!--__ANIMATION_ASSETS__-->', 1)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('w') as stream:
        stream.write(before)
        for key, encoded in animations.items():
            stream.write('<script type="text/plain" id="fmj-animation-' + key + '">' + encoded + '</script>\n')
        stream.write(after)
    manifest = {**data['summary'], 'revision': data['revision'], 'renderRevision': data['renderRevision'],
                'reviewRoundId': data['reviewRoundId'], 'reviewScope': data['reviewScope'],
                'classicRenderRevision': data['classicRenderRevision'], 'version': data['version'],
                'createdAt': data['createdAt'], 'htmlBytes': args.output.stat().st_size,
                'animationBytes': sum(case['imageBytes'] + case.get('classic', {}).get('imageBytes', 0) for case in records.values())}
    args.output.with_suffix('.manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(manifest, ensure_ascii=False))


if __name__ == '__main__':
    main()
