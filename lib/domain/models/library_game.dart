/// 合集内置游戏；存储键保持固定，避免后续调整展示顺序影响偏好。
enum LibraryGame {
  fmj('伏魔记', '经典角色扮演', 'assets/images/fmj_cover.png'),
  sgby('三国霸业', '经典回合策略', 'assets/images/sgby_cover.png');

  const LibraryGame(this.title, this.subtitle, this.coverAsset);
  final String title;
  final String subtitle;
  final String coverAsset;

  static LibraryGame? fromName(String? name) {
    for (final game in values) {
      if (game.name == name) return game;
    }
    return null;
  }
}
