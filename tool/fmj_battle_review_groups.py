"""共享战斗动效分组和上轮意见迁移，不依赖渲染器、Pillow 或浏览器。

主 SRS 是共享动画的身份；施放者、技能名称、全体范围和追加状态仍由原 case
承载。分组只建立索引，不删除、不重排案例身份，也不把上轮意见当成本轮输入。
"""

from collections import Counter
import hashlib
import json


ACTION_NAMES = {
    'attack': '普通攻击', 'death': '死亡退场', 'hit': '受击', 'weak': '濒危待机',
    'self': '自伤动作', 'defend': '防御', 'flee-fail': '逃跑失败',
    'flee-success': '逃跑成功', 'poison': '毒伤结算', 'throw': '无独立SRS投掷',
    'item': '无独立SRS物品',
}


def _unique(values):
    """按首次出现顺序去重，保留原目录的阅读顺序。"""
    return list(dict.fromkeys(value for value in values if value is not None and value != ''))


def _identity(case):
    """只依据主资源或动作类型建组，追加状态不参与主动画身份。"""
    if case['kind'] == 'status':
        movies = case.get('observedMovies', [])
        primary = next((value for value in movies if value.startswith('1:')), None)
        if primary is None:
            raise ValueError(f"状态案例缺少原始 SRS：{case['id']}")
        return 'srs-' + primary.replace(':', '-'), primary, None
    movie = case.get('movie')
    if isinstance(movie, int) and movie > 0:
        primary = f'2:{movie}'
        return 'srs-' + primary.replace(':', '-'), primary, None
    kind = case['kind']
    return 'action-' + kind, None, kind


def _has_feedback(review):
    """文字优先于手动状态，兼容旧导出中“未审核但已填意见”的案例。"""
    return bool(str(review.get('comment') or '').strip()) or any(
        str(marker.get('comment') or '').strip() for marker in review.get('markers', [])
        if isinstance(marker, dict)
    )


def feedback_round(feedback):
    """为反馈快照生成稳定身份，供历史轮次、导出和浏览器存储共同使用。"""
    metadata = {key: feedback.get(key) for key in (
        'documentType', 'schema', 'version', 'revision', 'renderRevision', 'exportedAt')}
    identity = metadata.get('exportedAt')
    if not identity:
        identity = hashlib.sha256(json.dumps(feedback, ensure_ascii=False, sort_keys=True).encode()).hexdigest()[:20]
    metadata['id'] = 'fmj-feedback:' + str(identity)
    return metadata


def _history_entry(group, review, source_round, case=None):
    """把案例／共享组意见提升为只读历史，保留发生轮次与坐标所关联的案例。"""
    entry = dict(review)
    entry.update(scope='case' if case else 'group', groupId=group['id'],
                 caseIds=[case['id']] if case else list(group['caseIds']),
                 round=source_round, roundId=source_round['id'])
    entry['comment'] = review.get('comment') or ''
    entry['markers'] = review.get('markers') or []
    if case:
        entry.update(caseId=case['id'], title=case['title'], actor=case.get('actorName'), resource=case.get('resource'))
    else:
        # 组意见适用于全部变体；代表case只用于“查看变体”，不缩小意见范围。
        entry.update(caseId=group['caseIds'][0],title=review.get('title') or group['title'])
    entry.pop('historyReviews', None)
    return entry


def build_review_groups(cases, feedback):
    """将原 case 无损映射为共享动效组，并生成只读历史意见及初始审核状态。

    Args:
        cases: 原始目录案例列表；每个 id 必须唯一，函数不会修改列表或案例。
        feedback: 旧逐案例或新版共享组导出。仅当前comment／带字marker决定待复审；
            approved、status与更早historyReviews不影响本轮初始认可范围。

    Returns:
        可直接嵌入离线 HTML 的组列表，caseIds 可完整恢复原始案例集合。
    """
    by_id = {case['id']: case for case in cases}
    if len(by_id) != len(cases):
        raise ValueError('原目录存在重复 case ID')
    reviews = feedback.get('reviews', {})
    grouped_reviews = feedback.get('groupReviews', {})
    is_grouped = feedback.get('documentType') == 'fmj-color-battle-review-groups'
    current_round = feedback_round(feedback)
    previous_round = feedback_round(feedback.get('feedbackRound') or {})
    unknown = set(reviews) - set(by_id)
    if unknown:
        raise ValueError(f'历史意见存在无法对应的 case ID：{sorted(unknown)}')
    grouped = {}
    for case in cases:
        group_id, primary, action = _identity(case)
        group = grouped.setdefault(group_id, dict(
            id=group_id, primarySrs=primary, actionKind=action, caseIds=[],
            aliases=[], actorNames=[], categories=[], observedMovies=[], historyReviews=[],
        ))
        group['caseIds'].append(case['id'])
        alias = case.get('skill')
        if not alias and case['kind'] != 'movie':
            alias = case['title'].split(' · ', 1)[-1]
        if alias:
            group['aliases'].append(alias)
        group['actorNames'].append(case.get('actorName'))
        group['categories'].append(case.get('group'))
        group['observedMovies'].extend(case.get('observedMovies', []))
    for group in grouped.values():
        for key in ('aliases', 'actorNames', 'categories', 'observedMovies'):
            group[key] = _unique(group[key])
        aliases = group['aliases']
        label = ' / '.join(aliases[:3])
        if len(aliases) > 3:
            label += f' 等{len(aliases)}个名称'
        group['title'] = (f"SRS {group['primarySrs']} · {label or '独立资源预览'}"
                          if group['primarySrs'] else ACTION_NAMES.get(group['actionKind'], label))
        pending = False
        if is_grouped:
            previous = grouped_reviews.get(group['id'], {})
            if previous.get('caseIds') is not None and set(previous['caseIds']) != set(group['caseIds']):
                raise ValueError(f"共享组案例身份发生变化：{group['id']}")
            for row in previous.get('historyReviews', []):
                if not _has_feedback(row):
                    continue
                source_round = row.get('round') or previous_round
                source_round = {**source_round, 'id': row.get('roundId') or source_round.get('id') or feedback_round(source_round)['id']}
                if row.get('scope') == 'group':
                    entry = _history_entry(group, row, source_round)
                else:
                    case_id = row.get('caseId')
                    if case_id not in group['caseIds']:
                        raise ValueError(f'历史意见案例不属于共享组：{case_id}')
                    entry = _history_entry(group, row, source_round, by_id[case_id])
                group['historyReviews'].append(entry)
            pending = _has_feedback(previous)
            if pending:
                group['historyReviews'].append(_history_entry(group, previous, current_round))
        else:
            for case_id in group['caseIds']:
                previous = reviews.get(case_id, {})
                if _has_feedback(previous):
                    pending = True
                    group['historyReviews'].append(_history_entry(group, previous, current_round, by_id[case_id]))
        group['pendingFeedbackRoundId'] = current_round['id'] if pending else None
        group['initialStatus'] = '已修改待复审' if pending else '通过'
    groups = list(grouped.values())
    indexed = [case_id for group in groups for case_id in group['caseIds']]
    assert Counter(indexed) == Counter(by_id.keys()), '分组不能丢失或重复任何案例'
    if is_grouped:
        unknown_groups = set(grouped_reviews) - set(grouped)
        if unknown_groups:
            raise ValueError(f'反馈存在无法对应的共享组：{sorted(unknown_groups)}')
        expected_history = sum(_has_feedback(row) + sum(_has_feedback(old) for old in row.get('historyReviews', []))
                               for row in grouped_reviews.values())
    else:
        expected_history = sum(_has_feedback(review) for review in reviews.values())
    assert sum(len(group['historyReviews']) for group in groups) == expected_history, '分组不能丢失任何一轮文字或坐标意见'
    return groups
