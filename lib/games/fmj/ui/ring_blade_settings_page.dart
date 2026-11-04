import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../engine/game_engine.dart';
import 'game_view_model.dart';
import 'goods_icon.dart';

/// 独立武器设置页：草稿只留在本页，保存一次性更新模型并持久化。
/// 所有输入控制器在退出时释放；校验会话身份，避免异步页面写入新的游戏会话。
final class RingBladeSettingsPage extends StatefulWidget {
  const RingBladeSettingsPage({
    super.key,
    required this.model,
    required this.game,
  });
  final GameViewModel model;
  final GameEngine game;
  @override
  State<RingBladeSettingsPage> createState() => _RingBladeSettingsPageState();
}

final class _RingBladeSettingsPageState extends State<RingBladeSettingsPage> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  late Map<String, dynamic> _draft;
  @override
  void initState() {
    super.initState();
    _draft = Map.from(widget.game.ringBlade.settings);
    for (final entry in _draft.entries) {
      if (entry.value is int) {
        _controllers[entry.key] = TextEditingController(text: '${entry.value}');
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _defaults() {
    setState(() {
      _draft = Map.from(GameRingBlade.defaults);
      for (final entry in _controllers.entries) {
        entry.value.text = '${_draft[entry.key]}';
      }
    });
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (!identical(widget.model.engine, widget.game)) {
      Navigator.of(context).pop();
      return;
    }
    for (final entry in _controllers.entries) {
      _draft[entry.key] = int.tryParse(entry.value.text) ?? _draft[entry.key];
    }
    widget.model.action(
      (g) => g.setPreference('ringBlade', Map<String, dynamic>.from(_draft)),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('大环刀设置已保存，已装备角色同步生效')));
    Navigator.of(context).pop();
  }

  Widget _toggle(String key, String title, String detail) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(detail),
    value: _draft[key] == true,
    onChanged: (value) => setState(() => _draft[key] = value),
  );
  Widget _number(
    String key,
    String label, {
    String? toggle,
    int max = 999999,
    int min = 0,
    String suffix = '点',
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        if (toggle != null)
          Switch(
            value: _draft[toggle] == true,
            onChanged: (v) => setState(() => _draft[toggle] = v),
          ),
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        SizedBox(
          width: 125,
          child: TextFormField(
            key: ValueKey('ring-field-$key'),
            controller: _controllers[key],
            enabled: toggle == null || _draft[toggle] == true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              suffixText: suffix,
            ),
            validator: (text) {
              final n = int.tryParse(text ?? '');
              return n == null || n < min || n > max ? '$min～$max' : null;
            },
          ),
        ),
      ],
    ),
  );
  Widget _section(String title, String description, List<Widget> children) =>
      Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('大环刀设置'),
      actions: [TextButton(onPressed: _defaults, child: const Text('恢复默认'))],
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: FilledButton.icon(
          key: const ValueKey('save-ring-blade'),
          onPressed: _save,
          icon: const Icon(Icons.check),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('保存并应用'),
          ),
        ),
      ),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      GoodsIcon(
                        id: GameRingBlade.id,
                        art: widget.model.modernArt,
                        size: 72,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '大环刀',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const Text('仅装备到手持部位后生效，三名队员均可使用。'),
                            Text(
                              '百草地钨龙剑右侧一格 · 见师父前可领取一次',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _section('属性加成', '独立开关与数值；增加上限不会自动补满当前气血、真气。改设置或读档不会重复叠加。', [
                    for (final pair in [
                      ('maxHp', '气血上限'),
                      ('maxMp', '真气上限'),
                      ('attack', '攻击'),
                      ('defense', '防御'),
                      ('speed', '身法'),
                      ('spirit', '灵力'),
                      ('luck', '吉运'),
                    ])
                      _number(pair.$1, pair.$2, toggle: '${pair.$1}On'),
                  ]),
                  _section(
                    '命中吸取',
                    '普通攻击命中后，从该目标剩余资源额外吸取，恢复给装备者。群攻逐个命中目标结算；不足只吸实际数值，恢复不超过自身上限。法术、防御、自伤和投掷不触发。',
                    [
                      _number('hpDrain', '吸取气血', toggle: 'hpDrainOn'),
                      _number('mpDrain', '吸取真气', toggle: 'mpDrainOn'),
                    ],
                  ),
                  _section('战斗经验', '默认全队经验2倍。有多把大环刀也只乘一次；仍沿用满级与阵亡队员的经验规则。', [
                    _number(
                      'experienceMultiplier',
                      '经验倍率',
                      toggle: 'experienceOn',
                      min: 1,
                      max: 1000,
                      suffix: '倍',
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _draft['experienceScope'] as String,
                      key: ValueKey('scope-${_draft['experienceScope']}'),
                      decoration: const InputDecoration(
                        labelText: '经验生效范围',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'team', child: Text('全队')),
                        DropdownMenuItem(
                          value: 'wearer',
                          child: Text('仅大环刀装备者'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _draft['experienceScope'] = v);
                        }
                      },
                    ),
                  ]),
                  _section('攻击范围', '跟随大环刀的范围设置；全局“普通攻击群攻”作弊若开启，仍会让普通攻击变为全体。', [
                    _toggle('groupAttack', '群体攻击', '开启后普通攻击与投掷作用于全体敌人。'),
                  ]),
                  _section(
                    '敌人异常 · 默认关闭',
                    '普通攻击命中时施加给该目标，忽略目标吉运但保留对应免疫。四项可独立开启，也可同时存在。',
                    [
                      _toggle('enemyPoison', '中毒', '行动收尾损失气血。'),
                      _toggle('enemyConfuse', '混乱', '敌人的普通行动可能变为自伤。'),
                      _toggle('enemySeal', '咒封', '限制敌人的正常法术。'),
                      _toggle('enemySleep', '昏眠', '跳过对应敌人的行动。'),
                      _number('statusRounds', '异常持续回合', max: 999, suffix: '回合'),
                      const Text('0表示持续至解除或战斗结束。'),
                    ],
                  ),
                  _section('自身免疫', '默认四项全部开启；与其他装备提供的免疫共同生效，卸下大环刀后只撤回本武器的免疫。', [
                    _toggle('immunityPoison', '免疫中毒', '开启时同时清除已有中毒。'),
                    _toggle('immunityConfuse', '免疫混乱', '开启时同时清除已有混乱。'),
                    _toggle('immunitySeal', '免疫咒封', '开启时同时清除已有咒封。'),
                    _toggle('immunitySleep', '免疫昏眠', '开启时同时清除已有昏眠。'),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
