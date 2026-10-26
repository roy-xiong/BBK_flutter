import 'package:flutter/material.dart';

import '../view_models/game_view_model.dart';

/// 展示三国霸业敌方城池及城内武将的只读信息。
Future<void> showSgbyEnemyCitySheet(
  BuildContext context, {
  required SgbyEnemyCityInfo city,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return FractionallySizedBox(
        heightFactor: 0.72,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Row(
                  children: [
                    const Icon(Icons.location_city),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            city.name,
                            style: Theme.of(sheetContext).textTheme.titleLarge,
                          ),
                          Text('所属势力：${city.rulerName}'),
                        ],
                      ),
                    ),
                    Chip(label: Text('${city.generals.length} 人')),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: city.generals.isEmpty
                    ? const Center(child: Text('城内没有可显示的武将'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: city.generals.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final general = city.generals[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            leading: CircleAvatar(
                              child: Icon(
                                general.isCaptive
                                    ? Icons.person_off
                                    : Icons.person,
                              ),
                            ),
                            title: Text(
                              general.isCaptive
                                  ? '${general.name}（俘虏）'
                                  : general.name,
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _AttributeChip(label: '等级 ${general.level}'),
                                  _AttributeChip(label: '武力 ${general.force}'),
                                  _AttributeChip(label: '智力 ${general.iq}'),
                                  _AttributeChip(
                                    label: '忠诚 ${general.devotion}',
                                  ),
                                  _AttributeChip(label: '兵力 ${general.arms}'),
                                  _AttributeChip(
                                    label:
                                        '兵种 ${_armsTypeName(general.armsType)}',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 紧凑显示单项武将属性，避免长文本在窄屏中溢出。
class _AttributeChip extends StatelessWidget {
  const _AttributeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}

String _armsTypeName(int index) {
  const names = <String>['骑兵', '步兵', '弓兵', '水兵', '极兵', '玄兵'];
  return index >= 0 && index < names.length ? names[index] : '未知';
}
