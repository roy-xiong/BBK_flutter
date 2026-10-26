import 'dart:math' as math;

import '../../domain/models/game_battle.dart';
import '../../domain/models/game_report.dart';
import '../../domain/models/game_world.dart';
import '../../domain/use_cases/battle_ai.dart';
import '../../domain/use_cases/battle_engine.dart';
import '../rendering/battle_scene_renderer.dart';
import 'native_game_session.dart';

/// 战场输入与动画状态机。原版等待被拆成可暂停的步骤，不阻塞Flutter主isolate。
///
/// 一个会话只持有一个流程。所有定时步骤依赖session.advance；弹出宿主面板、
/// 后台、读档或退出后不会有独立Timer继续下令。
final class BattleFlow {
  BattleFlow(this.session, this.battle, {required this.completed})
    : engine = BattleEngine(session.resources, options: session.options) {
    ai = BattleAi(engine);
    renderer = BattleSceneRenderer(session.canvas, engine);
  }
  final NativeGameSession session;
  final GameBattle battle;
  final void Function() completed;
  final BattleEngine engine;
  late final BattleAi ai;
  late final BattleSceneRenderer renderer;
  GameWorld? get world => session.world;
  BattlePath? _path;
  int? _selected, _rangeSource, _skill;
  (int, int)? _backup;
  void Function()? _pending;
  int _wait = 0, _blinkTime = 0, _frame = 0;
  bool _enemy = false, _finished = false, _situation = false;
  int _situationSide = 1, _situationTop = 0;
  bool? _lastAnimationsDisabled;
  int _mainSelection = 0;

  void start() {
    final data = world;
    if (data == null || session.isDisposed) return;
    session.activeBattle = battle;
    session.onBattleInput = input;
    session.onBattleTap = tap;
    session.onBattleSwipe = swipe;
    session.onBattleRedraw = draw;
    session.onBattleEndTurn = () {
      if (!_enemy && _pending == null && session.scene == NativeScene.battle) {
        _startEnemy();
      }
    };
    session.onAdvance = advance;
    _syncOptions();
    engine.onArmsLost = (source, victim, loss) => data.battleRecord.armsLost(
      (data.playerRulerIndex ?? -1) + 1,
      source,
      victim,
      loss,
    );
    final reports = engine.initialize(data, battle);
    if (battle.result != 0) {
      _finish();
      return;
    }
    draw();
    session.displayReports(reports, completed: _beginDay);
  }

  void _syncOptions() {
    engine.invincible = session.options.enabled('invincible');
    engine.oneHitKill = session.options.enabled('oneHitKill');
    engine.wideGroupAttack = session.options.enabled('wideGroupAttack');
    engine.freeMovement = session.options.enabled('freeMovement');
    engine.foodProtection = session.options.enabled('foodProtection');
    final disabled = session.options.enabled('animationsDisabled');
    if (_lastAnimationsDisabled != disabled &&
        (_lastAnimationsDisabled != null || disabled)) {
      final data = world;
      if (data != null) {
        data.lookBattleMovie = !disabled;
        data.slowBattleMovement = !disabled;
        data.lookEnemyMovement = !disabled;
      }
    }
    _lastAnimationsDisabled = disabled;
  }

  void advance(int microseconds) {
    if (_finished || session.isDisposed || world == null) return;
    _syncOptions();
    if (session.scene == NativeScene.battleSituation) {
      _blinkTime += microseconds;
      if (_blinkTime >= 500000) {
        _blinkTime %= 500000;
        _frame = 1 - _frame;
        _drawSituation();
      }
      return;
    }
    if (battle.result != 0 &&
        !engine.hasPendingCommand &&
        session.scene == NativeScene.battle) {
      _finish();
      return;
    }
    if (session.scene != NativeScene.battle) return;
    if (_pending != null) {
      // 保留本帧剩余预算。10毫秒数字动画在8倍速时可于一帧内推进多步，
      // 不会因显示器刷新率被限制为每帧一步；有操作上限避免异常回调死循环。
      var budget = microseconds, operations = 0;
      while (_pending != null &&
          session.scene == NativeScene.battle &&
          !_finished &&
          operations++ < 256) {
        if (_wait > budget) {
          _wait -= budget;
          return;
        }
        budget -= _wait;
        final action = _pending;
        _pending = null;
        _wait = 0;
        action?.call();
      }
      return;
    }
    _blinkTime += microseconds;
    if (_blinkTime >= 500000) {
      _blinkTime %= 500000;
      _frame = 1 - _frame;
      draw();
    }
    if (!_enemy && session.options.enabled('autoBattle') && _selected == null) {
      _autoPlayerStep();
    }
  }

  /// 重放原增强脚本的自动输入阶段，确认前不把己方单位直接写到目标位置。
  ///
  /// 光标按先横后纵逐格移动，保留 220ms 按键、420ms 阶段等待及高倍率最短可见
  /// 时间。所有步骤仍挂在会话时钟上；关闭自动、读档或退出会在下一步安全取消。
  void _autoPlayerStep() {
    final data = world;
    if (data == null) return;
    final plan = ai.planPlayer(data, battle);
    if (plan == null) {
      _startEnemy();
      return;
    }
    final source = plan.command.source, unit = battle.units[source];
    final origin = (unit.x, unit.y);
    var committed = false;
    _selected = source;
    bool valid() {
      if (_finished ||
          session.isDisposed ||
          !identical(world, data) ||
          !identical(session.activeBattle, battle)) {
        return false;
      }
      if (unit.active != 0 || [1, 6, 8].contains(unit.state)) {
        _selected = null;
        _path = null;
        draw();
        return false;
      }
      if (session.options.enabled('autoBattle')) return true;
      _path = null;
      if (committed) {
        _selected = source;
        _backup = origin;
        _actionMenu();
      } else {
        _selected = null;
        draw();
      }
      return false;
    }

    int stageDelay() => math.max(420, 90 * session.currentSpeed);
    void moveCursor(int x, int y, void Function() arrived) {
      if (!valid()) return;
      if (battle.focusX == x && battle.focusY == y) {
        arrived();
        return;
      }
      _later(math.max(220, 55 * session.currentSpeed), () {
        if (!valid()) return;
        input(
          battle.focusX != x
              ? (battle.focusX < x ? NativeInput.right : NativeInput.left)
              : (battle.focusY < y ? NativeInput.down : NativeInput.up),
        );
        moveCursor(x, y, arrived);
      });
    }

    _later(stageDelay(), () {
      moveCursor(origin.$1, origin.$2, () {
        _path = plan.path;
        draw();
        _later(stageDelay(), () {
          moveCursor(plan.x, plan.y, () {
            _later(math.max(220, 55 * session.currentSpeed), () {
              if (!valid()) return;
              if (!plan.path.contains(plan.x, plan.y)) {
                _playerReady();
                return;
              }
              unit
                ..x = plan.x
                ..y = plan.y;
              committed = true;
              _path = null;
              draw();
              _later(stageDelay(), () {
                if (valid()) _execute(plan.command, _playerReady);
              });
            });
          });
        });
      });
    });
  }

  void _later(int milliseconds, void Function() action) {
    _wait = milliseconds * 1000;
    _pending = action;
    session.submitScene(NativeScene.battle);
  }

  void draw() {
    final data = world;
    if (data == null || _finished) return;
    renderer.draw(
      data,
      battle,
      path: _path,
      rangeSource: _rangeSource,
      skill: _skill,
      frame: _frame,
      showTroopIcons: session.options.enabled('showTroopIcons'),
      selected: _selected,
    );
    session.submitScene(NativeScene.battle);
  }

  void _beginDay() {
    if (_finished || world == null) return;
    session.enhancements.applyEnemyArmsLimit(world!);
    final reports = engine.beginDay(world!, battle);
    draw();
    if (battle.result != 0) {
      session.displayReports(reports, completed: _finish);
      return;
    }
    final x = (session.canvas.width - 130) ~/ 2,
        y = (session.canvas.height - 64) ~/ 2;
    session.canvas.picture(27 + battle.weather, 0, x, y);
    session.submitScene(NativeScene.battle);
    _later(500, () {
      draw();
      session.canvas.picture(33, 0, x + 46, y + 18);
      final label = '${battle.day}';
      session.canvas.text(x + 64 - (label.length - 1) * 3, y + 22, label);
      session.submitScene(NativeScene.battle);
      _later(
        500,
        () => session.displayReports(reports, completed: _playerReady),
      );
    });
  }

  void _playerReady() {
    if (battle.result != 0) {
      _finish();
      return;
    }
    _enemy = false;
    _selected = null;
    _path = null;
    _rangeSource = null;
    _skill = null;
    final first = battle.units.indexWhere((unit) => unit.state != 8);
    if (first >= 0) engine.focus(battle, first);
    draw();
  }

  void _startEnemy() {
    _enemy = true;
    _selected = null;
    _path = null;
    _rangeSource = null;
    _skill = null;
    draw();
    _later(420, _enemyStep);
  }

  void _enemyStep() {
    if (battle.result != 0) {
      _finish();
      return;
    }
    final data = world;
    if (data == null) return;
    final source = ai.selectEnemy(battle);
    if (source == null) {
      engine.consumeFood(data, battle);
      _beginDay();
      return;
    }
    final path = engine.path(data, battle, source);
    void choose() {
      final command = ai.enemyCommand(data, battle, source);
      final target = command.target;
      void execute() => _execute(command, _enemyStep);
      if ((command.type == 0 || command.type == 1) && target != null) {
        engine.focus(battle, target);
        draw();
        final unit = battle.units[target];
        session.playMovie(
          27,
          first: 12,
          last: 17,
          x: (unit.x - battle.viewX) * 16,
          y: (unit.y - battle.viewY) * 16,
          completed: execute,
        );
      } else {
        execute();
      }
    }

    void move() {
      _path = null;
      ai.moveEnemy(data, battle, source, path);
      if (data.lookEnemyMovement) {
        engine.focus(battle, source);
        draw();
        if (data.slowBattleMovement) {
          _later(500, choose);
          return;
        }
      }
      choose();
    }

    if (data.lookEnemyMovement) {
      engine.focus(battle, source);
      _path = path;
      draw();
      _later(100, () {
        final unit = battle.units[source];
        session.canvas.picture(
          8,
          battle.terrain(unit.x, unit.y),
          (unit.x - battle.viewX) * 16,
          (unit.y - battle.viewY) * 16,
        );
        session.submitScene(NativeScene.battle);
        _later(100, () {
          draw();
          _later(data.slowBattleMovement ? 500 : 0, move);
        });
      });
    } else {
      move();
    }
  }

  /// 平移视口不修改焦点和行动目标，拖动途中不会意外确认一次攻击。
  void swipe(int dx, int dy) {
    if (_finished || _pending != null || _enemy) return;
    if (_situation) {
      input(
        dx.abs() > dy.abs()
            ? (dx < 0 ? NativeInput.right : NativeInput.left)
            : (dy < 0 ? NativeInput.down : NativeInput.up),
      );
      return;
    }
    final columns = session.canvas.width ~/ 16,
        rows = session.canvas.height ~/ 16 - 1;
    battle.viewX = (battle.viewX - dx ~/ 16).clamp(
      0,
      math.max(0, battle.width - columns),
    );
    battle.viewY = (battle.viewY - dy ~/ 16).clamp(
      0,
      math.max(0, battle.height - rows),
    );
    draw();
  }

  void input(NativeInput input) {
    if (_finished || _pending != null || _enemy || world == null) return;
    if (_situation) {
      if (input == NativeInput.confirm || input == NativeInput.cancel) {
        _situation = false;
        draw();
        return;
      }
      if (input == NativeInput.left || input == NativeInput.right) {
        _situationSide = 1 - _situationSide;
        _situationTop = 0;
      }
      final count = battle.people
              .skip(_situationSide * 10)
              .take(10)
              .takeWhile((id) => id != null)
              .length,
          page = (session.canvas.height - 1 - 30) ~/ 12;
      if (input == NativeInput.up && _situationTop > 0) _situationTop -= page;
      if (input == NativeInput.down &&
          count >= page &&
          _situationTop < count - page) {
        _situationTop += page;
      }
      _drawSituation();
      return;
    }
    if (input == NativeInput.help) {
      showInformation();
      return;
    }
    if (input == NativeInput.search) {
      showSituation();
      return;
    }
    if (input == NativeInput.cancel) {
      if (_rangeSource != null) {
        _rangeSource = null;
        _skill = null;
        _actionMenu();
      } else if (_selected != null) {
        _selected = null;
        _path = null;
        draw();
      } else {
        _mainMenu();
      }
      return;
    }
    if (input == NativeInput.confirm) {
      final selected = _selected;
      if (_rangeSource != null && selected != null) {
        var target = battle.unitAt(battle.focusX, battle.focusY);
        if (_skill == null && engine.wideGroupAttack && target == selected) {
          target = <int>[
            for (var i = 10; i < 20; i++)
              if (battle.units[i].state != 8 &&
                  engine.inRange(world!, battle, selected, i))
                i,
          ].firstOrNull;
        }
        if (target == null ||
            !engine.inRange(world!, battle, selected, target, skill: _skill)) {
          return;
        }
        if (_skill == null && target < 10 ||
            _skill != null &&
                !engine.skillTarget(
                  world!,
                  battle,
                  selected,
                  target,
                  _skill!,
                )) {
          return;
        }
        _execute(
          BattleCommand(
            selected,
            _skill == null ? 0 : 1,
            target: target,
            skill: _skill,
          ),
          _playerReady,
        );
      } else if (selected != null && _path != null) {
        if (!_path!.contains(battle.focusX, battle.focusY)) return;
        final unit = battle.units[selected];
        _backup = (unit.x, unit.y);
        unit.x = battle.focusX;
        unit.y = battle.focusY;
        _path = null;
        _actionMenu();
      } else {
        final index = battle.unitAt(battle.focusX, battle.focusY);
        if (index == null ||
            index >= 10 ||
            battle.units[index].active != 0 ||
            [1, 6, 8].contains(battle.units[index].state)) {
          return;
        }
        _selected = index;
        _path = engine.path(world!, battle, index);
        engine.focus(battle, index);
        if (battle.units[index].move == 1) {
          _backup = (battle.units[index].x, battle.units[index].y);
          _path = null;
          _actionMenu();
        } else {
          draw();
        }
      }
      return;
    }
    final step = input == NativeInput.pageUp || input == NativeInput.pageDown
        ? 5
        : 1;
    if (input == NativeInput.left) {
      battle.focusX = math.max(0, battle.focusX - step);
    }
    if (input == NativeInput.right) {
      battle.focusX = math.min(battle.width - 1, battle.focusX + step);
    }
    if (input == NativeInput.up || input == NativeInput.pageUp) {
      battle.focusY = math.max(0, battle.focusY - step);
    }
    if (input == NativeInput.down || input == NativeInput.pageDown) {
      battle.focusY = math.min(battle.height - 1, battle.focusY + step);
    }
    final columns = session.canvas.width ~/ 16,
        rows = session.canvas.height ~/ 16 - 1;
    if (battle.focusX < battle.viewX) battle.viewX = battle.focusX;
    if (battle.focusY < battle.viewY) battle.viewY = battle.focusY;
    if (battle.focusX >= battle.viewX + columns) {
      battle.viewX = battle.focusX - columns + 1;
    }
    if (battle.focusY >= battle.viewY + rows) {
      battle.viewY = battle.focusY - rows + 1;
    }
    draw();
  }

  void tap(int x, int y) {
    if (_situation) {
      _situation = false;
      draw();
      return;
    }
    if (_pending != null || _enemy || y >= session.canvas.height - 16) return;
    final mx = battle.viewX + x ~/ 16, my = battle.viewY + y ~/ 16;
    if (mx >= battle.width || my >= battle.height) return;
    final repeated = mx == battle.focusX && my == battle.focusY;
    battle.focusX = mx;
    battle.focusY = my;
    draw();
    if (repeated || _path != null || _rangeSource != null) {
      input(NativeInput.confirm);
    }
  }

  void _actionMenu() {
    if (_selected == null || world == null) {
      _playerReady();
      return;
    }
    draw();
    final unit = battle.units[_selected!],
        screenX = (battle.units[_selected!].x - battle.viewX) * 16;
    final x = screenX + 42 > session.canvas.width - 1
        ? screenX - 24
        : screenX + 18;
    final screenY = (unit.y - battle.viewY) * 16;
    final y = (session.canvas.height - 1 - screenY - 24) ~/ 12 < 4
        ? session.canvas.height - 67
        : screenY + 4;
    session.canvasMenu(
      _menu(8, 2),
      (choice) {
        if (choice == null) {
          final backup = _backup;
          if (backup != null) {
            unit.x = backup.$1;
            unit.y = backup.$2;
          }
          _playerReady();
        } else if (choice == 3) {
          _execute(BattleCommand(_selected!, 3), _playerReady);
        } else if (choice == 2) {
          showInformation(completed: _actionMenu);
        } else if (choice == 1) {
          _skillMenu();
        } else {
          _rangeSource = _selected;
          _skill = null;
          draw();
        }
      },
      x: x,
      y: y,
      columns: 4,
    );
  }

  List<String> _menu(int item, int width) {
    final value = session.resources.text(1, item);
    return [
      for (var i = 0; i < value.length; i += width)
        value.substring(i, math.min(value.length, i + width)),
    ];
  }

  void _skillMenu() {
    final selected = _selected;
    if (selected == null || world == null) return;
    if (battle.units[selected].state == 2) {
      _actionMenu();
      return;
    }
    final skills = engine.skills(world!, battle, selected);
    draw();
    session.canvasMenu(
      [for (final id in skills) session.resources.text(11, id)],
      (choice) {
        if (choice == null) {
          _actionMenu();
          return;
        }
        final skill = skills[choice],
            error = engine.skillError(world!, battle, selected, skills[choice]);
        if (error != 0) {
          draw();
          session.displayReports([
            GameReport(session.resources.text(1, error)),
          ], completed: _skillMenu);
          return;
        }
        if (skill == 22 || skill == 30) {
          _execute(
            BattleCommand(selected, 1, target: selected, skill: skill),
            _playerReady,
          );
          return;
        }
        _skill = skill;
        _rangeSource = selected;
        draw();
      },
      x: 30,
      y: 12,
      columns: 4,
    );
  }

  void _mainMenu() {
    draw();
    session.canvasMenu(
      _menu(9, 4),
      (choice) {
        if (choice == null) {
          draw();
          return;
        }
        _mainSelection = choice;
        if (choice == 0) {
          _startEnemy();
          return;
        }
        if (choice == 1) {
          session.canvasMenu(
            ['全军撤退'],
            (confirm) {
              if (confirm == null) {
                _mainMenu();
              } else {
                battle.result = 2;
                _finish();
              }
            },
            x: 56,
            y: 20,
            columns: 4,
          );
          return;
        }
        final data = world;
        if (data == null) return;
        final enabled = choice == 2
            ? data.lookBattleMovie
            : choice == 3
            ? data.slowBattleMovement
            : data.lookEnemyMovement;
        session.canvasMenu(
          _menu(choice == 3 ? 11 : 10, 2),
          (selected) {
            if (selected != null) {
              if (choice == 2) {
                data.lookBattleMovie = selected == 1;
              } else if (choice == 3) {
                data.slowBattleMovement = selected == 1;
              } else {
                data.lookEnemyMovement = selected == 1;
              }
            }
            _mainMenu();
          },
          x: (session.canvas.width - 1) ~/ 2 - 12,
          y: (session.canvas.height - 1) ~/ 2 - 12,
          columns: 4,
          initialSelection: enabled ? 1 : 0,
        );
      },
      columns: 8,
      initialSelection: _mainSelection,
    );
  }

  void _execute(BattleCommand command, void Function() done) {
    final data = world, target = command.target, skill = command.skill;
    if (data == null) return;
    _selected = null;
    _path = null;
    _rangeSource = null;
    _skill = null;
    final arms = [
      for (final id in battle.people) id == null ? 0 : data.person(id)!.arms,
    ];
    final states = [for (final unit in battle.units) unit.state];
    final targets = command.type == 1 && skill != null && target != null
        ? engine.skillTargets(data, battle, command.source, target, skill)
        : <int>[];
    final food =
        command.type == 1 &&
            skill != null &&
            target != null &&
            !const [22, 27, 30].contains(skill)
        ? engine.skillFoodDamage(data, battle, command.source, target, skill)
        : 0;
    engine.beginCommand(data, battle, command);
    draw();
    void finish() => _completeCommand(done);
    if (command.type == 3 || target == null) {
      finish();
      return;
    }
    if (command.type == 0) {
      _attackVisual(
        command.source,
        target,
        arms[target] - data.person(battle.people[target]!)!.arms,
        finish,
      );
      return;
    }
    if (skill == null) {
      finish();
      return;
    }
    final name = session.resources.text(11, skill);
    if (engine.lastSkillSucceeded == false) {
      session.showCanvasReport(
        () => session.canvas.graphicMessage(
          ' $name  ${session.resources.text(1, 26)}',
        ),
        completed: finish,
        delayMilliseconds: 1000,
      );
      return;
    }
    void success() {
      if (skill == 22) {
        draw();
        session.canvas.picture(
          27 + battle.weather,
          0,
          (session.canvas.width - 130) ~/ 2,
          (session.canvas.height - 64) ~/ 2,
        );
        session.submitScene(NativeScene.battle);
        _later(500, finish);
        return;
      }
      if (skill == 30) {
        session.displayReports([
          GameReport(
            session.resources.text(1, 55),
            person: battle.people[command.source],
          ),
        ], completed: finish);
        return;
      }
      if (skill == 27) {
        // 围攻按左、上、右、下的相邻友军顺序播放各自的普通攻击。
        final center = battle.units[target];
        final attackers = <int>[];
        for (final delta in [(-1, 0), (0, -1), (1, 0), (0, 1)]) {
          final index = battle.unitAt(center.x + delta.$1, center.y + delta.$2);
          if (index != null &&
              !((target < 10 && index < 10) || (target > 10 && index > 10))) {
            attackers.add(index);
          }
        }
        var remaining = arms[target], index = 0;
        void next() {
          if (index >= attackers.length) {
            finish();
            return;
          }
          final source = attackers[index++];
          final hurt = math.min(
            remaining,
            engine.attackHurt(data, battle, source, target),
          );
          remaining -= hurt;
          _attackVisual(source, target, hurt, next);
        }

        next();
        return;
      }
      var index = 0;
      void next() {
        if (index >= targets.length) {
          finish();
          return;
        }
        final slot = targets[index++], id = battle.people[targets[index - 1]]!;
        void status() {
          final state = battle.units[slot].state;
          if (states[slot] != state && state != 0 && state != 8) {
            final text =
                '${session.resources.personName(data.period, id)}${session.resources.text(1, 27)}${session.resources.text(1, 28 + state)}${session.resources.text(1, 36)}';
            session.showCanvasReport(
              () => session.renderer.report(text),
              completed: next,
              delayMilliseconds: 1000,
            );
          } else {
            next();
          }
        }

        void number() {
          final amount = arms[slot] - data.person(id)!.arms;
          if (amount != 0) {
            _showDelta(slot, amount, status);
          } else {
            status();
          }
        }

        _skillAnimation(skill, number, sourceFriendly: command.source < 10);
      }

      if (food != 0) {
        _showDelta(target, food, next, food: true);
      } else {
        next();
      }
    }

    if (!data.lookBattleMovie) {
      session.showCanvasReport(
        () => session.canvas.graphicMessage('      $name', line: 0),
        completed: success,
        delayMilliseconds: 1000,
      );
    } else {
      success();
    }
  }

  /// 兵力、粮草提示复用原版资源和数字轨迹。无动画时在目标格显示带符号文字。
  void _showDelta(
    int target,
    int amount,
    void Function() completed, {
    bool food = false,
  }) {
    if (world?.lookBattleMovie == true) {
      final x = (session.canvas.width - 130) ~/ 2,
          y = (session.canvas.height - 64) ~/ 2;
      session.canvas.text(
        x + 40,
        y + 2,
        session.resources.text(
          1,
          food
              ? 25
              : amount < 0
              ? 24
              : 23,
        ),
      );
      _showNumber(x + 40, y + 40, amount.abs(), () => _later(500, completed));
    } else {
      final unit = battle.units[target];
      final x = (unit.x - battle.viewX) * 16, y = (unit.y - battle.viewY) * 16;
      if (x < 0 ||
          y < 0 ||
          x >= session.canvas.width ||
          y >= session.canvas.height) {
        engine.focus(battle, target);
        draw();
      }
      session.canvas.text(
        (unit.x - battle.viewX) * 16,
        (unit.y - battle.viewY) * 16,
        '${amount < 0 ? '+' : '-'}${amount.abs()}',
      );
      session.submitScene(NativeScene.battle);
      _later(500, completed);
    }
  }

  void _attackVisual(
    int source,
    int target,
    int hurt,
    void Function() completed,
  ) {
    final data = world;
    if (data == null) return;
    if (!data.lookBattleMovie) {
      _showDelta(target, hurt, completed);
      return;
    }
    final from = engine.armType(data, battle.people[source]!),
        to = engine.armType(data, battle.people[target]!);
    final water =
        battle.terrain(battle.units[target].x, battle.units[target].y) == 7;
    final length = const [11, 10, 9, 10, 9, 10][from],
        first = water ? 0 : length * to;
    final x = (session.canvas.width - 130) ~/ 2,
        y = (session.canvas.height - 64) ~/ 2;
    session.canvas.picture(16, 0, x, y);
    session.playMovie(
      water ? 25 : 19 + from,
      first: first,
      last: water ? 4 : first + length - 1,
      x: x,
      y: y,
      completed: () =>
          _showNumber(x + 40, y + 40, hurt, () => _later(500, completed)),
      visualLabel: '${session.resources.text(64, 17 + from)}攻击',
      sourceType: from,
      targetType: to,
      sourceFriendly: source < 10,
      targetFriendly: target < 10,
    );
  }

  /// 通用计谋每个目标都播放一次；动画编号、帧段与横移逐项来自原版静态表。
  void _skillAnimation(
    int skill,
    void Function() completed, {
    bool sourceFriendly = true,
  }) {
    if (world?.lookBattleMovie != true) {
      completed();
      return;
    }
    const ids = [
      19,
      19,
      19,
      19,
      35,
      37,
      37,
      20,
      21,
      21,
      35,
      36,
      38,
      39,
      39,
      40,
      41,
      35,
      36,
      39,
      0,
      0,
      42,
      43,
      0,
      0,
      0,
      0,
      41,
    ];
    const first = [
      11,
      11,
      11,
      11,
      0,
      0,
      0,
      10,
      9,
      9,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ];
    const last = [
      21,
      21,
      21,
      21,
      7,
      7,
      0,
      20,
      17,
      17,
      7,
      7,
      14,
      7,
      7,
      7,
      7,
      7,
      7,
      7,
      0,
      0,
      7,
      7,
      0,
      0,
      0,
      0,
      7,
    ];
    final index = skill - 1;
    if (index < 0 || index >= ids.length || ids[index] == 0) {
      completed();
      return;
    }
    final x = (session.canvas.width - 130) ~/ 2,
        y = (session.canvas.height - 64) ~/ 2;
    if (const [0, 1, 2, 3, 7, 8, 9, 12].contains(index)) {
      session.canvas.picture(16, 0, x, y);
    }
    session.playMovie(
      ids[index],
      first: first[index],
      last: last[index],
      x:
          x +
          (const [
                4,
                5,
                6,
                10,
                11,
                13,
                14,
                15,
                16,
                17,
                18,
                19,
                22,
                23,
                28,
              ].contains(index)
              ? 33
              : 0),
      y: y,
      completed: completed,
      visualLabel: session.resources.text(11, skill),
      sourceFriendly: sourceFriendly,
    );
  }

  /// FgtAtvShowNum按资源原始宽高的一半推进，而非按逻辑缩放后的尺寸。
  /// 保留精修4X版本的逐字上升轨迹，每次等待交给同一会话时钟处理。
  void _showNumber(int x, int y, int amount, void Function() completed) {
    final picture = session.resources.pictures(15);
    if (picture == null) {
      completed();
      return;
    }
    final digits = amount.clamp(0, 200000).toString().codeUnits;
    var digit = 0, row = 0;
    void step() {
      if (_finished || session.isDisposed) return;
      if (digit >= digits.length) {
        completed();
        return;
      }
      session.canvas.picture(
        15,
        digits[digit] - 48,
        x + digit * (picture.width ~/ 2),
        y - row,
      );
      session.submitScene(NativeScene.battle);
      row++;
      if (row >= picture.height ~/ 2) {
        row = 0;
        digit++;
        _later(10, () {
          if (digit >= digits.length) {
            completed();
          } else {
            _later(40, step);
          }
        });
      } else {
        _later(10, step);
      }
    }

    _later(40, step);
  }

  /// 顺序消费升级和死亡事件，上一位武将的动画与报告结束后才处理下一位。
  void _completeCommand(void Function() done) {
    final data = world;
    if (data == null) return;
    final iterator = engine.completeCommand(data, battle).iterator;
    void next() {
      if (_finished || session.isDisposed || world == null) return;
      if (!iterator.moveNext()) {
        draw();
        if (battle.result != 0) {
          _finish();
        } else {
          done();
        }
        return;
      }
      final report = iterator.current;
      void show() {
        draw();
        session.displayReports([report], completed: next);
      }

      final id = report.person, first = report.changeFrame;
      final slot = id == null ? -1 : battle.people.indexOf(id);
      if (first != null && slot >= 0) {
        final unit = battle.units[slot], state = battle.units[slot].state;
        unit.state = report.previousState ?? state;
        draw();
        unit.state = state;
        session.playMovie(
          27,
          first: first,
          last: first + 5,
          x: (unit.x - battle.viewX) * 16,
          y: (unit.y - battle.viewY) * 16,
          completed: show,
          visualLabel: first == 6 ? '部队击溃' : '武将升级',
          visualEffect: first == 6 ? 'defeat' : 'level',
          sourceType: engine.armType(data, id!),
          sourceFriendly: slot < 10,
        );
      } else {
        show();
      }
    }

    next();
  }

  void showInformation({void Function()? completed}) {
    final data = world;
    if (data == null) return;
    draw();
    session.showCanvasReport(
      () => renderer.information(data, battle),
      completed: completed ?? draw,
    );
  }

  void showSituation() {
    _situation = true;
    _situationSide = 1;
    _situationTop = 0;
    _drawSituation();
  }

  void _drawSituation() {
    final data = world;
    if (data == null) return;
    renderer.situation(
      data,
      battle,
      _situationSide,
      _situationTop,
      blink: _frame == 1,
    );
    session.submitScene(NativeScene.battleSituation);
  }

  void _finish() {
    if (_finished || world == null) return;
    _finished = true;
    _pending = null;
    engine.finish(world!, battle);
    session.onAdvance = null;
    engine.onArmsLost = null;
    session.onBattleInput = null;
    session.onBattleTap = null;
    session.onBattleSwipe = null;
    session.onBattleEndTurn = null;
    completed();
  }
}
