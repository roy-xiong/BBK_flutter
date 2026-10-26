/// 特殊武将的可逆隐藏记录，随所在世界存档，不跨新局或档位共享。
///
/// 隐藏仅更改归属、原归属、兵力及队列位置，装备和其他属性仍保留在人物记录。
/// 恢复使用继任后的势力编号，不让已经退位的特殊君主重新夺回君主身份。
final class HiddenGeneralBackup {
  const HiddenGeneralBackup({
    required this.index,
    required this.belong,
    required this.oldBelong,
    required this.arms,
    required this.city,
  });
  final int index;
  final int belong;
  final int oldBelong;
  final int arms;
  final int? city;

  HiddenGeneralBackup withSuccessor(int previous, int successor) =>
      HiddenGeneralBackup(
        index: index,
        belong: belong == previous ? successor : belong,
        oldBelong: oldBelong == previous ? successor : oldBelong,
        arms: arms,
        city: city,
      );

  Map<String, Object?> toJson() => {
    'index': index,
    'belong': belong,
    'oldBelong': oldBelong,
    'arms': arms,
    'city': city,
  };
}
