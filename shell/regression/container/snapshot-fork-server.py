import calendar
import contextlib
import datetime
import hashlib
import io
import json
import os
from pathlib import Path
import re
import select
import signal
import socket
import stat
import struct
import sys
import threading


socket_path, source_path = sys.argv[1:]
source = Path(source_path).read_text()
function = source.split("\ndockerPortHoppingTargetSnapshot() {", 1)[1].split(
    "\ndockerPortHoppingTargetLockSnapshot() {", 1)[0]
body = function.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0] + "\n"
compiled = compile(body, "<stdin>", "exec")
expected = body.encode()
environment_names = (
    "PYTHONHOME", "PYTHONPATH", "PYTHONHASHSEED", "PYTHONUTF8", "PYTHONIOENCODING",
    "PYTHONNOUSERSITE", "PYTHONSAFEPATH", "PYTHONWARNINGS", "PYTHONDONTWRITEBYTECODE",
    "PYTHONOPTIMIZE", "PYTHONINSPECT", "PYTHONVERBOSE", "PYTHONDEVMODE",
    "PYTHONPROFILEIMPORTTIME", "HOME", "LANG", "LC_ALL", "LC_CTYPE", "TZ",
)
startup_environment = {}
for item in Path("/proc/self/environ").read_bytes().split(b"\0"):
    if item:
        name, value = item.split(b"=", 1)
        startup_environment[os.fsdecode(name)] = os.fsdecode(value)


def receive(connection, size):
    result = bytearray()
    while len(result) < size:
        data = connection.recv(size - len(result))
        if not data:
            raise EOFError("short snapshot request")
        result.extend(data)
    return result


def receive_data(connection):
    size = struct.unpack("!I", receive(connection, 4))[0]
    if size > 65536:
        raise ValueError("oversized snapshot request")
    return bytes(receive(connection, size))


def execute(connection, arguments):
    stdout, stderr = io.StringIO(), io.StringIO()
    status = 0
    sys.argv = arguments
    sys.stdin = io.StringIO("")
    with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
        try:
            # 只复用编译和模块加载；每个请求在独立子进程读取当前文件与元数据。
            exec(compiled, {"__name__": "__main__"})
        except SystemExit as error:
            if error.code is None:
                status = 0
            elif isinstance(error.code, int):
                status = error.code % 256
            else:
                print(error.code, file=sys.stderr)
                status = 1
        except BaseException:
            # 意外异常交给独立解释器输出原诊断，不能改变回归失败信息。
            status = 0xFFFFFFFF
    output, error = stdout.getvalue().encode(), stderr.getvalue().encode()
    connection.sendall(struct.pack("!III", status, len(output), len(error)) + output + error)

def watch_client(connection, master):
    while os.getppid() == master:
        try:
            readable, _, _ = select.select([connection], [], [], 0.1)
            if readable:
                break
        except OSError:
            break
    # 客户端中途退出时终止只读 worker，不能留下等待文件读取的子进程。
    os._exit(0)


server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(socket_path)
os.chmod(socket_path, 0o600)
server.listen(16)
signal.signal(signal.SIGINT, signal.default_int_handler)
signal.signal(signal.SIGCHLD, signal.SIG_IGN)
Path(socket_path + ".ready").write_text("")
while True:
    connection, _ = server.accept()
    with connection:
        try:
            connection.settimeout(5)
            count = struct.unpack("!I", receive(connection, 4))[0]
            if count != 7:
                raise ValueError("invalid snapshot argument count")
            arguments = [receive_data(connection).decode() for _ in range(count)]
            directory = receive_data(connection).decode()
            ignored_signals = [receive_data(connection) == b"1" for _ in range(2)]
            for name in environment_names:
                present = receive_data(connection) == b"1"
                value = receive_data(connection).decode()
                # Python 会自动补 LC_CTYPE，比较 exec 前的环境以保留真实 Bash 调用。
                if present != (name in startup_environment) or value != startup_environment.get(name, ""):
                    raise ValueError("snapshot interpreter environment changed")
            _, uid, gid = struct.unpack("3i", connection.getsockopt(
                socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i")))
            if uid != os.geteuid() or gid != os.getegid():
                raise ValueError("snapshot credentials changed")
            actual = receive_data(connection)
            if actual != expected:
                raise ValueError("snapshot body changed")
            process = os.fork()
            if process == 0:
                try:
                    server.close()
                    os.chdir(directory)
                    signal.signal(signal.SIGINT, signal.SIG_IGN if ignored_signals[0]
                                  else signal.default_int_handler)
                    signal.signal(signal.SIGTERM, signal.SIG_IGN if ignored_signals[1]
                                  else signal.SIG_DFL)
                    threading.Thread(target=watch_client, args=(connection, os.getppid()),
                                     daemon=True).start()
                    execute(connection, arguments)
                finally:
                    os._exit(0)
        except (OSError, EOFError, ValueError):
            # 正文变化或连接失败必须由客户端回退到原始 Python 入口。
            try:
                connection.sendall(struct.pack("!III", 0xFFFFFFFF, 0, 0))
            except OSError:
                pass
