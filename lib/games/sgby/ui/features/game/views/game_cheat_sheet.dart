import 'dart:async';

import 'package:flutter/material.dart';

import '../view_models/game_view_model.dart';
import 'sgby_enemy_arms_limit_slider.dart';

/// 单个作弊选项的 UI 定义。
class _CheatOption {
  const _CheatOption({
    required this.action,
    required this.title,
    required this.description,
    required this.icon,
    this.stateKey,
  });

  final String action;
  final String title;
  final String description;
  final IconData icon;
  final String? stateKey;
}

/// 战后自动处理使用的俘虏处置方式。
enum _PostBattleCaptiveAction {
  recruit('recruit', '招降', Icons.group_add_outlined, '全部归属我方，忠诚设为 100'),
  execute('execute', '处斩', Icons.gavel, '永久移除俘虏，装备收入原所在城池'),
  exile('exile', '流放', Icons.exit_to_app, '改为在野并移至非我方城池');

  const _PostBattleCaptiveAction(
    this.wireValue,
    this.label,
    this.icon,
    this.description,
  );

  final String wireValue;
  final String label;
  final IconData icon;
  final String description;
}

_PostBattleCaptiveAction _postBattleCaptiveActionFromState(
  Map<String, bool> state,
) {
  if (state['postBattleCaptiveExecute'] == true) {
    return _PostBattleCaptiveAction.execute;
  }
  if (state['postBattleCaptiveExile'] == true) {
    return _PostBattleCaptiveAction.exile;
  }
  return _PostBattleCaptiveAction.recruit;
}

/// 作弊搜索对隐藏人物和物品的统一处理方式。
enum _SearchOutcome {
  none('none', '全部搜不到', Icons.search_off, '不发现任何隐藏人物或隐藏物品'),
  all('all', '全部搜到', Icons.manage_search, '发现我方全部城池中的隐藏人物和隐藏物品');

  const _SearchOutcome(this.wireValue, this.label, this.icon, this.description);

  final String wireValue;
  final String label;
  final IconData icon;
  final String description;
}

/// 所有战败武将的强制结算方式，既覆盖参战人员，也覆盖失守城池内的未参战人员。
enum _BattleLoserOutcome {
  original('original', '原版算法', '参战武将按智力随机逃跑、被俘或战死，留守武将按原版占领规则处理'),
  death('death', '必死', '三种战斗方向的所有败方武将战死，装备留在战斗城市'),
  captive('captive', '必被俘', '三种战斗方向的所有败方武将成为实际胜方的俘虏'),
  escape('escape', '必逃跑', '退往原势力随机城市；原势力无城可退时转为在野'),
  wild('wild', '必在野', '所有战败方武将留在战斗城市并变为在野');

  const _BattleLoserOutcome(this.wireValue, this.label, this.description);

  final String wireValue;
  final String label;
  final String description;
}

_SearchOutcome _searchOutcomeFromState(Map<String, bool> state) {
  return state['searchOutcomeNone'] == true
      ? _SearchOutcome.none
      : _SearchOutcome.all;
}

_BattleLoserOutcome _battleLoserOutcomeFromState(Map<String, bool> state) {
  if (state['battleLoserOutcomeDeath'] == true) {
    return _BattleLoserOutcome.death;
  }
  if (state['battleLoserOutcomeCaptive'] == true) {
    return _BattleLoserOutcome.captive;
  }
  if (state['battleLoserOutcomeEscape'] == true) {
    return _BattleLoserOutcome.escape;
  }
  if (state['battleLoserOutcomeWild'] == true) {
    return _BattleLoserOutcome.wild;
  }
  return _BattleLoserOutcome.original;
}

OverlayEntry? _activeCheatToast;
Timer? _activeCheatToastTimer;

/// 在根 Overlay 显示游戏结果；普通作弊位于顶部，战后通知可单独放到底部。
void showCheatToast(
  BuildContext context,
  CheatResult result, {
  bool atBottom = false,
  Duration duration = const Duration(milliseconds: 2600),
}) {
  _activeCheatToastTimer?.cancel();
  final previousEntry = _activeCheatToast;
  if (previousEntry?.mounted ?? false) previousEntry?.remove();

  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) => Positioned(
      top: atBottom ? null : 10,
      bottom: atBottom ? 10 : null,
      left: 16,
      right: 16,
      child: SafeArea(
        top: !atBottom,
        bottom: atBottom,
        child: IgnorePointer(
          child: Material(
            color: result.isSuccess
                ? const Color(0xFF2E6E4F)
                : Theme.of(overlayContext).colorScheme.error,
            elevation: 8,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Icon(
                    result.isSuccess ? Icons.check_circle : Icons.error,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      result.message,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  _activeCheatToast = entry;
  overlay.insert(entry);
  _activeCheatToastTimer = Timer(duration, () {
    if (entry.mounted) entry.remove();
    if (identical(_activeCheatToast, entry)) _activeCheatToast = null;
  });
}

/// 展示当前游戏专属的作弊选项。
Future<void> showGameCheatSheet(
  BuildContext context, {
  required GameViewModel viewModel,
}) {
  return viewModel.withSgbyAutomationPaused(
    () => _showGameCheatSheetContent(context, viewModel: viewModel),
  );
}

/// 在自动操作已暂挂的期间读取作弊状态并展示面板，保留原有配置与确认流程。
Future<void> _showGameCheatSheetContent(
  BuildContext context, {
  required GameViewModel viewModel,
}) async {
  const options = <_CheatOption>[
    _CheatOption(
      action: 'sgby_auto_save_after_turn',
      title: '策略结束自动存档',
      description: '默认开启，本轮策略和战后处理结束后自动覆盖第一个档位',
      icon: Icons.save,
      stateKey: 'autoSaveAfterTurn',
    ),
    _CheatOption(
      action: 'sgby_enemy_arms_limit',
      title: '敌军兵力上限',
      description: '开启后用滑块替代每名敌将带兵上限，可调高或调低，不立即补兵',
      icon: Icons.groups_2,
      stateKey: 'enemyArmsLimitEnabled',
    ),
    _CheatOption(
      action: 'sgby_diplomacy_protection',
      title: '我方外交保护',
      description: '阻止敌方外交改变我方武将归属、忠诚或我方城池，不影响我方外交',
      icon: Icons.verified_user,
      stateKey: 'diplomacyProtection',
    ),
    _CheatOption(
      action: 'sgby_hide_special_generals',
      title: '隐藏特殊武将',
      description: '可逆隐藏通宵虫和南方小鬼；特殊君主由同势力武将继任，恢复时保留普通身份',
      icon: Icons.person_off,
      stateKey: 'hideSpecialGenerals',
    ),
    _CheatOption(
      action: 'sgby_max_all',
      title: '自动拉满与搜索',
      description: '策略结束自动拉满、搜索全部城池，且我方驻军不消耗城池粮草',
      icon: Icons.auto_graph,
      stateKey: 'autoMaxCities',
    ),
    _CheatOption(
      action: 'sgby_search_outcome',
      title: '隐藏内容搜索结果',
      description: '控制作弊搜索、策略结束自动搜索和战后自动搜索',
      icon: Icons.manage_search,
    ),
    _CheatOption(
      action: 'sgby_generals',
      title: '武将自动满属性',
      description: '开启时拉满现有武将，之后一键搜出或招降的武将也自动拉满',
      icon: Icons.shield,
      stateKey: 'autoMaxGenerals',
    ),
    _CheatOption(
      action: 'sgby_free_movement',
      title: '全员移动 8 步',
      description: '战斗中我方固定移动 8 步，不受地形、兵种和装备限制',
      icon: Icons.directions_run,
      stateKey: 'freeMovement',
    ),
    _CheatOption(
      action: 'sgby_food_protection',
      title: '粮草保护',
      description: '战斗回合不消耗我方粮草，城池缺粮时不再导致士兵减半',
      icon: Icons.rice_bowl,
      stateKey: 'foodProtection',
    ),
    _CheatOption(
      action: 'sgby_attack_any_city',
      title: '任意攻城',
      description: '我方出征可攻击任意敌方或空城，忽略战略地图城市连线',
      icon: Icons.alt_route,
      stateKey: 'attackAnyCity',
    ),
    _CheatOption(
      action: 'sgby_enemy_escape_route',
      title: '敌军逃跑遵循路线',
      description: '敌方君主和武将战败逃跑时，只能沿连线经过原势力城市撤退',
      icon: Icons.route,
      stateKey: 'enemyEscapeRoute',
    ),
    _CheatOption(
      action: 'sgby_disable_animations',
      title: '关闭过程动效',
      description: '跳过敌方移动展示和战斗动画，并使用最快的敌军移动速度',
      icon: Icons.motion_photos_off_outlined,
      stateKey: 'animationsDisabled',
    ),
    _CheatOption(
      action: 'sgby_post_battle_automation',
      title: '战后自动处理',
      description: '每次战斗后按所选方式处理实际胜方俘虏；我方城池继续自动拉满和搜索',
      icon: Icons.auto_mode,
      stateKey: 'postBattleAutomation',
    ),
    _CheatOption(
      action: 'sgby_battle_loser_outcome',
      title: '战败武将结局',
      description: '覆盖参战和留守败将；我攻敌、敌攻我、敌敌互战均生效',
      icon: Icons.rule,
    ),
    _CheatOption(
      action: 'sgby_search_city',
      title: '搜出我方全部隐藏内容',
      description: '立即发现我方所有城池内已经存在的隐藏人物和隐藏物品',
      icon: Icons.travel_explore,
    ),
    _CheatOption(
      action: 'sgby_search_world_generals',
      title: '一键搜索全地图武将',
      description: '所有当前在野武将（含城外）加入对应城市；空城由第一名武将自立',
      icon: Icons.public,
    ),
    _CheatOption(
      action: 'sgby_execute_wild_generals',
      title: '处死全地图在野武将',
      description: '永久移除所有当前与未来在野武将，城内城外全部处理',
      icon: Icons.person_remove,
    ),
    _CheatOption(
      action: 'sgby_recruit_captives',
      title: '一键招降全部俘虏',
      description: '招降当前我方城池全部俘虏，忠诚设为 100',
      icon: Icons.group_add,
    ),
    _CheatOption(
      action: 'sgby_execute_captives',
      title: '一键处斩全部俘虏',
      description: '处斩当前我方城池全部俘虏，并回收其装备',
      icon: Icons.gavel,
    ),
    _CheatOption(
      action: 'sgby_edit_general',
      title: '单个武将详细调整',
      description: '选择我方武将，单独修改属性、兵种和战场状态',
      icon: Icons.manage_accounts,
    ),
    _CheatOption(
      action: 'sgby_faction_colors',
      title: '阵营城池着色',
      description: '我方、空城和不同敌方势力使用独立颜色',
      icon: Icons.color_lens,
      stateKey: 'factionColors',
    ),
    _CheatOption(
      action: 'sgby_invincible',
      title: '我方无敌',
      description: '敌方普通攻击和技能无法削减我方兵力或施加异常状态',
      icon: Icons.health_and_safety,
      stateKey: 'invincible',
    ),
    _CheatOption(
      action: 'sgby_one_hit_kill',
      title: '我方一击必杀',
      description: '我方普通攻击和伤害技能直接击溃敌方目标',
      icon: Icons.flash_on,
      stateKey: 'oneHitKill',
    ),
    _CheatOption(
      action: 'sgby_wide_group_attack',
      title: '扩大范围与群攻',
      description: '普通攻击改为 7×7 范围；选择自己可攻击范围内全部敌军',
      icon: Icons.grid_on,
      stateKey: 'wideGroupAttack',
    ),
    _CheatOption(
      action: 'sgby_force_win',
      title: '当前战斗立即胜利',
      description: '仅在战斗过程中生效，并按正常胜利流程结算',
      icon: Icons.emoji_events,
    ),
  ];

  var cheatState = await viewModel.getCheatState();
  var enemyArmsLimit = await viewModel.getSgbyEnemyArmsLimit();
  var postBattleCaptiveAction = _postBattleCaptiveActionFromState(cheatState);
  var searchOutcome = _searchOutcomeFromState(cheatState);
  var battleLoserOutcome = _battleLoserOutcomeFromState(cheatState);
  if (!context.mounted) return;
  final hostContext = context;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      String? runningAction;
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> setEnemyArmsLimit(int value) async {
            if (runningAction != null) return;
            setSheetState(() => runningAction = 'sgby_enemy_arms_limit_value');
            final result = await viewModel.applyCheat(
              'sgby_enemy_arms_limit_value',
              parameters: <String, Object?>{'value': value},
            );
            if (!sheetContext.mounted) return;
            setSheetState(() {
              runningAction = null;
              if (result.isSuccess) enemyArmsLimit = value;
            });
            if (!result.isSuccess && hostContext.mounted) {
              showCheatToast(hostContext, result);
            }
          }

          Future<void> setPostBattleCaptiveAction(
            _PostBattleCaptiveAction action,
          ) async {
            setSheetState(
              () => runningAction = 'sgby_post_battle_captive_action',
            );
            final result = await viewModel.applyCheat(
              'sgby_post_battle_captive_action',
              parameters: <String, Object?>{'mode': action.wireValue},
            );
            if (!sheetContext.mounted) return;
            final latestState = await viewModel.getCheatState();
            if (!sheetContext.mounted) return;
            setSheetState(() {
              runningAction = null;
              cheatState = latestState;
              postBattleCaptiveAction = _postBattleCaptiveActionFromState(
                latestState,
              );
            });
            showCheatToast(hostContext, result);
          }

          /// 保存搜索结果模式，并用会话返回的真实状态重新校准控件。
          Future<void> setSearchOutcome(_SearchOutcome outcome) async {
            setSheetState(() => runningAction = 'sgby_search_outcome');
            final result = await viewModel.applyCheat(
              'sgby_search_outcome',
              parameters: <String, Object?>{'mode': outcome.wireValue},
            );
            if (!sheetContext.mounted) return;
            final latestState = await viewModel.getCheatState();
            if (!sheetContext.mounted) return;
            setSheetState(() {
              runningAction = null;
              cheatState = latestState;
              searchOutcome = _searchOutcomeFromState(latestState);
              battleLoserOutcome = _battleLoserOutcomeFromState(latestState);
            });
            showCheatToast(hostContext, result);
          }

          /// 保存战败结算模式，并立即同步到当前运行中的 原生会话。
          Future<void> setBattleLoserOutcome(
            _BattleLoserOutcome outcome,
          ) async {
            setSheetState(() => runningAction = 'sgby_battle_loser_outcome');
            final result = await viewModel.applyCheat(
              'sgby_battle_loser_outcome',
              parameters: <String, Object?>{'mode': outcome.wireValue},
            );
            if (!sheetContext.mounted) return;
            final latestState = await viewModel.getCheatState();
            if (!sheetContext.mounted) return;
            setSheetState(() {
              runningAction = null;
              cheatState = latestState;
              searchOutcome = _searchOutcomeFromState(latestState);
              battleLoserOutcome = _battleLoserOutcomeFromState(latestState);
            });
            showCheatToast(hostContext, result);
          }

          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.82,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '三国霸业作弊系统',
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: options.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final option = options[index];
                        final isRunning = runningAction == option.action;
                        final stateKey = option.stateKey;
                        final stateEnabled = stateKey != null
                            ? cheatState[stateKey] == true
                            : false;

                        Future<void> runOption() async {
                          if (option.action == 'sgby_edit_general') {
                            if (hostContext.mounted) {
                              await showSgbyGeneralEditor(
                                hostContext,
                                viewModel: viewModel,
                              );
                            }
                            return;
                          }
                          if (option.action == 'sgby_execute_captives' ||
                              option.action == 'sgby_execute_wild_generals') {
                            final executeWild =
                                option.action == 'sgby_execute_wild_generals';
                            final confirmed =
                                await showDialog<bool>(
                                  context: hostContext,
                                  builder: (dialogContext) => AlertDialog(
                                    title: Text(
                                      executeWild ? '处死全地图在野武将？' : '处斩全部俘虏？',
                                    ),
                                    content: Text(
                                      executeWild
                                          ? '将永久移除所有城市中的在野武将。该操作不可撤销，请先确认存档。'
                                          : '将处斩当前选中我方城池内的所有俘虏。该操作不可撤销，请先确认存档。',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(
                                          dialogContext,
                                        ).pop(false),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.of(
                                          dialogContext,
                                        ).pop(true),
                                        child: Text(
                                          executeWild ? '确认处死' : '确认处斩',
                                        ),
                                      ),
                                    ],
                                  ),
                                ) ??
                                false;
                            if (!confirmed || !sheetContext.mounted) return;
                          }
                          setSheetState(() => runningAction = option.action);
                          final result = await viewModel.applyCheat(
                            option.action,
                          );
                          if (!sheetContext.mounted) return;
                          final latestState = await viewModel.getCheatState();
                          if (!sheetContext.mounted) return;
                          setSheetState(() {
                            runningAction = null;
                            cheatState = latestState;
                            postBattleCaptiveAction =
                                _postBattleCaptiveActionFromState(latestState);
                            searchOutcome = _searchOutcomeFromState(
                              latestState,
                            );
                            battleLoserOutcome = _battleLoserOutcomeFromState(
                              latestState,
                            );
                          });
                          showCheatToast(
                            hostContext,
                            result,
                            duration:
                                option.action == 'sgby_search_city' ||
                                    option.action ==
                                        'sgby_search_world_generals'
                                ? const Duration(seconds: 6)
                                : const Duration(milliseconds: 2600),
                          );
                        }

                        if (option.action == 'sgby_search_outcome') {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ListTile(
                                leading: Icon(option.icon),
                                title: Text(option.title),
                                subtitle: Text(option.description),
                                trailing: isRunning
                                    ? const SizedBox.square(
                                        dimension: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : null,
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SegmentedButton<_SearchOutcome>(
                                      showSelectedIcon: false,
                                      segments: _SearchOutcome.values
                                          .map(
                                            (outcome) => ButtonSegment(
                                              value: outcome,
                                              icon: Icon(outcome.icon),
                                              label: Text(outcome.label),
                                            ),
                                          )
                                          .toList(growable: false),
                                      selected: <_SearchOutcome>{searchOutcome},
                                      onSelectionChanged: runningAction == null
                                          ? (selection) {
                                              if (selection.isNotEmpty) {
                                                unawaited(
                                                  setSearchOutcome(
                                                    selection.first,
                                                  ),
                                                );
                                              }
                                            }
                                          : null,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      searchOutcome.description,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }

                        if (option.action == 'sgby_battle_loser_outcome') {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ListTile(
                                leading: Icon(option.icon),
                                title: Text(option.title),
                                subtitle: Text(option.description),
                                trailing: isRunning
                                    ? const SizedBox.square(
                                        dimension: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : null,
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    DropdownButtonFormField<
                                      _BattleLoserOutcome
                                    >(
                                      key: ValueKey<_BattleLoserOutcome>(
                                        battleLoserOutcome,
                                      ),
                                      initialValue: battleLoserOutcome,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: '处理方式',
                                        prefixIcon: Icon(Icons.rule),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: _BattleLoserOutcome.values
                                          .map(
                                            (outcome) => DropdownMenuItem(
                                              value: outcome,
                                              child: Text(outcome.label),
                                            ),
                                          )
                                          .toList(growable: false),
                                      onChanged: runningAction == null
                                          ? (outcome) {
                                              if (outcome != null) {
                                                unawaited(
                                                  setBattleLoserOutcome(
                                                    outcome,
                                                  ),
                                                );
                                              }
                                            }
                                          : null,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      battleLoserOutcome.description,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }

                        final optionTile = ListTile(
                          leading: Icon(option.icon),
                          title: Text(option.title),
                          subtitle: Text(option.description),
                          trailing: isRunning
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : stateKey != null
                              ? Switch(
                                  value: stateEnabled,
                                  onChanged: runningAction == null
                                      ? (_) => runOption()
                                      : null,
                                )
                              : const Icon(Icons.chevron_right),
                          enabled: runningAction == null,
                          onTap: runOption,
                        );
                        if (option.action == 'sgby_enemy_arms_limit') {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              optionTile,
                              SgbyEnemyArmsLimitSlider(
                                value: enemyArmsLimit,
                                enabled: stateEnabled,
                                busy: runningAction != null,
                                onSubmitted: (value) =>
                                    unawaited(setEnemyArmsLimit(value)),
                              ),
                            ],
                          );
                        }
                        if (option.action != 'sgby_post_battle_automation') {
                          return optionTile;
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            optionTile,
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SegmentedButton<_PostBattleCaptiveAction>(
                                    segments: _PostBattleCaptiveAction.values
                                        .map(
                                          (action) => ButtonSegment(
                                            value: action,
                                            icon: Icon(action.icon),
                                            label: Text(action.label),
                                          ),
                                        )
                                        .toList(growable: false),
                                    selected: <_PostBattleCaptiveAction>{
                                      postBattleCaptiveAction,
                                    },
                                    onSelectionChanged: runningAction == null
                                        ? (selection) {
                                            if (selection.isNotEmpty) {
                                              unawaited(
                                                setPostBattleCaptiveAction(
                                                  selection.first,
                                                ),
                                              );
                                            }
                                          }
                                        : null,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    postBattleCaptiveAction.description,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  _SgbyCheatStatus(state: cheatState),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// 展示三国霸业单武将编辑面板。
Future<void> showSgbyGeneralEditor(
  BuildContext context, {
  required GameViewModel viewModel,
}) {
  return viewModel.withSgbyAutomationPaused(
    () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.88,
          child: _SgbyGeneralEditorSheet(viewModel: viewModel),
        );
      },
    ),
  );
}

/// 三国霸业单武将属性编辑器。
class _SgbyGeneralEditorSheet extends StatefulWidget {
  const _SgbyGeneralEditorSheet({required this.viewModel});

  final GameViewModel viewModel;

  @override
  State<_SgbyGeneralEditorSheet> createState() =>
      _SgbyGeneralEditorSheetState();
}

class _SgbyGeneralEditorSheetState extends State<_SgbyGeneralEditorSheet> {
  static const List<String> _armsTypeNames = <String>[
    '骑兵',
    '步兵',
    '弓兵',
    '水兵',
    '极兵',
    '玄兵',
  ];

  SgbyCheatData? _data;
  int? _selectedGeneralIndex;
  String? _runningAction;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({int? preferredGeneralIndex}) async {
    final data = await widget.viewModel.getSgbyCheatData();
    if (!mounted) return;
    final availableIndexes = data.generals
        .map((general) => general.index)
        .toSet();
    final nextIndex =
        preferredGeneralIndex != null &&
            availableIndexes.contains(preferredGeneralIndex)
        ? preferredGeneralIndex
        : availableIndexes.contains(_selectedGeneralIndex)
        ? _selectedGeneralIndex
        : data.generals.firstOrNull?.index;
    setState(() {
      _data = data;
      _selectedGeneralIndex = nextIndex;
    });
  }

  SgbyGeneralCheatInfo? get _selectedGeneral {
    final selectedIndex = _selectedGeneralIndex;
    if (selectedIndex == null) return null;
    for (final general in _data?.generals ?? const <SgbyGeneralCheatInfo>[]) {
      if (general.index == selectedIndex) return general;
    }
    return null;
  }

  Future<void> _apply(
    String action, {
    Map<String, Object?> extraParameters = const <String, Object?>{},
  }) async {
    final selectedIndex = _selectedGeneralIndex;
    if (_runningAction != null || selectedIndex == null) return;
    setState(() => _runningAction = action);
    final result = await widget.viewModel.applyCheat(
      action,
      parameters: <String, Object?>{
        'generalIndex': selectedIndex,
        ...extraParameters,
      },
    );
    if (!mounted) return;
    await _loadData(preferredGeneralIndex: selectedIndex);
    if (!mounted) return;
    setState(() => _runningAction = null);
    showCheatToast(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return const SafeArea(child: Center(child: CircularProgressIndicator()));
    }
    if (!data.isSuccess || data.generals.isEmpty) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_off, size: 40),
                const SizedBox(height: 12),
                Text(
                  data.message.isEmpty ? '没有可编辑的我方武将' : data.message,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新读取'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final selected = _selectedGeneral;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '单个武将调整',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '刷新武将数据',
                  onPressed: _runningAction == null ? _loadData : null,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                DropdownButtonFormField<int>(
                  key: ValueKey<int?>(_selectedGeneralIndex),
                  initialValue: _selectedGeneralIndex,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '我方武将',
                    prefixIcon: Icon(Icons.person_search),
                    border: OutlineInputBorder(),
                  ),
                  items: data.generals
                      .map(
                        (general) => DropdownMenuItem<int>(
                          value: general.index,
                          child: Text(
                            '${general.name} · ${general.cityName}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _runningAction == null
                      ? (value) => setState(() => _selectedGeneralIndex = value)
                      : null,
                ),
                if (selected != null) ...[
                  const SizedBox(height: 16),
                  _GeneralAttributeSummary(
                    general: selected,
                    maxLevel: data.maxLevel,
                    armsTypeNames: _armsTypeNames,
                  ),
                  const SizedBox(height: 20),
                  Text('属性强化', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _actionButton(
                        '全部拉满',
                        Icons.auto_graph,
                        'sgby_general_all',
                      ),
                      _actionButton(
                        '武力 100',
                        Icons.fitness_center,
                        'sgby_general_force',
                      ),
                      _actionButton(
                        '智力 100',
                        Icons.psychology,
                        'sgby_general_iq',
                      ),
                      _actionButton(
                        '体力 100',
                        Icons.favorite,
                        'sgby_general_thew',
                      ),
                      _actionButton(
                        '忠诚 100',
                        Icons.handshake,
                        'sgby_general_devotion',
                      ),
                      _actionButton(
                        '等级 ${data.maxLevel}',
                        Icons.upgrade,
                        'sgby_general_level',
                      ),
                      _actionButton(
                        '兵力 65535',
                        Icons.groups,
                        'sgby_general_arms',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<int>(
                    key: ValueKey<String>(
                      '${selected.index}:${selected.baseArmsType}',
                    ),
                    initialValue: selected.baseArmsType
                        .clamp(0, _armsTypeNames.length - 1)
                        .toInt(),
                    decoration: const InputDecoration(
                      labelText: '基础兵种',
                      prefixIcon: Icon(Icons.security),
                      border: OutlineInputBorder(),
                    ),
                    items: List<DropdownMenuItem<int>>.generate(
                      _armsTypeNames.length,
                      (index) => DropdownMenuItem<int>(
                        value: index,
                        child: Text(_armsTypeNames[index]),
                      ),
                    ),
                    onChanged: _runningAction == null
                        ? (value) {
                            if (value != null) {
                              _apply(
                                'sgby_general_arm_type',
                                extraParameters: <String, Object?>{
                                  'armsType': value,
                                },
                              );
                            }
                          }
                        : null,
                  ),
                  if (selected.effectiveArmsType != selected.baseArmsType)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '当前装备将实际兵种覆盖为：'
                        '${_armsTypeName(selected.effectiveArmsType)}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text('当前战斗', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _actionButton(
                        '移动 8 步并恢复行动',
                        Icons.directions_run,
                        'sgby_general_move',
                        enabled: selected.inBattle,
                      ),
                      _actionButton(
                        '恢复生命、技能与状态',
                        Icons.healing,
                        'sgby_general_restore',
                        enabled: selected.inBattle,
                      ),
                    ],
                  ),
                  if (!selected.inBattle)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('该武将当前不在我方战场队列中'),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    String label,
    IconData icon,
    String action, {
    bool enabled = true,
  }) {
    final running = _runningAction == action;
    return OutlinedButton.icon(
      onPressed: enabled && _runningAction == null
          ? () => _apply(action)
          : null,
      icon: running
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(label),
    );
  }

  String _armsTypeName(int index) {
    return index >= 0 && index < _armsTypeNames.length
        ? _armsTypeNames[index]
        : '未知兵种';
  }
}

/// 当前选中武将的属性摘要。
class _GeneralAttributeSummary extends StatelessWidget {
  const _GeneralAttributeSummary({
    required this.general,
    required this.maxLevel,
    required this.armsTypeNames,
  });

  final SgbyGeneralCheatInfo general;
  final int maxLevel;
  final List<String> armsTypeNames;

  @override
  Widget build(BuildContext context) {
    String armsTypeName(int index) => index >= 0 && index < armsTypeNames.length
        ? armsTypeNames[index]
        : '未知';

    final labels = <String>[
      '等级 ${general.level}/$maxLevel',
      '武力 ${general.force}',
      '智力 ${general.iq}',
      '体力 ${general.thew}',
      '忠诚 ${general.devotion}',
      '经验 ${general.experience}',
      '兵力 ${general.arms}',
      '兵种 ${armsTypeName(general.effectiveArmsType)}',
      if (general.inBattle) '移动 ${general.battleMove}',
      if (general.inBattle) '生命 ${general.battleHp}',
      if (general.inBattle) '技能 ${general.battleMp}',
      if (general.inBattle) general.canAct ? '可行动' : '已行动',
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: labels
          .map((label) => Chip(label: Text(label)))
          .toList(growable: false),
    );
  }
}

/// 三国霸业持续作弊与阵营着色状态。
class _SgbyCheatStatus extends StatelessWidget {
  const _SgbyCheatStatus({required this.state});

  final Map<String, bool> state;

  @override
  Widget build(BuildContext context) {
    final enabledLabels = <String>[
      if (state['factionColors'] == true) '阵营城池着色',
      if (state['invincible'] == true) '我方无敌',
      if (state['oneHitKill'] == true) '一击必杀',
      if (state['freeMovement'] == true) '全员移动 8 步',
      if (state['autoMaxGenerals'] == true) '武将自动满属性',
      if (state['autoMaxCities'] == true) '自动拉满与搜索',
      if (state['foodProtection'] == true) '粮草保护',
      if (state['attackAnyCity'] == true) '任意攻城',
      if (state['enemyEscapeRoute'] == true) '敌军逃跑遵循路线',
      if (state['animationsDisabled'] == true) '关闭过程动效',
      if (state['postBattleAutomation'] == true)
        '战后自动处理（${_postBattleCaptiveActionFromState(state).label}）',
      '搜索：${_searchOutcomeFromState(state).label}',
      if (_battleLoserOutcomeFromState(state) != _BattleLoserOutcome.original)
        '败方：${_battleLoserOutcomeFromState(state).label}',
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF303438))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('当前增强状态', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: enabledLabels.isEmpty
                  ? const <Widget>[Chip(label: Text('未开启持续增强'))]
                  : enabledLabels
                        .map(
                          (label) => Chip(
                            avatar: const Icon(Icons.check_circle, size: 18),
                            label: Text(label),
                          ),
                        )
                        .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}
