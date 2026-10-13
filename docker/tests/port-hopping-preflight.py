#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys


SCRIPT = Path(__file__).resolve()
ROOT = SCRIPT.parents[2]

def tool():
    fixture = json.loads(Path(os.environ["HOP_FIXTURE"]).read_text())
    name, *args = sys.argv[2:]
    with Path(os.environ["HOP_COMMANDS"]).open("a") as output:
        output.write(json.dumps([name, *args]) + "\n")
    if fixture.get("fail") == name:
        print("fixture tool failure", file=sys.stderr)
        sys.exit(1)
    if fixture.get("warning") == name:
        print("fixture incomplete listing", file=sys.stderr)
    if name in {"iptables", "ip6tables"}:
        print(fixture.get("version", "iptables v1.8.11 (nf_tables)") if args == ["--version"]
              else fixture[name])
    elif name == "nft":
        print(json.dumps(fixture["nft"]))
    elif name == "ss":
        print(fixture["ss"])
    else:
        sys.exit(99)


def python():
    import runpy

    arguments = sys.argv[2:]
    assert len(arguments) == 6 and arguments[0] == "/dev/fd/3" and arguments[2] == "preflight"
    body = Path(arguments[0]).read_text()
    fixture = Path(os.environ["HOP_FIXTURE"])
    install = runpy.run_path(str(SCRIPT.with_name("port-hopping-ownership.py")))[
        "install_tool_mock_runner"]
    install(tool, fixture.parent / "bin")
    sys.argv = arguments
    exec(compile(body, "<port-hopping-preflight-fixture>", "exec"), {"__name__": "__main__"})


def main():
    import copy
    import subprocess
    import tempfile

    source = (ROOT / "docker/images/net/entrypoint.sh").read_text()
    base = {
        "iptables": "-P PREROUTING ACCEPT\n-P INPUT ACCEPT\n-P OUTPUT ACCEPT\n"
                    "-P POSTROUTING ACCEPT\n-N DOCKER\n"
                    "-A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER\n"
                    "-A DOCKER -p udp -m udp --dport 35461 -j DNAT "
                    "--to-destination 172.18.0.2:35461\n"
                    "-A POSTROUTING -s 172.18.0.0/16 ! -o br0 -j MASQUERADE",
        "ip6tables": "-P PREROUTING ACCEPT\n-P INPUT ACCEPT\n-P OUTPUT ACCEPT\n"
                     "-P POSTROUTING ACCEPT",
        "nft": {"nftables": [{"metainfo": {}}, {"chain": {
            "family": "ip", "table": "nat", "name": "PREROUTING",
            "type": "nat", "hook": "prerouting", "prio": -100}}]},
        "ss": "UNCONN 0 0 0.0.0.0:35461 0.0.0.0:*\n"
              "UNCONN 0 0 [::]:35461 [::]:*",
    }
    cases = []

    def case(name, accepted, rule=None, family="iptables", ports=None, **changes):
        value = copy.deepcopy(base)
        if rule:
            value[family] += "\n" + rule
        value.update(changes)
        cases.append((name, accepted, value, ports or ["36561", "36562", "35461"]))

    case("docker-baseline", True)
    for selected, accepted in (("36560", True), ("36563", True), ("36561", False),
                               ("36562", False), ("36000:37000", False),
                               ("35000:36561", False), ("36562:40000", False),
                               ("30000:30001,36563", True), ("30000,36562", False),
                               ("65536", False), ("foo", False), ("36562:36561", False)):
        for family in ("iptables", "ip6tables"):
            selector = "--dports" if "," in selected else "--dport"
            case(f"{family}-{selected}", accepted,
                 f"-A PREROUTING -p udp -m multiport {selector} {selected} "
                 "-j DNAT --to-destination 192.0.2.1:35461", family)
    for name, rule, accepted in (
        ("tcp", "-p tcp --dport 36561 -j DNAT --to-destination 192.0.2.1:9", True),
        ("docker-interface-negation", "! -i docker0 -p udp --dport 35461 "
         "-j DNAT --to-destination 172.17.0.2:35461", True),
        ("scoped", "-p udp -s 192.0.2.1 -d 192.0.2.2 --dport 36561 "
         "-j REDIRECT --to-ports 9", False),
        ("unknown-range", "-p udp -j DNAT --to-destination 192.0.2.1:9", False),
        ("negated", "-p udp -m udp ! --dport 36560 -j REDIRECT --to-ports 9", False),
        ("negated-protocol", "! -p tcp --dport 36561 -j DNAT "
         "--to-destination 192.0.2.1:9", False),
        ("duplicate", "-p udp --dport 36560 --dport 36561 -j REDIRECT --to-ports 9", False),
        ("unknown-target", "-p udp --dport 36560 -j UNKNOWN", False),
        ("netmap", "-p udp --dport 36561 -j NETMAP --to 192.0.2.0/24", False),
    ):
        case(name, accepted, "-A PREROUTING " + rule)
    case("orphan-owner", False, "-N padm-hop-0123456789ab", "ip6tables")
    case("legacy-backend", False, version="iptables v1.8.11 (legacy)")
    case("native-nft", False, nft={"nftables": [{"chain": {
        "family": "inet", "table": "outside", "name": "ingress", "type": "nat"}}]})
    for expression in ({"dnat": {"addr": "192.0.2.1", "port": 35461}},
                       {"redirect": {"port": 35461}}, {"mangle": {"value": 35461}}):
        native = copy.deepcopy(base["nft"])
        native["nftables"].append({"rule": {
            "family": "ip", "table": "nat", "chain": "PREROUTING",
            "expr": [{"match": {"op": "==", "left": {"payload": {
                "protocol": "udp", "field": "dport"}}, "right": 36561}}, expression]}})
        case("standard-chain-native-" + next(iter(expression)), False, nft=native)
    for tool in ("iptables", "ip6tables", "nft", "ss"):
        case("failed-" + tool, False, fail=tool)
        case("partial-" + tool, False, warning=tool)
    for listener in ("0.0.0.0:36561", "[::]:36562", "192.0.2.2:36561"):
        case("listener-" + listener, False, ss=f"UNCONN 0 0 {listener} *:*")
        case("connected-" + listener, False, ss=f"ESTAB 0 0 {listener} 192.0.2.1:9")
    case("bad-listing", False, ss="not a UDP socket listing")
    for ports in (["36562", "36561", "35461"], ["36561", "36562", "36562"],
                  ["0", "36562", "35461"], ["036561", "36562", "35461"],
                  ["36561", "65536", "35461"]):
        case("bad-ports-" + "-".join(ports), False, ports=ports)

    with tempfile.TemporaryDirectory(prefix="padm-hopping-preflight.") as directory:
        work = Path(directory)
        functions = work / "functions.sh"
        functions.write_text(source.split('case "${1:-idle}" in')[0])
        binaries = work / "bin"
        binaries.mkdir()
        for name in ("iptables", "ip6tables", "nft", "ss"):
            path = binaries / name
            path.write_text(f'#!/bin/sh\nexec /usr/bin/python3 -S "{SCRIPT}" tool "{name}" "$@"\n')
            path.chmod(0o755)
        adapter = binaries / "python3"
        adapter.write_text(
            '#!/bin/sh\nif [ "${1:-}" = /dev/fd/3 ] && [ "${3:-}" = preflight ]; then\n'
            f'    exec /usr/bin/python3 -S "{SCRIPT}" python "$@"\n'
            'fi\nexec /usr/bin/python3 "$@"\n')
        adapter.chmod(0o755)
        fixture, commands = work / "fixture.json", work / "commands.jsonl"
        environment = dict(os.environ, PATH=f"{binaries}:{os.environ['PATH']}",
                           HOP_FIXTURE=str(fixture), HOP_COMMANDS=str(commands))
        state = work / "state"
        state.mkdir()
        for name, accepted, value, ports in cases:
            fixture.write_text(json.dumps(value))
            commands.write_text("")
            before = fixture.read_bytes()
            result = subprocess.run(["sh", "-c",
                '. "$1"; STATE_ROOT=$2; port_hopping_preflight "$3" "$4" "$5"',
                "test", str(functions), str(state), *ports],
                env=environment, capture_output=True, text=True, timeout=10)
            assert (result.returncode == 0) == accepted, (name, result.stderr)
            assert not result.stdout and fixture.read_bytes() == before
            assert list(state.iterdir()) == []
            for line in commands.read_text().splitlines():
                tool, *args = json.loads(line)
                assert (tool in {"iptables", "ip6tables"} and
                        args in [["--version"], ["-w", "-t", "nat", "-S"]]
                        or tool == "nft" and args == ["-j", "list", "ruleset"]
                        or tool == "ss" and args == ["-H", "-u", "-a", "-n"]), line
        (state / "port-hopping.state").symlink_to(work / "missing")
        fixture.write_text(json.dumps(base))
        commands.write_text("")
        result = subprocess.run(["sh", "-c",
            '. "$1"; STATE_ROOT=$2; port_hopping_preflight 36561 36562 35461',
            "test", str(functions), str(state)], env=environment, capture_output=True,
            text=True, timeout=10)
        assert result.returncode != 0 and not commands.read_text()
        assert (state / "port-hopping.state").is_symlink()
    print(f"docker-port-hopping-preflight-ok: {len(cases) + 1} read-only cases")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "tool":
        tool()
    elif len(sys.argv) > 1 and sys.argv[1] == "python":
        python()
    else:
        main()
