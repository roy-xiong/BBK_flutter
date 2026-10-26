part of 'game_engine.dart';

/// 菜单只保存会话中的选择状态；回调不捕获 Flutter View 或 BuildContext。
final class GameMenu {
  GameMenu(
    this.kind,
    this.items, {
    this.ids = const [],
    this.mode = '',
    this.actor = 0,
    this.onSelect,
  });
  final String kind;
  final List<String> items;
  final List<String> ids;
  final String mode;
  final int actor;
  final void Function(int index)? onSelect;
  int selected = 0, page = 0;
}

extension GameMenus on GameEngine {
  void _menuKey(GameKey key, bool down) {
    if (menus.isEmpty) return;
    final menu = menus.last;
    final count = menu.kind == 'state'
        ? players.length
        : menu.kind == 'equipment'
        ? 8
        : menu.items.length;
    if (!down && key == GameKey.cancel) {
      menus.removeLast();
      return;
    }
    if (down && key.index < 4 && count > 0) {
      if (menu.kind == 'equipment' &&
          (key == GameKey.left || key == GameKey.right)) {
        menu.selected = (menu.selected + 4) % 8;
      } else {
        menu.selected =
            (menu.selected +
                (key == GameKey.up || key == GameKey.left ? -1 : 1)) %
            count;
      }
      menu.page = 0;
    }
    if (down && (key == GameKey.pageDown || key == GameKey.pageUp)) {
      if (menu.kind == 'equipment' && players.length > 1) {
        final actor =
            (menu.actor + (key == GameKey.pageDown ? 1 : -1)) % players.length;
        menus.removeLast();
        openEquipment(actor);
      } else {
        menu.page = math.max(
          0,
          menu.page + (key == GameKey.pageDown ? 80 : -80),
        );
      }
    }
    if (!down && key == GameKey.confirm && count > 0) {
      menu.onSelect?.call(menu.selected);
    }
  }

  void openMainMenu() {
    if (players.isEmpty ||
        battle != null ||
        operation != null ||
        cursor?.running == true) {
      return;
    }
    menus.add(
      GameMenu(
        'main',
        ['属性', '魔法', '物品', '系统'],
        onSelect: (i) {
          switch (i) {
            case 0:
              menus.add(
                GameMenu(
                  'properties',
                  ['状态', '穿戴'],
                  onSelect: (i) {
                    menus.removeLast();
                    if (i == 0) {
                      openState();
                    } else {
                      openEquipment(0);
                    }
                  },
                ),
              );
            case 1:
              _selectPlayer((p) => openMagic(p));
            case 2:
              menus.add(
                GameMenu(
                  'goods',
                  ['使用', '装备'],
                  onSelect: (i) {
                    menus.removeLast();
                    openInventory(mode: i == 0 ? 'use' : 'equip');
                  },
                ),
              );
            case 3:
              openSystemMenu();
          }
        },
      ),
    );
    render();
  }

  void openSystemMenu() {
    menus.add(
      GameMenu(
        'system',
        ['存储进度', '读入进度', '返回游戏', '结束游戏'],
        onSelect: (i) {
          switch (i) {
            case 0:
              openSaveMenu();
            case 1:
              openSaveMenu(load: true);
            case 2:
              menus.clear();
            case 3:
              menus.clear();
              screen = 'title';
          }
        },
      ),
    );
  }

  void openState() {
    if (players.isNotEmpty) {
      menus.add(GameMenu('state', players.map((p) => p.name).toList()));
    }
  }

  void _selectPlayer(void Function(GameActor player) callback) {
    if (players.isEmpty) return;
    menus.add(
      GameMenu(
        'actors',
        players.map((p) => p.name).toList(),
        onSelect: (i) {
          menus.removeLast();
          callback(players[i]);
        },
      ),
    );
  }

  void openSaveMenu({bool load = false, bool force = false}) {
    if (!load &&
        !force &&
        (disableSave ||
            players.isEmpty ||
            battle != null ||
            operation != null ||
            cursor?.running == true)) {
      notice = '当前场景不能存档';
      return;
    }
    menus.add(
      GameMenu(
        load ? 'load' : 'save',
        ['1', '2', '3'],
        onSelect: (i) {
          if (load) {
            final save = saves[i];
            if (save == null) {
              notice = '这是空档位';
              return;
            }
            try {
              restore(save);
              notice = '已读入进度';
            } catch (e) {
              notice = '读档失败：$e';
            }
          } else {
            saves[i] = GameData.decodeObject(jsonEncode(snapshot()));
            menus.removeLast();
            notice = '已保存到档位 ${i + 1}';
            onSaveChanged?.call();
          }
        },
      ),
    );
    render();
  }

  void openInventory({
    String mode = 'use',
    void Function(String id)? select,
    List<String>? items,
  }) {
    final ids =
        items ??
        inventory.keys.where((id) {
          final type = int.tryParse(id.split(':').first) ?? 0;
          return mode == 'equip'
              ? type <= 7
              : mode == 'use'
              ? type >= 8
              : true;
        }).toList();
    final menu = GameMenu(
      'inventory',
      ids.map(goodsName).toList(),
      ids: ids,
      mode: mode,
      onSelect: (i) {
        final id = ids[i], r = goods(id);
        if (r == null) return;
        if (select != null) {
          menus.removeLast();
          select(id);
          return;
        }
        if (mode == 'buy') {
          if (money < r.word(18)) {
            notice = '金钱不足';
            return;
          }
          money -= r.word(18);
          addGoods(id);
          notice = '购入 ${goodsName(id)}';
        } else if (mode == 'sell') {
          if (r.word(132) != 0) {
            notice = '此物不能出售';
            return;
          }
          if (useGoods(id)) {
            money += r.word(20);
            notice = '售出 ${goodsName(id)}';
          }
        } else if (mode == 'equip') {
          _selectPlayer((p) {
            if (equip(p, id)) notice = '已装备 ${goodsName(id)}';
          });
        } else {
          final type = r.byte(0);
          if (type == 13) {
            menus.clear();
            if (!triggerEvent(255)) notice = '当前无法使用';
          } else if (type >= 9 && type <= 11) {
            _selectPlayer((p) {
              consumeMedicine(p, id);
            });
          } else {
            notice = type == 8 || type == 12 ? '战斗中才能使用!' : '当前无法使用!';
          }
        }
      },
    );
    menus.add(menu);
  }

  void _openShop(String text) {
    final bytes = data.encoding.encode(text), ids = <String>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final id = '${bytes[i]}:${bytes[i + 1]}';
      if (goods(id) != null) ids.add(id);
    }
    openInventory(mode: 'buy', items: ids);
  }

  void openMagic(GameActor actor, {void Function(String id)? select}) {
    final ids = actor.magics(data);
    menus.add(
      GameMenu(
        'magic',
        ids.map(magicName).toList(),
        ids: ids,
        onSelect: (i) {
          final id = ids[i], r = magic(id);
          if (r == null) return;
          if (actor.mp < r.byte(4)) {
            notice = '真气不足';
            return;
          }
          if (select != null) {
            menus.removeLast();
            select(id);
            return;
          }
          if (r.byte(0) != 3) {
            notice = '战斗中才能使用!';
            return;
          }
          _selectPlayer((target) {
            if (actor.mp < r.byte(4)) return;
            actor.mp -= r.byte(4);
            target.hp = (target.hp + r.word(18)).clamp(0, target.maxHp);
            target.clearStatus(r.byte(24));
            notice = '已使用 ${magicName(id)}';
          });
        },
      ),
    );
  }

  void openEquipment(int actor) {
    if (players.isEmpty) return;
    actor = actor.clamp(0, players.length - 1);
    menus.add(
      GameMenu(
        'equipment',
        List.filled(8, ''),
        actor: actor,
        onSelect: (slot) {
          final p = players[actor];
          menus.add(
            GameMenu(
              'equipment-action',
              ['更换', '卸下', '说明'],
              onSelect: (action) {
                menus.removeLast();
                if (action == 0) {
                  const types = [6, 6, 5, 3, 7, 2, 4, 1];
                  final ids = inventory.keys
                      .where((id) => id.startsWith('${types[slot]}:'))
                      .toList();
                  openInventory(
                    mode: 'equip',
                    items: ids,
                    select: (id) => equip(p, id, slot: slot),
                  );
                } else if (action == 1) {
                  unequip(p, slot);
                } else {
                  final id = p.equipment[slot];
                  if (id != null) {
                    notice = '${goodsName(id)}：${goods(id)?.text(30) ?? ''}';
                  }
                }
              },
            ),
          );
        },
      ),
    );
  }

  bool equip(GameActor p, String id, {int? slot, bool fromBag = true}) {
    final r = goods(id);
    if (r == null || r.byte(0) > 7 || r.byte(3) & (1 << (p.index - 1)) == 0) {
      notice = '该角色无法装备';
      return false;
    }
    const types = [6, 6, 5, 3, 7, 2, 4, 1];
    slot ??= types.indexWhere((type) => type == r.byte(0));
    if (slot < 0 ||
        slot >= 8 ||
        types[slot] != r.byte(0) ||
        fromBag && (inventory[id] ?? 0) <= 0) {
      return false;
    }
    if (r.byte(0) == 6 && p.equipment[slot] != null && p.equipment[1] == null) {
      slot = 1;
    }
    unequip(p, slot);
    if (fromBag && !useGoods(id)) return false;
    p.equipment[slot] = id;
    _equipmentDelta(p, r, 1);
    return true;
  }

  void unequip(GameActor p, int slot) {
    if (slot < 0 || slot >= 8) return;
    final id = p.equipment[slot];
    if (id == null) return;
    final r = goods(id);
    if (r != null) _equipmentDelta(p, r, -1);
    p.equipment[slot] = null;
    addGoods(id);
  }

  void _equipmentDelta(GameActor p, GameRecord r, int sign) {
    final type = r.byte(0);
    if (type != 6) {
      p.maxMp = (p.maxMp + sign * r.signedByte(22)).clamp(0, 999);
      p.maxHp = (p.maxHp + sign * r.signedByte(23)).clamp(1, 999);
    }
    p.defense = (p.defense + sign * r.signedByte(24)).clamp(0, 999);
    p.attack = (p.attack + sign * r.byte(25)).clamp(0, 999);
    p.spirit = (p.spirit + sign * r.signedByte(26)).clamp(0, 99);
    p.speed = (p.speed + sign * r.signedByte(27)).clamp(0, 99);
    p.luck = (p.luck + sign * r.signedByte(29)).clamp(0, 99);
    if (type == 7) {
      if (sign > 0) {
        p.attackStatus = r.byte(28);
        p.attackStatusRounds = r.byte(4);
      } else {
        p.attackStatus = 0;
        p.attackStatusRounds = 0;
      }
    } else if (type != 6) {
      if (sign > 0) {
        p.changeImmunity(r.byte(28), 1);
      } else {
        p.changeImmunity(r.byte(28), -1);
      }
    }
    if (r.word(132) > 0) {
      if (sign > 0) {
        flags.add(r.word(132));
      } else {
        flags.remove(r.word(132));
      }
    }
    p.hp = p.hp.clamp(0, p.maxHp);
    p.mp = p.mp.clamp(0, p.maxMp);
  }

  void consumeMedicine(GameActor p, String id) {
    final r = goods(id);
    if (r == null || !useGoods(id)) return;
    switch (r.byte(0)) {
      case 9:
        p.hp = (p.hp + r.word(22)).clamp(0, p.maxHp);
        p.mp = (p.mp + r.word(24)).clamp(0, p.maxMp);
        p.clearStatus(r.byte(28));
      case 10:
        p.mp = (p.mp + p.maxMp * r.byte(23).clamp(0, 100) ~/ 100).clamp(
          0,
          p.maxMp,
        );
      case 11:
        p.maxMp = (p.maxMp + r.signedByte(22)).clamp(0, 999);
        p.maxHp = (p.maxHp + r.signedByte(23)).clamp(1, 999);
        p.defense = (p.defense + r.signedByte(24)).clamp(0, 999);
        p.attack = (p.attack + r.signedByte(25)).clamp(0, 999);
        p.spirit = (p.spirit + r.signedByte(26)).clamp(0, 99);
        p.speed = (p.speed + r.signedByte(27)).clamp(0, 99);
        p.luck = (p.luck + r.signedByte(29)).clamp(0, 99);
    }
    notice = '${p.name}使用了${goodsName(id)}';
  }

  /// 选关拥有独立备份；准备角色与剧情状态，不写入三个常规档位。
  void selectStage(Map<String, dynamic> stage) {
    if (canSave) _stageBackup = jsonEncode(snapshot());
    startNewGame();
    operation = null;
    cursor?.running = false;
    flags.addAll((stage['flags'] as List).cast<int>());
    variables[1] = stage['variable'] as int? ?? 0;
    final x = stage['x'] as int, y = stage['y'] as int;
    _loadMap(stage['mapId'] as String, x - 4, y - 3);
    players.clear();
    for (final id in (stage['actors'] as List).cast<int>()) {
      final p = GameActor.load(data, 1, id);
      if (p != null) {
        p.x = x;
        p.y = y;
        players.add(p);
      }
    }
    for (final value in stage['goods'] as List) {
      final item = Map<String, dynamic>.from(value as Map);
      final id = item['id'] as String, minimum = item['count'] as int;
      if ((inventory[id] ?? 0) < minimum) {
        addGoods(id, minimum - (inventory[id] ?? 0));
      }
    }
    for (final value in stage['equipment'] as List) {
      final item = Map<String, dynamic>.from(value as Map);
      final p = _player(item['actor'] as int);
      if (p != null) {
        equip(
          p,
          item['id'] as String,
          slot: item['slot'] as int,
          fromBag: false,
        );
      }
    }
    for (final p in players) {
      p.levelUp(data, stage['level'] as int? ?? 5);
      p.hp = p.maxHp;
      p.mp = p.maxMp;
      p.status = 0;
    }
    money = 5000;
    disableSave = false;
    _chapter(stage['scriptId'] as String);
    if (stage['scriptId'] == '9:13') {
      final event = stage['event'] as int? ?? 0;
      stageStoneProgress = flags.contains(231)
          ? 8
          : event >= 1 && event <= 8
          ? event - 1
          : 0;
    }
    final p = player;
    final direction = stage['direction'];
    if (p != null && direction is int) {
      p.step = (p.step + 1) % 4;
      p.direction = [1, 2, 3, 4][direction.clamp(0, 3)];
    }
    sceneName = stage['scene'] as String? ?? '';
    notice = '已进入「${stage['title']}」';
    onSaveChanged?.call();
    render();
  }

  bool restoreBeforeStage() {
    final backup = _stageBackup;
    if (backup == null) return false;
    restore(GameData.decodeObject(backup));
    _stageBackup = null;
    return true;
  }
}
