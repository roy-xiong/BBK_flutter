"""将成功的打包产物校验后发布到 Releases，不重新构建任何平台。"""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def gh(*args, missing_ok=False):
    result = subprocess.run(['gh', *args], text=True, capture_output=True)
    if result.returncode:
        if missing_ok and 'HTTP 404' in result.stderr:
            return None
        raise RuntimeError(f'GitHub 操作失败：{args[0]}；{result.stderr.strip()}')
    return result.stdout


def api(path, **kwargs):
    result = gh('api', path, **kwargs)
    return json.loads(result) if result is not None else None


def validate_run(run, repository):
    if (run.get('status') != 'completed' or run.get('conclusion') != 'success'
            or run.get('head_branch') != 'main'
            or run.get('head_repository', {}).get('full_name') != repository
            or run.get('path') != '.github/workflows/packages.yml'
            or run.get('event') != 'workflow_dispatch'):
        raise ValueError('只能发布本仓库 main 上已成功的手动打包产物')


def artifact_version(name):
    match = re.fullmatch(r'bbk-(macos|android|ios|windows)-(\d+\.\d+\.\d+)\+([1-9]\d*)', name)
    return match.groups() if match else None


def build_commit(commits, source_sha, version, build):
    """版本提交由独立 job 创建，不能误用打包触发时尚未递增的 head_sha。"""
    expected = f'chore: package {version}+{build} [skip ci]'
    matches = [commit['sha'] for commit in commits
               if commit['commit']['message'].splitlines()[0] == expected
               and any(parent['sha'] == source_sha for parent in commit['parents'])]
    if len(matches) != 1:
        raise ValueError('无法唯一确定实际构建的版本提交')
    return matches[0]


def verify_artifact(folder, platform, version, build):
    prefix = f'BBK-Flutter-'
    suffix = f'{version}+{build}'
    names = {
        'macos': {f'{prefix}macOS-{suffix}.dmg', f'{prefix}macOS-{suffix}.zip'},
        'android': {f'{prefix}Android-{suffix}.apk'},
        'ios': {f'{prefix}iOS-unsigned-{suffix}.ipa'},
        'windows': {f'{prefix}Windows-portable-{suffix}.zip'},
    }[platform]
    if {p.name for p in folder.iterdir()} != names | {'SHA256SUMS.txt'}:
        raise ValueError(f'{platform} 产物文件不完整或包含额外文件')
    checked = set()
    for line in (folder / 'SHA256SUMS.txt').read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  (.+)', line)
        if not match or match[2] not in names or match[2] in checked:
            raise ValueError('校验清单的文件名无效或重复')
        digest, name = match.groups()
        path = folder / name
        if path.is_symlink() or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f'产物 SHA-256 不一致：{name}')
        checked.add(name)
    if checked != names:
        raise ValueError('存在未校验的安装包')
    return [folder / name for name in sorted(names)]


def version_changes(changelog, version, build):
    """只读取实际构建提交中的版本章节，防止 main 后续更新串入旧版本说明。"""
    heading = re.escape(f'{version}+{build}')
    match = re.search(r'^## ' + heading + r'\s*\n(.*?)(?=^## |\Z)', changelog, re.M | re.S)
    if not match or not match[1].strip():
        raise ValueError('实际构建版本缺少变更记录')
    return match[1].strip()


def release_notes(repository, tag, version, build, platforms, changes, files, run_url, revision):
    """Release 正文明确提供直达附件的下载链接，附件校验完成后才公开。"""
    labels = {'.dmg': 'macOS DMG 安装包', '.zip': 'macOS ZIP 便携包', '.apk': 'Android APK', '.ipa': 'iOS 未签名 IPA'}
    downloads = []
    for path in files:
        if path.name == 'SHA256SUMS.txt':
            label = 'SHA-256 校验清单'
        elif 'Windows' in path.name:
            label = 'Windows ZIP 便携包'
        else:
            label = labels.get(path.suffix, path.name)
        downloads.append(f'- [{label}](https://github.com/{repository}/releases/download/{tag}/{path.name})')
    platform_names = {'macos': 'macOS', 'ios': 'iOS', 'android': 'Android', 'windows': 'Windows'}
    selected = '、'.join(platform_names[p] for p in sorted(platforms))
    macos = '\nmacOS 同时兼容 Apple Silicon 与 Intel，应用名为「步步高经典游戏2」。采用 ad-hoc 签名，未做 Apple 公证。\n' if 'macos' in platforms else ''
    return (f'步步高经典游戏2 **{version}+{build}** · 本次平台：**{selected}**。\n\n'
            f'### 本次变更\n\n{changes}\n\n### 下载\n\n' + '\n'.join(downloads) + '\n'
            + macos + f'\n[成功的打包流水线]({run_url}) · 构建提交 `{revision}`。\n')


def main():
    repository, run_id = os.environ['GH_REPO'], os.environ['SOURCE_RUN_ID']
    if not re.fullmatch(r'[\w.-]+/[\w.-]+', repository) or not re.fullmatch(r'[1-9]\d*', run_id):
        raise ValueError('仓库或 Run ID 无效')
    prefix = f'repos/{repository}'
    run = api(f'{prefix}/actions/runs/{run_id}')
    validate_run(run, repository)
    pages = json.loads(gh('api', f'{prefix}/actions/runs/{run_id}/artifacts?per_page=100', '--paginate', '--slurp'))
    artifacts = [item for page in pages for item in page['artifacts'] if artifact_version(item['name'])]
    if not artifacts or any(item['expired'] for item in artifacts):
        raise ValueError('可发布的打包产物不存在或已过期')
    versions = {artifact_version(item['name'])[1:] for item in artifacts}
    if len(versions) != 1:
        raise ValueError('多个平台的版本不一致')
    version, build = versions.pop()
    commits = api(f'{prefix}/commits?sha=main&per_page=100')
    revision = build_commit(commits, run['head_sha'], version, build)
    content = api(f'{prefix}/contents/pubspec.yaml?ref={revision}')
    pubspec = base64.b64decode(content['content']).decode()
    if not re.search(r'^version:\s*' + re.escape(f'{version}+{build}') + r'\s*$', pubspec, re.M):
        raise ValueError('实际构建提交与安装包版本不一致')
    history = api(f'{prefix}/contents/CHANGELOG.md?ref={revision}')
    changes = version_changes(base64.b64decode(history['content']).decode(), version, build)
    tag = f'v{version}-build.{build}'
    tag_ref = api(f'{prefix}/git/ref/tags/{tag}', missing_ok=True)
    if tag_ref and tag_ref['object']['sha'] != revision:
        raise ValueError('已有标签指向不同提交，拒绝改写')
    if not tag_ref:
        gh('api', f'{prefix}/git/refs', '--method', 'POST', '-f', f'ref=refs/tags/{tag}', '-f', f'sha={revision}')
    releases = json.loads(gh('api', f'{prefix}/releases?per_page=100', '--paginate', '--slurp'))
    existing = next((item for page in releases for item in page if item['tag_name'] == tag), None)
    with tempfile.TemporaryDirectory(prefix='bbk-release-') as temporary:
        root = Path(temporary)
        output = root / 'release'
        output.mkdir()
        platforms = []
        for artifact in artifacts:
            platform, _, _ = artifact_version(artifact['name'])
            platforms.append(platform)
            folder = root / artifact['name']
            gh('run', 'download', run_id, '--repo', repository, '--name', artifact['name'], '--dir', str(folder))
            for path in verify_artifact(folder, platform, version, build):
                shutil.copyfile(path, output / path.name.replace(f'+{build}', f'-build.{build}'))
        files = sorted(output.iterdir())
        (output / 'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n' for p in files))
        files = sorted(output.iterdir())
        notes = root / 'release-notes.md'
        notes.write_text(release_notes(repository, tag, version, build, platforms, changes, files, run['html_url'], revision), encoding='utf-8')
        if existing and not existing['draft']:
            remote = {asset['name']:asset for asset in existing['assets']}
            if set(remote) != {p.name for p in files}:
                raise ValueError('已有正式 Release 的附件不一致，拒绝覆盖')
        else:
            if not existing:
                gh('release', 'create', tag, '--repo', repository, '--draft', '--prerelease', '--title', f'步步高经典游戏2 {version}+{build} · {" / ".join(sorted(platforms))}', '--notes-file', str(notes))
            gh('release', 'upload', tag, *[str(p) for p in files], '--repo', repository, '--clobber')
            current = api(f'{prefix}/releases?per_page=100')
            release = next(item for item in current if item['tag_name'] == tag)
            remote = {asset['name']:asset for asset in release['assets']}
        if set(remote) != {p.name for p in files}:
            raise ValueError('Release 附件尚未完整上传')
        for path in files:
            asset = remote[path.name]
            if asset['size'] != path.stat().st_size or asset.get('digest') != 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest():
                raise ValueError('Release 附件大小或摘要校验失败')
        if not existing or existing['draft']:
            gh('release', 'edit', tag, '--repo', repository, '--draft=false', '--prerelease')
        url = f'https://github.com/{repository}/releases/tag/{tag}'
        print('已发布并校验：' + url)
        summary = os.environ.get('GITHUB_STEP_SUMMARY')
        if summary:
            with open(summary, 'a') as stream:
                stream.write(f'[macOS 预览版下载]({url})\n')


if __name__ == '__main__':
    main()
