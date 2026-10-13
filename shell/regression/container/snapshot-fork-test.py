import json
import os
from pathlib import Path
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time


client, source_path = sys.argv[1:]
source = Path(source_path).read_text()
function = source.split("\ndockerPortHoppingTargetSnapshot() {", 1)[1].split(
    "\ndockerPortHoppingTargetLockSnapshot() {", 1)[0]
body = (function.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0] + "\n").encode()
owner, domain = str(os.getpid()), "fixture.example.com"
count = 0
default_environment = {}
for item in Path("/proc/self/environ").read_bytes().split(b"\0"):
    if item:
        name, value = item.split(b"=", 1)
        default_environment[os.fsdecode(name)] = os.fsdecode(value)


def wait_for(check, message):
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(0.01)
    raise AssertionError(message)


def execute(binary, arguments, script=body, environment=None, directory=None):
    return subprocess.run([binary, "-", *map(str, arguments)], input=script,
                          capture_output=True, env=default_environment if environment is None else environment,
                          cwd=directory, timeout=5)


def compare(arguments, accepted, script=body, environment=None, directory=None):
    global count
    standalone = execute(sys.executable, arguments, script, environment, directory)
    adapted = execute(client, arguments, script, environment, directory)
    assert (standalone.returncode == 0) == accepted, standalone.stderr
    assert (standalone.returncode, standalone.stdout, standalone.stderr) == (
        adapted.returncode, adapted.stdout, adapted.stderr), (
        arguments[0], standalone, adapted)
    count += 1
    return standalone


with tempfile.TemporaryDirectory(prefix="snapshot-fork-check-") as temporary:
    root = Path(temporary) / "state"
    (root / "locks/deployment.lock").mkdir(parents=True)
    for name in ("", "locks", "locks/deployment.lock"):
        (root / name).chmod(0o750)
    pid = root / "locks/deployment.lock/pid"
    pid.write_text(owner + "\n")
    pid.chmod(0o640)
    for directory in ("config/sing-box", "secrets/tls", "data/sing-box",
                      "data/traffic", "data/static"):
        (root / directory).mkdir(parents=True)
    for name in ("config/spec.json", "deployment.json", "images.env", "compose.json",
                 "config/sing-box/users.base", "config/sing-box/config.json",
                 "data/traffic/state.json", "secrets/tls/" + domain + ".crt",
                 "secrets/tls/" + domain + ".key"):
        (root / name).write_text("fixture-content\n")
    lock_arguments = ("lock", root, owner, "", "", "")
    files_arguments = ("files", root, "", domain, "", "")
    expected = compare(lock_arguments, True).stdout.decode().strip()
    files = compare(files_arguments, True).stdout
    start_arguments = ("start", root, owner, domain, "", expected)
    combined = compare(start_arguments, True)
    assert combined.stdout == expected.encode() + b"\n" + files
    compare(("start", root, owner, domain, "2099-01-01T00:00:00Z", expected), True)
    compare(("start", root, owner, domain, "", "[]"), False)
    compare(("files", root, "", "../fixture", "", ""), False)
    compare(("files", root, "", domain, "2000-01-01T00:00:00Z", ""), False)
    compare(("files", root, "", domain, "2026-02-30T00:00:00Z", ""), False)
    compare(("lock", "relative", owner, "", "", ""), False)
    compare(("lock", "/" + str(root), owner, "", "", ""), False)
    compare(("lock", "/", owner, "", "", ""), False)
    pid.chmod(0o600)
    assert compare(start_arguments, False).stdout == b""
    pid.chmod(0o640)
    for mutation in ("replaced", "hardlink", "symlink", "missing"):
        replacement = pid.with_name("replacement")
        shutil.copy2(pid, replacement)
        if mutation == "replaced":
            os.replace(replacement, pid)
            assert compare(start_arguments, False).stdout.strip() != expected.encode()
            expected = compare(lock_arguments, True).stdout.decode().strip()
            start_arguments = ("start", root, owner, domain, "", expected)
        elif mutation == "hardlink":
            extra = pid.with_name("link")
            os.link(pid, extra)
            compare(start_arguments, False)
            extra.unlink()
        elif mutation == "symlink":
            pid.unlink()
            pid.symlink_to(replacement.name)
            compare(start_arguments, False)
            pid.unlink()
            os.replace(replacement, pid)
        else:
            pid.unlink()
            compare(start_arguments, False)
            os.replace(replacement, pid)
        replacement.unlink(missing_ok=True)
    expected = compare(lock_arguments, True).stdout.decode().strip()
    start_arguments = ("start", root, owner, domain, "", expected)
    certificate = root / "secrets/tls" / (domain + ".crt")
    certificate.unlink()
    assert compare(start_arguments, False).stdout == expected.encode() + b"\n"
    certificate.write_text("fixture-content\n")
    first = compare(files_arguments, True).stdout
    shutil.copy2(certificate, certificate.with_suffix(".next"))
    os.replace(certificate.with_suffix(".next"), certificate)
    assert compare(files_arguments, True).stdout != first
    compare(lock_arguments, True, body + b"\n# changed body\n")
    assert compare(lock_arguments, True, b"import sys\nprint('changed')\n").stdout == b"changed\n"
    compare(("files", "state", "", domain, "", ""), True, directory=temporary)
    for name, value in (("PYTHONOPTIMIZE", "1"), ("PYTHONHASHSEED", "123"),
                        ("PYTHONIOENCODING", "utf-8"), ("LC_ALL", "C"), ("TZ", "UTC")):
        compare(lock_arguments, True, environment=dict(default_environment, **{name: value}))
    assert (Path(os.environ["PADM_SNAPSHOT_FORK_SOCKET"]).stat().st_mode & 0o777) == 0o600
    assert (Path(client).parent.stat().st_mode & 0o777) == 0o700
    unavailable = dict(default_environment, PADM_SNAPSHOT_FORK_SOCKET=str(root / "unavailable"))
    compare(lock_arguments, True, environment=unavailable)
    partial_socket = str(root / "partial.socket")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        server.bind(partial_socket)
        server.listen(1)

        def partial_response():
            connection, _ = server.accept()
            with connection:
                connection.recv(65536)
                connection.sendall(struct.pack("!III", 0, 100, 0) + b"partial")

        thread = threading.Thread(target=partial_response)
        thread.start()
        partial = dict(default_environment, PADM_SNAPSHOT_FORK_SOCKET=partial_socket)
        compare(lock_arguments, True, environment=partial)
        thread.join(timeout=5)
        assert not thread.is_alive()
    master = int(os.environ["PADM_SNAPSHOT_FORK_PID"])
    master_ignored = int(next(line.split()[1] for line in
                              Path(f"/proc/{master}/status").read_text().splitlines()
                              if line.startswith("SigIgn:")), 16)
    assert not master_ignored & (1 << (signal.SIGINT - 1))
    children_path = Path(f"/proc/{master}/task/{master}/children")
    wait_for(lambda: not children_path.read_text().strip(), "snapshot worker leaked")
    # 独立诊断正文只验证 fork 生命周期，不能替换真实快照正文的校验。
    diagnostic = b"import time\ntime.sleep(30)\n"
    diagnostic_source = root / "diagnostic.sh"
    diagnostic_source.write_text(
        "\ndockerPortHoppingTargetSnapshot() {\npython3 - <<'PY'\n" +
        diagnostic.decode() + "PY\n}\ndockerPortHoppingTargetLockSnapshot() {\n}\n")
    diagnostic_socket = str(root / "diagnostic.socket")
    diagnostic_environment = dict(default_environment, PADM_SNAPSHOT_FORK_SOCKET=diagnostic_socket)
    diagnostic_master = subprocess.Popen(
        [sys.executable, str(Path(__file__).with_name("snapshot-fork-server.py")),
         diagnostic_socket, str(diagnostic_source)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env=default_environment,
        preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_IGN))
    try:
        wait_for(lambda: Path(diagnostic_socket + ".ready").exists(), "diagnostic master not ready")
        diagnostic_children = Path(
            f"/proc/{diagnostic_master.pid}/task/{diagnostic_master.pid}/children")
        for sent_signal in (signal.SIGINT, signal.SIGTERM, signal.SIGKILL):
            ignored = sent_signal == signal.SIGKILL

            def dispositions():
                if ignored:
                    signal.signal(signal.SIGINT, signal.SIG_IGN)
                    signal.signal(signal.SIGTERM, signal.SIG_IGN)

            process = subprocess.Popen([client, "-", *map(str, lock_arguments)],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, env=diagnostic_environment,
                                       cwd=temporary, preexec_fn=dispositions)
            process.stdin.write(diagnostic)
            process.stdin.close()
            process.stdin = None
            worker = int(wait_for(lambda: diagnostic_children.read_text().strip(),
                                  "diagnostic worker not started"))
            wait_for(lambda: os.readlink(f"/proc/{worker}/cwd") == temporary,
                     "snapshot worker cwd changed")
            def matching_dispositions():
                ignored_mask = int(next(line.split()[1] for line in
                                        Path(f"/proc/{worker}/status").read_text().splitlines()
                                        if line.startswith("SigIgn:")), 16)
                return all(bool(ignored_mask & (1 << (value - 1))) == ignored
                           for value in (signal.SIGINT, signal.SIGTERM))

            wait_for(matching_dispositions, "snapshot worker signal disposition changed")
            process.send_signal(sent_signal)
            output, error = process.communicate(timeout=2)
            assert process.returncode == -sent_signal and not output and not error
            wait_for(lambda: not diagnostic_children.read_text().strip(),
                     "disconnected snapshot worker leaked")
            count += 1
        process = subprocess.Popen([client, "-", *map(str, lock_arguments)],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, env=diagnostic_environment)
        process.stdin.write(diagnostic)
        process.stdin.close()
        process.stdin = None
        worker = int(wait_for(lambda: diagnostic_children.read_text().strip(),
                              "master-death worker not started"))
        diagnostic_master.terminate()
        diagnostic_master.communicate(timeout=2)
        wait_for(lambda: not Path(f"/proc/{worker}").exists(), "orphan snapshot worker leaked")
        process.terminate()
        process.communicate(timeout=2)
        count += 1
    finally:
        diagnostic_master.terminate()
        diagnostic_master.communicate(timeout=2)
print(f"snapshot-fork-ok: {count} live reads, identity, failure and fallback checks")
