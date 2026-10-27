"""公开呈现连续回放的最后步骤，失败时无需下载私有 CI 日志定位断点。"""
import json
import os
from pathlib import Path

target = os.environ.get('GITHUB_STEP_SUMMARY')
trace = Path('build/validation/full-story-navigation.json')
if target and trace.exists():
    rows = json.loads(trace.read_text(encoding='utf-8'))
    with open(target, 'a', encoding='utf-8') as output:
        output.write('### 连续故事导航回放\n\n')
        output.write(f'共记录 {len(rows)} 次操作；最后步骤：\n\n')
        output.write('```json\n')
        output.write(json.dumps([
            {key: value for key, value in row.items() if key != 'flags'}
            for row in rows[-18:]
        ], ensure_ascii=False, indent=2))
        output.write('\n```\n')
        log = Path('build/validation/tests.log')
        if log.exists():
            failures = [line for line in log.read_text(encoding='utf-8', errors='replace').splitlines()
                        if any(term in line for term in ['未结束', '目标反复', 'Expected:', 'Actual:', 'Reason:', '[E]'])]
            output.write('\n```text\n' + '\n'.join(failures[-18:]) + '\n```\n')
