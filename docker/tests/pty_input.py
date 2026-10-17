import os
import time


def wait_for_input(pid):
    # 提示输出早于 read 阻塞；此时发 TERM 可能延迟到下一次输入才执行 trap。
    # shortcut: 仅限提示后直接 read 的驱动；增加其它阻塞步骤时改用明确握手。
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        with open(f"/proc/{pid}/stat") as stream:
            state = stream.read().rsplit(") ", 1)[1].split()[0]
        with open(f"/proc/{pid}/wchan") as stream:
            wchan = stream.read().strip()
        with open(f"/proc/{pid}/task/{pid}/children") as stream:
            children = stream.read().strip()
        if state == "S" and wchan not in ("", "0") and not children:
            return
        os.sched_yield()
    raise AssertionError(f"输入子进程未进入等待: state={state}, wchan={wchan}, children={children}")
