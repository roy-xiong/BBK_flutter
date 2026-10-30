"""从与文档相同的反馈和统一要求导出定向审核范围；不加载渲染器或图片。"""

import argparse
import json
from pathlib import Path

from fmj_battle_review_groups import build_review_groups, build_review_scope


ROOT = Path(__file__).resolve().parents[1]


def main():
    """只输出JSON；可选--output落盘，供CI渲染器读取同一caseIds作为唯一选择依据。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, default=ROOT / 'build/battle-review', help='包含catalog.json的raw目录')
    parser.add_argument('--catalog', type=Path, help='显式指定catalog文件，优先于--input')
    parser.add_argument('--feedback', type=Path, default=ROOT / 'tool/fmj_battle_review_feedback_round3.json')
    parser.add_argument('--scope', type=Path, default=ROOT / 'tool/fmj_battle_review_scope_round4.json')
    parser.add_argument('--no-scope', action='store_true', help='不附加聊天统一要求，仅按文字／坐标意见选取')
    parser.add_argument('--output', type=Path, help='可选输出JSON文件；stdout始终输出相同JSON')
    args = parser.parse_args()
    catalog = json.loads((args.catalog or args.input / 'catalog.json').read_text())
    feedback = json.loads(args.feedback.read_text())
    instruction = None if args.no_scope else json.loads(args.scope.read_text())
    groups = build_review_groups(catalog['cases'], feedback, instruction)
    payload = json.dumps(build_review_scope(groups, feedback), ensure_ascii=False, indent=2) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload)
    print(payload, end='')


if __name__ == '__main__':
    main()
