import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../engine/game_engine.dart';
import 'goods_icon.dart';
import 'modern_art.dart';

/// 自适应武器选择弹窗：缓存本次排序，搜索只过滤，不改变背包和游戏中的菜单状态。
/// 返回ID后由作弊面板发放；控制器随弹窗销毁，列表共用会话图集，不重复解码图片。
final class WeaponCheatDialog extends StatefulWidget {
  const WeaponCheatDialog({super.key, required this.game, this.art});
  final GameEngine game;
  final ModernArt? art;
  @override
  State<WeaponCheatDialog> createState() => _WeaponCheatDialogState();
}

final class _WeaponCheatDialogState extends State<WeaponCheatDialog> {
  final _search = TextEditingController();
  late final _weapons = widget.game.cheatWeaponIds;
  late List<String> _filtered = _weapons;
  bool _selected = false;

  /// 快速连点只提交一次，不能在弹窗退场期间再次pop底下的作弊面板。
  void _select(String id) {
    if (_selected) return;
    _selected = true;
    Navigator.of(context).pop(id);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _filter(String value) {
    final query = value.trim();
    setState(
      () => _filtered = _weapons
          .where(
            (id) =>
                widget.game.goodsName(id).contains(query) || id.contains(query),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final height = math.min(640.0, math.max(0.0, size.height - keyboard - 48));
    final compact = height < 280;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: SizedBox(
        width: math.min(520, math.max(0, size.width - 32)),
        height: height,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                compact ? 6 : 16,
                16,
                compact ? 6 : 8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!compact)
                    Text(
                      '获取999把武器',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  if (!compact) const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          onChanged: _filter,
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            labelText: '搜索武器名称或编号',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      if (compact)
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('取消'),
                        ),
                    ],
                  ),
                  if (!compact) const SizedBox(height: 6),
                  if (!compact)
                    Text(
                      '攻击加成从高到低 · ${_filtered.length}/${_weapons.length}把',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('没有匹配的武器'))
                  : ListView.builder(
                      key: const ValueKey('cheat-weapon-list'),
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final id = _filtered[index], game = widget.game;
                        return ListTile(
                          key: ValueKey('cheat-weapon-$id'),
                          leading: GoodsIcon(id: id, art: widget.art),
                          title: Text(game.goodsName(id)),
                          subtitle: Text(
                            '攻击 +${game.goods(id)!.byte(25)} · '
                            '${game.goodsTargetsAll(id) ? '群攻' : '单体'} · '
                            '背包 ${game.inventory[id] ?? 0}',
                          ),
                          trailing: const Text('+999'),
                          onTap: () => _select(id),
                        );
                      },
                    ),
            ),
            if (!compact)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
