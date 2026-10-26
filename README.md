# 步步高经典游戏2

步步高经典游戏2，内置 **伏魔记**与**三国霸业**两个纯 Flutter / Dart 游戏。首页沿用 BBK 的游戏封面选择方式，支持触摸、鼠标与键盘。

## 来源

- 伏魔记来自 `roy-xiong/fmj_flutter` 的本地 `1.0.334+1334`，包含尚未在原仓库提交的地图、室内及宝箱修复。
- 三国霸业来自 `roy-xiong/sgby_flutter` 的提交 `4ac9432`。
- 原工程保持独立；这里复制了游戏引擎、资源、测试及许可说明。具体来源和文件 SHA-256 见 `tool/source_snapshot.json`。
- 旧 `BBK` 项目仅提供首页视觉参考与封面素材。合集运行时不依赖 WebView、JavaScript、WASM 或 FFI 游戏引擎。

## 结构

```text
lib/games/fmj/        伏魔记引擎与界面
lib/games/sgby/       三国霸业引擎与界面
lib/ui/features/     合集首页、路由和退出确认
assets/fmj/          伏魔记资源
assets/sgby/         三国霸业资源
assets/branding/     立体游戏机图标、浅色与深色设计源文件
test/games/          原游戏回归测试与原版比对素材
```

存档写入当前应用的数据目录，分别位于 `games/fmj`、`games/sgby`。新应用有独立应用标识，不会覆盖旧 BBK 或两个独立应用的数据。旧应用的存档不会自动搬入。

从游戏返回首页会释放时钟、监听与图片资源。伏魔记返回前保存可保存的进度；三国霸业保留原有手动存档规则和自动存档选项，返回时提示未保存战局。

## 工具链

沿用兄弟项目的 Flutter **3.44.4**、Dart **3.12.2**、Java **17**、AGP **9.0.1**、NDK **27.2.12479018**，固定 `path_provider_android: 2.2.23` 与已提交的依赖锁文件。

## 图标

基于旧 BBK 的可编辑 SVG 制作：浅色象牙白、深色石墨青，同一游戏机造型具有机身厚度、屏幕玻璃、按键高光与投影。

- iOS 18 的 `AppIcon.appiconset` 含默认、深色与灰度着色变体。
- iOS 26 / macOS 26 使用 `Runner/BBKIcon.icon`，在系统图标样式中选择默认或深色时呈现对应外观；旧系统由 Xcode 生成兼容图标。
- macOS 15 及更早系统在应用运行时自动切换 Dock 的浅色、深色图标，不更改系统主题。
- Android、Windows 使用同一套浅色设计导出的各尺寸资源。
- `tool/render_icons.cjs` 可用 Node.js 和 `sharp` 重新光栅化 SVG；运行应用不需要这些工具。

## 固定 Android 签名

应用标识为 `com.xiongjian.bbk_flutter`。Debug 与 Release 均使用项目专属固定 RSA-4096 证书。

- 本机私钥及口令放在忽略的 `.signing/` 和 `android/key.properties`，需要妥善备份。
- 云端从仓库加密 Secret `BBK_ANDROID_SIGNING` 恢复同一证书。
- `android/signing/certificate.sha256` 只包含公开证书指纹。
- Release 缺少配置时构建失败，不能退回随机 Debug 签名。构建后 `tool/verify_android_signature.py` 核对 APK 证书。

## GitHub Actions

`BBK Flutter 校验` 在推送与 PR 时执行静态分析、源快照和回归测试。

`BBK Flutter 手动打包` 只接受手动触发，默认平台是 **macOS**。首次先构建 macOS，其他平台等待验收后选择，不会因推送自动打包。

每次打包递增 `pubspec.yaml` 版本并提交，所有选中平台引用同一提交。产物包含 SHA-256：

打包成功后，`BBK Flutter 发布下载链接` 自动校验原始安装包并发布到 [GitHub Releases](https://github.com/roy-xiong/BBK_flutter/releases)。已有成功任务也可用该流程的 `run_id` 输入补发，无须重新打包。发布标签绑定实际构建的版本提交，附件完整上传并核对摘要后才公开。

- macOS：通用 arm64 / x86_64 的 DMG、ZIP，校验 ad-hoc 签名。
- Android：固定签名 APK。
- iOS：未签名 IPA，安装前需自行签名。
- Windows：带运行库的便携 ZIP。

macOS 预览包使用 ad-hoc 签名，未做 Apple 开发者签名和公证。素材及原引擎许可信息保存在 `licenses/` 与各资源清单中。

## 版本与变更说明

手动打包会同时递增 `versionName` 和构建号，并把 [CHANGELOG.md](CHANGELOG.md) 的「未发布」内容归档到本次版本。Release 从实际构建提交读取对应版本的变更记录，正文附上各安装包直链；只有附件全部上传且摘要一致才公开。

伏魔记已接入逐项审核通过的美术修订，版本组合和资源校验信息见 `tool/fmj_art_approval.json`。来源工程和原始ROM/地图/剧情资源保留，合集内修订可从 `tool/source_snapshot.json` 的 `integrationRevisions` 追溯。
