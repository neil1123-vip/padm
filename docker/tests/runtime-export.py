#!/usr/bin/env python3
"""验证导出的符号链接、缺失依赖拒绝及独立运行能力。"""

import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch


source = Path(__file__).resolve().parents[1] / "runtime/export-runtime.py"
spec = importlib.util.spec_from_file_location("export_runtime", source)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)

with tempfile.TemporaryDirectory(prefix="padm-runtime-export-") as temporary:
    base = Path(temporary)
    inputs = base / "inputs"
    inputs.mkdir()
    (inputs / "data").write_text("runtime\n", encoding="utf-8")
    (inputs / "relative").symlink_to("data")
    (inputs / "absolute").symlink_to(inputs / "data")
    (inputs / "tests").mkdir()
    (inputs / "tests/unused").write_text("excluded\n", encoding="utf-8")
    (inputs / "lib-dynload").mkdir()
    for name in ("_testcapi.so", "_xxtestfuzz.so", "_ctypes_test.so", "xxsubtype.so", "_ssl.so", "_ctypes.so"):
        (inputs / "lib-dynload" / name).write_text("extension fixture\n", encoding="utf-8")
    output = base / "rootfs"
    runtime.export(output, [str(inputs)])
    exported = output / inputs.relative_to("/")
    assert os.readlink(exported / "relative") == "data"
    assert os.readlink(exported / "absolute") == str(inputs / "data")
    assert (exported / "relative").read_text() == "runtime\n"
    assert not (exported / "tests").exists()
    assert sorted(path.name for path in (exported / "lib-dynload").iterdir()) == ["_ctypes.so", "_ssl.so"]
    if (output / "bin").is_symlink():
        assert os.readlink(output / "bin") == "usr/bin"
    runtime.export(output, [str(inputs / "data")])
    assert (exported / "relative").read_text() == "runtime\n"

    licenses = []
    package_output = base / "packages"
    with patch.object(runtime.shutil, "which", return_value="/usr/bin/dpkg-query"), \
            patch.object(runtime.subprocess, "run", side_effect=[
                subprocess.CompletedProcess([], 1, "runtime-one:amd64: /bin/runtime-one\n", ""),
                subprocess.CompletedProcess([], 0, "runtime-one\t1.0\tamd64\n", ""),
                subprocess.CompletedProcess([], 0, "runtime-two: /usr/bin/runtime-two\n", ""),
                subprocess.CompletedProcess([], 0, "runtime-two\t2.0\tamd64\n", ""),
            ]) as query:
        runtime.export_packages(
            package_output,
            [Path("/usr/bin/runtime-one"), Path("/usr/local/bin/python3")],
            licenses.append,
        )
        runtime.export_packages(package_output, [Path("/usr/bin/runtime-two")], licenses.append)
        assert "/bin/runtime-one" in query.call_args_list[0].args[0]
        assert "/usr/bin/runtime-one" in query.call_args_list[0].args[0]
    assert licenses == [
        Path("/usr/share/common-licenses"),
        Path("/usr/share/doc/runtime-one/copyright"),
        Path("/usr/share/common-licenses"),
        Path("/usr/share/doc/runtime-two/copyright"),
    ]
    assert (package_output / "usr/share/padm/runtime-packages.txt").read_text() == (
        "runtime-one\t1.0\tamd64\nruntime-two\t2.0\tamd64\n"
    )

    with patch.object(runtime.subprocess, "run", return_value=subprocess.CompletedProcess(
        [], 0, "libmissing.so => not found\n", ""
    )):
        try:
            runtime.export(base / "missing-library", ["/bin/ls"])
        except ValueError as error:
            assert "missing ELF dependency" in str(error)
        else:
            raise AssertionError("missing ELF library was accepted")

    runnable = base / "runnable"
    runtime.export(runnable, ["/bin/sh"])
    if (runnable / "bin").is_symlink():
        assert os.readlink(runnable / "bin") == "usr/bin"
    if os.geteuid() == 0:
        result = subprocess.run(
            ["chroot", str(runnable), "/bin/sh", "-c", "printf runtime-ok"],
            text=True, capture_output=True, check=True,
        )
        assert result.stdout == "runtime-ok"
    assert f"{Path('/bin').resolve()}/sh\n" in (
        runnable / "usr/share/padm/runtime-files.txt"
    ).read_text(encoding="utf-8")

print("runtime-export-regression-ok")
