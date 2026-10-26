/// 原版的无符号定宽整数转换，Dart 整数不会自动按 C 的字段宽度截断。
int u8(int value) => value & 0xff;
int u16(int value) => value & 0xffff;
int u32(int value) => value & 0xffffffff;

/// 旧 WASM 使用的 rand_r 序列，包含 LCG 更新及 musl temper 步骤。
///
/// 会话只持有一个随机源，策略、月结和战斗按原顺序消费；界面和动画不能
/// 调用此实例。存档保存的是更新后的 state，以便恢复到下一次随机调用。
final class OriginalRandom {
  OriginalRandom(int seed) : _state = u32(seed);

  int _state;
  int get state => _state;

  /// S/L开关只决定读档是否恢复随机序列，不能被误解为禁用进度存取。
  void restore(int seed) => _state = u32(seed);

  /// 返回 0 到 2^31-1 的随机数，同时推进且仅推进一次状态。
  int next() {
    _state = u32(_state * 1103515245 + 12345);
    var value = _state;
    value = u32(value ^ (value >> 11));
    value = u32(value ^ ((value << 7) & 0x9d2c5680));
    value = u32(value ^ ((value << 15) & 0xefc60000));
    value = u32(value ^ (value >> 18));
    return value >> 1;
  }
}
