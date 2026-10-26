# 国风手绘场景与1994版角色头像

正式应用只读取 `assets/art` 内的三张PNG与图集索引。模型生成、抠图、分色、裁剪与拼图均在开发阶段完成，Flutter运行时只绘制已缓存图片，不依赖生成模型、Blender或联网图片加载。

- 画风参考已确认的《伏魔记》手绘素材：清晰描线、木石与金属细节、适度卡通比例和柔和立体光影。旧Blender玩具模型不再作为正式素材补位。
- 战略城池、点击和滚动始终使用原 `C_CITYPOS` / `C_MAP` 的12×9矩阵。绘画陆地使用原矩阵陆地遮罩；38座城池使用原坐标，绘画河道连续绕开城池图标，图标不落海。
- 骑、步、弓、水、极、玄六兵种通过坐骑、盾矛、弓与箭筒、战船、重肩甲与戟、布袍羽扇区分。衣甲、披风、船帆大面积采用我军红、敌军青，肤色与木石金属保持原稿。
- 六个动作相位为待机、轻步、蓄势、攻击、受击、倒地。轻步从本人待机原稿的下摆与脚步派生，其余独立生成；来源清单明确区分派生图。动作继续读取原动画帧，不另建定时器或改变寻路。
- 陆军死亡退场使用受击、失衡、侧倒、接地四个阶段，绑定原播放器的六个时隙，首尾各短暂停留。共享缩放比例和脚下锚点。骑兵倒地由分别核对过的完整骑手、马匹和落地长枪合成，避免双主体生成的人马融合。
- 水军的甲板后层合入正确比例的弓手，近侧船舷遮住脚部；倾覆帧从同一完整船体派生，保留相同的帆、桅杆、船桨与小比例船员。原水线裁剪和逐步下沉完成沉船，不使用生成器误画的巨人或换船帧。
- 角色头像只采用核对过的1994版《三国演义》角色剧照。来源、原图SHA-256和裁剪框位于 `portraits_1994.json`，原图位于 `sources/portraits_1994`。
- 没有核实剧照的人物按时期/人物编号读取原LIB中的头像，保留原始黑白像素。绝不使用其他武将、演员生活照、游戏画像或生成的人脸补位。
- 姓名勘误集中在 `lib/engine/resources/person_names.dart`，黑白和彩色共用。美术导出读取同一份勘误表，人物ID不变。

本机现有原稿目录的增量维护流程（MFLUX、Pillow、NumPy、OpenCV由开发环境提供，不作为应用依赖）：

```sh
python3 tool/art/prepare_handpainted.py --root "$SGBY_ART_ROOT"
python3 tool/art/prepare_handpainted_actions.py --root "$SGBY_ART_ROOT"
python3 tool/art/prepare_handpainted_singles.py --root "$SGBY_ART_ROOT"
python3 tool/art/generate_handpainted.py --root "$SGBY_ART_ROOT" --cache "$SGBY_MODEL_CACHE" --plan "$SGBY_ART_ROOT/final_jobs.json"
python3 tool/art/repair_cavalry_art.py --root "$SGBY_ART_ROOT"
python3 tool/art/generate_handpainted.py --root "$SGBY_ART_ROOT" --cache "$SGBY_MODEL_CACHE" --plan "$SGBY_ART_ROOT/cavalry_jobs.json"
python3 tool/art/repair_cavalry_art.py --root "$SGBY_ART_ROOT" --compose
python3 tool/art/repair_scholar_art.py --root "$SGBY_ART_ROOT"
python3 tool/art/generate_handpainted.py --root "$SGBY_ART_ROOT" --cache "$SGBY_MODEL_CACHE" --plan "$SGBY_ART_ROOT/scholar_jobs.json"
# 弓兵箭向终稿由selection.json指定；水军使用同一终稿合入船员。
python3 tool/art/repair_ship_art.py --root "$SGBY_ART_ROOT"
python3 tool/art/prepare_handpainted_skills.py --root "$SGBY_ART_ROOT"
python3 tool/art/generate_handpainted.py --root "$SGBY_ART_ROOT" --cache "$SGBY_MODEL_CACHE" --plan "$SGBY_ART_ROOT/skill_jobs.json"
python3 tool/art/prepare_battle_readability.py --root "$SGBY_ART_ROOT"
python3 tool/art/generate_handpainted.py --root "$SGBY_ART_ROOT" --cache "$SGBY_MODEL_CACHE" --plan "$SGBY_ART_ROOT/readability_jobs.json"
# 人工逐张检查、修正 selection.json 中的原稿绑定后，输出到独立候选目录。
python3 tool/art/pack_handpainted.py --root "$SGBY_ART_ROOT" --out .dart_tool/handpainted_candidate
python3 tool/art/portrait_report.py
```

箭向修正等逐张筛选的最终绑定记录在 `handpainted_sources.json` 的 `selection` 中；初始准备脚本只用于补充任务，组图前应保留已经核对的终稿绑定。

模型固定为本机缓存的 `mlx-community/flux2-klein-4b-4bit`，MFLUX 0.23.0、4步、guidance=1；逐张记录提示词、参考、种子、耗时和原图SHA-256。正式来源清单位于 `handpainted_sources.json`。失败原稿（重复马匹、缺格、武器混乱等）保留在Downloads原稿目录供追溯，不进入应用。不要把混乱的动作大图直接按格裁成正式帧。

计策资源号以原版 `consdef.h` 为准：35火、36水、37滚木/礌石、38撞击、39封/定、40流言、41援兵/援军、42石阵、43陷阱。第五种天气以 `fight.h` 的 `WEATHER_HAIL=5` 为准，显示冰雹。对应测试检查正式画笔的中心像素和不同实体，排除仅更改标题导致的假通过。

战场步兵与弓兵使用独立的远景待机/行军切片，强化盾矛、金色长弓和白色箭羽；特写沿用相同服饰和身份。重装兵部分原稿朝左，`facingCorrections`先离线归一化，再由运行时将敌军实体镜像；文字、兵力和血条不镜像。

城池近景门楼只扩大绘制范围，脚底仍锚定原16点城格；城字与防守旗放在驻军前层。战略城名底板采用我红、敌青、空城灰，当前城市与将领共用稳定的金色选框，不引入闪烁计时器。

战争通知使用已确认的国风面板与完整胜负布景，报告通过独立城市字段解析地点，保留原来的1000/3000毫秒自动展示时序。画笔不绘制确认按钮，也不持有关闭回调。新增复现从真实群攻输入出发检查三位敌军逐人退场，避免兵力先扣零后，彩色画面把尚未轮到动画的单位提前隐藏。

图集核对后同步更新 `tool/baseline/realistic_art_assets.json`。Flutter测试检查四时期800个头像绑定、553个原图回退位置的逐像素一致性、姓名字形覆盖、红青着色比例、绿幕残留及原地图坐标与点击。图片解码总内存限制为64MiB，单图边长不超过4096。`tool/export_native_art_test.dart`可导出正式绘制器的菜单、地图、战场、攻击和胜负场景，不构建平台应用。真实UI测试同时导出竖屏手机及桌面原手柄布局。

新增或更换照片时先核实具体角色和1994版剧集，并检查合照裁剪对象；只在确认后更新 `portraits_1994.json`。运行 `portrait_report.py`会在Downloads重新输出单文件深色HTML头像及缺图清单。

选中框先于实体、城名与军牌绘制。像素回归检查选中前后的城名字形、兵种和兵力字形不会被描边覆盖，同时验证操控部队离开目的地光标后仍保持金框。
