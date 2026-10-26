import '../../domain/models/game_order.dart';
import '../../domain/models/game_world.dart';
import '../../domain/models/game_battle.dart';
import '../../domain/models/game_report.dart';
import '../../domain/use_cases/advance_calendar.dart';
import '../../domain/use_cases/computer_strategy.dart';
import '../../domain/use_cases/execute_strategy_order.dart';
import '../../domain/use_cases/resolve_battle.dart';
import 'battle_flow.dart';
import 'native_game_session.dart';

/// GameDevDrv的回合事务：电脑策略→逐槽命令→战斗→环境更新→下月玩家地图。
///
/// 报告、守城选将与新君选择通过会话继续，不将未完成的半回合暴露为可再次结束。
final class StrategyTurnFlow {
  StrategyTurnFlow(this.session)
    : resolver = ResolveBattle(session.resources),
      execute = ExecuteStrategyOrder(
        session.resources,
        dialogs: session.resources.strategyDialogs,
      );
  final NativeGameSession session;
  final ResolveBattle resolver;
  final ExecuteStrategyOrder execute;
  GameBattle? _postBattle;
  GameWorld? get world => session.world;

  void start() {
    if (session.isDisposed || session.resolvingTurn || world == null) return;
    session.resolvingTurn = true;
    resolver.onGeneralDied = (person, belong, arms, winner) =>
        world?.battleRecord.generalDied(
          (world?.playerRulerIndex ?? -1) + 1,
          person,
          belong,
          arms,
          winner,
        );
    session.showStrategy();
    session.submitScene(NativeScene.processing);
    final data = world!;
    final enemies = session.resources
        .rulers(data)
        .where((id) => id != data.playerRulerIndex)
        .toList(growable: false);
    _showTacticNotes(data, enemies, 0);
  }

  /// 对齐原版 ShowTacticNote：先依城池顺序展示敌方君主，再执行电脑策略。
  ///
  /// 由会话报告时钟推进，暂停和倍速沿用现有逻辑；期间锁住本回合，避免重复
  /// 点击再次结算。读档替换世界后旧回调直接失效，不访问或修改新存档。
  void _showTacticNotes(GameWorld data, List<int> enemies, int index) {
    if (session.isDisposed ||
        !identical(world, data) ||
        !session.resolvingTurn) {
      return;
    }
    if (index >= enemies.length) {
      session.showStrategy();
      session.submitScene(NativeScene.processing);
      _executeComputer();
      return;
    }
    session.showCanvasReport(
      () => session.renderer.tacticNote(data, enemies[index]),
      // 原 GamDelay(5, false)，JS定时器每单位10毫秒。
      delayMilliseconds: 50,
      dismissible: false,
      completed: () => _showTacticNotes(data, enemies, index + 1),
    );
  }

  /// 只在原版策略提示全部结束后进入原有电脑下令、战斗与月结链。
  void _executeComputer() {
    if (session.isDisposed || world == null || !session.resolvingTurn) return;
    session.enhancements.maintenance(world!);
    session.enhancements.applyEnemyArmsLimit(world!);
    ComputerStrategy(session.resources, options: session.options)(
      world!,
      activity: session.options.worldActivity,
    );
    session.enhancements.applyEnemyArmsLimit(world!);
    _next();
  }

  void _next() {
    final data = world;
    if (data == null || session.isDisposed) return;
    final order = data.orders.firstOrNull;
    if (order == null) {
      _calendar();
      return;
    }
    if (order.orderId == 27) {
      _battle(order);
      return;
    }
    final reports = execute(
      data,
      order,
      worldActivity: session.options.worldActivity,
      diplomacyProtection: session.options.enabled('diplomacyProtection'),
    );
    data.removeOrder(order);
    session.showStrategy();
    session.displayReports(reports, completed: _next);
  }

  void _battle(
    GameOrder order, {
    List<int>? defenders,
    bool attackShown = false,
  }) {
    final data = world;
    if (data == null) return;
    if (!attackShown && order.fighters.isNotEmpty) {
      final actor = data.person(order.fighters.first);
      session.showStrategy();
      session.displayReports(
        [
          GameReport(
            '',
            kind: GameReportKind.attack,
            actor: actor == null ? null : actor.belong - 1,
            target: order.object,
            city: order.object,
          ),
        ],
        completed: () =>
            _battle(order, defenders: defenders, attackShown: true),
      );
      return;
    }
    final prepared = resolver.prepare(
      data,
      order,
      selectedDefenders: defenders,
    );
    if (prepared.defenders != null) {
      final selected = <int>[];
      void choose() {
        final available = prepared.defenders!
            .where((id) => !selected.contains(id))
            .toList();
        if (available.isEmpty || selected.length >= 10) {
          _battle(order, defenders: selected, attackShown: true);
          return;
        }
        session.choosePeople(available, (id) {
          if (id == null) {
            _battle(order, defenders: selected, attackShown: true);
          } else {
            selected.add(id);
            choose();
          }
        });
      }

      if (session.options.enabled('autoBattle')) {
        _battle(
          order,
          defenders: prepared.defenders!.take(1).toList(),
          attackShown: true,
        );
      } else {
        choose();
      }
      return;
    }
    final battle = prepared.battle;
    if (battle == null) {
      data.removeOrder(order);
      session.showStrategy();
      session.displayReports(prepared.reports, completed: _next);
      return;
    }
    void startBattle() {
      BattleFlow(
        session,
        battle,
        completed: () {
          final result = resolver(
            data,
            battle,
            loserOutcome: session.options.loserOutcome,
            enemyEscapeRoute: session.options.enabled('enemyEscapeRoute'),
          );
          void finish() {
            data.removeOrder(order);
            if (battle.entered) _postBattle = battle;
            session.activeBattle = null;
            session.showStrategy();
            _next();
          }

          session.showStrategy();
          session.displayReports(
            result.reports,
            completed: () {
              final ruler = result.lostRuler;
              if (ruler == null || result.heirs.isEmpty) {
                finish();
                return;
              }
              void choose() {
                session.choosePeople(result.heirs, (id) {
                  if (id == null) {
                    choose();
                  } else {
                    resolver.inherit(data, ruler, id, result.heirs);
                    finish();
                  }
                });
              }

              choose();
            },
          );
        },
      ).start();
    }

    session.showStrategy();
    session.displayReports([
      if (battle.mode == 2)
        GameReport(
          '',
          kind: GameReportKind.fight,
          actor: data.person(order.fighters.first)!.belong - 1,
          target: battle.originalCityBelong - 1,
          city: battle.city,
        ),
    ], completed: startBattle);
  }

  void _calendar() {
    final data = world;
    if (data == null) return;
    final food = session.enhancements.protectFood(data);
    final reports = AdvanceCalendar(session.resources)(
      data,
      largeArmies: session.options.enabled('enemyArmsLimitEnabled'),
      foodProtection: session.options.enabled('foodProtection'),
    );
    session.enhancements.applyEnemyArmsLimit(data);
    session.enhancements.restoreFood(data, food);
    session.resources.assignSatraps(data);
    session.showStrategy();
    session.displayReports(
      reports,
      completed: () {
        session.resolvingTurn = false;
        session.activeBattle = null;
        session.showStrategy();
        final pending = _postBattle;
        _postBattle = null;
        if (pending != null) {
          session.enhancements.executeDefeatedCaptives(data, pending);
          session.enhancements.postBattle(data, pending);
        }
        if (!session.checkGameOver()) session.completeStrategyTurn();
      },
    );
  }
}
