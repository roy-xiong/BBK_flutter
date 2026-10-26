import 'package:flutter/material.dart';

import '../view_models/game_view_model.dart';

/// 展示三国霸业最近 50 次手动或战后自动搜索记录。
Future<void> showSgbySearchHistorySheet(
  BuildContext context, {
  required GameViewModel viewModel,
}) {
  return viewModel.withSgbyAutomationPaused(
    () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.8,
        child: _SgbySearchHistorySheet(viewModel: viewModel),
      ),
    ),
  );
}

/// 搜索历史面板状态，支持用户在面板内主动刷新最新记录。
class _SgbySearchHistorySheet extends StatefulWidget {
  const _SgbySearchHistorySheet({required this.viewModel});

  final GameViewModel viewModel;

  @override
  State<_SgbySearchHistorySheet> createState() =>
      _SgbySearchHistorySheetState();
}

class _SgbySearchHistorySheetState extends State<_SgbySearchHistorySheet> {
  SgbySearchHistoryData? _data;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    final data = await widget.viewModel.getSgbySearchHistory();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '搜索记录',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '刷新搜索记录',
                  onPressed: _loading ? null : _load,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildContent(data)),
        ],
      ),
    );
  }

  Widget _buildContent(SgbySearchHistoryData? data) {
    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!data.isSuccess) {
      return const Center(child: Text('读取搜索记录失败，请稍后刷新'));
    }
    if (data.records.isEmpty) {
      return const Center(child: Text('暂无搜索记录'));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: data.records.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final record = data.records[index];
        final battleSource = record.battleSource;
        final accentColor = _sourceAccentColor(context, battleSource);
        return ExpansionTile(
          leading: Icon(
            battleSource == null
                ? Icons.manage_search
                : battleSource.direction == SgbyBattleDirection.playerDefence
                ? Icons.shield_outlined
                : Icons.sports_martial_arts,
            color: accentColor,
          ),
          title: _SearchRecordSource(
            source: record.source,
            battleSource: battleSource,
            accentColor: accentColor,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record.gameTime} · ${record.realTime}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    if (record.peopleCount > 0)
                      _SearchCount(
                        icon: Icons.person_search,
                        label: '人物',
                        count: record.peopleCount,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    if (record.toolCount > 0)
                      _SearchCount(
                        icon: Icons.inventory_2_outlined,
                        label: '物品',
                        count: record.toolCount,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    if (record.recruitedCount > 0)
                      _SearchCount(
                        icon: Icons.group_add_outlined,
                        label: '招降',
                        count: record.recruitedCount,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    if (record.executedCount > 0)
                      _SearchCount(
                        icon: Icons.gavel,
                        label: '处斩',
                        count: record.executedCount,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    if (record.exiledCount > 0)
                      _SearchCount(
                        icon: Icons.exit_to_app,
                        label: '流放',
                        count: record.exiledCount,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ],
            ),
          ),
          children: record.cities.isEmpty
              ? const <Widget>[
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.info_outline),
                    title: Text('本次未发现新人物、物品或可招降武将'),
                  ),
                ]
              : record.cities
                    .map(
                      (city) => ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 4,
                        ),
                        title: Text(
                          city.cityName,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            if (city.people.isNotEmpty)
                              _SearchResultLine(
                                icon: Icons.person_search,
                                label: '人物',
                                values: city.people,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            if (city.tools.isNotEmpty)
                              _SearchResultLine(
                                icon: Icons.inventory_2_outlined,
                                label: '物品',
                                values: city.tools,
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                            if (city.recruited.isNotEmpty)
                              _SearchResultLine(
                                icon: Icons.group_add_outlined,
                                label: '招降',
                                values: city.recruited,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            if (city.executed.isNotEmpty)
                              _SearchResultLine(
                                icon: Icons.gavel,
                                label: '处斩',
                                values: city.executed,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            if (city.exiled.isNotEmpty)
                              _SearchResultLine(
                                icon: Icons.exit_to_app,
                                label: '流放',
                                values: city.exiled,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
        );
      },
    );
  }
}

Color _sourceAccentColor(BuildContext context, SgbySearchBattleSource? source) {
  final colors = Theme.of(context).colorScheme;
  return switch (source?.direction) {
    SgbyBattleDirection.playerAttack => colors.error,
    SgbyBattleDirection.playerDefence => colors.secondary,
    SgbyBattleDirection.auto => colors.tertiary,
    null => colors.primary,
  };
}

class _SearchRecordSource extends StatelessWidget {
  const _SearchRecordSource({
    required this.source,
    required this.battleSource,
    required this.accentColor,
  });

  final String source;
  final SgbySearchBattleSource? battleSource;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final battle = battleSource;
    if (battle == null) {
      return Text(
        source,
        style: TextStyle(color: accentColor, fontWeight: FontWeight.w700),
      );
    }
    final direction = switch (battle.direction) {
      SgbyBattleDirection.playerAttack => '我方进攻',
      SgbyBattleDirection.playerDefence => '我方防守',
      SgbyBattleDirection.auto => '势力交战',
    };
    final attackerLabel = battle.direction == SgbyBattleDirection.playerAttack
        ? '我方'
        : battle.attackerRulerName;
    final defenderLabel = battle.direction == SgbyBattleDirection.playerDefence
        ? '我方'
        : battle.defenderRulerName;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          direction,
          style: theme.textTheme.titleSmall?.copyWith(
            color: accentColor,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            children: [
              const TextSpan(text: '进攻主公 '),
              TextSpan(
                text: attackerLabel,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const TextSpan(text: '  ·  防守主公 '),
              TextSpan(
                text: defenderLabel,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const TextSpan(text: '  ·  城市 '),
              TextSpan(
                text: battle.cityName,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SearchCount extends StatelessWidget {
  const _SearchCount({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          '$label $count',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _SearchResultLine extends StatelessWidget {
  const _SearchResultLine({
    required this.icon,
    required this.label,
    required this.values,
    required this.color,
  });

  final IconData icon;
  final String label;
  final List<String> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$label：',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          Expanded(child: Text(values.join('、'))),
        ],
      ),
    );
  }
}
