import 'package:flutter/material.dart';

import '../view_models/game_view_model.dart';
import 'game_cheat_sheet.dart';
import 'sgby_general_portrait.dart';
import '../../../../engine/resources/baye_database.dart';

/// 按分组和搜索词筛选将领。
///
/// 精确命中敌方君主时，将君主移到势力搜索结果首位；精确命中普通武将时只返回姓名
/// 命中项。没有精确姓名命中时，继续支持武将、城池和势力模糊搜索。
List<SgbyGeneralCheatInfo> filterSgbyGeneralRoster(
  Iterable<SgbyGeneralCheatInfo> generals,
  SgbyGeneralGroup group,
  String rawQuery,
) {
  final scoped = generals
      .where((general) => general.group == group)
      .toList(growable: false);
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return scoped;

  final fuzzyMatches = scoped
      .where(
        (general) =>
            general.name.toLowerCase().contains(query) ||
            general.cityName.toLowerCase().contains(query) ||
            general.factionName.toLowerCase().contains(query),
      )
      .toList(growable: false);
  final exactRulers = group == SgbyGeneralGroup.enemy
      ? fuzzyMatches
            .where(
              (general) =>
                  general.isRuler && general.name.trim().toLowerCase() == query,
            )
            .toList(growable: false)
      : const <SgbyGeneralCheatInfo>[];
  if (exactRulers.isNotEmpty) {
    final rulerIndexes = exactRulers.map((general) => general.index).toSet();
    return <SgbyGeneralCheatInfo>[
      ...exactRulers,
      ...fuzzyMatches.where((general) => !rulerIndexes.contains(general.index)),
    ];
  }

  final exactNameMatches = scoped
      .where((general) => general.name.trim().toLowerCase() == query)
      .toList(growable: false);
  if (exactNameMatches.isNotEmpty) return exactNameMatches;
  return fuzzyMatches;
}

/// 返回独立君主结果使用的所在地文案。
String formatSgbyGeneralLocation(SgbyGeneralCheatInfo general) {
  return '所在地：${general.cityName}';
}

/// 展示按阵营与登场状态分类的将领列表。
Future<void> showSgbyGeneralRosterSheet(
  BuildContext context, {
  required GameViewModel viewModel,
}) {
  return viewModel.withSgbyAutomationPaused(
    () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.88,
        child: _SgbyGeneralRosterSheet(viewModel: viewModel),
      ),
    ),
  );
}

/// 将领列表状态，支持分组浏览以及人物名、城池名和势力名实时过滤。
class _SgbyGeneralRosterSheet extends StatefulWidget {
  const _SgbyGeneralRosterSheet({required this.viewModel});

  final GameViewModel viewModel;

  @override
  State<_SgbyGeneralRosterSheet> createState() =>
      _SgbyGeneralRosterSheetState();
}

class _SgbyGeneralRosterSheetState extends State<_SgbyGeneralRosterSheet>
    with SingleTickerProviderStateMixin {
  static const List<String> _armsTypeNames = <String>[
    '骑兵',
    '步兵',
    '弓兵',
    '水兵',
    '极兵',
    '玄兵',
  ];
  static const List<SgbyGeneralGroup> _groups = <SgbyGeneralGroup>[
    SgbyGeneralGroup.player,
    SgbyGeneralGroup.enemy,
    SgbyGeneralGroup.currentWild,
    SgbyGeneralGroup.futureWild,
  ];

  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;
  SgbyCheatData? _data;
  bool _loading = false;
  int? _changingGeneralIndex;
  String _query = '';
  int? _portraitPeriod;
  BayeDatabase? _portraitResources;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _groups.length, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    final session = widget.viewModel.session;
    final period = session?.world?.period;
    final data = await widget.viewModel.getSgbyCheatData();
    if (widget.viewModel.cartoonEnabled &&
        widget.viewModel.cartoonAssets == null) {
      await widget.viewModel.cartoonArtReady;
    }
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
      _portraitPeriod = period;
      _portraitResources = session?.resources;
    });
  }

  List<SgbyGeneralCheatInfo> _filteredGenerals(SgbyGeneralGroup group) {
    return filterSgbyGeneralRoster(
      _data?.generals ?? const <SgbyGeneralCheatInfo>[],
      group,
      _query,
    );
  }

  String _groupLabel(SgbyGeneralGroup group) => switch (group) {
    SgbyGeneralGroup.player => '我方将领',
    SgbyGeneralGroup.enemy => '敌方将领',
    SgbyGeneralGroup.currentWild => '当前在野',
    SgbyGeneralGroup.futureWild => '未来在野',
  };

  /// 点击将领后选择新的基础兵种，并复用作弊面板已有的白名单修改动作。
  ///
  /// 对话框只返回固定的 0~5 兵种序号，不接受任意脚本内容。修改期间锁定对应行，等待
  /// 原生引擎 返回后重新读取列表，确保装备覆盖兵种等实际状态与游戏引擎保持一致。
  Future<void> _changeArmsType(SgbyGeneralCheatInfo general) async {
    if (general.group != SgbyGeneralGroup.player ||
        _changingGeneralIndex != null ||
        !mounted) {
      return;
    }
    final selectedArmsType = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('修改 ${general.name} 的兵种'),
        children: List<Widget>.generate(_armsTypeNames.length, (index) {
          final selected = index == general.baseArmsType;
          return SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(index),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected
                      ? Theme.of(dialogContext).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(_armsTypeNames[index])),
              ],
            ),
          );
        }),
      ),
    );
    if (!mounted ||
        selectedArmsType == null ||
        selectedArmsType == general.baseArmsType) {
      return;
    }
    setState(() => _changingGeneralIndex = general.index);
    final result = await widget.viewModel.applyCheat(
      'sgby_general_arm_type',
      parameters: <String, Object?>{
        'generalIndex': general.index,
        'armsType': selectedArmsType,
      },
    );
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    setState(() => _changingGeneralIndex = null);
    showCheatToast(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final visibleCount = _groups.fold<int>(
      0,
      (count, group) => count + _filteredGenerals(group).length,
    );
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '将领列表 · $visibleCount 人',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '刷新将领列表',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: '搜索武将、城池或势力',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空搜索',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: _groups
                .map(
                  (group) => Tab(
                    text:
                        '${_groupLabel(group)} ${_filteredGenerals(group).length}',
                  ),
                )
                .toList(growable: false),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _groups
                  .map(
                    (group) =>
                        _buildContent(data, group, _filteredGenerals(group)),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    SgbyCheatData? data,
    SgbyGeneralGroup group,
    List<SgbyGeneralCheatInfo> generals,
  ) {
    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!data.isSuccess) {
      return Center(
        child: Text(data.message.isEmpty ? '读取将领失败' : data.message),
      );
    }
    if (generals.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? '当前没有${_groupLabel(group)}' : '没有匹配的武将、城池或势力',
        ),
      );
    }

    final normalizedQuery = _query.trim().toLowerCase();
    SgbyGeneralCheatInfo? highlightedRuler;
    if (group == SgbyGeneralGroup.enemy && normalizedQuery.isNotEmpty) {
      for (final general in generals) {
        if (general.isRuler &&
            general.name.trim().toLowerCase() == normalizedQuery) {
          highlightedRuler = general;
          break;
        }
      }
    }

    final cityGroups = <String, List<SgbyGeneralCheatInfo>>{};
    for (final general in generals) {
      if (general.index == highlightedRuler?.index) continue;
      cityGroups
          .putIfAbsent(general.cityName, () => <SgbyGeneralCheatInfo>[])
          .add(general);
    }
    final colorScheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      key: PageStorageKey<String>('sgby-general-roster-${group.name}'),
      slivers: <Widget>[
        if (highlightedRuler != null)
          SliverToBoxAdapter(child: _buildHighlightedRuler(highlightedRuler)),
        for (final entry in cityGroups.entries) ...<Widget>[
          SliverMainAxisGroup(
            slivers: <Widget>[
              SliverPersistentHeader(
                pinned: true,
                delegate: _CityHeaderDelegate(
                  cityName: entry.key,
                  backgroundColor: colorScheme.surface,
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _buildGeneralTile(entry.value[index]),
                      if (index < entry.value.length - 1)
                        const Divider(height: 1),
                    ],
                  );
                }, childCount: entry.value.length),
              ),
            ],
          ),
        ],
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }

  /// 构建精确搜索敌方君主时的独立顶部结果，不与下方城池分组重复显示。
  Widget _buildHighlightedRuler(SgbyGeneralCheatInfo ruler) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.tertiaryContainer.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.workspace_premium,
                    size: 18,
                    color: colorScheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '君主',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.tertiary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      formatSgbyGeneralLocation(ruler),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            _buildGeneralTile(ruler),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }

  /// 构建单个将领条目；只有我方将领允许进入兵种修改流程。
  Widget _buildGeneralTile(SgbyGeneralCheatInfo general) {
    final editable = general.group == SgbyGeneralGroup.player;
    final changing = _changingGeneralIndex == general.index;
    final rulerColor = Theme.of(context).colorScheme.tertiary;
    return ListTile(
      enabled: !editable || _changingGeneralIndex == null,
      onTap: editable ? () => _changeArmsType(general) : null,
      leading: SgbyGeneralPortrait(
        key: ValueKey('roster-portrait-$_portraitPeriod-${general.index}'),
        person: general.index,
        period: _portraitPeriod,
        resources: _portraitResources,
        assets: widget.viewModel.cartoonEnabled
            ? widget.viewModel.cartoonAssets
            : null,
        label: '${general.name}头像',
      ),
      title: Row(
        children: <Widget>[
          Flexible(child: Text(general.name)),
          if (general.isRuler) ...<Widget>[
            const SizedBox(width: 8),
            Icon(Icons.workspace_premium, size: 17, color: rulerColor),
            const SizedBox(width: 3),
            Text(
              '君主',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: rulerColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            if (general.group == SgbyGeneralGroup.enemy)
              Text('势力 ${general.factionName}'),
            if (general.group == SgbyGeneralGroup.currentWild)
              const Text('当前在野'),
            if (general.group == SgbyGeneralGroup.futureWild &&
                general.appearanceYear > 0)
              Text('登场 ${general.appearanceYear} 年'),
            Text('等级 ${general.level}'),
            Text('武力 ${general.force}'),
            Text('智力 ${general.iq}'),
            Text('忠诚 ${general.devotion}'),
            Text('兵力 ${general.arms}'),
            Text('兵种 ${_armsTypeName(general.effectiveArmsType)}'),
          ],
        ),
      ),
      trailing: changing
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : editable
          ? const Tooltip(message: '修改兵种', child: Icon(Icons.swap_horiz))
          : null,
    );
  }

  String _armsTypeName(int index) {
    return index >= 0 && index < _armsTypeNames.length
        ? _armsTypeNames[index]
        : '未知';
  }
}

/// 固定高度的城池吸顶标题，在下一座城池到达时自然被替换。
class _CityHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _CityHeaderDelegate({
    required this.cityName,
    required this.backgroundColor,
  });

  final String cityName;
  final Color backgroundColor;

  @override
  double get minExtent => 42;

  @override
  double get maxExtent => 42;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: backgroundColor,
      elevation: overlapsContent ? 2 : 0,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(cityName, style: Theme.of(context).textTheme.titleMedium),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_CityHeaderDelegate oldDelegate) {
    return cityName != oldDelegate.cityName ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}
