#!/usr/bin/env python3
"""Read-only independent verification of the native v3.44.1 ICMP experiment."""
import argparse
import copy
import hashlib
import io
import ipaddress
import json
import re
import struct
import sys
import tarfile
from pathlib import Path, PurePosixPath
from collections import Counter


VERSION = "3.44.1"
TARGET = "203.0.113.200"
MODES = ("direct", "filtered", "denied")
IMAGE_NAMES = {"xray", "sing-box", "nginx", "ops", "net"}
EMPTY_SHA = hashlib.sha256(b"").hexdigest()
COMMIT = "b8c22dba010f127f01bce04b00b2c024323b3496"
MANIFEST_SHA = "de7c32979710cdeddda9cb8ad465c66d33baa0b54b91c92e8647d93cdcfc3edc"
BUNDLE_SHA = "cda1c2f20cbfdcbdbd0454ecdfd4fd0299cba9c54695e30b73457834a944dd4f"
SIGNATURE_SHA = "51f6564d9ecd403a949b94439dbb12a26149abde7fbc67052947e472f953e8ce"
GUEST_INPUT = "/root/padm-icmp-input"
CLI = "/usr/local/bin/padm-docker"
TARGET_NS = ("ip", "netns", "exec", "padm-icmp-target")
SCOPE = "formal-3.44.1-native-amd64-host-icmp-ipv4"
SIGNER = "https://github.com/neil1123-vip/padm/.github/workflows/create_release.yml@refs/heads/main"
ISSUER = "https://token.actions.githubusercontent.com"
NEGATIVE_SCRIPT = ('set +e; output=$(timeout --foreground -k 2 25 docker run --rm --network host '
                   '--read-only --cap-drop ALL --security-opt no-new-privileges "$1" '
                   'tls ping -ip 192.0.2.1 cloudflare.com:443 2>&1); code=$?; '
                   'printf "%s\\nPROBE_RC=%s\\n" "$output" "$code"; '
                   '[[ "$code" == 0 || "$code" == 1 || "$code" == 124 ]] && '
                   '[[ "$output" != *"Handshake succeeded"* ]]')
BASE_SHA512 = ("3247873136ba09b060fab45e9c115239f81c1d401fce00b8fa9b872013f7135d6a40b"
               "12462ab5ac03b9fa4ed5955dd0e8d1c900109a939ad7a0a4dafe7dea47b")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def equal(left, right, message):
    require(left == right, message)


def sha(content):
    return hashlib.sha256(content).hexdigest()


def pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def reject_constant(value):
    raise AssertionError(f"non-finite JSON number: {value}")


def load_bytes(content):
    return json.loads(content.decode("utf-8"), object_pairs_hook=pairs,
                      parse_constant=reject_constant,
                      parse_float=lambda value: reject_constant(value) if abs(float(value)) == float("inf")
                      else float(value))


def safe_name(value):
    require(isinstance(value, str) and "\\" not in value and "\0" not in value,
            "unsafe artifact name")
    path = PurePosixPath(value)
    require(value and path.parts and not path.is_absolute() and ".." not in path.parts
            and str(path) == value and ":" not in value, "unsafe artifact path")
    return value


class Evidence:
    def __init__(self, root):
        self.root = root.resolve()
        self.used = set()

    def read(self, name):
        safe_name(name)
        path = self.root / name
        require(path.is_file() and not path.is_symlink(), f"missing artifact: {name}")
        require(path.resolve().is_relative_to(self.root), "artifact escaped input root")
        self.used.add(name)
        return path.read_bytes()

    def json(self, name):
        return load_bytes(self.read(name))

    def bind(self, name, expected):
        content = self.read(name)
        require(expected == {"sha256": sha(content), "bytes": len(content)},
                f"artifact digest/size mismatch: {name}")
        return content


class Archive(Evidence):
    def __init__(self, content):
        self.used = set()
        self.files = {}
        with tarfile.open(fileobj=io.BytesIO(content), mode="r:") as archive:
            for member in archive:
                if member.name == "." and member.isdir():
                    continue
                name = safe_name(member.name.removeprefix("./"))
                require(member.isfile() and "/" not in name and name not in self.files,
                        "unexpected guest tar path, type or duplicate entry")
                self.files[name] = archive.extractfile(member).read()

    def read(self, name):
        self.used.add(name)
        require(name in self.files, f"missing guest artifact: {name}")
        return self.files[name]


def checksum(packet):
    if len(packet) % 2:
        packet += b"\0"
    total = sum(struct.unpack(f"!{len(packet) // 2}H", packet))
    while total >> 16:
        total = (total & 65535) + (total >> 16)
    return ~total & 65535


def packet_bytes(value):
    require(isinstance(value, str) and re.fullmatch(r"(?:[0-9a-f]{2})+", value),
            "invalid packet hex")
    return bytes.fromhex(value)


def icmp_body(content, nonce, expected_type):
    require(len(content) == 8 + len(nonce), "ICMP length or nonce length changed")
    require(content[:2] == bytes((expected_type, 0)), "ICMP type/code mismatch")
    require(checksum(content) == 0, "invalid ICMP checksum")
    require(content[8:] == nonce, "ICMP nonce mismatch")
    return dict(type=content[0], code=content[1],
                identifier=int.from_bytes(content[4:6], "big"),
                sequence=int.from_bytes(content[6:8], "big"))


def ipv4_icmp(content, nonce, expected_type):
    require(len(content) >= 28 and content[0] >> 4 == 4, "not IPv4 ICMP")
    ihl = (content[0] & 15) * 4
    require(20 <= ihl <= 60 and len(content) >= ihl + 8, "bad IPv4 header length")
    require(int.from_bytes(content[2:4], "big") == len(content), "bad IPv4 total length")
    require(content[9] == 1, "not ICMP protocol")
    require(int.from_bytes(content[6:8], "big") & 0x3FFF == 0,
            "fragmented ICMP cannot establish a complete echo")
    require(checksum(content[:ihl]) == 0, "invalid IPv4 header checksum")
    result = icmp_body(content[ihl:], nonce, expected_type)
    result.update(source=str(ipaddress.IPv4Address(content[12:16])),
                  destination=str(ipaddress.IPv4Address(content[16:20])))
    require(result["destination" if expected_type == 8 else "source"] == TARGET,
            "ICMP target mismatch")
    return result


def linux_status(text):
    require(isinstance(text, str), "process status is not raw text")
    fields = {}
    for line in text.splitlines():
        key, sep, value = line.partition(":")
        if sep:
            require(key not in fields, "duplicate process status field")
            fields[key] = value.strip()
    require({"Uid", "Gid", "Groups", "CapEff"} <= fields.keys(), "incomplete process status")
    return dict(uid=[int(x) for x in fields["Uid"].split()],
                gid=[int(x) for x in fields["Gid"].split()],
                groups=[int(x) for x in fields["Groups"].split()],
                capeff=int(fields["CapEff"], 16))


def netns(value):
    require(isinstance(value, str) and re.fullmatch(r"net:\[[1-9][0-9]*\]", value),
            "invalid network namespace identity")
    return value


def stable(value, handles=True):
    if isinstance(value, list):
        return [stable(item, handles) for item in value]
    if not isinstance(value, dict):
        return value
    result = {}
    for key, item in value.items():
        if key in {"stats", "stats64"} or key == "handle" and not handles:
            continue
        if key == "counter" and isinstance(item, dict):
            require(set(item) == {"packets", "bytes"}, "unknown nft counter fields")
            require(all(type(number) is int and number >= 0 for number in item.values()),
                    "invalid nft counter")
            result[key] = dict(packets=0, bytes=0)
        else:
            result[key] = stable(item, handles)
    return result


def at_least(current, before):
    require(current.keys() == before.keys(), "ledger identities changed")
    for key in before:
        if isinstance(before[key], dict):
            at_least(current[key], before[key])
        elif key in {"upload", "download"}:
            require(type(current[key]) is int and type(before[key]) is int
                    and current[key] >= before[key] >= 0,
                    f"ledger counter decreased: {key}")
        else:
            require(current[key] == before[key], f"ledger identity changed: {key}")


def record(current):
    return {"sha256": sha(current), "bytes": len(current)}


def file_record(value):
    require(isinstance(value, dict) and set(value) == {"sha256", "bytes", "mode", "uid", "gid"},
            "unknown file metadata")
    require(re.fullmatch(r"[0-9a-f]{64}", value["sha256"]) is not None
            and type(value["bytes"]) is int and value["bytes"] >= 0
            and type(value["mode"]) is int and 0 <= value["mode"] <= 0o777
            and value["uid"] == value["gid"] == 0, "invalid file metadata")


def probe_evidence(probe, mode, host_ns):
    require(probe["passed"] is True and probe["mode"] == mode, "probe outcome mismatch")
    require(netns(probe["caller_netns"]) == netns(probe["host_netns"]) == host_ns,
            "probe did not run in guest host netns")
    require(probe["uid"] == 0 and probe["gid"] == 10001 and probe["groups"] == [10001],
            "probe group qualification mismatch")
    status = linux_status(probe["probe_status"])
    require(status["uid"] == [0] * 4 and status["gid"] == [10001] * 4
            and status["groups"] == [10001], "raw probe process identity mismatch")
    require(ping_range(probe["ping_group_range"]) == expected_range(mode),
            "probe range is not the scenario range")
    require(re.fullmatch(r"padm-native-icmp-[0-9a-f]{32}", probe["nonce"]) is not None,
            "unexpected ICMP nonce")
    nonce = probe["nonce"].encode("ascii")
    equal(probe["nonce_sha256"], sha(nonce), "nonce digest mismatch")
    sent = icmp_body(packet_bytes(probe["sent_icmp_hex"]), nonce, 8)
    require(sent["identifier"] == 0 and sent["sequence"] == 1, "altered client echo request")
    counts = dict(tun_requests=0, wire_requests=0, wire_replies=0, echo_replies=0)
    flow = {}
    for captured in probe["captures"]:
        kind = captured["type"]
        interface = captured["interface"]
        require(kind in (0, 8) and interface in ("padm-tun", "icmp-uplink"),
                "unexpected ICMP interface/type")
        packet = packet_bytes(captured["packet_hex"])
        decoded = ipv4_icmp(packet, nonce, kind)
        equal({name: captured[name] for name in decoded}, decoded, "ICMP capture fields changed")
        require(captured["payload_hex"] == nonce.hex() and captured["icmp_checksum"] == 0
                and captured["protocol"] == 0x800 and decoded["sequence"] == sent["sequence"],
                "bad nonce, checksum or sequence in observed capture")
        require(captured["packet_type"] == (4 if kind == 8 else 0),
                "echo capture direction mismatch")
        flow.setdefault((interface, kind), []).append(decoded)
        if kind == 8:
            counts["tun_requests" if interface == "padm-tun" else "wire_requests"] += 1
        elif interface == "icmp-uplink":
            counts["wire_replies"] += 1
    client_echoes = []
    for received in probe["ping_received"]:
        if "errno" in received:
            require(set(received) == {"errno"} and type(received["errno"]) is int
                    and received["errno"] > 0 and mode != "direct", "unexpected ping socket failure")
            continue
        require(mode == "direct" and received["address"][0] == TARGET,
                "echo sender did not match remote target")
        body = icmp_body(packet_bytes(received["packet_hex"]), nonce, 0)
        require(body["sequence"] == sent["sequence"], "ping socket sequence mismatch")
        client_echoes.append(body)
        counts["echo_replies"] += 1
    require(counts["tun_requests"] > 0, "caller bypassed TUN")
    expected = {"direct": (1, 1, 1), "filtered": (1, 0, 0), "denied": (0, 0, 0)}[mode]
    equal(tuple(counts[key] for key in ("wire_requests", "wire_replies", "echo_replies")),
          expected, "incorrect observed wire or ping counts")
    equal(probe["counts"], counts, "reported counts did not match raw capture")
    if mode == "direct":
        wire_request, = flow[("icmp-uplink", 8)]
        wire_reply, = flow[("icmp-uplink", 0)]
        require(wire_request["source"] == wire_reply["destination"]
                and wire_request["identifier"] == wire_reply["identifier"],
                "wire Echo Reply did not bind to the outgoing wire request")
        require(any(request["identifier"] == client_echoes[0]["identifier"]
                    for request in flow[("padm-tun", 8)]), "ping reply did not bind to host TUN request")
    for protocol, payload in [("tcp", nonce + b"\n"), ("udp", nonce)]:
        sample = probe[protocol]
        equal(sample["peer"], [TARGET, 35991], f"{protocol} peer did not match target")
        require(sample["sent_hex"] == sample["received_hex"] == payload.hex(),
                f"{protocol} did not return the exact nonce")
        require(ipaddress.IPv4Address(sample["local"][0])
                and type(sample["local"][1]) is int and 1 <= sample["local"][1] <= 65535,
                f"invalid {protocol} local IPv4 socket")
    return counts


def ping_range(value):
    require(isinstance(value, str) and re.fullmatch(r"\d+[ \t]+\d+\n", value),
            "unrecognized raw ping_group_range")
    return tuple(map(int, value.split()))


def expected_range(mode):
    return (10001, 10001) if mode == "denied" else (0, 2147483647)


def filter_evidence(value):
    rules = [entry["rule"] for entry in value["nftables"] if "rule" in entry]
    tables = [entry["table"] for entry in value["nftables"] if "table" in entry]
    chains = [entry["chain"] for entry in value["nftables"] if "chain" in entry]
    require(len(rules) == len(tables) == len(chains) == 1, "unexpected filter table contents")
    table, chain, rule = tables[0], chains[0], rules[0]
    require((table["family"], table["name"]) == ("inet", "icmp_target")
            and (chain["family"], chain["table"], chain["name"], chain["hook"],
                 chain["type"], chain["policy"], chain["prio"])
            == ("inet", "icmp_target", "input", "input", "filter", "accept", 0)
            and (rule["family"], rule["table"], rule["chain"]) == ("inet", "icmp_target", "input"),
            "filter was not at the target namespace input")
    expr = rule["expr"]
    require(len(expr) == 4 and expr[3] == {"drop": None}, "not a unique target-drop rule")
    for item, layer, field, right in [
        (expr[0], "ip", "daddr", TARGET), (expr[1], "icmp", "type", "echo-request")
    ]:
        equal(item, {"match": {"left": {"payload": {"protocol": layer, "field": field}},
                              "op": "==", "right": right}}, "target filter match changed")
    counter = expr[2]["counter"]
    require(type(counter["packets"]) is int and counter["packets"] == 1
            and type(counter["bytes"]) is int and counter["bytes"] > 0,
            "target drop did not count exactly one IPv4 Echo request")


def ledger_accounts(ledger):
    require(isinstance(ledger["accounts"], dict) and ledger["accounts"], "empty account ledger")
    return ledger["accounts"]


def preserved_material(before, after):
    require(set(before) == set(after) == {"accounts", "account_semantics_sha256", "secrets",
            "ledger", "business_config_sha256"}, "unknown material fields")
    for field in ("accounts", "account_semantics_sha256", "secrets", "business_config_sha256"):
        equal(before[field], after[field], f"business identity changed: {field}")
    for field in ("account_semantics_sha256", "business_config_sha256"):
        require(re.fullmatch(r"[0-9a-f]{64}", before[field]) is not None, "bad business digest")
    require(isinstance(before["accounts"], list) and len(before["accounts"]) == 1,
            "expected one dedicated account")
    account, = before["accounts"]
    require(account["name"] == "native-icmp" and re.fullmatch(r"[A-Za-z0-9_.-]+", account["id"]),
            "test account identity changed")
    require(not ({"uuid", "password", "shadowsocks_password"} & account.keys()),
            "unredacted account credentials")
    equal(set(account["credentials"]), {"uuid", "password", "shadowsocks_password"},
          "credential redaction shape")
    for item in account["credentials"].values():
        require(set(item) == {"sha256", "bytes"} and re.fullmatch(r"[0-9a-f]{64}", item["sha256"])
                and type(item["bytes"]) is int and item["bytes"] > 0, "bad credential digest")
    for name, item in before["secrets"].items():
        require(safe_name(name).startswith("secrets/"), "secret metadata outside expected path")
        file_record(item)
    old, new = ledger_accounts(before["ledger"]), ledger_accounts(after["ledger"])
    require(account["id"] in old and old.keys() == new.keys(), "ledger identities changed")
    require(old[account["id"]]["limit_bytes"] == 1024**3
            and old[account["id"]]["name"] == account["name"], "test quota/name not bound")
    for identifier in old:
        if not {"upload", "download"} <= old[identifier].keys():
            raise AssertionError("ledger account absent totals")
        at_least({key: new[identifier][key] for key in ("name", "limit_bytes", "upload", "download")},
                 {key: old[identifier][key] for key in ("name", "limit_bytes", "upload", "download")})
    return account["id"]


def release_assets(root):
    evidence = Evidence(root)
    manifest_raw = evidence.read("release-manifest.json")
    require(sha(manifest_raw) == MANIFEST_SHA, "not the pinned formal manifest")
    manifest = load_bytes(manifest_raw)
    require(manifest["release"]["version"] == VERSION
            and manifest["release"]["commit"] == COMMIT, "formal release identity changed")
    require(manifest["control"]["sha256"] == BUNDLE_SHA, "formal bundle reference changed")
    require(sha(evidence.read("release-manifest.sigstore.json")) == SIGNATURE_SHA,
            "formal release signature artifact changed")
    require(sha(evidence.read("padm-docker-bundle.tar.gz")) == BUNDLE_SHA,
            "not the pinned formal bundle")
    images = {}
    for name in sorted(IMAGE_NAMES):
        row = manifest["images"][name]
        index_raw = evidence.read(f"image-{name}-index.json")
        require("sha256:" + sha(index_raw) == row["index_digest"], f"{name} index mismatch")
        index = load_bytes(index_raw)
        platform = [m for m in index["manifests"]
                    if m.get("platform") == {"os": "linux", "architecture": "amd64"}]
        require(len(platform) == 1, f"{name} amd64 descriptor missing or duplicated")
        require(platform[0]["digest"] == row["platforms"]["linux/amd64"],
                f"{name} platform digest mismatch")
        raw = evidence.read(f"image-{name}-amd64-manifest.json")
        require("sha256:" + sha(raw) == platform[0]["digest"]
                and len(raw) == platform[0]["size"], f"{name} platform manifest mismatch")
        image = load_bytes(raw)
        require(re.fullmatch(r"sha256:[0-9a-f]{64}", image["config"]["digest"]) is not None,
                f"{name} image config digest invalid")
        images[name] = dict(reference=row["reference"],
                            index_digest=row["index_digest"],
                            platform_digest=platform[0]["digest"],
                            config_digest=image["config"]["digest"],
                            index=index, platform=platform[0], manifest=image)
    installed = {}
    with tarfile.open(root / "padm-docker-bundle.tar.gz", "r:gz") as archive:
        for member in archive:
            safe_name(member.name)
            require(member.isfile() and member.name not in installed,
                    "formal bundle contains links, directories or duplicate paths")
            installed[member.name] = archive.extractfile(member).read()
    require({"versions.lock", "docker-bake.hcl", "docker/contracts/bundle.paths"}
            <= installed.keys(), "formal bundle shape changed")
    payload = {name: content for name, content in installed.items()
               if name not in {"versions.lock", "docker-bake.hcl"}}
    return dict(images=images, payload=payload, assets={
        name: record(evidence.read(name))
        for name in sorted(evidence.used)})


class Commands:
    def __init__(self, evidence):
        self.rows = {}
        self.outputs = {}
        finished = 0
        for i, row in enumerate(evidence.json("commands.json"), 1):
            label = row["label"]
            require(re.fullmatch(r"[A-Za-z0-9_.-]+", label) and label not in self.rows
                    and row["sequence"] == i, "invalid command sequence or label")
            require(type(row["started_ns"]) is int and type(row["finished_ns"]) is int
                    and finished < row["started_ns"] < row["finished_ns"]
                    and row["exit"] == 0, f"nonsequential or failed command: {label}")
            finished = row["finished_ns"]
            require(row["private_output"] is (label == "account-create"),
                    "unverified private command output")
            self.rows[label] = row
            streams = {}
            for stream in ("stdout", "stderr"):
                meta = row[stream]
                if row["private_output"]:
                    require(set(meta) == {"sha256", "bytes"}
                            and re.fullmatch(r"[0-9a-f]{64}", meta["sha256"])
                            and type(meta["bytes"]) is int and meta["bytes"] >= 0,
                            "invalid digest-only command evidence")
                else:
                    name = f"cmd-{i:04d}-{label}.{stream}"
                    equal(meta["path"], name, "command stream path mismatch")
                    streams[stream] = evidence.bind(name, {key: value for key, value in meta.items()
                                                           if key != "path"})
            self.outputs[label] = streams
        require(self.rows, "empty command evidence")

    def seq(self, label):
        return self.rows[label]["sequence"]

    def bytes(self, label, *argv, stream="stdout"):
        equal(self.rows[label]["argv"], list(argv), f"unexpected command: {label}")
        return self.outputs[label][stream]

    def obj(self, label, *argv):
        return load_bytes(self.bytes(label, *argv))

    def ordered(self, *labels):
        values = [self.seq(label) for label in labels]
        require(values == sorted(set(values)), f"command order changed: {labels}")


NETWORK_COMMANDS = {
    "links": ("ip", "-j", "-d", "link"),
    "addresses4": ("ip", "-j", "-4", "address"),
    "addresses6": ("ip", "-j", "-6", "address"),
    "routes4": ("ip", "-j", "-N", "-4", "route", "show", "table", "all"),
    "routes6": ("ip", "-j", "-N", "-6", "route", "show", "table", "all"),
    "rules4": ("ip", "-j", "-N", "-4", "rule"),
    "rules6": ("ip", "-j", "-N", "-6", "rule"),
    "nft": ("nft", "-j", "-a", "list", "ruleset"),
    "iptables": ("iptables", "-w", "-S"),
    "ip6tables": ("ip6tables", "-w", "-S"),
}


def network_snapshot(evidence, commands, label, value, host):
    equal(evidence.json(label + ".json"), value, f"{label} raw snapshot differs")
    equal(set(value), set(NETWORK_COMMANDS) | {"sysctl", "host_netns", "caller_netns", "owner"},
          f"{label} snapshot resource set differs")
    require(netns(value["host_netns"]) == netns(value["caller_netns"]) == host,
            "network snapshot not observed in guest host")
    for item, argv in NETWORK_COMMANDS.items():
        output = commands.bytes(label + "-" + item, *argv)
        parsed = output.decode("utf-8") if item in ("iptables", "ip6tables") else load_bytes(output)
        equal(value[item], parsed, f"{label} {item} did not match raw command")
    equal(set(value["sysctl"]), {"ping_group_range", "icmp_echo_ignore_all", "ip_forward"},
          "sysctl snapshot was incomplete")
    require(value["sysctl"]["icmp_echo_ignore_all"].strip() == "0",
            "host ignored ICMP Echo independently of this scenario")
    return value


def resources(snapshot, handles):
    value = copy.deepcopy(snapshot)
    for link in value["links"]:
        info = link.get("linkinfo", {})
        if info.get("info_kind") == "bridge":
            for timer in ("hello_timer", "tcn_timer", "topology_change_timer", "gc_timer"):
                info["info_data"].pop(timer, None)
    for route in value["routes6"]:
        if route.get("protocol") == "9" and "expires" in route:
            require(type(route["expires"]) is int and route["expires"] >= 0, "bad RA expiry")
            route["expires"] = 0
    for key in ("addresses4", "addresses6"):
        for device in value[key]:
            for item in device.get("addr_info", []):
                for lifetime in ("valid_life_time", "preferred_life_time"):
                    if lifetime in item:
                        require(type(item[lifetime]) is int and item[lifetime] >= 0,
                                "bad address lifetime")
                        item[lifetime] = 0
    for key in ("links", "routes6"):
        value[key] = Counter(json.dumps(stable(row), sort_keys=True) for row in value[key])
    return stable(value, handles)


def owner_evidence(value, host, boot, container):
    file_record(value["record"])
    raw = packet_bytes(value["content_hex"])
    equal(value["record"], {**record(raw), "mode": 0o600, "uid": 0, "gid": 0},
          "TUN ownership original bytes or permissions changed")
    owner = load_bytes(raw)
    require(owner["schema_version"] == 1 and owner["phase"] == "active"
            and owner["netns"] == host and owner["boot_id"] == boot
            and owner["cid"] == container["Id"] and owner["started_at"] == container["State"]["StartedAt"],
            "ownership did not bind active core, boot, and network namespace")
    require(re.fullmatch(r"[0-9a-f]{32}", owner["token"]) is not None
            and owner["owned"]["ifindex"] > 0, "invalid TUN owner identity")
    return owner


def native_evidence(evidence, commands, native):
    equal(evidence.json("native.json"), native, "native summary differs from artifact")
    for name, key, argv in [
        ("native-arch", "architecture", ("uname", "-m")),
        ("native-kernel", "kernel", ("uname", "-r")),
        ("native-virt", "virtualization", ("systemd-detect-virt", "--vm"))
    ]:
        equal(native[key], commands.bytes(name, *argv).decode().strip(), "native command mismatch")
    require(native["architecture"] == "x86_64" and native["pid1"] == "systemd"
            and native["virtualization"] == "kvm"
            and "microsoft" not in native["kernel"].lower()
            and re.fullmatch(r"[0-9a-f]{32}", native["machine_id"])
            and re.fullmatch(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", native["boot_id"]),
            "not a native full-kernel systemd amd64 guest")
    require(netns(native["pid1_netns"]) == netns(native["caller_netns"]),
            "driver did not start in the guest host netns")
    engine = commands.obj("native-engine", "docker", "info", "--format", "{{json .}}")
    equal(native["engine"], engine, "Docker Engine summary differs")
    require(engine["OSType"] == "linux" and engine["Architecture"] in {"x86_64", "amd64"}
            and "name=rootless" not in engine["SecurityOptions"]
            and engine["KernelVersion"] == native["kernel"] and engine["ID"],
            "engine is not the native rootful Linux Docker Engine")
    return native["pid1_netns"]


def release_evidence(evidence, commands, summary, formal):
    equal(evidence.json("release-binding.json"), summary, "release summary differs from artifact")
    require(summary["release"]["version"] == VERSION and summary["release"]["commit"] == COMMIT
            and summary["manifest_sha256"] == MANIFEST_SHA and summary["bundle_sha256"] == BUNDLE_SHA
            and summary["signature_sha256"] == SIGNATURE_SHA, "guest release digest not pinned")
    payload = dict(formal["payload"])
    payload[".padm-docker-bundle-ref"] = (COMMIT + "\n").encode()
    payload[".padm-docker-bundle-manifest"] = "".join(
        f"{sha(payload[name])}  {name}\n" for name in sorted(payload)).encode()
    equal(summary["bundle_files"], {
        name: {**record(content), "mode": 0o750 if name == "install-docker.sh" else 0o640,
               "uid": 0, "gid": 0} for name, content in payload.items()
    }, "installed formal bundle bytes/metadata mismatch")
    deployment = summary["deployment"]
    require(deployment["padm_version"] == VERSION and deployment["bundle_version"] == COMMIT
            and deployment["manifest"]["sha256"] == MANIFEST_SHA
            and deployment["manifest"]["signature_identity"] == SIGNER, "deployment identity mismatch")
    equal(set(summary["images"]), IMAGE_NAMES, "incomplete runtime image set")
    equal(deployment["images"], {name: {"index_digest": image["index_digest"]}
                                 for name, image in formal["images"].items()},
          "deployment did not bind all five image indices")
    for name, expected in formal["images"].items():
        row = summary["images"][name]
        ref = expected["reference"]
        repo = ref.split("@", 1)[0].rsplit(":", 1)[0]
        require(ref.endswith("@" + expected["index_digest"]), "image reference not pinned")
        platform_ref = repo + "@" + expected["platform_digest"]
        inspect, = commands.obj("image-inspect-" + name, "docker", "image", "inspect", ref)
        equal(row, {"reference": ref, "image": inspect, "index": expected["index"],
                    "platform": expected["platform"], "platform_manifest": expected["manifest"],
                    "platform_reference": platform_ref},
              f"{name} report/image inspect mismatch")
        require(inspect["Architecture"] == "amd64" and inspect["Os"] == "linux"
                and repo + "@" + expected["index_digest"] in inspect["RepoDigests"],
                f"{name} architecture or repo digest mismatch")
        accepted = {expected["config_digest"], expected["index_digest"], expected["platform_digest"]}
        require(inspect["Id"] in accepted, f"{name} is not the pinned runtime image")
        commands.bytes("formal-pull-" + name, "docker", "pull", ref)
    return len(formal["payload"])


def scenario_evidence(evidence, commands, mode, scenario, guest):
    host, boot = guest["native"]["pid1_netns"], guest["native"]["boot_id"]
    equal(evidence.json("mode-" + mode + ".json"), scenario, "scenario summary mismatch")
    require(scenario["passed"] is True, f"{mode} did not pass")
    labels = {name: mode + "-" + name for name in
              ("enable", "diagnose", "inspect", "core-status", "probe", "off", "off-status", "core-log")}
    order = [mode + "-baseline-links", labels["enable"], mode + "-diagnose-before-ip6tables",
             labels["diagnose"], mode + "-diagnose-after-links", labels["inspect"],
             labels["core-status"], labels["probe"], labels["core-log"], labels["off"],
             mode + "-off-down", mode + "-off-container-set",
             mode + "-after-off-ip6tables", labels["off-status"]]
    commands.ordered(*order)
    for name in ("enable", "diagnose", "probe", "off"):
        equal(scenario[name + "_command"], commands.seq(labels[name]), "reported sequence was not observed")
    confirm = ("--confirm", "PADM-DOCKER-EDIT")
    commands.bytes(labels["enable"], CLI, "edit", "--tun-enable", *confirm)
    commands.bytes(labels["off"], CLI, "edit", "--tun-off", *confirm)
    commands.bytes(mode + "-off-down", CLI, "down")
    equal(commands.bytes(mode + "-off-container-set", "docker", "ps", "-aq").strip(),
          b"", "containers remained after the official off/down")
    diagnosed = commands.obj(labels["diagnose"], CLI, "protocol", "tun-diagnose")
    equal(scenario["diagnosis"], diagnosed, "diagnosis did not match official CLI output")
    expected = dict(enabled=True, runtime="observed", family="ipv4", policy="direct", uid=0,
                    gid=0, net_raw_effective=False, netns=host, ping_group_allowed=mode != "denied",
                    ping_group_range=list(expected_range(mode)), socket_probe="not_tested",
                    echo_roundtrip="not_tested", capture="not_verified")
    for name, item in expected.items():
        current = diagnosed[name]
        require(type(current) is type(item) and current == item, f"{mode} diagnose: {name}")
    cid = diagnosed["container_id"]
    require(re.fullmatch(r"[0-9a-f]{64}", cid), "bad diagnosed core container ID")
    container, = commands.obj(labels["inspect"], "docker", "inspect", cid)
    equal(scenario["container"], container, "actual running container mismatch")
    image = guest["release"]["images"]["sing-box"]
    require(container["Id"] == cid and container["State"]["Running"] is True
            and container["HostConfig"]["NetworkMode"] == "host"
            and container["Config"]["Image"] == image["reference"]
            and container["Image"] == image["image"]["Id"],
            "core is not the formal running host-network container")
    raw_status = commands.bytes(labels["core-status"], "docker", "exec", "--env", "LD_PRELOAD=",
                                cid, "sh", "-ec",
                                'cat /proc/1/status; printf "\\nNetNS: "; readlink /proc/1/ns/net')
    equal(scenario["core_status"], raw_status.decode(), "core /proc status was not original")
    status = linux_status(scenario["core_status"])
    require(status["uid"][1] == status["gid"][1] == 0
            and 10001 not in status["groups"] and status["capeff"] & (1 << 13) == 0
            and netns(re.search(r"^NetNS:\s*(\S+)$", scenario["core_status"], re.M)[1]) == host,
            "core privileges or host namespace differ from experiment")
    require(status["groups"] == diagnosed["groups"]
            and status["capeff"] == int(diagnosed["cap_effective"], 16)
            and re.search(r"^Pid:\s*(\d+)$", scenario["core_status"], re.M)[1] == str(diagnosed["pid"]),
            "CLI did not diagnose the actual observed process")
    equal(any(expected_range(mode)[0] <= group <= expected_range(mode)[1]
              for group in [status["gid"][1], *status["groups"]]), diagnosed["ping_group_allowed"],
          "diagnosed group permission did not follow process identity")
    for name in ("baseline", "diagnose_before", "diagnose_after", "after_off"):
        network_snapshot(evidence, commands, f"{mode}-{name.replace('_', '-')}", scenario[name], host)
        equal(ping_range(scenario[name]["sysctl"]["ping_group_range"]), expected_range(mode),
              f"{mode} raw sysctl mismatch at {name}")
    before, after = scenario["diagnose_before"], scenario["diagnose_after"]
    equal(before["owner"], after["owner"], "diagnosis changed TUN ownership bytes")
    owner = owner_evidence(before["owner"], host, boot, container)
    tun, = [link for link in before["links"] if link["ifname"] == "padm-tun"]
    equal(tun["ifindex"], owner["owned"]["ifindex"], "owned TUN interface differs")
    equal(resources(before, True), resources(after, True), "diagnosis changed network resources")
    baseline, off = scenario["baseline"], scenario["after_off"]
    require(baseline["owner"] is None and off["owner"] is None, "ownership survives disabled TUN")
    require(any(row.get("dst") == "default" and row.get("gateway") == "192.0.2.2"
                and row.get("dev") == "icmp-uplink" for row in baseline["routes4"]),
            "target default route missing before enabling TUN")
    equal(resources(baseline, False), resources(off, False), "off did not restore network resources")
    for point in (baseline, off):
        require("padm-tun" not in {link["ifname"] for link in point["links"]}, "TUN survives off")
    equal(ping_range(scenario["ping_group_range"]), expected_range(mode), "mode range mismatch")
    probe = commands.obj(labels["probe"], "python3", "-B", f"{GUEST_INPUT}/probe-native-icmp.py", mode)
    equal(scenario["probe"], probe, "probe bytes did not match scenario")
    counts = probe_evidence(probe, mode, host)
    if mode == "filtered":
        label = mode + "-target-filter"
        observed = commands.obj(label, *TARGET_NS, "nft", "-j", "-a", "list", "table", "inet", "icmp_target")
        equal(scenario["target_filter"], observed, "target drop table did not match raw output")
        commands.ordered("filter-table", "filter-chain", "filter-rule", labels["enable"],
                         labels["probe"], label, labels["off"], "filter-remove")
        filter_evidence(observed)
    traffic_before = network_snapshot(evidence, commands, mode + "-traffic-before",
                                      scenario["traffic_before"], host)
    traffic_after = network_snapshot(evidence, commands, mode + "-traffic-after",
                                     scenario["traffic_after"], host)
    require(traffic_before["nft"] != traffic_after["nft"], "nft raw counters did not change with traffic")
    equal(traffic_before["owner"], before["owner"], "ownership drift before traffic")
    equal(resources(traffic_before, True), resources(traffic_after, True),
          "traffic changed live resource ownership/configuration")
    commands.ordered(mode + "-traffic-before-ip6tables", labels["probe"],
                     mode + "-traffic-after-links", labels["off"])
    logs = [commands.bytes(labels["core-log"], "docker", "logs", cid, stream=stream)
            for stream in ("stdout", "stderr")]
    permission = any(re.search(rb"permission denied|operation not permitted", log, re.I) for log in logs)
    require(scenario["permission_error_observed"] is permission, "permission log result mismatch")
    require(mode != "denied" or permission, "denied Echo lacks a core permission error")
    off_status = commands.obj(labels["off-status"], CLI, "protocol", "tun-status")
    require(off_status["enabled"] is False, "official tun-status not disabled")
    equal(scenario["off_status"], off_status, "off status did not match CLI")
    preserved_material(scenario["materials_before"], scenario["materials_after"])
    return {"nonce": probe["nonce"], "counts": counts, "permission_error_observed": permission}


def guest_evidence(evidence, formal):
    guest = evidence.json("guest-result.json")
    require(guest["schema"] == 1 and guest["scope"] == SCOPE and guest["passed"] is True
            and guest["scenarios_passed"] is True and guest["cleanup"]["passed"] is True
            and guest["transparent_enabled_reboot"] is False and guest["production_access"] is False,
            "guest did not complete the declared isolated scope")
    commands = Commands(evidence)
    host = native_evidence(evidence, commands, guest["native"])
    payload_count = release_evidence(evidence, commands, guest["release"], formal)
    initial_scope = evidence.json("initial-scope.json")
    equal(initial_scope, {"engine_absent": True, "padm_absent": True},
          "guest was not pristine before official install")
    equal(commands.bytes("initial-engine", "systemctl", "show", "docker.service", "-p", "LoadState").strip(),
          b"LoadState=not-found", "an Engine already existed before installation")
    equal(commands.bytes("initial-containers", "docker", "ps", "-a",
                         "--format", "{{json .}}").strip(), b"", "unexpected initial Docker containers")
    args = ("--manifest", f"{GUEST_INPUT}/assets/release-manifest.json",
            "--bundle", f"{GUEST_INPUT}/assets/release-manifest.sigstore.json",
            "--control-bundle", f"{GUEST_INPUT}/assets/padm-docker-bundle.tar.gz")
    xray = guest["release"]["images"]["xray"]["reference"]
    commands.bytes("egress-xray-pull", "docker", "pull", xray)
    negative = commands.bytes("guest-egress-negative", "bash", "-ec", NEGATIVE_SCRIPT, "bash", xray)
    require(b"Handshake succeeded" not in negative
            and re.search(rb"\nPROBE_RC=(0|1|124)\n$", negative), "TEST-NET succeeded or failed to run")
    jq_version = commands.bytes("distro-jq-version", "/usr/bin/jq", "--version").decode().strip()
    require(jq_version in ("jq-1.7", "jq-1.7.1"), "not the distro jq 1.7")
    equal(commands.bytes("distro-jq-owner", "dpkg-query", "-S", "/usr/bin/jq").strip(),
          b"jq: /usr/bin/jq", "jq is not the distro package")
    equal(commands.bytes("distro-jq-verify", "dpkg", "--verify", "jq").strip(), b"",
          "distro jq was modified")
    equal(guest["distro_jq"], {"version": jq_version, "path": "/usr/bin/jq", "package_verified": True},
          "distro jq witness mismatch")
    commands.bytes("install-cosign", "install", "-m", "0755", f"{GUEST_INPUT}/cosign", "/usr/local/bin/cosign")
    commands.bytes("verify-signature", "cosign", "verify-blob", "--bundle", args[3],
                   "--certificate-identity", SIGNER, "--certificate-oidc-issuer", ISSUER, args[1])
    source = GUEST_INPUT + "/source"
    commands.bytes("extract-bundle", "tar", "-xzf", args[5], "-C", source)
    commands.bytes("formal-install", "bash", "-ec",
                   f"printf 'y\\n' | bash {source}/install-docker.sh install --source {source} --ref {COMMIT} --no-menu")
    commands.bytes("formal-configure", CLI, "configure", "--spec", f"{GUEST_INPUT}/spec.json", *args)
    equal(evidence.json("protocol-baseline.json"), {
        "type": "sing-box", "secondary_type": None, "protocols": [
            {"id": 1, "listener_id": "entry-icmp", "address_families": ["ipv4"], "target": "b.951101.xyz"}],
    }, "not the supported IPv4 single-entry REALITY topology")
    equal(commands.rows["account-create"]["argv"],
          [CLI, "account", "create", "--name", "native-icmp", "--listeners", "entry-icmp"],
          "account creation command mismatch")
    require(commands.rows["account-create"]["stdout"]["bytes"] > 0, "missing private account witness")
    target = evidence.json("target-ready.json")
    equal(guest["target"], target, "target startup evidence differs")
    require(netns(target["netns"]) != host and netns(target["pid1_netns"]) == host
            and target["target"] == TARGET and target["port"] == 35991 and target["pid"] > 1,
            "target is not an independent namespace in the same full kernel")
    equal(guest["target_argv"], [*TARGET_NS, "python3", "-B", f"{GUEST_INPUT}/probe-native-icmp.py",
                               "serve", "/root/padm-icmp-evidence/target-ready.json"],
          "target server command differs")
    commands.bytes("target-netns", "ip", "netns", "add", "padm-icmp-target")
    commands.bytes("host-target-route", "ip", "route", "add", TARGET + "/32",
                   "via", "192.0.2.2", "dev", "icmp-uplink")
    commands.bytes("host-target-default", "ip", "route", "add", "default",
                   "via", "192.0.2.2", "dev", "icmp-uplink")
    commands.bytes("cleanup-veth", "ip", "link", "delete", "icmp-uplink")
    commands.bytes("cleanup-netns", "ip", "netns", "delete", "padm-icmp-target")
    validation_ip = commands.rows["validation-wan"]["argv"][-1]
    require(ipaddress.IPv4Address(validation_ip).is_global, "validation destination not public IPv4")
    route, = commands.obj("validation-wan", "ip", "-j", "-4", "route", "get", validation_ip)
    require(route["dev"] == "wan" and route["dst"] == validation_ip, "validation route not using WAN")
    path = (validation_ip + "/32", "via", route["gateway"], "dev", "wan")
    commands.bytes("host-validation-route", "ip", "route", "add", *path)
    commands.bytes("cleanup-validation-route", "ip", "route", "delete", *path)
    commands.bytes("baseline-down", CLI, "down")
    equal(commands.bytes("baseline-container-set", "docker", "ps", "-aq").strip(), b"",
          "containers existed at the stopped baseline")
    for index, prefix in enumerate(("0.0.0.0/1", "128.0.0.0/1")):
        commands.bytes("control-plane-route-" + str(index), "ip", "route", "add", prefix,
                       "via", route["gateway"], "dev", "wan")
        commands.bytes("cleanup-control-plane-route-" + str(index), "ip", "route", "delete", prefix,
                       "via", route["gateway"], "dev", "wan")
    evidence.read("target-server.log")
    initial = network_snapshot(evidence, commands, "initial-network", guest["initial_network"], host)
    final = network_snapshot(evidence, commands, "final-network", guest["final_network"], host)
    require(initial["owner"] is None and final["owner"] is None, "owner exists outside experiment")
    equal(resources(initial, False), resources(final, False), "network not restored to initial baseline")
    equal(initial["sysctl"], final["sysctl"], "original sysctls not restored")
    for point in (initial, final):
        require(not {"padm-tun", "icmp-uplink", "icmp-peer"}.intersection(
            link["ifname"] for link in point["links"]), "experiment interface survives final cleanup")
        require(not any(r.get("dst") in (TARGET, TARGET + "/32") or r.get("dev") == "icmp-uplink"
                        for r in point["routes4"]), "experiment route survives final cleanup")
    require(guest["cleanup"]["target_exit"] in (-15, 0), "unexpected target cleanup exit")
    equal(set(guest["scenarios"]), set(MODES), "incomplete scenario set")
    results = {mode: scenario_evidence(evidence, commands, mode, guest["scenarios"][mode], guest)
               for mode in MODES}
    require(len({row["nonce"] for row in results.values()}) == 3, "cross-scenario nonce reuse")
    ordering = ["initial-engine", "install-cosign",
                "verify-signature", "extract-bundle", "formal-install",
                "distro-jq-version", "distro-jq-owner", "distro-jq-verify",
                "native-arch", "native-engine", "initial-containers",
                "egress-xray-pull", "guest-egress-negative", "formal-configure",
                "account-create", "account-limit", "baseline-down", "baseline-container-set",
                "initial-network-ip6tables", "validation-wan", "host-validation-route",
                "control-plane-route-0", "control-plane-route-1",
                "target-netns", "host-target-route", "host-target-default"]
    for mode in MODES:
        ordering += [mode + "-baseline-links", mode + "-off-status"]
    commands.ordered(*ordering, "cleanup-veth", "cleanup-netns", "cleanup-validation-route",
                     "cleanup-control-plane-route-0", "cleanup-control-plane-route-1", "final-network-links")
    material = guest["initial_material"]
    for mode in MODES:
        for stage in ("materials_before", "materials_after"):
            subsequent = guest["scenarios"][mode][stage]
            preserved_material(material, subsequent)
            material = subsequent
    account_id = preserved_material(material, guest["final_material"])
    commands.bytes("account-limit", CLI, "traffic", "limit", account_id, "1")
    return {"cases": results, "guest_kernel": guest["native"]["kernel"],
            "payload_count": payload_count, "guest_commands": len(commands.rows),
            "boot_id": guest["native"]["boot_id"]}, guest


def rejects(label, operation, expected=None):
    try:
        operation()
    except (AssertionError, ValueError, UnicodeError, KeyError, TypeError) as error:
        require(expected is None or expected in str(error), f"{label}: rejected for wrong reason: {error}")
        return label
    raise AssertionError(f"negative control accepted: {label}")


def semantic_controls(archive, formal):
    def encode(value):
        return (json.dumps(value, sort_keys=True) + "\n").encode()

    def rejected(label, changer, expected):
        mutated = copy.copy(archive)
        mutated.files, mutated.used = dict(archive.files), set()
        guest = mutated.json("guest-result.json")
        commands = mutated.json("commands.json")

        def command_bytes(name, raw, stream="stdout"):
            row, = [row for row in commands if row["label"] == name]
            path = row[stream]["path"]
            mutated.files[path] = raw
            row[stream] = {"path": path, **record(raw)}

        changer(guest, command_bytes, commands)
        for mode, scenario in guest["scenarios"].items():
            mutated.files[f"mode-{mode}.json"] = encode(scenario)
        mutated.files["guest-result.json"] = encode(guest)
        mutated.files["commands.json"] = encode(commands)
        return rejects(label, lambda: guest_evidence(mutated, formal), expected)

    def probe_field(mode, path, changed):
        def mutate(guest, command_bytes, _):
            probe = guest["scenarios"][mode]["probe"]
            row = probe
            for key in path[:-1]:
                row = row[key]
            row[path[-1]] = changed(row[path[-1]])
            command_bytes(mode + "-probe", encode(probe))
        return mutate

    def diagnose_filtered(guest, command_bytes, _):
        diagnosis = guest["scenarios"]["filtered"]["diagnosis"]
        diagnosis["capture"] = "verified"
        command_bytes("filtered-diagnose", encode(diagnosis))

    def bad_filter(guest, command_bytes, _):
        value = guest["scenarios"]["filtered"]["target_filter"]
        for row in value["nftables"]:
            for expr in row.get("rule", {}).get("expr", []):
                if "counter" in expr:
                    expr["counter"]["packets"] = 0
        command_bytes("filtered-target-filter", encode(value))

    def no_core_permission(guest, command_bytes, _):
        guest["scenarios"]["denied"]["permission_error_observed"] = False
        for stream in ("stdout", "stderr"):
            command_bytes("denied-core-log", b"", stream)

    def quota(guest, _, __):
        before = guest["scenarios"]["denied"]["materials_after"]
        account = before["accounts"][0]["id"]
        before["ledger"]["accounts"][account]["limit_bytes"] += 1

    def owner(guest, _, __):
        guest["scenarios"]["direct"]["diagnose_after"]["owner"]["record"]["bytes"] += 1

    def cli_order(_, __, commands):
        row, = [row for row in commands if row["label"] == "direct-enable"]
        row["argv"][2] = "--tun-off"

    return [
        rejected("probe-netns-substitution", probe_field("direct", ["caller_netns"], lambda _: "net:[1]"),
                 "probe did not run in guest host netns"),
        rejected("denied-probe-group", probe_field("denied", ["gid"], lambda _: 0),
                 "probe group qualification mismatch"),
        rejected("direct-missing-wire-request", probe_field("direct", ["captures"],
                 lambda items: [row for row in items if (row["interface"], row["type"]) != ("icmp-uplink", 8)]),
                 "incorrect observed wire or ping counts"),
        rejected("fake-observed-counts", probe_field("filtered", ["counts", "wire_requests"], lambda _: 2),
                 "reported counts did not match raw capture"),
        rejected("altered-tcp-payload", probe_field("denied", ["tcp", "received_hex"], lambda _: "00"),
                 "tcp did not return the exact nonce"),
        rejected("altered-udp-peer", probe_field("filtered", ["udp", "peer"], lambda _: [TARGET, 35992]),
                 "udp peer did not match target"),
        rejected("diagnose-overclaim", diagnose_filtered, "filtered diagnose: capture"),
        rejected("drop-counter-zero", bad_filter, "target drop did not count exactly one"),
        rejected("denied-no-core-permission-log", no_core_permission, "denied Echo lacks a core permission error"),
        rejected("off-changed-quota", quota, "ledger identity changed: limit_bytes"),
        rejected("owner-evidence-mirror", owner, "raw snapshot differs"),
        rejected("changed-formal-enable-command", cli_order, "unexpected command: direct-enable"),
    ]


def host_evidence(evidence, sources, report, archive):
    require(report["passed"] is True and report["functional_passed"] is True
            and report["guest_exit"] == report["archive_exit"] == report["poweroff_exit"]
            == report["qemu_exit"] == 0 and report["forced"] is False,
            "guest or normal poweroff failed")
    equal(report["archive_sha256"], sha(archive), "guest evidence archive changed")
    require(report["accelerator"] == "kvm" and report["outer_kernel"],
            "KVM or outer kernel evidence is missing")
    require(re.fullmatch(r"[0-9a-f]{64}", report["base_sha256"])
            and report["base_final_sha256"] == report["base_sha256"]
            and report["base_sha512"] == BASE_SHA512, "parent disk hash changed")
    for name in ("guest-native-icmp.py", "probe-native-icmp.py", "run-native-icmp.py"):
        equal(report["drivers"][name], sha(sources.read(name)), f"frozen driver changed: {name}")
    equal(set(report["drivers"]), {"guest-native-icmp.py", "probe-native-icmp.py", "run-native-icmp.py"},
          "driver set changed")
    launch, disk = evidence.json("qemu.json"), evidence.json("disk.json")
    require(isinstance(launch, list) and launch[0] == "qemu-system-x86_64"
            and launch.count("-accel") == launch.count("-cpu") == launch.count("-drive") == 1
            and launch[launch.index("-accel") + 1] == "kvm"
            and launch[launch.index("-cpu") + 1] == "host" and "-no-reboot" in launch,
            "unexpected guest accelerator, CPU, disk or reboot policy")
    child, parent = disk
    equal(launch[launch.index("-drive") + 1], f"file={child['filename']},if=virtio,format=qcow2",
          "running disk is not the experiment overlay")
    require(child["format"] == parent["format"] == "qcow2"
            and child["full-backing-filename"] == parent["filename"] == report["base"]
            and child["filename"] != parent["filename"]
            and child["filename"].endswith("/guest.qcow2")
            and report["base"].endswith("/debian-13-genericcloud-amd64-20261111-2659.qcow2"),
            "wrong qcow2 backing chain")
    console = evidence.read("console.log")
    require(b"reboot: Power down" in console and b"systemd-shutdown" in console,
            "guest console did not show clean kernel poweroff")
    evidence.read("poweroff.stdout")
    evidence.read("poweroff.stderr")
    return dict(outer_kernel=report["outer_kernel"], parent_sha256=report["base_sha256"],
                console_sha256=sha(console), shutdown_verified=True)


def verify(root, sources=None):
    evidence = Evidence(root)
    sources = Evidence(sources or root)
    formal = release_assets(sources.root / "assets")
    report = evidence.json("host-result.json")
    content = evidence.read("guest-evidence.stdout")
    result = host_evidence(evidence, sources, report, content)
    archive = Archive(content)
    guest_result, guest = guest_evidence(archive, formal)
    equal(archive.used, set(archive.files), "unbound or unrecognized guest archive file")
    require(guest_result["guest_kernel"] != result["outer_kernel"], "guest and outer kernel are not distinct")
    return dict(passed=True, scope=SCOPE, release=VERSION, source=COMMIT,
                guest_artifacts=len(archive.files), assets=len(formal["assets"]),
                host_artifacts={name: record(content if name == "guest-evidence.stdout" else evidence.read(name))
                                for name in sorted(evidence.used)},
                **result, **guest_result, component_negative_controls=self_check(),
                semantic_negative_controls=semantic_controls(archive, formal))


def self_check():
    def rejected(label, operation):
        return rejects(label, operation)

    nonce = b"padm-tun-icmp-" + b"f" * 32
    body = struct.pack("!BBHHH", 8, 0, 0, 7, 1) + nonce
    body = body[:2] + struct.pack("!H", checksum(body)) + body[4:]
    header = bytearray(struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(body),
                                  1, 0x4000, 64, 1, 0,
                                  ipaddress.IPv4Address("192.0.2.1").packed,
                                  ipaddress.IPv4Address(TARGET).packed))
    header[10:12] = struct.pack("!H", checksum(header))
    packet = bytes(header) + body
    require(ipv4_icmp(packet, nonce, 8)["sequence"] == 1, "packet positive control")
    controls = [
        rejected("duplicate-json", lambda: load_bytes(b'{"a":1,"a":2}')),
        rejected("nonfinite-json", lambda: load_bytes(b'{"a":NaN}')),
        rejected("json-exponent-overflow", lambda: load_bytes(b'{"a":1e999}')),
        rejected("parent-path", lambda: safe_name("../x")),
        rejected("absolute-path", lambda: safe_name("/x")),
        rejected("windows-path", lambda: safe_name("C:/x")),
        rejected("backslash-path", lambda: safe_name("a\\x")),
        rejected("nonce", lambda: ipv4_icmp(packet, b"other", 8)),
        rejected("icmp-checksum", lambda: ipv4_icmp(packet[:-1] + b"0", nonce, 8)),
        rejected("ip-checksum", lambda: ipv4_icmp(bytes([0x46]) + packet[1:], nonce, 8)),
        rejected("truncated", lambda: ipv4_icmp(packet[:-1], nonce, 8)),
        rejected("wrong-type", lambda: ipv4_icmp(packet, nonce, 0)),
        rejected("namespace", lambda: netns("host")),
        rejected("ledger-decrease", lambda: at_least({"used": 1}, {"used": 2})),
        rejected("ledger-identity", lambda: at_least({"name": "b"}, {"name": "a"})),
        rejected("quota-increase", lambda: at_least({"limit_bytes": 2}, {"limit_bytes": 1})),
        rejected("counter-decrease", lambda: at_least({"upload": 1}, {"upload": 2})),
    ]
    fragment = bytearray(packet)
    fragment[6:8] = b"\x20\0"
    fragment[10:12] = b"\0\0"
    fragment[10:12] = struct.pack("!H", checksum(fragment[:20]))
    controls.append(rejected("fragment", lambda: ipv4_icmp(bytes(fragment), nonce, 8)))
    return controls


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", type=Path)
    parser.add_argument("--sources", type=Path)
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        result = {"passed": True, "component_negative_controls": self_check()}
    else:
        require(args.root is not None, "evidence root is required")
        result = verify(args.root, args.sources)
    print(json.dumps(result, indent=2, sort_keys=True))
