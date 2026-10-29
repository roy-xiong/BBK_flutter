part of 'game_engine.dart';

final class BattleAction {
  BattleAction(
    this.actor,
    this.targets,
    this.kind, {
    this.resource,
    this.fleeSucceeded = false,
  });
  final GameActor actor;
  final List<GameActor> targets;
  final String kind;
  final String? resource;
  final bool fleeSucceeded;
  int frame = 0, tick = 0, originX = 0, originY = 0;
  bool started = false;
  GameMovie? movie;
  int stage = 0, tipTicks = 0;
  bool hitApplied = false;
  final List<BattleRaise> raises = [];
  final Map<GameActor, (int, int)> cooperativeOrigins = {};
  final Map<GameActor, int> changes = {};
}

/// 伤害上浮与异常图标沿用原 40ms 驱动和 SRS 帧顺序。
final class BattleRaise {
  BattleRaise(GameData data, this.x, this.y, this.delta, int mask, {this.actor})
    : showing = delta != 0 {
    for (final entry in [
      (8, 243),
      (4, 244),
      (2, 245),
      (1, 246),
      (32, 240),
      (64, 241),
      (128, 242),
    ]) {
      if (mask & entry.$1 != 0 && data.record(5, 1, entry.$2) != null) {
        movies.add(GameMovie(data, 1, entry.$2)..iterations = 1);
      }
    }
  }
  final int x, y, delta;

  /// 仅供新版表现层定位；原坐标仍供经典画面使用。
  final GameActor? actor;
  final List<GameMovie> movies = [];
  bool showing;
  int elapsed = 0, step = 0, dy = 0;
  bool update() {
    if (showing) {
      elapsed += 40;
      if (elapsed > 50) {
        elapsed = 0;
        step++;
        dy -= step;
        if (step > 4) showing = false;
      }
      return true;
    }
    if (movies.isEmpty) return false;
    if (!movies.first.update()) movies.removeAt(0);
    return movies.isNotEmpty;
  }
}

final class VictoryCard {
  VictoryCard(
    this.kind,
    this.text, {
    this.y = 36,
    this.rows = const [],
    this.detail = '',
  });
  final String kind, text, detail;
  final int y;
  final List<List<int>> rows;
}

/// 回合、剧情战斗事件与原坐标动画由同一状态机持有。
final class GameBattle {
  GameBattle(
    this.game, {
    required List<int> monsters,
    required this.background,
    required this.randomFight,
    this.maxRound = 0,
    this.eventRounds = const [],
    this.events = const [],
    this.loss = 0,
    this.win = 0,
  }) {
    for (final id in monsters.where((id) => id > 0)) {
      final monster = GameActor.load(game.data, 3, id);
      if (monster != null) this.monsters.add(monster);
    }
    for (final p in game.players) {
      if (p.hp <= 0) p.hp = 1;
    }
    totalMoney = this.monsters.fold(0, (v, m) => v + m.money);
    totalExp = this.monsters.fold(0, (v, m) => v + m.rewardExp);
    // 原剧情单敌战斗在 0 号位保留隐藏占位角色，真实敌人使用 1 号位置。
    if (!randomFight && this.monsters.length == 1) {
      final ghost = GameActor.load(game.data, 3, this.monsters.first.index);
      if (ghost != null) {
        ghost.hp = -1;
        ghost.visible = false;
        this.monsters.insert(0, ghost);
      }
    }
    _positions();
    presentationEnemies = List.unmodifiable(
      this.monsters.where((m) => m.visible),
    );
    presentationOrigins = Map.unmodifiable({
      for (final actor in [...game.players, ...this.monsters])
        actor: (actor.combatX, actor.combatY),
    });
    _background();
  }
  final GameEngine game;

  /// 仅向表现层提供初始坐标，避免新版站位反向修改原版进攻轨迹和伤害位置。
  late final Map<GameActor, (int, int)> presentationOrigins;
  late final List<GameActor> presentationEnemies;
  final List<GameActor> monsters = [];
  final List<int> background, eventRounds, events;
  final bool randomFight;
  final int maxRound, loss, win;
  final List<BattleAction> queue = [];
  PixelSurface? terrain;
  BattleAction? current;
  bool _postPending = false;
  final List<BattleRaise> _postRaises = [];
  List<BattleRaise> get visibleRaises {
    if (_postPending) return _postRaises.isEmpty ? [] : [_postRaises.first];
    final action = current;
    if (action == null) return [];
    if (action.kind == 'attack' && action.frame >= 5 || action.stage == 2) {
      return action.raises;
    }
    return [];
  }

  int round = 0,
      actorIndex = 0,
      icon = 1,
      targetIndex = 0,
      phaseTicks = 0,
      totalMoney = 0,
      totalExp = 0;
  String phase = 'select', targetKind = '';
  String? resource;
  bool auto = false, eventChecked = false, scriptPaused = false;
  final Set<GameActor> defending = {};
  final List<VictoryCard> victoryShown = [];
  final List<VictoryCard> _victoryPending = [];
  bool _victoryAdvance = false, _exitWin = false;
  int _victoryElapsed = 0;
  GameMovie? _lossMovie;
  int _playerIndicatorTicks = 0,
      _targetIndicatorTicks = 0,
      _monsterIndicatorTicks = 0;
  GameActor? get selectedPlayer => game.players.isEmpty
      ? null
      : game.players[actorIndex.clamp(0, game.players.length - 1)];
  List<GameActor> get targets =>
      targetKind == 'help' || targetKind == 'item' ? game.players : monsters;

  void _positions() {
    const pp = [(76, 70), (108, 66), (140, 58)],
        mp = [(12, 25), (44, 14), (82, 11)];
    for (var i = 0; i < game.players.length; i++) {
      final p = game.players[i], pos = pp[i.clamp(0, 2)];
      p.combatX = pos.$1;
      p.combatY = pos.$2;
      p.combatFrame = p.alive ? 1 : 12;
    }
    final offset = monsters.length == 1 && !randomFight ? 1 : 0;
    for (var i = 0; i < monsters.length; i++) {
      final m = monsters[i],
          image = game.data.image(8, 3, m.sprite),
          pos = mp[(i + offset).clamp(0, 2)],
          w = image?.width ?? 0,
          h = image?.height ?? 0;
      m.combatX = pos.$1 - w ~/ 6 + w ~/ 2;
      m.combatY = pos.$2 - h ~/ 10 + h ~/ 2;
      m.combatFrame = 1;
    }
  }

  void _background() {
    final s = PixelSurface(160, 96);
    s.clear();
    for (var i = 0; i < math.min(3, background.length); i++) {
      final image = game.data.image(11, 4, background[i]);
      if (image == null) continue;
      s.blit(
        image.frame(0),
        i == 2 ? 160 - image.width : 0,
        i == 1 ? 96 - image.height : 0,
      );
    }
    terrain = s;
  }

  int _computed(GameActor p, int mask, int base) =>
      base + (base * (p.modifiers[mask]?.$1 ?? 0) ~/ 100);
  int _speed(GameActor p) => _computed(p, 128, p.speed);

  void update() {
    if (game.preferences['invincible'] == true) {
      for (final p in game.players) {
        game._clearInvincibleStatus(p);
      }
    }
    phaseTicks++;
    if (scriptPaused && game.cursor?.running != true) scriptPaused = false;
    if (phase == 'select') {
      if (!auto && game.preferences['autoBattle'] != true) {
        if (targetKind.isEmpty) {
          _playerIndicatorTicks++;
        } else if (targetKind == 'help' || targetKind == 'item') {
          _targetIndicatorTicks++;
        } else {
          _monsterIndicatorTicks++;
        }
      }
      if (!eventChecked && !randomFight) {
        eventChecked = true;
        for (var i = 0; i < math.min(events.length, eventRounds.length); i++) {
          if (events[i] > 0 &&
              eventRounds[i] == round &&
              game.triggerEvent(events[i])) {
            scriptPaused = true;
            return;
          }
        }
      }
      if (auto ||
          game.preferences['autoBattle'] == true &&
              targetKind.isEmpty &&
              game.menus.isEmpty) {
        _autoActions();
      }
    } else if (phase == 'perform') {
      if (_postPending) {
        if (_postRaises.isNotEmpty) {
          if (!_postRaises.first.update()) _postRaises.removeAt(0);
          if (_postRaises.isNotEmpty) return;
        }
        _postPending = false;
        if (queue.isNotEmpty) {
          current = queue.removeAt(0);
          return;
        }
      }
      final action = current;
      if (action != null) {
        if (!action.started) {
          _prepare(action);
          return;
        }
        if (!_updateAction(action)) {
          _afterAction(action);
          current = null;
        }
        return;
      }
      if (queue.isNotEmpty) {
        _prepare(queue.removeAt(0));
        return;
      }
      if (monsters.every((p) => !p.alive)) {
        _victory();
      } else if (game.players.every((p) => !p.alive)) {
        phase = 'loss';
        phaseTicks = 0;
      } else {
        round++;

        phase = 'select';
        actorIndex = game.players.indexWhere((p) => p.alive);
        icon = 1;
        targetKind = '';
        // 固定参考运行时仅在首次选择阶段读取剧情战斗事件。
        defending.clear();
      }
    } else if (phase == 'win') {
      _victoryElapsed += 40;
      if (_victoryElapsed > 1000 || _victoryAdvance) {
        _victoryElapsed = 0;
        _victoryAdvance = false;
        if (_victoryPending.isEmpty) {
          _exitWin = true;
          phase = 'exit';
        } else {
          victoryShown.add(_victoryPending.removeAt(0));
        }
      }
    } else if (phase == 'loss') {
      if (randomFight) {
        _lossMovie ??= GameMovie(game.data, 1, 249)..iterations = 5;
        if (_lossMovie?.update() == true) return;
      }
      _exitWin = false;
      phase = 'exit';
    } else if (phase == 'exit') {
      _finish(_exitWin);
    }
  }

  void key(GameKey key, bool down) {
    if (phase == 'win') {
      if (!down) _victoryAdvance = true;
      return;
    }
    if (phase != 'select') return;
    if (targetKind.isNotEmpty) {
      if (down && key.index < 4 && targets.isNotEmpty) {
        for (var i = 0; i < targets.length; i++) {
          targetIndex =
              (targetIndex +
                  (key == GameKey.up || key == GameKey.left ? -1 : 1)) %
              targets.length;
          if (targets[targetIndex].alive ||
              targetKind == 'item' ||
              targetKind == 'help') {
            break;
          }
        }
      }
      if (!down && key == GameKey.cancel) {
        targetKind = '';
        resource = null;
      }
      if (!down && key == GameKey.confirm && targets.isNotEmpty) {
        final p = selectedPlayer;
        if (p != null) {
          _select(
            BattleAction(
              p,
              [targets[targetIndex.clamp(0, targets.length - 1)]],
              targetKind,
              resource: resource,
            ),
          );
        }
      }
      return;
    }
    if (down) {
      if (key == GameKey.up) icon = 1;
      if (key == GameKey.left) icon = 2;
      if (key == GameKey.down) icon = 3;
      if (key == GameKey.right && game.players.length > 1) icon = 4;
    } else if (key == GameKey.confirm) {
      final p = selectedPlayer;
      if (p == null) return;
      switch (icon) {
        case 1:
          if (game.preferences['normalAttackAll'] == true ||
              p.attackStatus & 16 != 0) {
            _select(
              BattleAction(
                p,
                monsters.where((p) => p.alive).toList(),
                'attack',
              ),
            );
          } else {
            _target('attack');
          }
        case 2:
          if (p.status & 2 != 0) return;
          game.openMagic(
            p,
            select: (id) {
              final m = game.magic(id);
              if (m == null) return;
              resource = id;
              final help = m.byte(0) != 1 && m.byte(0) != 5;
              if (m.byte(3) & 128 != 0) {
                _select(
                  BattleAction(
                    p,
                    help ? game.players : monsters,
                    help ? 'help' : 'magic',
                    resource: id,
                  ),
                );
              } else {
                _target(help ? 'help' : 'magic');
              }
            },
          );
        case 3:
          _misc();
        case 4:
          _target('coop');
      }
    } else if (key == GameKey.cancel && actorIndex > 0) {
      actorIndex--;
      while (actorIndex > 0 && !game.players[actorIndex].alive) {
        actorIndex--;
      }
      if (queue.isNotEmpty) queue.removeLast();
      icon = 1;
    }
  }

  void _prepare(BattleAction selected) {
    var next = selected;
    final actor = next.actor;
    if (!actor.alive || actor.status & 1 != 0) {
      _postRaises
        ..clear()
        ..addAll(_awardAndDecay(actor));
      _postPending = true;
      current = null;
      return;
    }
    if (actor.status & 4 != 0) {
      next = BattleAction(actor, [actor], 'self');
    } else if (actor.status & 2 != 0 &&
        (next.kind == 'magic' || next.kind == 'help')) {
      next = BattleAction(
        actor,
        next.targets,
        next.kind == 'magic' ? 'attack' : 'defend',
      );
    }
    if (next.targets.isNotEmpty &&
        next.targets.every((p) => !p.alive) &&
        next.kind != 'help' &&
        next.kind != 'item') {
      final available = actor.type == 1
          ? monsters.where((p) => p.alive).toList()
          : game.players.where((p) => p.alive).toList();
      if (next.targets.length != 1 || available.isEmpty) {
        _postRaises
          ..clear()
          ..addAll(_awardAndDecay(actor));
        _postPending = true;
        current = null;
        return;
      }
      final target = actor.type == 1
          ? available.first
          : available[game.random.nextInt(available.length)];
      next = BattleAction(actor, [target], next.kind, resource: next.resource);
    }
    current = next;
    _begin(next);
  }

  void _target(String kind) {
    targetKind = kind;
    targetIndex = targets
        .indexWhere((p) => p.alive)
        .clamp(0, math.max(0, targets.length - 1));
  }

  void _misc() {
    game.menus.add(
      GameMenu(
        'battle-misc',
        ['围攻', '防御', '逃跑', '物品', '状态'],
        onSelect: (i) {
          game.menus.removeLast();
          final p = selectedPlayer;
          if (p == null) return;
          switch (i) {
            case 0:
              auto = true;
              _autoActions();
            case 1:
              _select(BattleAction(p, [p], 'defend'));
            case 2:
              _flee();
            case 3:
              game.menus.add(
                GameMenu(
                  'battle-goods',
                  ['装备', '投掷', '使用'],
                  onSelect: (mode) {
                    game.menus.removeLast();
                    List<String> available() => game.inventory.keys.where((id) {
                      final type = int.tryParse(id.split(':').first) ?? 0;
                      return mode == 0
                          ? type <= 7
                          : mode == 1
                          ? type == 8 || (type == 7 && game.allowTossArm)
                          : type >= 9 && type <= 12;
                    }).toList();
                    game.openInventory(
                      mode: mode == 0
                          ? 'equip'
                          : mode == 1
                          ? 'throw'
                          : 'use',
                      itemsProvider: available,
                      select: (id) {
                        if (mode == 0) {
                          game.selectEquipmentOwner(id);
                          return;
                        }
                        resource = id;
                        final r = game.goods(id);
                        if (r == null) return;
                        if (r.byte(28) & 16 != 0) {
                          _select(
                            BattleAction(
                              p,
                              mode == 1 ? monsters : game.players,
                              mode == 1 ? 'throw' : 'item',
                              resource: id,
                            ),
                          );
                        } else {
                          _target(mode == 1 ? 'throw' : 'item');
                        }
                      },
                    );
                  },
                ),
              );
            case 4:
              game.openState();
          }
        },
      ),
    );
  }

  void _flee() {
    for (var i = actorIndex; i < game.players.length; i++) {
      final p = game.players[i],
          success = p.alive && randomFight && game.random.nextBool();
      queue.add(BattleAction(p, [], 'flee', fleeSucceeded: success));
      if (success) break;
    }
    _startTurn();
  }

  void _select(BattleAction action) {
    if (action.kind == 'coop') {
      queue.clear();
      queue.add(action);
      _startTurn();
      return;
    }
    queue.add(action);
    targetKind = '';
    resource = null;
    icon = 1;
    var next = actorIndex + 1;
    while (next < game.players.length && !game.players[next].alive) {
      next++;
    }
    if (next >= game.players.length) {
      _startTurn();
    } else {
      actorIndex = next;
    }
  }

  void _autoActions() {
    queue.clear();
    final living = monsters.where((p) => p.alive).toList();
    if (living.isEmpty) {
      _victory();
      return;
    }
    for (final p in game.players.where((p) => p.alive)) {
      queue.add(
        BattleAction(
          p,
          p.attackStatus & 16 != 0 ||
                  game.preferences['normalAttackAll'] == true
              ? living
              : [living.first],
          'attack',
        ),
      );
    }
    _startTurn();
  }

  void _startTurn() {
    final alive = game.players.where((p) => p.alive).toList();
    if (alive.isNotEmpty) {
      for (final m in monsters.where((m) => m.alive)) {
        final target = alive[game.random.nextInt(alive.length)];
        final magics = m
            .magics(game.data)
            .where((id) => (game.magic(id)?.byte(4) ?? 999) < m.mp)
            .toList();
        if (m.status & 2 == 0) {
          final restore = magics
              .where((id) => game.magic(id)?.byte(0) == 3)
              .firstOrNull;
          final attack = magics
              .where((id) => game.magic(id)?.byte(0) == 1)
              .firstOrNull;
          final iq = m.iq / 100;
          if (m.maxHp ~/ m.hp > 3 &&
              restore != null &&
              game.random.nextDouble() < math.sqrt(iq)) {
            final all = (game.magic(restore)?.byte(3) ?? 0) & 128 != 0;
            queue.add(
              BattleAction(m, all ? monsters : [m], 'help', resource: restore),
            );
            continue;
          }
          if (attack != null && game.random.nextDouble() < iq) {
            final all = (game.magic(attack)?.byte(3) ?? 0) & 128 != 0;
            queue.add(
              BattleAction(
                m,
                all ? game.players : [target],
                'magic',
                resource: attack,
              ),
            );
            continue;
          }
        }
        queue.add(
          BattleAction(
            m,
            m.attackStatus & 16 != 0 ? alive : [target],
            'attack',
          ),
        );
      }
    }
    // Dart 的 List.sort 不保证同速稳定性，显式保留原队列的先后顺序。
    final order = <BattleAction, int>{
      for (var i = 0; i < queue.length; i++) queue[i]: i,
    };
    queue.sort((a, b) {
      final pa = a.kind == 'flee' ? _speed(a.actor) * 100 : _speed(a.actor),
          pb = b.kind == 'flee' ? _speed(b.actor) * 100 : _speed(b.actor);
      return pa == pb
          ? (order[a] ?? 0).compareTo(order[b] ?? 0)
          : pb.compareTo(pa);
    });
    phase = 'perform';
    phaseTicks = 0;
    targetKind = '';
    resource = null;
  }

  void _begin(BattleAction action) {
    final actor = action.actor;
    action.started = true;
    action.originX = actor.combatX;
    action.originY = actor.combatY;
    if (action.kind == 'defend' || action.kind == 'flee') return;
    final id = action.resource;
    final record = id == null
        ? null
        : action.kind == 'item' || action.kind == 'throw'
        ? game.goods(id)
        : game.magic(id);
    if ((action.kind == 'item' || action.kind == 'throw') &&
        (id == null || !game.useGoods(id))) {
      return;
    }
    if (record != null) {
      final type = action.kind == 'item' || action.kind == 'throw' ? 2 : 2;
      final animation = action.kind == 'item' || action.kind == 'throw'
          ? record.byte(26)
          : record.byte(5);
      if (animation > 0 && game.data.record(5, type, animation) != null) {
        action.movie = GameMovie(game.data, type, animation)..iterations = 2;
      }
    }
    final beforeStatuses =
        <GameActor, (int, Map<int, int>, Map<int, (int, int)>)>{};
    for (final target in action.targets) {
      action.changes[target] = target.hp;
      beforeStatuses[target] = (
        target.status,
        Map.of(target.statusRounds),
        Map.of(target.modifiers),
      );
    }
    if (action.kind == 'coop') {
      for (final p in game.players) {
        action.cooperativeOrigins[p] = (p.combatX, p.combatY);
      }
    }
    switch (action.kind) {
      case 'attack':
        for (final target in action.targets.where((p) => p.alive)) {
          _physical(actor, target);
        }
      case 'self':
        _physical(actor, actor, allowMiss: false);
      case 'magic':
        if (record != null) _attackMagic(actor, action.targets, record);
      case 'help':
        if (record != null) {
          if (actor.mp < record.byte(4)) break;
          actor.mp -= record.byte(4);
          for (final target in action.targets) {
            switch (record.byte(0)) {
              case 2:
                _modifier(target, 32, record.byte(23), record.byte(24) >> 4);
                _modifier(target, 64, record.byte(22), record.byte(24) >> 4);
                _modifier(target, 128, record.byte(25), record.byte(24) >> 4);
              case 3:
                target.hp = math.min(target.maxHp, target.hp + record.word(18));
                target.clearStatus(record.byte(24));
              case 4:
                target.hp = math.min(
                  target.maxHp,
                  target.hp + target.maxHp * record.word(18) ~/ 100,
                );
            }
          }
        }
      case 'throw':
        if (record != null) {
          for (final target in action.targets) {
            final hp = record.byte(0) == 7
                    ? record.byte(25) * 50
                    : record.signedWord(22),
                mp = record.byte(0) == 7 ? 0 : record.signedWord(24);
            _hurt(actor, target, hp);
            target.mp = math.min(target.maxMp, target.mp - mp);
            _status(record.byte(28) & 15, record.byte(4), target, luck: 0);
          }
        }
      case 'item':
        // 库存已在_begin入口统一扣一份，不能在全体目标循环里再次扣除。
        // 比例回气、永久成长与增强药按ROM中的数值和回合数生效。
        if (record != null) {
          for (final target in action.targets) {
            if (record.byte(0) >= 9 && record.byte(0) <= 11) {
              game._applyMedicineEffect(target, record);
            } else if (record.byte(0) == 12) {
              _modifier(target, 32, record.byte(25), record.byte(4));
              _modifier(target, 64, record.byte(24), record.byte(4));
              _modifier(target, 128, record.byte(27), record.byte(4));
            }
          }
        }
      case 'coop':
        final decoration = game.players.isEmpty
            ? null
            : game.players.first.equipment.first;
        final equipment = decoration == null ? null : game.goods(decoration);
        final magicId = equipment?.byte(28) ?? 0;
        final magic = magicId > 0 ? game.data.record(4, 1, magicId) : null;
        action.movie = GameMovie(game.data, 2, magic?.byte(5) ?? 240)
          ..iterations = 1;
        for (final p in game.players) {
          if (magic != null) {
            _attackMagic(p, action.targets, magic);
          } else {
            for (final target in action.targets.where((p) => p.alive)) {
              _physical(p, target, rate: 1.6);
            }
          }
        }
    }
    for (final target in action.changes.keys.toList()) {
      final delta = target.hp - (action.changes[target] ?? target.hp);
      action.changes[target] = delta;
      final previous = beforeStatuses[target];
      var mask = 0;
      if (previous != null) {
        for (final bit in [1, 2, 4, 8]) {
          if ((previous.$1 & bit) != (target.status & bit) ||
              previous.$2[bit] != target.statusRounds[bit]) {
            mask |= bit;
          }
        }
        for (final bit in [32, 64, 128]) {
          if (previous.$3[bit] != target.modifiers[bit]) mask |= bit;
        }
      }
      action.raises.add(
        BattleRaise(
          game.data,
          target.combatX,
          target.combatY,
          delta,
          mask,
          actor: target,
        ),
      );
    }
  }

  bool _miss(GameActor source, GameActor target) =>
      game.allowMiss &&
      game.random.nextDouble() <
          (-(_speed(source) - _speed(target)) * .003 + .3);
  void _physical(
    GameActor source,
    GameActor target, {
    double rate = 1,
    bool allowMiss = true,
  }) {
    if (allowMiss && _miss(source, target)) return;
    final base = math.max(
      0,
      _computed(source, 32, source.attack) -
          _computed(target, 64, target.defense),
    );
    final damage =
        math.max(1, (base * rate).truncate()) +
        (game.random.nextDouble() * 10).truncate();
    _hurt(source, target, damage);
    _status(source.attackStatus, source.attackStatusRounds, target);
  }

  void _attackMagic(
    GameActor source,
    List<GameActor> targets,
    GameRecord magic,
  ) {
    if (magic.byte(0) == 5) {
      if (targets.isNotEmpty) {
        final target = targets.first;
        if (target.steal[2] > 0 && game.random.nextDouble() >= .5) {
          game.addGoods('${target.steal[0]}:${target.steal[1]}');
          target.steal[2]--;
        }
      }
      return;
    }
    final all = magic.byte(3) & 128 != 0;
    if (all) source.mp -= magic.byte(4);
    for (final target in targets) {
      if (_miss(source, target)) continue;
      if (!all) source.mp -= magic.byte(4);
      int hurt(int value) => value > 0
          ? math.max(
              0,
              value +
                  (value * (source.spirit - target.spirit) / 100).truncate(),
            )
          : value *
                (target.level <= 8
                    ? 1
                    : target.level <= 16
                    ? 2
                    : 3);
      final hp = hurt(magic.signedWord(18));
      _hurt(source, target, all ? hp : hp.abs());
      if (!all) {
        if (hp < 0) source.hp = math.min(source.maxHp, source.hp - hp);
        final mp = hurt(magic.signedWord(20));
        target.mp = math.min(target.maxMp, target.mp - mp.abs());
        if (mp < 0) source.mp = math.min(source.maxMp, source.mp - mp);
      }
      _status(magic.byte(24) & 15, magic.byte(3) & 127, target);
      _modifier(target, 32, -magic.byte(23), magic.byte(3) & 127);
      _modifier(target, 64, -magic.byte(22), magic.byte(3) & 127);
      _modifier(target, 128, -magic.byte(25), magic.byte(3) & 127);
    }
  }

  void _hurt(GameActor source, GameActor target, int damage) {
    if (target.type == 1 && game.preferences['invincible'] == true) return;
    if (source.type == 1 &&
        target.type == 3 &&
        game.preferences['oneHitKill'] == true) {
      damage = target.hp;
    }
    target.hp = math.min(target.maxHp, target.hp - damage);
  }

  void _status(int mask, int rounds, GameActor target, {int? luck}) {
    if (target.type == 1 && game.preferences['invincible'] == true) return;
    for (final bit in [1, 2, 4, 8]) {
      if (mask & bit != 0 &&
          target.immunity & bit == 0 &&
          game.random.nextDouble() + .01 >=
              math.sqrt((luck ?? target.luck) / 100)) {
        target.status |= bit;
        if (rounds == 0) target.permanentStatus |= bit;
        target.statusRounds[bit] = math.max(
          target.statusRounds[bit] ?? 0,
          rounds,
        );
      }
    }
  }

  void _modifier(GameActor target, int mask, int value, int rounds) {
    if (value < 0 &&
        target.type == 1 &&
        game.preferences['invincible'] == true) {
      return;
    }
    if (value != 0) {
      target.modifiers[mask] = (value, rounds);
    }
  }

  void _decay(GameActor actor) {
    for (final bit in actor.statusRounds.keys.toList()) {
      final rounds = actor.statusRounds[bit] ?? 0;
      if (rounds <= 0) continue;
      final left = rounds - 1;
      if (left <= 0) {
        if (actor.permanentStatus & bit == 0) actor.status &= ~bit;
        actor.statusRounds.remove(bit);
      } else {
        actor.statusRounds[bit] = left;
      }
    }
    final m = actor.modifiers;
    for (final bit in m.keys.toList()) {
      final v = m[bit];
      if (v == null) continue;
      if (v.$2 == 0) continue;
      if (v.$2 <= 1) {
        m.remove(bit);
      } else {
        m[bit] = (v.$1, v.$2 - 1);
      }
    }
  }

  int _restFrame(GameActor p) => !p.alive
      ? 12
      : p.status & 1 != 0 || p.hp < p.maxHp ~/ 10
      ? 11
      : 1;
  bool _updateRaises(BattleAction action) {
    action.raises.removeWhere((r) => !r.update());
    return action.raises.isNotEmpty;
  }

  void _hitTargets(BattleAction action) {
    if (action.hitApplied || action.targets.length != 1) return;
    action.hitApplied = true;
    for (final target in action.targets) {
      if (target.type == 1) {
        target.combatFrame = 10;
      } else {
        target.combatX += 2;
        target.combatY += 2;
      }
    }
  }

  bool _updateAction(BattleAction action) {
    action.tick++;
    if (action.tick % 2 == 0) action.frame++;
    final frame = action.frame, a = action.actor;
    if (action.kind == 'defend') return false;
    if (action.kind == 'flee') {
      if (frame < 5) {
        a.combatY = action.originY + (96 - action.originY) * frame ~/ 5;
        return true;
      }
      if (!action.fleeSucceeded) {
        a.combatY = action.originY;
        a.combatFrame = 11;
      }
      return false;
    }
    if (action.kind == 'attack') {
      if (frame < 5 && action.targets.isNotEmpty) {
        final t = action.targets.first;
        a.combatX = (action.originX + (t.combatX - action.originX) * frame / 5)
            .truncate();
        a.combatY = (action.originY + (t.combatY - action.originY) * frame / 5)
            .truncate();
        final frames =
            game.data
                .image(
                  a.type == 1 ? 11 : 8,
                  3,
                  a.type == 1 ? a.index : a.sprite,
                )
                ?.frames
                .length ??
            1;
        a.combatFrame = a.type == 1 ? frame + 1 : frames * frame ~/ 5 + 1;
      } else if (frame == 5) {
        a.combatX = action.originX;
        a.combatY = action.originY;
        a.combatFrame = _restFrame(a);
        _hitTargets(action);
      } else if (frame > 5) {
        return _updateRaises(action);
      }
      return true;
    }
    final coop = action.kind == 'coop', threshold = coop ? 15 : 10;
    if (action.stage == 0) {
      if (frame < threshold) {
        if (coop) {
          var i = 0;
          const points = [(92, 52), (109, 63), (126, 74)];
          for (final p in game.players) {
            final origin =
                    action.cooperativeOrigins[p] ?? (p.combatX, p.combatY),
                dest = points[i.clamp(0, 2)];
            if (frame < 5) {
              p.combatX = (origin.$1 + (dest.$1 - origin.$1) * frame / 5)
                  .truncate();
              p.combatY = (origin.$2 + (dest.$2 - origin.$2) * frame / 5)
                  .truncate();
            } else {
              p.combatFrame = (frame - 5) * 3 ~/ 10 + 6;
            }
            i++;
          }
        } else if (action.kind == 'self') {
          a.combatX = action.originX + 2;
          a.combatY = action.originY + 2;
        } else if (a.type == 1) {
          a.combatFrame = 6 + frame * 3 ~/ 10;
        } else {
          a.combatX = action.originX + 2;
          a.combatY = action.originY + 2;
        }
      } else {
        action.stage = action.kind == 'self' ? 2 : 1;
        a.combatX = action.originX;
        a.combatY = action.originY;
      }
      return true;
    }
    if (action.stage == 1) {
      if (action.movie?.update() == true) return true;
      action.stage = 2;
      a.combatX = action.originX;
      a.combatY = action.originY;
      a.combatFrame = _restFrame(a);
      if (coop) {
        for (final p in game.players) {
          final origin = action.cooperativeOrigins[p];
          if (origin != null) {
            p.combatX = origin.$1;
            p.combatY = origin.$2;
          }
          p.combatFrame = _restFrame(p);
        }
      }
      if (action.kind == 'magic' || action.kind == 'throw') _hitTargets(action);
      return true;
    }
    if (action.stage == 2) {
      if (_updateRaises(action)) return true;
      if (action.kind == 'magic' &&
          (action.resource == null ||
              (game.magic(action.resource!)?.byte(3) ?? 0) & 128 == 0)) {
        action.stage = 3;
        return true;
      }
      return false;
    }
    return false;
  }

  void _afterAction(BattleAction action) {
    final a = action.actor;
    a.combatX = action.originX;
    a.combatY = action.originY;
    a.combatFrame = a.alive ? 1 : 12;
    if (action.hitApplied) {
      for (final target in action.targets) {
        if (target.type == 3) {
          target.combatX -= 2;
          target.combatY -= 2;
        } else {
          target.combatFrame = _restFrame(target);
        }
      }
    }
    _postRaises
      ..clear()
      ..addAll(_awardAndDecay(a));
    _postPending = true;
    if (action.kind == 'flee' && action.fleeSucceeded) {
      _finish(true, flee: true);
    }
    for (final target in action.targets) {
      if (target.type == 3 && !target.alive) target.visible = false;
    }
    for (final p in game.players) {
      p.combatFrame = !p.alive
          ? 12
          : p.status & 1 != 0 || p.hp < p.maxHp ~/ 10
          ? 11
          : 1;
    }
  }

  /// 状态与饰品的回合结算也作用于睡眠/跳过动作的角色。
  List<BattleRaise> _awardAndDecay(GameActor a) {
    final animations = <BattleRaise>[];
    if (a.alive) {
      if (a.type == 1) {
        final decorations = a.equipment.take(2).whereType<String>().toList();
        if (decorations.isNotEmpty) {
          final before = a.hp;
          for (final id in decorations) {
            final r = game.goods(id);
            if (r != null) {
              a.hp = math.min(a.maxHp, a.hp + r.signedByte(23));
              a.mp = math.min(a.maxMp, a.mp + r.signedByte(22));
            }
          }
          animations.add(
            BattleRaise(
              game.data,
              a.combatX,
              a.combatY,
              a.hp - before,
              0,
              actor: a,
            ),
          );
        }
      }
      if (a.status & 8 != 0 &&
          !(a.type == 1 && game.preferences['invincible'] == true)) {
        final before = a.hp;
        a.hp = a.hp == 1 ? 0 : (a.hp * .75).truncate();
        animations.add(
          BattleRaise(
            game.data,
            a.combatX,
            a.combatY,
            a.hp - before,
            0,
            actor: a,
          ),
        );
      }
    }
    _decay(a);
    return animations;
  }

  /// 奖励在进入胜利态时一次性结算，展示与按键只推进原顺序的提示卡片。
  void _victory() {
    if (phase == 'win') return;
    phase = 'win';
    phaseTicks = 0;
    _victoryElapsed = 0;
    _victoryAdvance = false;
    game.money += totalMoney;
    final levels = <VictoryCard>[];
    for (final p in game.players.where((p) => p.alive)) {
      final chain = game.data.record(12, 2, p.index);
      if (chain == null) continue;
      if (p.level >= chain.byte(2)) break;
      final needed = chain.word(4 + (p.level - 1) * 20 + 14),
          exp = p.exp + totalExp;
      p.exp = exp;
      if (exp >= needed) {
        final previous = p.level;
        p.exp = exp - needed;
        p.levelUp(game.data, previous + 1);
        int difference(int offset, {bool byte = false}) => byte
            ? chain.byte(4 + (p.level - 1) * 20 + offset) -
                  chain.byte(4 + (previous - 1) * 20 + offset)
            : chain.word(4 + (p.level - 1) * 20 + offset) -
                  chain.word(4 + (previous - 1) * 20 + offset);
        final rows = <List<int>>[
          [p.hp, p.maxHp - difference(0), p.maxHp, p.maxHp],
          [p.mp, p.maxMp - difference(4), p.maxMp, p.maxMp],
          [p.attack - difference(8), p.attack],
          [p.defense - difference(10), p.defense],
          [p.speed - difference(16, byte: true), p.speed],
          [p.spirit - difference(17, byte: true), p.spirit],
          [p.luck - difference(18, byte: true), p.luck],
        ];
        levels.add(VictoryCard('message', '${p.name}修行提升'));
        levels.add(VictoryCard('level', '${p.name}修行提升', rows: rows));
        final magicChain = game.data.record(12, 1, p.chain),
            old = chain.byte(4 + (previous - 1) * 20 + 19),
            next = chain.byte(4 + (p.level - 1) * 20 + 19);
        if (magicChain != null) {
          for (var i = old; i < next && i < magicChain.byte(2); i++) {
            final id =
                '${magicChain.byte(3 + i * 2)}:${magicChain.byte(4 + i * 2)}';
            levels.add(
              VictoryCard('learn', p.name, detail: game.magicName(id)),
            );
          }
        }
      }
    }
    var luck = 10;
    for (final p in game.players) {
      luck = math.max(luck, p.luck);
    }
    luck = (luck - 10).clamp(0, 100);
    final goods = <String, int>{};
    for (final m in monsters) {
      if (m.drop.every((v) => v > 0) && game.random.nextInt(101) < luck) {
        final id = '${m.drop[0]}:${m.drop[1]}';
        game.addGoods(id, m.drop[2]);
        goods[id] = (goods[id] ?? 0) + m.drop[2];
      }
    }
    final e = '$totalExp', m = '$totalMoney';
    victoryShown
      ..clear()
      ..add(
        VictoryCard(
          'message',
          '${'获得经验     '.substring(0, (9 - e.length).clamp(0, 9))}$e',
          y: 18,
        ),
      )
      ..add(
        VictoryCard(
          'message',
          '${'战斗获得        '.substring(0, (10 - m.length).clamp(0, 12))}$m钱',
          y: 46,
        ),
      );
    _victoryPending.clear();
    for (final group in [true, false]) {
      for (final item in goods.entries) {
        final type = int.tryParse(item.key.split(':').first) ?? 0;
        if ((type >= 8) == group) {
          _victoryPending.add(
            VictoryCard(
              'message',
              '得到 ${game.goodsName(item.key)} x${item.value}',
            ),
          );
        }
      }
    }
    _victoryPending.addAll(levels);
  }

  void _drawVictoryCard(VictoryCard card) {
    GameBitmap? background;
    PixelSurface panel;
    if (card.kind == 'message') {
      final width = game.data.encoding.encode(card.text).length * 8 + 8;
      panel = PixelSurface(width, 24, textLayout: game.textLayout);
      panel.clear();
      final side = game.data.image(11, 2, 8);
      panel.blit(side?.frame(0), 0, 0);
      panel.blit(side?.frame(1), width - 3, 0);
      panel.line(0, 1, width, 1);
      panel.line(0, 22, width, 22);
      // 原提示图的线段终点会落到下一行首列，显式保留底角像素而不允许越界。
      panel.dot(0, 23, 0xff000000);
      panel.text(game.data, card.text, 4, 4, right: width - 4, bottom: 20);
    } else {
      final image = game.data.image(11, 2, card.kind == 'level' ? 9 : 10);
      background = image?.frame(0);
      if (background == null) return;
      panel = PixelSurface(
        background.width,
        background.height,
        textLayout: game.textLayout,
      );
      panel.blit(background, 0, 0);
      if (card.kind == 'level') {
        for (var row = 0; row < card.rows.length; row++) {
          final values = card.rows[row],
              xs = row < 2 ? [37, 56, 86, 105] : [47, 96];
          for (var i = 0; i < values.length; i++) {
            panel.text(
              game.data,
              '${values[i]}',
              xs[i],
              9 + row * 12,
              fontSize: 8,
              right: xs[i] + 32,
              bottom: 20 + row * 12,
            );
          }
        }
      } else {
        panel.text(
          game.data,
          card.text,
          math.max(0, (panel.width - card.text.length * 14) ~/ 2),
          8,
          right: panel.width,
          bottom: 24,
        );
        panel.text(
          game.data,
          card.detail,
          math.max(0, (panel.width - card.detail.length * 14) ~/ 2),
          42,
          right: panel.width,
          bottom: 58,
        );
      }
    }
    final localX = (160 - panel.width) ~/ 2,
        localY = card.kind == 'message' ? card.y : (96 - panel.height) ~/ 2;
    final left = game.wide ? (localX * 2 + panel.width / 2).round() : localX,
        top = game.wide ? (localY * 2 + panel.height / 2).round() : localY;
    game.surface.blit(
      GameBitmap(panel.width, panel.height, panel.pixels),
      left,
      top,
    );
    for (final run in panel.textRuns) {
      game.surface.textRuns.add(
        SystemTextRun(
          run.text,
          run.x + left,
          run.y + top,
          run.width,
          run.height,
          run.selected,
          run.fontSize,
        ),
      );
    }
  }

  void forceWin() {
    for (final m in monsters) {
      m.hp = 0;
    }
    queue.clear();
    current = null;
    _victory();
  }

  void _finish(bool won, {bool flee = false}) {
    for (final p in game.players) {
      p.modifiers.clear(); // 战斗用临时加成不进入下一场战斗，永久成长保留在基础属性中。
      p.hp = math.max(1, p.hp);
      p.mp = math.max(1, p.mp);
      p.hp = (p.hp + (p.maxHp - p.hp) ~/ 10).clamp(1, p.maxHp);
      p.mp = (p.mp + p.maxMp ~/ 5).clamp(0, p.maxMp);
    }
    game.battle = null;
    game.route.clear();
    if (!randomFight) {
      game.jump(won ? win : loss);
    } else if (!won) {
      game.screen = 'title';
    }
    game.render();
  }

  void draw() {
    final s = game.surface, t = terrain;
    if (game.wide) {
      final grid = game.data.image(11, 4, 2)?.frame(0);
      s.clear();
      if (grid != null) {
        for (var y = 0; y < 192; y++) {
          for (var x = 0; x < 320; x++) {
            s.pixels[y * 320 + x] =
                grid.pixels[((y - 48) % 16) * grid.width + (x - 80) % 30];
          }
        }
      }
      if (t != null) s.blit(GameBitmap(160, 96, t.pixels), 80, 48);
    } else if (t != null) {
      s.pixels.setAll(0, t.pixels);
    }
    void fighter(GameActor p) {
      if (p.type == 3 && !p.visible) return;
      final image = game.data.image(
        p.type == 1 ? 11 : 8,
        3,
        p.type == 1 ? p.index : p.sprite,
      );
      if (image == null) return;
      final x = game.wide
          ? (p.combatX * 2 - image.width / 2).round()
          : p.combatX - image.width ~/ 2;
      final y = game.wide
          ? (p.combatY * 2 - image.height / 2 - 16).round()
          : p.combatY - image.height ~/ 2;
      s.blit(image.frame(p.combatFrame - 1), x, y);
    }

    for (final m in monsters) {
      fighter(m);
    }
    for (final p in game.players.reversed) {
      fighter(p);
    }
    final action = current;
    if (action != null && action.stage == 1 && action.movie != null) {
      final target = action.targets.isEmpty ? null : action.targets.first;
      final record = action.resource == null
          ? null
          : game.magic(action.resource!);
      final all = (record?.byte(3) ?? 0) & 128 != 0;
      final targetImage = target == null
          ? null
          : game.data.image(
              target.type == 1 ? 11 : 8,
              3,
              target.type == 1 ? target.index : target.sprite,
            );
      final animationY =
          (target?.combatY ?? 0) -
          ((action.kind == 'magic' || action.kind == 'coop')
              ? (targetImage?.height ?? 0) ~/ 2
              : 0);
      game._drawMovie(
        action.movie!,
        all ? 0 : target?.combatX ?? 0,
        all ? 0 : animationY,
        absolute: !all,
        worldOffset: game.wide ? -16 : 0,
      );
    }
    for (final raise in visibleRaises) {
      if (raise.showing) {
        final scale = game.wide ? 2 : 1;
        game.surface.text(
          game.data,
          '${raise.delta > 0 ? '+' : ''}${raise.delta}',
          raise.x * scale + (game.wide ? 4 : 0),
          (raise.y + raise.dy) * scale + (game.wide ? -13 : 0),
          fontSize: 8,
          right: raise.x * scale + 70,
          bottom: (raise.y + raise.dy) * scale + 14,
        );
      } else if (raise.movies.isNotEmpty) {
        game._drawMovie(
          raise.movies.first,
          raise.x,
          raise.y,
          absolute: true,
          worldOffset: game.wide ? -16 : 0,
        );
      }
    }
    if (phase == 'select' && !auto) {
      final p = selectedPlayer;
      if (targetKind.isEmpty) {
        final menu = game.data.image(11, 2, 1);
        s.blit(
          menu?.frame(icon - 1),
          game.wide ? 14 : 7,
          s.height - (menu?.height ?? 0),
        );
        if (p != null) {
          game._image(11, 2, 2, game.wide ? 98 : 49, game.wide ? 162 : 66);
          game._image(
            11,
            1,
            p.index,
            game.wide ? 99 : 50,
            game.wide ? 159 : 63,
          );
          game._smallNumber(p.hp, game.wide ? 128 : 79, game.wide ? 168 : 72);
          game._smallNumber(
            p.maxHp,
            game.wide ? 153 : 104,
            game.wide ? 168 : 72,
          );
          game._smallNumber(p.mp, game.wide ? 128 : 79, game.wide ? 179 : 83);
          game._smallNumber(
            p.maxMp,
            game.wide ? 153 : 104,
            game.wide ? 179 : 83,
          );
        }
      }
      const pp = [(69, 45), (101, 41), (133, 33)],
          mp = [(16, 14), (48, 3), (86, 0)];
      final ally = targetKind == 'help' || targetKind == 'item',
          positions = targetKind.isEmpty || ally ? pp : mp;
      var index = targetKind.isEmpty ? actorIndex : targetIndex;
      if (positions == mp && monsters.length == 1 && !randomFight) index++;
      final pos = positions[index.clamp(0, 2)],
          indicator = game.data.image(
            11,
            2,
            targetKind.isEmpty || ally ? 4 : 3,
          );
      if (indicator != null) {
        final frame = targetKind.isEmpty
            ? (_playerIndicatorTicks ~/ 5) % 2
            : ally
            ? 2 + (_targetIndicatorTicks ~/ 5) % 2
            : (_monsterIndicatorTicks ~/ 5) % indicator.frames.length;
        s.blit(
          indicator.frame(frame),
          game.wide ? (pos.$1 * 2 + indicator.width / 2).round() : pos.$1,
          game.wide ? (pos.$2 * 2 + indicator.height / 2 - 16).round() : pos.$2,
        );
      }
    } else if (phase == 'win') {
      for (final card in victoryShown) {
        _drawVictoryCard(card);
      }
    } else if (phase == 'loss' && randomFight && _lossMovie != null) {
      game._drawMovie(_lossMovie!, 0, 0);
    }
  }
}
