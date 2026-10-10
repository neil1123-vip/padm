#!/usr/bin/env python3
import importlib.util
import io
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ssh_client", ROOT / "docker/lib/ssh-source-client.py")
client = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(client)
username = "padm-source-" + "a" * 48
assert client.parameters(["2001:db8::10", "2222", username, "/client/known_hosts"])[0] == "2001:db8::10"
for values in (
    [], ["host.example", "22", username, "/client/known_hosts"],
    ["192.0.2.10", "65536", username, "/client/known_hosts"],
    ["192.0.2.10", "22", "real-account", "/client/known_hosts"],
    ["fe80::1%eth0", "22", username, "/client/known_hosts"],
):
    try:
        client.parameters(values)
    except ValueError:
        pass
    else:
        raise AssertionError("非法客户端输入被接受")


class AuthenticationException(Exception):
    pass


key = Mock()
key.get_name.return_value = "ssh-ed25519"
socket = Mock()
transport = Mock()
transport.get_remote_server_key.return_value = key
transport.auth_none.side_effect = AuthenticationException()
transport.is_active.return_value = True
transport.is_authenticated.return_value = False
hosts = Mock()
hosts.lookup.return_value = {"ssh-ed25519": key}
paramiko = SimpleNamespace(HostKeys=Mock(return_value=hosts), Transport=Mock(return_value=transport),
                           AuthenticationException=AuthenticationException)


def probe():
    with patch.object(client.socket, "create_connection", return_value=socket), \
            patch.object(client.time, "monotonic", side_effect=[0, 26]), redirect_stdout(io.StringIO()):
        client.probe("192.0.2.10", 2222, username, "/client/known_hosts", paramiko)


probe()
hosts.lookup.assert_called_with("[192.0.2.10]:2222")
transport.auth_none.assert_called_once_with(username)
transport.auth_password.assert_not_called()
transport.auth_publickey.assert_not_called()
transport.close.assert_called_once()
socket.close.assert_called_once()

# 主机密钥不符时，认证请求不得发出，已打开资源仍必须清理。
transport.reset_mock()
socket.reset_mock()
hosts.lookup.return_value = {"ssh-ed25519": Mock()}
try:
    probe()
except ValueError:
    pass
else:
    raise AssertionError("错误主机密钥被接受")
transport.auth_none.assert_not_called()
transport.close.assert_called_once()
socket.close.assert_called_once()

print("docker-ssh-source-client-regression-ok")
