import 'package:flutter/material.dart';
import 'game_view_model.dart';

/// 伏魔记原版十项辅助操作；显示设置、倍速和 UI 切换保留各自原有入口。
final class GameCheatPanel extends StatelessWidget {
  const GameCheatPanel({super.key, required this.model});
  final GameViewModel model;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final game = model.engine;
      if (game == null) return const SizedBox.shrink();
      Widget toggle(
        String key,
        String title,
        String description,
        IconData icon,
      ) => SwitchListTile(
        secondary: Icon(icon),
        title: Text(title),
        subtitle: Text(description),
        value: game.preferences[key] == true,
        onChanged: (value) => model.action((g) => g.setPreference(key, value)),
      );
      Widget action(
        String title,
        String description,
        IconData icon,
        VoidCallback action,
      ) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(description),
        onTap: action,
      );
      return ListView(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 24),
        children: [
          const ListTile(title: Text('作弊系统', style: TextStyle(fontSize: 20))),
          toggle(
            'invincible',
            '切换我方无敌',
            '免疫伤害、毒乱眠封及敌方削弱，开启时清除已有异常',
            Icons.health_and_safety,
          ),
          ListTile(
            leading: const Icon(Icons.paid),
            title: Text(game.moneyFarm.active ? '停止刷钱' : '一键刷钱'),
            subtitle: Text(
              game.moneyFarm.active
                  ? '本批${game.moneyFarm.pearls.clamp(0, 20)}/20个，已完成${game.moneyFarm.batches}批；点击停止，保留物品'
                  : '连续挑战客栈收集20个富贵珠 → 当铺一次卖20个 → 循环；再次点击或方向输入取消',
            ),
            trailing: Icon(
              game.moneyFarm.active
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline,
            ),
            onTap: () {
              model.action((g) => g.moneyFarm.toggle());
              // 关闭作弊面板后按原页面暂停规则恢复时钟；停止按钮也可在下次打开时点击。
              Navigator.of(context).pop();
            },
          ),
          toggle('oneHitKill', '切换一击必杀', '我方攻击命中后直接消灭所有受伤敌人', Icons.flash_on),
          toggle(
            'normalAttackAll',
            '切换普通攻击群攻',
            '我方角色的普通攻击同时攻击全部敌人',
            Icons.blur_circular,
          ),
          action(
            '全队完全恢复',
            '生命和真气回满，同时清除异常状态',
            Icons.favorite,
            () => model.action((g) {
              for (final p in g.players) {
                p.hp = p.maxHp;
                p.mp = p.maxMp;
                p.status = 0;
                p.permanentStatus = 0;
                p.statusRounds.clear();
                p.modifiers.clear();
              }
              g.notice = '全队生命、真气和状态已恢复';
            }),
          ),
          action(
            '增加十万金钱',
            '当前金钱增加 100000',
            Icons.monetization_on,
            () => model.action((g) {
              g.money = (g.money + 100000).clamp(0, 2147483647);
              g.notice = '已增加 100000 金钱';
            }),
          ),
          action(
            '全队属性拉满',
            '生命、真气、攻防、身法、灵力和幸运提升至上限',
            Icons.auto_graph,
            () => model.action((g) {
              for (final p in g.players) {
                p.maxHp = p.hp = p.maxMp = p.mp = p.attack = p.defense = 999;
                p.speed = p.spirit = p.luck = 99;
              }
              g.notice = '全队主要属性已提升至上限';
            }),
          ),
          action(
            '全队升至满级',
            '等级、成长链法术同步提升到上限',
            Icons.upgrade,
            () => model.action((g) {
              for (final p in g.players) {
                p.levelUp(
                  g.data,
                  g.data.record(12, 2, p.index)?.byte(2) ?? p.level,
                );
                p.learned = g.data.record(12, 1, p.chain)?.byte(2) ?? p.learned;
                p.exp = 0;
              }
              g.notice = '全队已提升至等级和成长链法术上限';
            }),
          ),
          action(
            '获得 99 把万能钥匙',
            '用于剧情锁箱和钥匙分支',
            Icons.vpn_key,
            () => model.action((g) {
              g.addGoods('14:2', 99);
              g.notice = '已获得万能钥匙 99 把';
            }),
          ),
          action(
            '当前战斗胜利',
            '仅在战斗过程中使用',
            Icons.emoji_events,
            () => model.action((g) {
              if (g.battle == null) {
                g.notice = '当前没有进行中的战斗';
              } else {
                g.battle?.forceWin();
              }
            }),
          ),
          toggle(
            'randomBattleDisabled',
            '切换随机战斗',
            '在开启和关闭随机战斗之间切换',
            Icons.sync_alt,
          ),
        ],
      );
    },
  );
}
