#!/usr/bin/env python3
"""Peg Champ Japanese Mod installer. Python 3 standard library only."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parent

def sha256(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def find_game(argument, manifest):
    if argument:
        path = Path(argument).expanduser().resolve()
        if path.is_dir():
            path = path / manifest['original_name']
        if not path.is_file():
            raise RuntimeError('ゲーム本体が見つかりません: ' + str(path))
        return path
    locations = list(dict.fromkeys([Path.cwd(), ROOT, ROOT.parent]))
    candidates = []
    for folder in locations:
        preferred = folder / manifest['original_name']
        if preferred.is_file():
            candidates.append(preferred)
        for path in folder.glob('*.exe'):
            if path not in candidates and path.stat().st_size in (manifest['original_size'], manifest['patched_size'], *manifest.get('previous_patched_sizes', [])):
                candidates.append(path)
    matches = [p.resolve() for p in candidates
               if sha256(p) in (manifest['original_sha256'], manifest['patched_sha256'], *manifest.get('previous_patched_sha256', []))]
    matches = list(dict.fromkeys(matches))
    if len(matches) != 1:
        raise RuntimeError('対象の本体を特定できません。パッチ一式をゲームフォルダーへ入れるか、\n'
                           'python3 patcher.py --game "/ゲームフォルダー/peg_champ_beta.exe" を実行してください。\n'
                           'このパッチは今回の添付ファイルと同じ版専用です。')
    return matches[0]

def patch(target, manifest, uninstall=False):
    target = Path(target)
    backup = target.with_name(target.name + '.jpmod-original')
    current = sha256(target)
    expected = manifest['original_sha256'] if uninstall else manifest['patched_sha256']
    if current == expected:
        return 'すでに元の状態です。' if uninstall else 'すでに日本語化されています。'
    previous = manifest.get('previous_patched_sha256', [])
    valid = [manifest['patched_sha256'], *previous] if uninstall else [manifest['original_sha256'], *previous]
    upgrading = not uninstall and current in previous
    if current not in valid:
        raise RuntimeError('本体のバージョンが異なるか、別の変更が加えられています。ファイルは変更しませんでした。')
    if uninstall:
        if not backup.is_file() or sha256(backup) != manifest['original_sha256']:
            raise RuntimeError('正しいバックアップが見つかりません。ファイルは変更しませんでした。')
    else:
        payload = ROOT / manifest['tail_file']
        if not payload.is_file() or sha256(payload) != manifest['tail_sha256']:
            raise RuntimeError('パッチデータが破損しています。ZIPを展開し直してください。')
        if backup.exists() and sha256(backup) != manifest['original_sha256']:
            raise RuntimeError('別のバックアップが存在します。上書きせずに中止しました。')
        if upgrading and not backup.is_file():
            raise RuntimeError('更新には .jpmod-original の元のバックアップが必要です。ファイルは変更しませんでした。')
    fd, temporary = tempfile.mkstemp(prefix=target.name + '.jpmod-', suffix='.tmp', dir=target.parent)
    os.close(fd)
    temporary = Path(temporary)
    try:
        if uninstall:
            shutil.copy2(backup, temporary)
        else:
            source_path = backup if upgrading else target
            with source_path.open('rb') as source, temporary.open('wb') as output:
                remaining = manifest['prefix_length']
                while remaining:
                    block = source.read(min(1024 * 1024, remaining))
                    if not block:
                        raise RuntimeError('本体ファイルの読み込みに失敗しました。')
                    output.write(block)
                    remaining -= len(block)
                with payload.open('rb') as source_tail:
                    shutil.copyfileobj(source_tail, output)
                for edit in manifest['edits']:
                    output.seek(edit['offset'])
                    output.write(bytes.fromhex(edit['hex']))
            shutil.copymode(target, temporary)
        if sha256(temporary) != expected:
            raise RuntimeError('作成ファイルの検証に失敗しました。本体は変更しませんでした。')
        if not uninstall and not backup.exists():
            # Exclusive creation keeps a backup from ever being silently overwritten.
            try:
                with backup.open('xb') as out, target.open('rb') as source:
                    shutil.copyfileobj(source, out)
                shutil.copystat(target, backup)
                if sha256(backup) != manifest['original_sha256']:
                    raise RuntimeError('バックアップの検証に失敗しました。')
            except Exception:
                backup.unlink(missing_ok=True)
                raise
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    return '元の状態に戻しました。' if uninstall else '日本語化が完了しました。ゲーム内の言語は「英語／米国旗」を選んでください。'

def main():
    parser = argparse.ArgumentParser(description='Peg Champ 日本語化パッチ')
    parser.add_argument('--game', help='ゲーム本体またはゲームフォルダー')
    parser.add_argument('--uninstall', action='store_true', help='元に戻す')
    parser.add_argument('--status', action='store_true', help='状態を確認')
    args = parser.parse_args()
    try:
        manifest = json.loads((ROOT / 'manifest.json').read_text(encoding='utf-8'))
        target = find_game(args.game, manifest)
        if args.status:
            print('日本語化済み' if sha256(target) == manifest['patched_sha256'] else '未適用')
        else:
            print(patch(target, manifest, args.uninstall))
        return 0
    except Exception as error:
        print('エラー: ' + str(error), file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())
