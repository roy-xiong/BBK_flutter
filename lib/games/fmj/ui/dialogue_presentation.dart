import '../engine/game_actor.dart';
import '../engine/game_engine.dart';
import 'dialogue_speakers.dart';

/// 对白的署名与当前页正文。原始文本、分页位置和脚本执行顺序保持由引擎持有。
///
/// 优先使用原文署名，其次使用头像对应的角色资源及实际触发事件的 NPC。
/// 无头像且原文未署名的对白按查验后的脚本地址补充，不推测未知旁白的说话人。
final class DialoguePresentation {
  const DialoguePresentation({required this.speaker, required this.text});
  final String? speaker;
  final String text;

  static final _prefix = RegExp(r'^([^：:\r\n，。！？!?]{1,16})[：:]');
  static const _innTitles = {'7:2': '建业客栈掌柜', '9:5': '客栈掌柜', '11:4': '小客栈掌柜'};

  static DialoguePresentation from(GameEngine game, GameOperation op) {
    final explicit = _prefix.firstMatch(op.text);
    final head = op.args.firstOrNull ?? 0;
    final hero = head >= 1 && head <= 3
        ? game.players.where((p) => p.index == head).firstOrNull ??
              GameActor.load(game.data, 1, head)
        : null;
    final reviewed = head == 0 ? reviewedDialogueSpeakers[op.scriptId] : null;
    // 交易柜台多数由地图事件42触发，并非可移动NPC；署名不能只依赖NPC姓名。
    // 经确认的null也要优先保留，不能让上一位说话人的名字串入未署名对白。
    final contextual = reviewed?.containsKey(op.address) == true
        ? reviewed![op.address]
        : op.speakerName;
    final rawName = explicit?.group(1) ?? hero?.name ?? contextual;
    var name = rawName
        ?.trim()
        .replaceAll('Npc', '')
        .replaceFirst('goods', '')
        .replaceFirst(RegExp(r'^三清游人\d+$'), '游人')
        .replaceFirst(RegExp(r'^(天道手下)\d+$'), '天道手下');
    if (name == '掌柜') name = _innTitles[op.scriptId] ?? name;
    if (name == '镇长' && op.scriptId == '9:4') name = '白水镇镇长';
    if (name == '无机') name = '无机道人';
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
