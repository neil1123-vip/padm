#!/usr/bin/env python3
"""从构建阶段导出显式运行文件及其 ELF 依赖，不携带包管理器。"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def excluded(path):
    parts = path.parts
    return (
        any(part in {"__pycache__", "test", "tests", "ensurepip"} for part in parts)
        or path.suffix in {".pyc", ".pyo", ".a"}
        or ("lib-dynload" in parts and path.name.startswith(("_test", "_xxtest", "_ctypes_test", "xx")))
        or ("site-packages" in parts and any(
            part == "pip" or part.startswith("pip-") for part in parts
        ))
    )


def export_packages(root, paths, copy):
    query = shutil.which("dpkg-query")
    if not query:
        return
    candidates = set()
    for path in paths:
        candidates.add(str(path))
        # dpkg 可能仍记录合并 /usr 前的路径。
        if path.parts[1:3] in {
            ("usr", "bin"), ("usr", "sbin"), ("usr", "lib"), ("usr", "lib64")
        }:
            candidates.add("/" + str(path.relative_to("/usr")))
    if not candidates:
        return
    result = subprocess.run(
        [query, "-S", *sorted(candidates)], text=True, capture_output=True,
        check=False, env=dict(os.environ, LC_ALL="C"),
    )
    # 官方 Python 的 /usr/local 文件和构建时生成的文件可以没有 Debian 包归属。
    if result.returncode not in {0, 1}:
        raise ValueError(f"cannot identify runtime packages: {result.stderr}")
    packages = set()
    for line in result.stdout.splitlines():
        if ": " not in line:
            continue
        for name in line.split(": ", 1)[0].split(", "):
            if re.fullmatch(r"[a-z0-9][a-z0-9+.-]*(?::[a-z0-9][a-z0-9-]*)?", name):
                packages.add(name)
    if not packages:
        return
    copy(Path("/usr/share/common-licenses"))
    result = subprocess.run(
        [query, "-W", "-f=${Package}\t${Version}\t${Architecture}\n", *sorted(packages)],
        text=True, capture_output=True, check=True,
    )
    for name in sorted(packages):
        copy(Path("/usr/share/doc") / name.split(":", 1)[0] / "copyright")
    metadata = root / "usr/share/padm/runtime-packages.txt"
    records = set(metadata.read_text(encoding="utf-8").splitlines()) if metadata.exists() else set()
    records.update(result.stdout.splitlines())
    metadata.parent.mkdir(parents=True, exist_ok=True)
    metadata.write_text("".join(f"{line}\n" for line in sorted(records)), encoding="utf-8")


def export(root, inputs):
    root = Path(root).resolve()
    root.mkdir(parents=True, exist_ok=True)
    seen = set()
    for name in ("bin", "sbin", "lib", "lib64"):
        source = Path("/") / name
        if source.is_symlink():
            destination = source.resolve().relative_to("/")
            (root / destination).mkdir(parents=True, exist_ok=True)
            alias = root / name
            if alias.is_symlink() and os.readlink(alias) == str(destination):
                continue
            if alias.exists() or alias.is_symlink():
                raise ValueError(f"conflicting runtime alias: {alias}")
            alias.symlink_to(destination)

    def copy(source):
        source = Path(os.path.abspath(source))
        source = source.parent.resolve() / source.name
        if source in seen or excluded(source):
            return
        seen.add(source)
        target = root / source.relative_to("/")
        # 文件使用构建系统的真实父路径；根目录别名仅使用安全的相对链接。
        parent = root
        for part in source.parts[1:-1]:
            parent /= part
            if parent.is_symlink():
                raise ValueError(f"symlink in runtime output parent: {parent}")
            parent.mkdir(exist_ok=True)
        if source.is_symlink():
            link = os.readlink(source)
            if target.exists() or target.is_symlink():
                if not target.is_symlink() or os.readlink(target) != link:
                    raise ValueError(f"conflicting runtime path: {source}")
            else:
                target.symlink_to(link)
            copy(link if os.path.isabs(link) else source.parent / link)
        elif source.is_dir():
            if target.is_symlink():
                raise ValueError(f"conflicting runtime directory: {source}")
            target.mkdir(exist_ok=True)
            shutil.copystat(source, target)
            for child in sorted(source.iterdir()):
                copy(child)
        elif source.is_file():
            if target.is_symlink():
                raise ValueError(f"conflicting runtime file: {source}")
            shutil.copy2(source, target)
            with source.open("rb") as stream:
                elf = stream.read(4) == b"\x7fELF"
            if not elf:
                return
            result = subprocess.run(
                ["ldd", str(source)], text=True, capture_output=True, check=False
            )
            output = result.stdout + result.stderr
            if "not found" in output:
                raise ValueError(f"missing ELF dependency: {source}\n{output}")
            if result.returncode and not any(
                message in output for message in (
                    "not a dynamic executable", "statically linked"
                )
            ):
                raise ValueError(f"cannot inspect ELF: {source}\n{output}")
            for line in output.splitlines():
                match = re.match(r"\s*(?:\S+\s+=>\s+)?(/[^\s]+)", line)
                if match:
                    copy(match.group(1))
        else:
            raise ValueError(f"missing or unsupported runtime file: {source}")

    for source in inputs:
        if not os.path.isabs(source):
            raise ValueError(f"runtime input must be absolute: {source}")
        copy(source)
    export_packages(root, [path for path in seen if not path.is_dir()], copy)
    manifest = root / "usr/share/padm/runtime-files.txt"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text("".join(
        f"/{path.relative_to(root)}\n" for path in sorted(root.rglob("*"))
        if not path.is_dir() or path.is_symlink()
    ), encoding="utf-8")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit("usage: export-runtime.py ROOT ABSOLUTE_PATH...")
    export(sys.argv[1], sys.argv[2:])
