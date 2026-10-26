#!/usr/bin/env bash
# 打包通用 macOS 应用；保留沙盒权限并校验临时签名、架构和磁盘镜像。
set -euo pipefail
package_version="${1:?缺少版本}"
package_build="${2:?缺少构建号}"
package_app='build/macos/Build/Products/Release/步步高经典游戏2.app'
package_dist=dist
test -d "$package_app"
package_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$package_app/Contents/Info.plist")"
lipo "$package_app/Contents/MacOS/$package_executable" -verify_arch arm64 x86_64
codesign --force --deep --sign - --entitlements macos/Runner/Release.entitlements "$package_app"
codesign --verify --deep --strict "$package_app"
mkdir -p "$package_dist"
ditto -c -k --sequesterRsrc --keepParent "$package_app" "$package_dist/BBK-Flutter-macOS-${package_version}+${package_build}.zip"
package_staging="$(mktemp -d "${TMPDIR:-/tmp}/bbk-flutter-dmg-XXXXXX")"
trap 'rm -rf "$package_staging"' EXIT
ditto "$package_app" "$package_staging/步步高经典游戏2.app"
ln -s /Applications "$package_staging/Applications"
hdiutil create -volname '步步高经典游戏2' -srcfolder "$package_staging" -format UDZO "$package_dist/BBK-Flutter-macOS-${package_version}+${package_build}.dmg"
hdiutil verify "$package_dist/BBK-Flutter-macOS-${package_version}+${package_build}.dmg"
python3 tool/checksums.py "$package_dist"
