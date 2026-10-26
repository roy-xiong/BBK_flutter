/// 原版延迟执行订单。编号和目标字段保持C内核语义，避免把下令直接当作最终结算。
///
/// 会话通过替换整个记录提交变化，界面持有的旧记录不会被异步任务修改。
final class GameOrder {
  const GameOrder({
    required this.orderId,
    required this.person,
    required this.city,
    required this.object,
    required this.arms,
    required this.food,
    required this.money,
    required this.consume,
    required this.timeCount,
    this.queueSlot,
    this.fighters = const <int>[],
  });

  final int orderId;
  final int person;
  final int city;
  final int object;
  final int arms;
  final int food;
  final int money;
  final int consume;
  final int timeCount;

  /// 原队列固定槽位；170～199供AddOrderEnd使用，不能按插入时间重排。
  final int? queueSlot;

  /// 出征者使用0基人物编号。只有BATTLE持有，避免误用Person的出征队列编号。
  final List<int> fighters;

  /// 生成属性快照；未指定的可空参数保留当前值。
  GameOrder copyWith({
    int? orderId,
    int? person,
    int? city,
    int? object,
    int? arms,
    int? food,
    int? money,
    int? consume,
    int? timeCount,
    int? queueSlot,
    List<int>? fighters,
  }) => GameOrder(
    orderId: orderId ?? this.orderId,
    person: person ?? this.person,
    city: city ?? this.city,
    object: object ?? this.object,
    arms: arms ?? this.arms,
    food: food ?? this.food,
    money: money ?? this.money,
    consume: consume ?? this.consume,
    timeCount: timeCount ?? this.timeCount,
    queueSlot: queueSlot ?? this.queueSlot,
    fighters: fighters == null
        ? this.fighters
        : List<int>.unmodifiable(fighters),
  );

  /// 使用原版字段名导出，以便对照旧内核或写入版本化存档。
  Map<String, Object?> toJson() => <String, Object?>{
    'OrderId': orderId,
    'Person': person,
    'City': city,
    'Object': object,
    'Arms': arms,
    'Food': food,
    'Money': money,
    'Consume': consume,
    'TimeCount': timeCount,
    'queueSlot': queueSlot,
    'fighters': List<int>.of(fighters),
  };
}
