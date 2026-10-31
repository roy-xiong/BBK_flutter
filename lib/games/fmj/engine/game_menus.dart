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
    this.onRefresh,
    this.purchase,
    this.equipmentOwner,
    this.equipmentSlot,
  });
  final String kind;
  final List<String> items;
  final List<String> ids;
  final String mode;
  final int actor;
  final void Function(int index)? onSelect;
  final void Function(GameMenu menu)? onRefresh;
  final GamePurchase? purchase;

  /// 从穿戴页进入时固定人物与部位；背包入口为空，按当前队伍逐人比较。
  final GameActor? equipmentOwner;
  final int? equipmentSlot;
  int selected = 0, page = 0, revision = 0;
}

/// 购买框只持有待确认数量。库存和金钱在确认前不变，取消无需回滚存档数据。
final class GamePurchase {
  GamePurchase(this.id, this.unitPrice, {this.selling = false});
  final String id;
  final int unitPrice;
  final bool selling;
  int quantity = 0, limit = 0;
  int get total => quantity * unitPrice;
}

/// 只读换装投影；变化项使用「属性名、当前值、更换后值」，不提前消费背包或触发标记。
final class EquipmentComparison {
  EquipmentComparison(
    this.player,
    this.slot,
    Iterable<(String, int, int)> changes,
    Iterable<String> added,
    Iterable<String> removed,
  ) : changes = List.unmodifiable(changes),
      addedEffects = List.unmodifiable(added),
      removedEffects = List.unmodifiable(removed);
  final GameActor player;
  final int slot;
  final List<(String, int, int)> changes;
  final List<String> addedEffects, removedEffects;
}

extension GameMenus on GameEngine {
  /// 库存列表必须跟随装备、卸下、购买、出售和消耗刷新。刷新只更新菜单数据，
  /// 不触发选择回调，不捕获Widget，保留仍存在的选中物品及合法的选择位置。
  void refreshMenus() {
    for (final menu in menus) {
      menu.onRefresh?.call(menu);
      final count = menu.kind == 'state'
          ? players.length
          : menu.kind == 'equipment'
          ? (players.isEmpty ? 0 : 8)
          : menu.items.length;
      menu.selected = count == 0 ? 0 : menu.selected.clamp(0, count - 1);
    }
  }

  /// 触屏与键盘共用提交入口。旧界面的点击不能作用到刷新后同一索引的新物品。
  bool selectMenu(GameMenu menu, int index, {String? expectedId}) {
    if (!identical(menus.lastOrNull, menu)) return false;
    refreshMenus();
    final count = menu.kind == 'equipment'
        ? (players.isEmpty ? 0 : 8)
        : menu.kind == 'state'
        ? players.length
        : menu.items.length;
    if (index < 0 ||
        index >= count ||
        (expectedId != null && menu.ids.elementAtOrNull(index) != expectedId)) {
      return false;
    }
    menu.selected = index;
    menu.onSelect?.call(index);
    refreshMenus();
    return true;
  }

  void _menuKey(GameKey key, bool down) {
    if (menus.isEmpty) return;
    refreshMenus();
    final menu = menus.last;
    if (menu.purchase != null) {
      if (down && key.index < 4) {
        changePurchaseQuantity(
          menu,
          key == GameKey.right || key == GameKey.up ? 1 : -1,
        );
      } else if (!down && key == GameKey.confirm) {
        selectMenu(menu, 0);
      } else if (!down && key == GameKey.cancel) {
        selectMenu(menu, 1);
      }
      return;
    }
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
      selectMenu(menu, menu.selected);
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
              navigation.cancel();
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

  void _selectPlayer(
    void Function(GameActor player) callback, {
    bool Function(GameActor player)? allowed,
    String emptyMessage = '当前没有可选择的人物',
  }) {
    if (players.isEmpty) return;
    final candidates = players.where((p) => allowed?.call(p) ?? true).toList();
    if (candidates.isEmpty) {
      notice = emptyMessage;
      return;
    }
    late final GameMenu menu;
    menu = GameMenu(
      'actors',
      candidates.map((p) => p.name).toList(),
      ids: candidates.map((p) => '${p.index}').toList(),
      onSelect: (i) {
        if (!identical(menus.lastOrNull, menu) ||
            i < 0 ||
            i >= candidates.length) {
          return;
        }
        final player = candidates[i];
        menus.removeLast();
        if (!players.contains(player) || !(allowed?.call(player) ?? true)) {
          notice = '人物状态已变化，请重新选择';
          return;
        }
        callback(player);
      },
    );
    menus.add(menu);
  }

  /// 读档列表首项固定为自动档；手动保存列表仍只允许写入原三个手动档位。
  List<String> saveSlotLabels({required bool load}) => [
    if (load) '自动存档  ${automaticSave?['scene'] ?? '暂无自动存档'}',
    for (var i = 0; i < saves.length; i++)
      '档位 ${i + 1}  ${saves[i]?['scene'] ?? '空档位'}',
  ];

  void openSaveMenu({bool load = false, bool force = false}) {
    if (!load &&
        !force &&
        (disableSave ||
            cursor?.previous != null ||
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
        saveSlotLabels(load: load),
        onRefresh: (menu) {
          menu.items
            ..clear()
            ..addAll(saveSlotLabels(load: load));
        },
        onSelect: (i) {
          if (load) {
            if (i < 0 || i > saves.length) return;
            final save = i == 0 ? automaticSave : saves[i - 1];
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
            if (i < 0 || i >= saves.length) return;
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
    List<String> Function()? itemsProvider,
    GameActor? equipmentOwner,
    int? equipmentSlot,
  }) {
    final catalog = items == null ? null : List<String>.of(items);
    List<String> currentIds() =>
        (itemsProvider?.call() ?? catalog ?? inventory.keys.toList()).where((
          id,
        ) {
          final record = goods(id);
          if (record == null) return false;
          if (mode == 'buy') return true; // 商店货架不依赖玩家是否已有该物品。
          if ((inventory[id] ?? 0) <= 0) return false;
          final type = record.byte(0);
          return switch (mode) {
            'equip' => type >= 1 && type <= 7,
            'use' => type >= 8,
            'throw' => type == 8 || (type == 7 && allowTossArm),
            _ => true,
          };
        }).toList();
    void rebuild(GameMenu menu) {
      final selectedId = menu.ids.elementAtOrNull(menu.selected),
          next = currentIds();
      if (next.length == menu.ids.length &&
          Iterable<int>.generate(
            next.length,
          ).every((i) => next[i] == menu.ids[i])) {
        return;
      }
      final oldIndex = menu.selected;
      menu.ids
        ..clear()
        ..addAll(next);
      menu.items
        ..clear()
        ..addAll(next.map(goodsName));
      final retained = selectedId == null ? -1 : next.indexOf(selectedId);
      menu.selected = retained >= 0
          ? retained
          : next.isEmpty
          ? 0
          : oldIndex.clamp(0, next.length - 1);
      menu.page = 0;
      menu.revision++;
    }

    late final GameMenu menu;
    menu = GameMenu(
      'inventory',
      <String>[],
      ids: <String>[],
      mode: mode,
      equipmentOwner: equipmentOwner,
      equipmentSlot: equipmentSlot,
      onRefresh: rebuild,
      onSelect: (i) {
        final id = menu.ids.elementAtOrNull(i);
        if (id == null) return;
        final r = goods(id);
        if (r == null) return;
        if (select != null) {
          menus.removeLast();
          select(id);
          return;
        }
        if (mode == 'buy') {
          if ((inventory[id] ?? 0) >= 999) {
            notice = '此物品已达到携带上限';
            return;
          }
          if (money < r.word(18)) {
            notice = '金钱不足';
            return;
          }
          _openPurchase(id, r.word(18));
        } else if (mode == 'sell') {
          if (r.byte(0) == 14 || r.word(132) != 0) {
            notice = '此物不能出售';
            return;
          }
          _openPurchase(id, r.word(20), selling: true);
        } else if (mode == 'equip') {
          selectEquipmentOwner(id);
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
    rebuild(menu);
    menus.add(menu);
  }

  /// 按BBK购买流程进入数量确认。库存上限沿用当前引擎，不能被预览加减提前消耗。
  void _openPurchase(String id, int price, {bool selling = false}) {
    final purchase = GamePurchase(id, price, selling: selling);
    void refresh(GameMenu menu) {
      final room = selling
          ? (inventory[id] ?? 0)
          : (999 - (inventory[id] ?? 0)).clamp(0, 999);
      final cash = selling ? 2147483647 - money : money;
      final affordable = price == 0 ? room : math.max(0, cash) ~/ price;
      final limit = math.min(room, affordable);
      final quantity = purchase.quantity.clamp(0, limit);
      if (purchase.limit != limit || purchase.quantity != quantity) {
        menu.revision++;
      }
      purchase.limit = limit;
      purchase.quantity = quantity;
    }

    late final GameMenu menu;
    menu = GameMenu(
      selling ? 'sell-quantity' : 'buy-quantity',
      [selling ? '确认出售' : '确认购买', '取消'],
      purchase: purchase,
      onRefresh: refresh,
      onSelect: (index) {
        if (!identical(menus.lastOrNull, menu)) return;
        refresh(menu);
        menus.removeLast();
        if (index != 0 || purchase.quantity == 0) return;
        // 在同一同步操作内再次检查数量、余额；旧弹窗或重复点击不能重复成交。
        final quantity = purchase.quantity, total = purchase.total;
        if (selling) {
          final record = goods(id);
          if (record == null ||
              record.byte(0) == 14 ||
              record.word(132) != 0 ||
              total > 2147483647 - money ||
              !useGoods(id, quantity)) {
            return;
          }
          money += total;
          notice = '售出 ${goodsName(id)} ×$quantity';
          return;
        }
        if (goods(id) == null ||
            quantity > 999 - (inventory[id] ?? 0) ||
            total > money) {
          return;
        }
        money -= total;
        addGoods(id, quantity);
        notice = '购入 ${goodsName(id)} ×$quantity';
      },
    );
    refresh(menu);
    menus.add(menu);
  }

  /// 键盘、虚拟方向键和触屏加减共用数量边界，模型变更后通知表现层刷新。
  void changePurchaseQuantity(GameMenu menu, int delta) {
    if (!identical(menus.lastOrNull, menu)) return;
    refreshMenus();
    final purchase = menu.purchase;
    if (purchase == null) return;
    final next = (purchase.quantity + delta).clamp(0, purchase.limit);
    if (next == purchase.quantity) return;
    purchase.quantity = next;
    menu.revision++;
  }

  /// 原购买指令使用“编号、类型”的字节对，清单位于指令参数，不能读取文本。
  void _openShop(List<int> bytes) {
    final ids = <String>[];
    for (var i = 0; i + 1 < bytes.length && bytes[i] != 0; i += 2) {
      final id = '${bytes[i + 1]}:${bytes[i]}';
      if (goods(id) != null) ids.add(id);
    }
    openInventory(mode: 'buy', items: ids);
  }

  /// 原版按角色ID的适用位筛选；男女通用、角色专属装备都沿用原资源限制。
  bool canEquip(GameActor player, String id) {
    final record = goods(id);
    return record != null &&
        record.byte(0) >= 1 &&
        record.byte(0) <= 7 &&
        player.index >= 1 &&
        player.index <= 4 &&
        record.byte(3) & (1 << (player.index - 1)) != 0;
  }

  /// 与实际换装共用槽位规则，显式更换第一饰品槽时不能自动改投第二槽。
  int? _equipmentSlot(GameActor p, GameRecord r, int? requested) {
    const types = [6, 6, 5, 3, 7, 2, 4, 1];
    var slot = requested ?? types.indexOf(r.byte(0));
    if (slot < 0 || slot >= types.length || types[slot] != r.byte(0)) {
      return null;
    }
    if (requested == null &&
        r.byte(0) == 6 &&
        p.equipment[slot] != null &&
        p.equipment[1] == null) {
      slot = 1;
    }
    return slot;
  }

  /// 物品仍保留在列表；此处只筛选可参与对比及确认换装的当前队员。
  List<GameActor> equipmentCandidates(
    String id, {
    GameActor? owner,
    int? slot,
  }) {
    final r = goods(id);
    if (r == null || (inventory[id] ?? 0) <= 0) return [];
    return players
        .where(
          (p) =>
              (owner == null || identical(owner, p)) &&
              canEquip(p, id) &&
              !p.equipment.contains(id) &&
              _equipmentSlot(p, r, slot) != null,
        )
        .toList();
  }

  /// 只在右侧无可对比人物时给出一条提示，不能为每名不适用队员重复占行。
  String equipmentSelectionNotice(String id, {GameActor? owner, int? slot}) {
    if (equipmentCandidates(id, owner: owner, slot: slot).isNotEmpty) return '';
    if (!players.any((p) => canEquip(p, id))) return '当前队伍无人可装备';
    if (owner != null && !canEquip(owner, id)) return '当前人物无法装备';
    return '适用人物已装备此物品';
  }

  /// 使用与穿戴完全相同的先卸后装及逐步封顶规则；仅修改临时属性载体。
  List<EquipmentComparison> equipmentComparisons(
    String id, {
    GameActor? owner,
    int? slot,
  }) {
    final r = goods(id);
    if (r == null) return [];
    return equipmentCandidates(id, owner: owner, slot: slot).map((p) {
      final target = _equipmentSlot(p, r, slot)!;
      final projected = GameActor(p.type, p.index)
        ..attack = p.attack
        ..defense = p.defense
        ..speed = p.speed
        ..spirit = p.spirit
        ..luck = p.luck
        ..maxHp = p.maxHp
        ..maxMp = p.maxMp;
      final old = p.equipment[target];
      final oldRecord = old == null ? null : goods(old);
      if (oldRecord != null) {
        _applyEquipmentAttributes(projected, oldRecord, -1);
      }
      _applyEquipmentAttributes(projected, r, 1);
      final equipment = List<String?>.of(p.equipment)..[target] = id;
      final before = _equipmentEffects(p.equipment),
          after = _equipmentEffects(equipment);
      return EquipmentComparison(
        p,
        target,
        [
          ('攻击', p.attack, projected.attack),
          ('防御', p.defense, projected.defense),
          ('身法', p.speed, projected.speed),
          ('灵力', p.spirit, projected.spirit),
          ('吉运', p.luck, projected.luck),
          ('气血上限', p.maxHp, projected.maxHp),
          ('真气上限', p.maxMp, projected.maxMp),
        ].where((v) => v.$2 != v.$3),
        after.difference(before),
        before.difference(after),
      );
    }).toList();
  }

  /// 按整套装备归并特效，保留另一件防具提供的相同免疫与饰品的合计回复。
  Set<String> _equipmentEffects(List<String?> equipment) {
    final result = <String>{};
    var hp = 0, mp = 0;
    if (preferences['normalAttackAll'] == true) result.add('普通攻击全体');
    for (final id in equipment.whereType<String>()) {
      final r = goods(id);
      if (r == null) continue;
      final type = r.byte(0), mask = r.byte(28);
      if (type == 6) {
        hp += r.signedByte(23);
        mp += r.signedByte(22);
      } else {
        if (type == 7 && (id == '7:9' || mask & 16 != 0)) result.add('普通攻击全体');
        for (final status in [(8, '中毒'), (4, '混乱'), (2, '咒封'), (1, '昏眠')]) {
          if (mask & status.$1 == 0) continue;
          result.add(
            type == 7 ? '攻击附带${status.$2}（${r.byte(4)}回合）' : '免疫${status.$2}',
          );
        }
      }
    }
    if (hp != 0) result.add('每回合气血${hp > 0 ? '+' : ''}$hp');
    if (mp != 0) result.add('每回合真气${mp > 0 ? '+' : ''}$mp');
    return result;
  }

  void selectEquipmentOwner(String id) => _selectPlayer(
    (p) {
      if (equip(p, id)) notice = '已装备 ${goodsName(id)}';
    },
    allowed: (p) => equipmentCandidates(id).contains(p),
    emptyMessage: '当前队伍无人可以装备${goodsName(id)}',
  );

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
            if (actor.mp < r.byte(4)) {
              notice = '真气不足';
              return;
            }
            actor.mp -= r.byte(4);
            final targets = r.byte(3) & 128 != 0 ? players : [target];
            for (final p in targets) {
              p.hp = (p.hp + r.word(18)).clamp(0, p.maxHp);
              p.clearStatus(r.byte(24));
            }
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
          final p = players.elementAtOrNull(actor);
          if (p == null) return;
          menus.add(
            GameMenu(
              'equipment-action',
              ['更换', '卸下', '说明'],
              onSelect: (action) {
                menus.removeLast();
                if (action == 0) {
                  const types = [6, 6, 5, 3, 7, 2, 4, 1];
                  openInventory(
                    mode: 'equip',
                    equipmentOwner: p,
                    equipmentSlot: slot,
                    itemsProvider: () => inventory.keys
                        .where((id) => id.startsWith('${types[slot]}:'))
                        .toList(),
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
    if (r == null || !canEquip(p, id)) {
      notice = '该角色无法装备';
      return false;
    }
    if (fromBag && p.equipment.contains(id)) {
      notice = '已装备 ${goodsName(id)}';
      return false;
    }
    slot = _equipmentSlot(p, r, slot);
    if (slot == null || fromBag && (inventory[id] ?? 0) <= 0) {
      return false;
    }
    final hp = p.hp, mp = p.mp;
    unequip(p, slot);
    if (fromBag && !useGoods(id)) return false;
    p.equipment[slot] = id;
    _equipmentDelta(p, r, 1);
    p.hp = hp.clamp(0, p.maxHp);
    p.mp = mp.clamp(0, p.maxMp);
    refreshMenus();
    return true;
  }

  void unequip(GameActor p, int slot) {
    if (slot < 0 || slot >= 8) return;
    final id = p.equipment[slot];
    if (id == null) return;
    final r = goods(id);
    p.equipment[slot] = null;
    if (r != null) _equipmentDelta(p, r, -1);
    addGoods(id);
  }

  /// 属性投影与真正穿戴共用；这里不写库存、免疫、剧情标记或当前气血真气。
  void _applyEquipmentAttributes(GameActor p, GameRecord r, int sign) {
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
  }

  void _equipmentDelta(GameActor p, GameRecord r, int sign) {
    final type = r.byte(0);
    _applyEquipmentAttributes(p, r, sign);
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
        final flag = r.word(132);
        final stillEquipped = players.any(
          (actor) => actor.equipment.whereType<String>().any(
            (id) => goods(id)?.word(132) == flag,
          ),
        );
        if (!stillEquipped) flags.remove(flag);
      }
    }
    p.hp = p.hp.clamp(0, p.maxHp);
    p.mp = p.mp.clamp(0, p.maxMp);
  }

  bool consumeMedicine(GameActor p, String id) {
    final r = goods(id);
    if (r == null || r.byte(0) < 9 || r.byte(0) > 11 || !useGoods(id)) {
      return false;
    }
    final targets = r.byte(0) == 9 && r.byte(28) & 16 != 0 && players.isNotEmpty
        ? List<GameActor>.of(players)
        : [p];
    for (final target in targets) {
      _applyMedicineEffect(target, r);
    }
    notice = '${targets.length > 1 ? '全队' : p.name}使用了${goodsName(id)}';
    refreshMenus();
    return true;
  }

  /// 数值效果不负责扣库存，战斗及场外均先按一次交易扣一份，再作用于目标。
  void _applyMedicineEffect(GameActor p, GameRecord r) {
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
    p.hp = p.hp.clamp(0, p.maxHp);
    p.mp = p.mp.clamp(0, p.maxMp);
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
