import '../engine/game_actor.dart';
import '../engine/game_engine.dart';

/// 对白的署名与当前页正文。原始文本、分页位置和脚本执行顺序保持由引擎持有。
///
/// 优先使用原文署名，其次使用头像对应的角色资源及实际触发事件的 NPC。
/// 无头像的开场和无机阁剧情另外按原脚本地址标注，不推测未知旁白的说话人。
final class DialoguePresentation {
  const DialoguePresentation({required this.speaker, required this.text});
  final String? speaker;
  final String text;

  static final _prefix = RegExp(r'^([^：:\r\n，。！？!?]{1,16})[：:]');

  static DialoguePresentation from(GameEngine game, GameOperation op) {
    final explicit = _prefix.firstMatch(op.text);
    final head = op.args.firstOrNull ?? 0;
    final hero = head >= 1 && head <= 3
        ? game.players.where((p) => p.index == head).firstOrNull ??
              GameActor.load(game.data, 1, head)
        : null;
    // 这些无头像对白由原版主剧情直接执行，不经过 NPC 的交互事件入口。
    final scripted = op.scriptId == '2:2'
        ? GameActor.load(game.data, 2, 1)?.name
        : op.scriptId == '1:1' && op.address == 172
        ? GameActor.load(game.data, 2, 2)?.name
        : op.scriptId == '1:5' && op.address == 254
        ? GameActor.load(game.data, 2, 1)?.name
        : op.scriptId == '3:12' && op.address == 504
        ? GameActor.load(game.data, 1, 2)?.name
        : op.scriptId == '14:11' && {659, 720}.contains(op.address)
        ? GameActor.load(game.data, 3, 45)?.name
        : op.scriptId == '7:2' && op.address == 317
        ? '掌柜'
        : null;
    final rawName =
        explicit?.group(1) ?? hero?.name ?? scripted ?? op.speakerName;
    final name = rawName
        ?.trim()
        .replaceAll('Npc', '')
        .replaceFirst('goods', '')
        .replaceFirst(RegExp(r'^三清游人\d+$'), '游人')
        .replaceFirst(RegExp(r'^(天道手下)\d+$'), '天道手下');
    final start = op.start.clamp(0, op.text.length);
    final end = op.next.clamp(start, op.text.length);
    var text = op.text.substring(start, end);
    if (start == 0 && explicit != null) {
      text = text.substring(explicit.end.clamp(0, text.length));
    }
    return DialoguePresentation(
      speaker: name == null || name.isEmpty ? null : name,
      text: text,
    );
  }
}
