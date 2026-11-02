part of 'game_engine.dart';

/// 作弊只使用当前ROM中的真实武器，不改写装备、物品价格或剧情发放条件。
extension GameCheats on GameEngine {
  /// 按武器实际攻击加成降序列出全部武器，同值按资源编号稳定排序。
  /// 攻击字段为无符号byte，嗜血剑250、九龙道剑150不能误读为负数。
  List<String> get cheatWeaponIds {
    final ids = data.offsets.keys
        .where((key) => key.startsWith('6:7:'))
        .map((key) => key.substring(2))
        .where((id) => goods(id)?.byte(0) == 7)
        .toList();
    ids.sort((a, b) {
      final damage = goods(b)!.byte(25).compareTo(goods(a)!.byte(25));
      return damage != 0
          ? damage
          : int.parse(
              a.split(':').last,
            ).compareTo(int.parse(b.split(':').last));
    });
    return List.unmodifiable(ids);
  }

  /// 一次选择增加999把而不是把总数设为999，取消或无效ID不修改库存。
  bool grantCheatWeapon(String id) {
    if (goods(id)?.byte(0) != 7) return false;
    addGoods(id, 999);
    notice = '已获得 ${goodsName(id)} ×999';
    return true;
  }
}
