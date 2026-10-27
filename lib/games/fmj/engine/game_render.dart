part of 'game_engine.dart';

extension GameRendering on GameEngine {
  /// 绘制逻辑帧，远视野布局直接采用 BBK wide-ui.js 的整数坐标。
  void render() {
    final target = surface;
    if (screen == 'intro') {
      target.clear();
      final movie = intro;
      if (movie != null) _drawMovie(movie, 0, 0, fullScale: true);
      return;
    }
    if (screen == 'title') {
      target.clear();
      if (wide) {
        _text('伏魔记', 136, 24);
        _drawList(['新的故事', '继续故事'], titleSelection, 64, 64, 256, 40);
      } else {
        final img = data.image(11, 2, 14);
        if (img != null) {
          target.blit(
            img.frame(0),
            (160 - img.width) ~/ 2,
            (96 - img.height) ~/ 2,
          );
        }
      }
      for (final menu in menus) {
        _drawMenu(menu);
      }
      return;
    }
    final op = operation;
    final movie = op?.movie;
    if (preferences['modernUi'] == true &&
        !forceClassic &&
        movie == null &&
        op?.kind != 'credits') {
      // 新版直接绘制高清场景，不能在每个 40ms 回调背后再软件绘制整幅经典地图。
      // 对白的 next 参与真实翻页状态机，仍按原窗口宽度分页，不能随像素绘制跳过。
      target.textRuns.clear();
      if (op?.kind == 'dialogue') {
        final head = op!.args.isNotEmpty
            ? data.image(11, 1, op.args.first)
            : null;
        final first = textLayout.fit(
          op.text,
          op.start,
          wide ? (head != null ? 202 : 262) : (head != null ? 101 : 131),
          wide ? 34 : 17,
        );
        op.next = textLayout
            .fit(op.text, first.next, wide ? 262 : 131, wide ? 34 : 17)
            .next;
      }
      return;
    }
    if (movie == null ||
        op == null ||
        op.args.length < 5 ||
        op.args[4] == 2 ||
        op.args[4] == 3) {
      if (battle != null) {
        battle?.draw();
      } else {
        _drawScene();
      }
    }
    if (op != null) {
      switch (op.kind) {
        case 'dialogue':
          _drawDialogue(op);
        case 'choice':
        case 'menu':
          final box = choiceLayout(op);
          _drawList(
            op.options,
            op.selected,
            box.left,
            box.top,
            box.right,
            box.rowHeight,
          );
        case 'message':
        case 'timed':
          _message(op.text);
        case 'movie':
          if (movie != null) _drawMovie(movie, op.args[2], op.args[3]);
        case 'credits':
          _drawCredits(op);
      }
    }
    for (final menu in menus) {
      _drawMenu(menu);
    }
  }

  /// 绘制与触摸共同使用同一选项窗口，避免新字体或滚动后命中错误选项。
  ({int left, int top, int right, int rowHeight, int first, int rows})
  choiceLayout(GameOperation op) {
    final rows = math.min(op.options.length, wide ? 8 : 4),
        first = (op.selected - rows + 1)
            .clamp(0, math.max(0, op.options.length - rows))
            .toInt();
    if (op.kind == 'menu') {
      return (
        left: wide ? 40 : 16,
        top: wide
            ? math.max(8, (192 - rows * 20 - 8) ~/ 2)
            : math.max(4, (96 - rows * 18 - 8) ~/ 2),
        right: wide ? 280 : 144,
        rowHeight: wide ? 20 : 18,
        first: first,
        rows: rows,
      );
    }
    return (
      left: wide ? 48 : 24,
      top: wide ? 56 : 28,
      right: wide ? 272 : 136,
      rowHeight: wide ? 28 : 18,
      first: first,
      rows: rows,
    );
  }

  void _text(
    String value,
    int x,
    int y, {
    bool selected = false,
    int? right,
    int? bottom,
    int start = 0,
  }) {
    surface.text(
      data,
      value,
      x,
      y,
      selected: selected,
      right: right,
      bottom: bottom,
      start: start,
    );
  }

  void _image(
    int kind,
    int type,
    int index,
    int x,
    int y, {
    int frame = 1,
    int scale = 1,
  }) {
    final image = data.image(kind, type, index);
    surface.blit(image?.frame(frame - 1), x, y, scale: scale);
  }

  void _drawList(
    List<String> items,
    int selected,
    int left,
    int top,
    int right,
    int rowHeight,
  ) {
    final rows = math.min(items.length, wide ? 8 : 4),
        first = (selected - rows + 1)
            .clamp(0, math.max(0, items.length - rows))
            .toInt();
    surface.frame(left, top, right, top + rows * rowHeight + 8);
    for (var i = 0; i < rows; i++) {
      final y = top + 5 + i * rowHeight, isSelected = i + first == selected;
      if (isSelected) {
        surface.frame(
          left + 3,
          y - 2,
          right - 3,
          y + rowHeight - 3,
          selected: true,
        );
      }
      _text(
        items[first + i],
        left + 8,
        y,
        selected: isSelected,
        right: right - 4,
      );
    }
  }

  void _message(String text) {
    if (wide) {
      final bytes = data.encoding.encode(text),
          lines = math.max(1, (bytes.length * 8 / 280).ceil());
      final h = math.min(152, lines * 16 + 16), top = ((192 - h) / 2).round();
      surface.frame(12, top, 308, top + h);
      _text(text, 20, top + 8, right: 300, bottom: top + h - 8);
    } else {
      final lines = (data.encoding.encode(text).length ~/ 16)
              .clamp(0, 4)
              .toInt(),
          y = 39 - lines * 8;
      surface.frame(11, y - 2, 149, y + 21 + lines * 16);
      _text(text, 16, y, right: 144, bottom: y + 16 + lines * 16);
    }
  }

  void _drawScene() {
    final m = map;
    if (m == null) {
      surface.clear(0xff28291c);
      return;
    }
    surface.clear();
    final left = wide
        ? (screenX - 5).clamp(0, math.max(0, m.width - 20)).toInt()
        : screenX;
    final top = wide
        ? (screenY - 3).clamp(0, math.max(0, m.height - 12)).toInt()
        : screenY;
    final cols = wide ? 20 : 9, rows = wide ? 12 : 6, offset = wide ? 0 : 8;
    final image = data.image(7, 1, m.tiles);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final mx = (left + x).clamp(0, m.width - 1).toInt(),
            my = (top + y).clamp(0, m.height - 1).toInt();
        surface.blit(
          image?.frame(m.cell(mx, my) & 127),
          x * 16 + offset,
          y * 16,
        );
      }
    }
    final actors = [...npcs.values, ?player];
    actors.sort((a, b) => a.y.compareTo(b.y));
    for (final actor in actors) {
      final resource = data.image(8, actor.type, actor.sprite);
      if (resource == null) continue;
      final base = switch (actor.direction) {
        1 => 0,
        2 => 3,
        3 => 6,
        _ => 9,
      };
      final frame = base + [0, 1, 2, 1][actor.step % 4];
      final x = (actor.x - left) * 16 + offset,
          y = (actor.y - top) * 16 + 16 - resource.height;
      if (!wide && (x < 8 || x >= 152)) continue;
      surface.blit(resource.frame(frame), x, y);
    }
    if (!wide) {
      surface.fill(0, 0, 8, 96);
      surface.fill(152, 0, 160, 96);
      for (var i = 0; i < 4; i++) {
        surface.line(i * 2, 0, i * 2, 96);
        surface.line(152 + i * 2, 0, 152 + i * 2, 96);
      }
    }
  }

  void _drawDialogue(GameOperation op) {
    final head = op.args.isNotEmpty ? data.image(11, 1, op.args.first) : null;
    if (wide) {
      final top = head != null ? 100 : 110;
      surface.frame(18, top, 302, 191);
      surface.rect(20, top + 2, 300, 189);
      if (head != null) {
        surface.blit(head.frame(0), 26, 92);
        surface.line(76, 100, 88, 112);
        surface.line(87, 112, 302, 112);
      }
      final next = surface.text(
        data,
        op.text,
        head != null ? 88 : 28,
        116,
        right: 290,
        bottom: 150,
        start: op.start,
      );
      op.next = surface.text(
        data,
        op.text,
        28,
        152,
        right: 290,
        bottom: 186,
        start: next,
      );
    } else {
      surface.frame(9, head != null ? 50 : 55, 151, 95);
      if (head != null) {
        surface.blit(head.frame(0), 13, 46);
        surface.line(38, 50, 44, 56);
        surface.line(44, 56, 151, 56);
      }
      final next = surface.text(
        data,
        op.text,
        head != null ? 44 : 14,
        58,
        right: 145,
        bottom: 75,
        start: op.start,
      );
      op.next = surface.text(
        data,
        op.text,
        14,
        76,
        right: 145,
        bottom: 93,
        start: next,
      );
    }
  }

  void _drawMovie(
    GameMovie movie,
    int dx,
    int dy, {
    bool fullScale = false,
    bool absolute = false,
    int worldOffset = 0,
  }) {
    final scale = wide ? 2 : 1;
    final curtain = wide && movie.id == '1:3';
    for (final item in movie.active) {
      final header = movie.headers[item[0]], index = header[4];
      if (index < 0 || index >= movie.bitmaps.length) continue;
      final image = movie.bitmaps[index], bitmap = image.frame(0);
      final x = header[0] + dx - (absolute ? movie.headers.first[0] : 0),
          y = header[1] + dy - (absolute ? movie.headers.first[1] : 0);
      if (fullScale || curtain || image.width == 160 && image.height == 96) {
        surface.blit(
          bitmap,
          x * scale,
          y * scale,
          scale: scale,
          extendCurtain: curtain && image.width == 159 && image.height == 2,
        );
      } else {
        surface.blit(
          bitmap,
          wide ? (x * 2 + image.width / 2).round() : x,
          wide ? (y * 2 + image.height / 2).round() + worldOffset : y,
        );
      }
    }
  }

  void _drawCredits(GameOperation op) {
    surface.clear();
    final scale = wide ? 2 : 1;
    final top = op.args.isNotEmpty ? data.image(11, 5, op.args[0]) : null;
    final bottom = op.args.length > 1 ? data.image(11, 5, op.args[1]) : null;
    final y =
        surface.height -
        (bottom?.height ?? 0) * scale -
        op.elapsed ~/ 50 * scale;
    final lines = (op.text.length * 16 / surface.width).ceil() + 1;
    surface.text(
      data,
      op.text,
      0,
      y,
      right: surface.width,
      bottom: y + lines * 16,
    );
    surface.blit(top?.frame(0), 0, 0, scale: scale);
    surface.blit(
      bottom?.frame(0),
      0,
      surface.height - (bottom?.height ?? 0) * scale,
      scale: scale,
    );
    if (y + lines * 16 < 0) operation = null;
  }

  void _smallNumber(int value, int x, int y) {
    surface.text(
      data,
      value.abs().toString(),
      x,
      y,
      fontSize: 8,
      right: x + 40,
      bottom: y + 11,
    );
  }

  void _drawMenu(GameMenu menu) {
    final kind = menu.kind;
    if (kind == 'main') {
      surface.frame(
        wide ? 12 : 8,
        wide ? 8 : 0,
        wide ? 160 : 94,
        wide ? 38 : 22,
      );
      _text('金钱:$money', wide ? 20 : 10, wide ? 15 : 3);
      _drawList(
        menu.items,
        menu.selected,
        wide ? 12 : 8,
        wide ? 44 : 24,
        wide ? 160 : 94,
        wide ? 30 : 17,
      );
    } else if (kind == 'system') {
      _drawList(
        menu.items,
        menu.selected,
        wide ? 80 : 40,
        wide ? 24 : 8,
        wide ? 248 : 124,
        wide ? 34 : 18,
      );
    } else if (kind == 'properties' || kind == 'goods') {
      _drawList(
        menu.items,
        menu.selected,
        wide ? 80 : 39,
        wide ? 56 : 16,
        wide ? 240 : 77,
        wide ? 28 : 16,
      );
    } else if (kind == 'inventory' || kind == 'magic') {
      surface.clear();
      final list = menu.ids;
      if (list.isEmpty) {
        _text(
          kind == 'magic' ? '没有法术' : '没有物品',
          wide ? 128 : 40,
          wide ? 88 : 40,
        );
        return;
      }
      final item = list[menu.selected.clamp(0, list.length - 1).toInt()];
      if (wide) {
        surface.frame(4, 4, 148, 188);
        surface.frame(152, 4, 316, kind == 'magic' ? 188 : 80);
        if (kind != 'magic') surface.frame(152, 84, 316, 188);
        final first = (menu.selected - 7)
            .clamp(0, math.max(0, list.length - 8))
            .toInt();
        for (var row = 0; row < 8 && first + row < list.length; row++) {
          final id = list[first + row],
              r = kind == 'magic' ? magic(id) : goods(id);
          if (kind != 'magic' && r != null) {
            _image(9, r.byte(0), r.byte(5), 12, 10 + row * 22);
          }
          _text(
            kind == 'magic' ? magicName(id) : goodsName(id),
            kind == 'magic' ? 12 : 40,
            kind == 'magic' ? 12 + row * 21 : 10 + row * 22,
            selected: first + row == menu.selected,
            right: 144,
          );
        }
        final r = kind == 'magic' ? magic(item) : goods(item);
        _text(
          kind == 'magic' ? magicName(item) : goodsName(item),
          160,
          12,
          right: 308,
        );
        _text(
          kind == 'magic'
              ? '耗真气:${r?.byte(4) ?? 0}'
              : '价格:${menu.mode == 'buy' ? r?.word(18) ?? 0 : r?.word(20) ?? 0}',
          160,
          kind == 'magic' ? 36 : 34,
          right: 308,
        );
        if (kind != 'magic') {
          _text(
            menu.mode == 'buy' ? '金钱:$money' : '数量:${inventory[item] ?? 0}',
            160,
            56,
            right: 308,
          );
        }
        _text(
          r?.text(kind == 'magic' ? 26 : 30) ?? '',
          160,
          kind == 'magic' ? 64 : 92,
          right: 308,
          bottom: 180,
          start: menu.page,
        );
      } else {
        final first = (menu.selected - 3)
            .clamp(0, math.max(0, list.length - 4))
            .toInt();
        _drawList(
          list
              .skip(first)
              .take(4)
              .map((v) => kind == 'magic' ? magicName(v) : goodsName(v))
              .toList(),
          menu.selected - first,
          0,
          0,
          100,
          20,
        );
      }
    } else if (kind == 'state') {
      surface.clear();
      final p = players[menu.selected.clamp(0, players.length - 1).toInt()];
      if (wide) {
        for (var i = 0; i < players.length; i++) {
          surface.frame(8, 8 + i * 54, 72, 56 + i * 54);
          _image(11, 1, players[i].index, 12, 12 + i * 54);
          _text(
            players[i].name,
            12,
            36 + i * 54,
            selected: i == menu.selected,
            right: 72,
          );
        }
        final chain = data.record(12, 2, p.index),
            next = chain != null && p.level <= chain.byte(2)
                ? chain.word(4 + (p.level - 1) * 20 + 14)
                : 0;
        final values = [
          '等级 ${p.level}',
          '生命 ${p.hp}/${p.maxHp}',
          '真气 ${p.mp}/${p.maxMp}',
          '攻击力 ${p.attack}',
          '防御力 ${p.defense}',
          '经验 ${p.exp}/$next',
          '身法 ${p.speed}',
          '灵力 ${p.spirit}',
          '幸运 ${p.luck}',
          '免疫 ${p.immunity == 0 ? '无' : '${p.immunity & 8 != 0 ? '毒' : ''}${p.immunity & 4 != 0 ? '乱' : ''}${p.immunity & 2 != 0 ? '封' : ''}${p.immunity & 1 != 0 ? '眠' : ''}'}',
        ];
        for (var i = 0; i < values.length; i++) {
          _text(values[i], 84, 6 + i * 18);
        }
      } else {
        _image(11, 1, p.index, 2, 2);
        _text(p.name, 2, 40);
        _text('等级 ${p.level}', 42, 4);
        _text('生命 ${p.hp}/${p.maxHp}', 42, 22);
        _text('真气 ${p.mp}/${p.maxMp}', 42, 40);
        _text('攻击 ${p.attack}', 42, 58);
        _text('防御 ${p.defense}', 42, 76);
      }
    } else if (kind == 'equipment') {
      surface.clear();
      final p = players[menu.actor.clamp(0, players.length - 1).toInt()];
      _image(11, 1, p.index, wide ? 8 : 0, 4);
      _text(p.name, wide ? 44 : 32, 8);
      if (wide) _text('穿戴', 260, 8);
      const labels = ['装饰', '装饰', '护腕', '脚蹬', '手持', '身穿', '肩披', '头戴'];
      for (var i = 0; i < 8; i++) {
        final x = wide ? 8 + (i >= 4 ? 156 : 0) : i % 4 * 40,
            y = wide ? 36 + i % 4 * 38 : 24 + i ~/ 4 * 34;
        surface.frame(x, y, x + (wide ? 148 : 38), y + 34);
        final id = p.equipment[i], r = id == null ? null : goods(id);
        if (r != null) _image(9, r.byte(0), r.byte(5), x + 4, y + 4);
        if (wide) {
          _text(
            id == null ? labels[i] : goodsName(id),
            x + 34,
            y + 9,
            selected: i == menu.selected,
            right: x + 145,
          );
        } else if (i == menu.selected) {
          surface.rect(x + 1, y + 1, x + 37, y + 33);
        }
      }
    } else if (kind == 'save' || kind == 'load') {
      surface.clear();
      _text(kind == 'save' ? '存储进度' : '读入进度', wide ? 128 : 48, wide ? 8 : 0);
      for (var i = 0; i < 3; i++) {
        final y = wide ? 36 + i * 50 : 20 + i * 24;
        surface.frame(
          wide ? 8 : 2,
          y,
          wide ? 312 : 158,
          y + (wide ? 44 : 22),
          selected: i == menu.selected,
        );
        _text(
          '${i + 1}',
          wide ? 16 : 6,
          y + (wide ? 14 : 3),
          selected: i == menu.selected,
        );
        final save = saves[i];
        _text(
          save?['scene'] as String? ?? '空档位',
          wide ? 116 : 24,
          y + (wide ? 14 : 3),
          selected: i == menu.selected,
          right: wide ? 308 : 156,
        );
        if (wide && save != null) {
          final ps = save['players'];
          if (ps is List) {
            for (var j = 0; j < math.min(3, ps.length); j++) {
              final p = ps[j];
              if (p is Map && p['index'] is int) {
                _image(11, 1, p['index'] as int, 32 + j * 24, y + 8);
              }
            }
          }
        }
      }
    } else {
      final rows = math.min(wide ? 8 : 4, menu.items.length),
          rh = wide ? 20 : 18;
      _drawList(
        menu.items,
        menu.selected,
        wide ? 40 : 16,
        math.max(4, (surface.height - rows * rh - 8) ~/ 2),
        wide ? 280 : 144,
        rh,
      );
    }
  }
}
