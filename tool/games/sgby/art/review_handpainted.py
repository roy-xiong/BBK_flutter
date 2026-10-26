"""从正式候选图集与正式Flutter绘制结果导出核对图；不生成或改写游戏素材。"""
from pathlib import Path
import argparse
import base64
import html
import json
import math

from PIL import Image, ImageDraw, ImageFont, ImageOps


NAMES = ['骑兵', '步兵', '弓兵', '水军', '极兵', '玄兵']
LABELS = {
    'idle': '待机', 'stride': '轻步', 'windup': '蓄势', 'attack': '攻击',
    'hit': '受击', 'down': '接地', 'kneel': '失衡', 'fall': '侧倒',
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--assets', type=Path, required=True)
    parser.add_argument('--runtime', type=Path)
    parser.add_argument('--html', type=Path)
    args = parser.parse_args()
    target = args.root / 'review'
    target.mkdir(exist_ok=True)
    manifest = json.loads((args.assets / 'manifest.json').read_text())
    atlas = Image.open(args.assets / 'atlas.png').convert('RGBA')
    try:
        font = ImageFont.truetype('/System/Library/Fonts/Hiragino Sans GB.ttc', 20)
    except OSError:
        font = ImageFont.load_default()

    def sprite(key):
        x, y, width, height = manifest['sprites'][key]
        return atlas.crop((x, y, x + width, y + height))

    def contact(name, entries, columns, cell=(224, 250)):
        sheet = Image.new('RGB', (columns * cell[0], math.ceil(len(entries) / columns) * cell[1]), '#d8d2be')
        draw = ImageDraw.Draw(sheet)
        for i, (label, image) in enumerate(entries):
            x, y = i % columns * cell[0], i // columns * cell[1]
            fitted = ImageOps.contain(image.convert('RGBA'), (cell[0] - 12, cell[1] - 40), Image.Resampling.LANCZOS)
            sheet.paste(fitted, (x + (cell[0] - fitted.width) // 2, y + cell[1] - 38 - fitted.height), fitted)
            draw.text((x + cell[0] // 2, y + cell[1] - 24), label, anchor='mm', font=font, fill='#25383b')
        path = target / (name + '.png')
        sheet.save(path, optimize=True)
        return path

    assets = []
    assets.append(('六兵种 · 我军红 / 敌军青', contact('teams', [
        (NAMES[kind] + (' · 我' if side == 'friendly' else ' · 敌'), sprite(f'unit/{side}/{kind}/idle'))
        for side in ['friendly', 'enemy'] for kind in range(6)
    ], 6)))
    for kind in range(6):
        entries = [(LABELS[pose], sprite(f'unit/friendly/{kind}/{pose}'))
                   for pose in ['idle', 'stride', 'windup', 'attack', 'hit']]
        entries += [(LABELS[pose], sprite(f'defeat/friendly/{kind}/{frame}'))
                    for pose, frame in [('kneel', 2), ('fall', 3), ('down', 4)]]
        assets.append((NAMES[kind] + ' · 完整动作与接地', contact(f'poses-{kind}', entries, 8, (192, 220))))
    assets.append(('城市、地形与补给', contact('props', [
        (key.split('/')[-1], sprite(key)) for key in [
            'city/capital', 'city/fort', 'city/harbor', 'terrain/mountain', 'terrain/tree',
            'terrain/village', 'terrain/camp', 'icon/supplies',
        ]
    ], 4)))
    assets.append(('天气与战斗特效', contact('effects', [
        (key.split('/')[-1], sprite(key)) for key in [
            'icon/sun', 'icon/cloud', 'icon/wind', 'icon/rain', 'icon/hail', 'effect/slash',
            'effect/impact', 'effect/fire', 'effect/water', 'effect/mist', 'effect/level',
            'effect/log', 'effect/rock', 'effect/trap',
        ]
    ], 6, (192, 210))))
    assets.append(('六类战斗布景', contact('scenes', [
        (name, sprite('scene/' + name)) for name in ['field', 'river', 'forest', 'siege', 'victory', 'defeat']
    ], 2, (640, 424))))
    assets.append(('战略底图 · 原矩阵陆地遮罩', args.assets / 'strategy_map.png'))

    if args.html:
        def embed(path):
            return 'data:image/png;base64,' + base64.b64encode(path.read_bytes()).decode('ascii')

        sections = []
        for title, path in assets:
            sections.append(f'<section><h2>{html.escape(title)}</h2><img loading="lazy" src="{embed(path)}" alt="{html.escape(title)}"></section>')
        if args.runtime:
            groups = [
                ('真实手机与桌面布局', ['runtime_390_strategy', 'runtime_390_battle', 'runtime_1280_strategy', 'runtime_1280_battle']),
                ('地图、菜单与将领', ['cartoon_main_menu', 'cartoon_periods', 'cartoon_rulers', 'cartoon_strategy', 'cartoon_strategy_no_roads', 'cartoon_mini_map', 'cartoon_command_menu', 'cartoon_generals', 'cartoon_tools', 'cartoon_food', 'cartoon_city', 'cartoon_dialogue', 'cartoon_save_slots']),
                ('战斗、范围与军情', ['cartoon_battle', 'cartoon_movement', 'cartoon_battle_situation', 'cartoon_battle_information']),
                ('攻击与计策', ['cartoon_attack_' + str(i) for i in range(6)] + ['cartoon_skill']),
                ('天气与状态', ['cartoon_weather_' + str(i) for i in range(5)] + ['cartoon_states']),
                ('退场实际绘制', ['defeat_land', 'defeat_water'] + ['defeat_runtime_1x_' + str(i) for i in [6, 8, 10, 11]]),
                ('胜负与结局', ['cartoon_victory', 'cartoon_defeat', 'cartoon_notice_attack', 'cartoon_notice_fight', 'cartoon_notice_victory', 'cartoon_notice_defeat', 'cartoon_ending_won', 'cartoon_ending_lost']),
                ('原版策略提示', ['strategy_note_bw', 'strategy_note_color']),
                ('计策资源语义核对', ['skill_semantics_35_火攻', 'skill_semantics_36_水淹', 'skill_semantics_37_滚木', 'skill_semantics_37_礌石', 'skill_semantics_38_撞击', 'skill_semantics_41_援兵', 'skill_semantics_42_石阵', 'skill_semantics_43_陷阱']),
            ]
            for title, names in groups:
                pictures = []
                for name in names:
                    path = args.runtime / (name + '.png')
                    if path.exists():
                        pictures.append(f'<figure><img loading="lazy" src="{embed(path)}" alt="{name}"><figcaption>{name}</figcaption></figure>')
                if pictures:
                    sections.append('<section><h2>' + title + '</h2><div class="grid">' + ''.join(pictures) + '</div></section>')
        proof = json.loads((target / 'art_proof.json').read_text())
        concise = {k: v for k, v in proof.items() if k not in ['files', 'poseChecks']}
        document = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>三国霸业 · 国风手绘实装核对</title>
<style>:root{color-scheme:dark}body{margin:0;background:#101a23;color:#dce5e8;font:16px/1.8 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}main{max-width:1500px;margin:auto;padding:32px 24px}h1,h2{color:#ead6a7}h2{font-size:23px}section{margin:32px 0;padding:20px;background:#192833;border:1px solid #334853;border-radius:14px}img{max-width:100%;height:auto;display:block;border-radius:8px}p{max-width:1100px}figure{margin:0}figcaption{font-size:13px;color:#9db0bc;overflow-wrap:anywhere}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(310px,1fr));gap:18px}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.7 monospace;color:#a9c5c7}a{color:#8dc8da}.note{border-left:3px solid #d8b777;padding:10px 18px;background:#263337}</style><main>
<h1>三国霸业 · 国风手绘实装核对</h1><p>2026-10-24 · 参考《伏魔记》已确认的描线、材质与轻3D光影。以下素材直接来自正式候选图集，界面截图来自正式Flutter绘制器，并非把效果稿作为游戏画面。</p>
<p class="note">保留原12×9矩阵、38座城池位置、菜单热区及NES操作面板；黑白模式和切换不变。我军红、敌军青。头像继续使用已核实的1994版角色剧照，缺图按时期与人物ID读取原始黑白头像。</p>
<p>角色逐动作生成后单独抠图、归一化和分色。陆军退场采用受击、失衡、侧倒、接地四个阶段绑定原六个时隙；首尾短暂停留。水军从同一完整船体派生倾侧帧，再以水线裁剪表现下沉。骑兵的倒地马匹与骑手分别制作，再按真实比例合成；长枪落在地面。没有增加动画计时器或更改伤害、随机数及结算回调。</p>
<p>计策与天气已交叉核对原版常量：35火攻、36水攻、37滚木/礌石、38撞击，援兵、石阵、陷阱分别表现；第五种天气为冰雹。</p>
<p>已淘汰的原稿问题包括重复马匹、缺格、双头兵器、营帐多余人物、天气图误生成人物与绿幕光晕；这些原稿不进入正式图集。胜利旗面的伪文字已局部清理，所有标题由系统字体绘制。</p>'''
        document += ''.join(sections)
        document += '<section><h2>素材与内存记录</h2><pre>' + html.escape(json.dumps(concise, ensure_ascii=False, indent=2)) + '</pre><p>模型：本机缓存 mlx-community/flux2-klein-4b-4bit，MFLUX 0.23.0，4步，guidance=1。完整提示词、参考、种子及原稿SHA-256保存在原稿目录与仓库tool/art/handpainted_sources.json。运行时仅读取三张PNG与JSON索引，无模型或生成服务依赖。</p></section></main></html>'
        args.html.write_text(document)
        print(args.html)
    for _, path in assets:
        print(path)


if __name__ == '__main__':
    main()
