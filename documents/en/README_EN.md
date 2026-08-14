<h1 align="center">padm</h1>

<p align="center"><strong>✨ One workflow for Xray-core / sing-box installation and long-term operations</strong></p>
<p align="center">🚀 Node setup · 🔗 Subscription publishing · 🌐 Multi-server coordination · 🧭 Routing · 🔐 Certificates · ⚙️ Core upgrades</p>
<p align="center"><a href="../../README.md">🌍 中文</a></p>

<p align="center">
  <a href="#quick-choice">🚀 Quick choice</a> ·
  <a href="#installation">📦 Installation</a> ·
  <a href="#protocol-selection">🧭 Protocols</a> ·
  <a href="#subscriptions-and-users">🔗 Subscriptions</a>
  <br>
  <a href="#routing-and-access-control">🧱 Routing</a> ·
  <a href="#cores-and-services">⚙️ Core services</a> ·
  <a href="#flag-reference">📋 Flags</a> ·
  <a href="#validation-and-regression">✅ Validation</a>
</p>

---

> **✨ Pick a protocol in one glance**
>
> 🧭 Direct/own domain `Reality Vision` · 🌐 CDN/reverse proxy `Reality XHTTP`
>
> 📍 No domain `Reality` · 🛡️ TLS fingerprint resistance `NaiveProxy`

## Quick Choice

For first-time use, you do not need to understand every protocol up front. Run the script and follow this path:

| Scenario | Menu entry | Notes |
| --- | --- | --- |
| 🧭 Not sure what to choose | `Install & reinstall` -> `Recommended direct Reality Vision` | Best default for new users; fewer moving parts, suitable for direct or own-domain entry. |
| 🌐 CDN / reverse proxy required | `Install & reinstall` -> `Recommended CDN Reality XHTTP` | Preferred for new CDN deployments; uses XHTTP and XMUX. |
| 📍 No domain | `Install & reinstall` -> `No-domain Reality` | Uses the server IP or a custom entry host; no local certificate is required. |
| 🛡️ Need TLS fingerprint resistance | `Install & reinstall` -> `TLS fingerprint resistance NaiveProxy` | Requires a real domain and trusted certificate; not a replacement for no-domain Reality. |
| 🧰 Legacy clients or migration | `Install & reinstall` -> `Traditional TLS compatibility install` | Use only when WS/TLS, VMess, Trojan, or similar legacy shapes are explicitly needed. |
| 🔗 Get subscriptions after installation | `Subscriptions & users` | If uninitialized, choose local-only use, controller mode, or controlled mode. |

> [!TIP]
> **First run:** Follow the recommended paths above. Open custom protocol combinations, CDN entry tuning, multi-server synchronization, or dangerous experiments only when the client, network, and maintenance goal require them.

## Installation

### Interactive Installation

```bash
wget -O /root/install.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

On first run, if the entry script detects missing `shell/`, `documents/`, `assets/`, or a module manifest mismatch, it downloads the full repository archive and restores the module bundle.

Force a module refresh if you suspect the local modules are stale:

```bash
wget -O /root/install.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh" && chmod 700 /root/install.sh && PADM_FORCE_SCRIPT_MODULE_REFRESH=1 /root/install.sh
```

Open the management panel again after installation:

```bash
padm
```

### Non-Interactive Installation

Show the currently supported flags and examples:

```bash
bash install.sh --help
```

Recommended direct Reality Vision:

```bash
bash install.sh --install-type custom --core xray --protocols 1 --entry-host node.example.com --reality-target www.ibm.com:443 --reality-server-name www.ibm.com --reuse-last no
```

Recommended CDN Reality XHTTP:

```bash
bash install.sh --install-type custom --core xray --protocols 2 --entry-host cdn.example.com --reality-target www.ibm.com:443 --reality-server-name www.ibm.com --reuse-last no
```

No-domain Reality:

```bash
bash install.sh --install-type reality --core xray --reality-target www.ibm.com:443 --reuse-last no --clean-acme no
```

NaiveProxy:

```bash
bash install.sh --install-type custom --core sing-box --protocols 5 --domain naive.example.com --port 443 --reuse-last no
```

Multiple protocols can be comma-separated, for example `--protocols 1,2,21`. The current public IDs are the only install inputs; the old `0..13/20` numbering is deprecated, so existing old setups should be reselected with current public IDs before reinstalling or adjusting.

Traditional TLS compatibility install with Cloudflare DNS-01 automation:

```bash
bash install.sh --install-type install --core xray --domain example.com --port 443 --tls-ca letsencrypt --dns-api yes --dns-api-type cloudflare --dns-api-wildcard yes --cloudflare-api-token <token> --cloudflare-zone-id <zone_id> --reuse-last no
```

Use a Cloudflare API token restricted to the target zone with at least `Zone:DNS:Edit`. To avoid writing the token into shell history, use environment variables:

```bash
PADM_CLOUDFLARE_API_TOKEN=<token> PADM_CLOUDFLARE_ZONE_ID=<zone_id> bash install.sh --install-type install --core xray --domain example.com --dns-api yes --dns-api-type cloudflare
```

Install or refresh only the HTTPS subscription publishing service for an existing node:

```bash
bash install.sh InstallSubscription --domain subscribe.example.com --subscribe-port 39778 --install-nginx yes
```

Subscription publishing manages its own TLS domain and certificate; it never implicitly uses the Reality entry or the traditional TLS domain. A matching usable certificate is reused. If no certificate exists, pass the same `--tls-ca`, `--dns-api`, and provider credential options shown above to issue one. Custom certificates can be reused but must be renewed externally.

## System Requirements

padm is designed for Linux servers. The code detects Debian, Ubuntu, RHEL/CentOS/AlmaLinux/Rocky/Oracle Linux, Fedora, and Alpine, then uses `apt`, `yum`, or `apk` as appropriate.

| Item | Requirement |
| --- | --- |
| Permission | root or equivalent privileges. |
| Architecture | `x86_64/amd64`, `aarch64/arm64`. |
| Basic commands | Entry download needs at least `curl` or `wget`; full bundle refresh needs `tar`. |
| Common dependencies | The script installs or uses `jq`, `nginx`, `acme.sh`, WireGuard tools, Fail2ban, and related tools as features require. |
| Service management | Core services prefer systemd; Alpine/OpenRC paths are handled separately. The controller/controlled subscription control service currently requires systemd and `python3`. |

> [!IMPORTANT]
> **CentOS / RHEL:** If SELinux is Enforcing, the script asks you to disable it manually before continuing.

## Main Menu

padm groups the main menu by task object. Each feature has one primary home:

| Menu | Responsibility |
| --- | --- |
| 🚀 Install & reinstall | New-user guidance; recommended direct, recommended CDN, no-domain Reality, NaiveProxy, custom install, and traditional TLS compatibility install. |
| 🔗 Subscriptions & users | Use the host locally or initialize a controller/controlled role, then handle subscription publishing, multi-server coordination, quota, sync, and backups. |
| 🧭 Protocols & entry | REALITY, XHTTP, Hysteria2, Tuic, entry ports, and CDN entry addresses. |
| 🔐 Sites & certificates | Traditional TLS fallback sites, 302 redirects, ALPN diagnostics/repair, and local TLS certificates. |
| 🧱 Routing & access control | WARP, IPv6, Socks5, DNS/hosts, BT blocking, domain/IP blocking, direct exceptions, and regional blocking. |
| ⚙️ Cores & services | Xray-core / sing-box lifecycles, service state, log diagnostics, and Xray Geo data; the home view reads local state only. |
| 🧰 System & script | Update padm, inspect script installation state, manage Fail2ban protection, and network optimization / BBR. |
| ⚠️ Advanced / dangerous operations | Uninstall and high-risk experimental switches such as VLESS Encryption. |

## Runtime Model

padm is not one giant Bash file. It is a self-refreshing entry script plus a modular runtime:

1. `install.sh` is the only entrypoint. It parses arguments, handles formal subcommands, checks module integrity, and downloads the full repository archive when needed.
2. Module refresh atomically replaces `shell/`, `documents/`, `assets/`, `README.md`, and `.padm-module-manifest`; on failure it tries to restore the previous module bundle.
3. `shell/core/bootstrap.sh` assembles the runtime by loading platform, runtime, protocol, Reality, service, routing, TLS, subscription, and menu modules.
4. The interactive menu and formal subcommands share the same module set. Formal subcommands include `RenewTLS`, `UpdateGeo`, `SyncSubscriptionGroups`, `SubscriptionControl`, and `InstallSubscription`.
5. For troubleshooting, identify the real control point first: entry script, module load order, state file, generated config, and validation command, not just menu copy.

| Path | Purpose |
| --- | --- |
| `install.sh` | 🚪 Repository entry script; handles self-refresh, argument parsing, formal subcommands, and first-run module bootstrap. |
| `shell/core/` | ⚙️ Platform detection, runtime helpers, protocol templates, Reality/TLS/routing/service/menu logic. |
| `shell/subscription/` | 🔗 Subscription publishing, subscription-group state, user accounts, WireGuard control plane, remote sync, and traffic accounting. |
| `shell/regression/` | 🧪 Selector-based suites, framework helpers, and contract / composition regressions. |
| `shell/subscription_groups_regression.sh` | 🧪 The single public regression dispatcher for suite, aggregate, contract, and composition selectors. |
| `shell/validate_install.sh` | ✅ Read-only post-install validation script. |
| `documents/` | 📚 Example configuration and the English README. |
| `assets/` | 🖼️ Traditional TLS fallback static-site templates. |

## Post-Install Control Points

These paths are the actual state sources padm reads, writes, and validates. Start here for troubleshooting, backups, migration, or code reading:

| Path | Purpose |
| --- | --- |
| `/etc/padm/install.sh` | 🚪 Installed entry script; the `padm` command ultimately returns here. |
| `/etc/padm/.padm-ref` | 🏷️ Installed module ref, used by script refresh status views. |
| `/etc/padm/.padm-module-manifest` | 🧾 Installed module manifest, used to detect whether the module bundle is complete. |
| `/etc/padm/xray/conf/` | 🧩 Xray fragment config directory; validated with `xray -test -confdir`. |
| `/etc/padm/sing-box/conf/config/` | 🧩 sing-box fragment config directory; merged into `config.json` before validation. |
| `/etc/padm/tls/` | 🔐 Local TLS certificates, keys, and acme logs. |
| `/etc/padm/subscribe/` | 🔗 Client-facing published subscription artifacts. |
| `/etc/padm/subscribe_local/` | 📦 Local subscription cache and intermediate artifacts. |
| `/etc/padm/subscribe_groups/groups.json` | 🧭 Source of truth for subscription roles, server sources, users, quotas, sync, and traffic accounting. |
| `/etc/padm/subscribe_groups/backups/` | 💾 Backup directory for `groups.json`. |
| `/etc/padm/wireguard/` | 🔒 Controller/controlled WireGuard control-plane state, keys, and peer metadata. |
| `/etc/wireguard/wg-padm.conf` | 🔒 padm control-plane WireGuard config. |
| `/etc/padm/reality_entry_host` | 📍 Current Reality client entry address. |
| `/etc/padm/reality_targets_results.tsv` | 📊 Unified Reality target measurement result table. |

Public subscriptions and server-to-server control use different address families:

- 🌍 Client subscriptions use HTTPS paths such as `/s/default/...`, `/s/clashMeta/...`, and `/s/sing-box...`.
- 🔒 Controller/controlled control APIs use `/s/control/...` only inside the WireGuard private network; there is no public HTTP/HTTPS source fallback.

## Protocol Selection

Choose protocols by goal, not by the number of features they appear to expose:

| Goal | Recommended protocol | Notes |
| --- | --- | --- |
| New direct setup, own domain, or personal use | `1` VLESS Reality Vision | Current default recommendation; does not depend on a local fallback website. |
| CDN / reverse proxy | `2` VLESS Reality XHTTP | Preferred for new CDN nodes; uses XHTTP and XMUX. In this project XHTTP is Xray-only, and sing-box currently has no XHTTP transport. |
| No domain | no-domain Reality | The menu uses the Reality fast path. |
| TLS fingerprint resistance | `5` NaiveProxy | Requires a real domain and certificate; depends on sing-box. |
| UDP, mobile, or lossy network | `3` Hysteria2 | Hysteria2 node traffic does not go through CDN/Nginx; reachable UDP is required, and port hopping can be enabled when needed. |
| Explicit AnyTLS need | `4` AnyTLS | Use only after confirming client support. |
| Compatibility or migration | Advanced protocols `21..31` | Use only for legacy clients, existing CDN setups, traditional TLS, or migration windows. |

The capability registry is the single source of truth for protocol selection, core support, Nginx topology, and subscription output. Only public IDs with `category=node` are accepted by `--protocols`; old public IDs are deprecated and are no longer accepted by the CLI, menus, or subscription sync.

### Recommended Public Node Capabilities

| ID | Capability | Project core | Nginx mode | UDP | CDN | Recommended use |
| --- | --- | --- | --- | --- | --- | --- |
| `1` | VLESS Reality Vision | Xray / sing-box | `none` | no | no | Default direct-connection choice, with or without a domain. |
| `2` | VLESS Reality XHTTP | Xray | `none` | no | conditional | Preferred for new CDN / reverse-proxy nodes; XHTTP is Xray-only in this project. |
| `3` | Hysteria2 | sing-box | `none` | yes | no | Mobile, UDP, lossy-network, and port-hopping scenarios; node traffic does not pass through CDN/Nginx. |
| `4` | AnyTLS | sing-box | `none` | no | no | Use when sing-box AnyTLS is explicitly needed and clients support it. |
| `5` | NaiveProxy | sing-box | `none` | no | no | Use when TLS fingerprint resistance is explicitly needed and a real domain plus trusted certificate are available. |

### Advanced Public Node Capabilities

gRPC, WebSocket, and HTTPUpgrade are advanced protocols, not removed protocols. They remain available for explicit selection, but new deployments should prefer the recommended capabilities, especially direct Reality Vision or CDN/reverse-proxy Reality XHTTP.

| ID | Capability | Project core | Nginx mode | Boundary |
| --- | --- | --- | --- | --- |
| `21` | VLESS WS TLS | Xray | `http_front` | WebSocket is an advanced compatibility path; prefer `2` for new CDN nodes. |
| `22` | VMess WS TLS | Xray | `http_front` | VMess and WS are both advanced compatibility paths; prefer `1` or `2` for new deployments. |
| `23` | VMess HTTPUpgrade TLS | Xray / sing-box | `http_front` | HTTPUpgrade is an advanced compatibility path; prefer `2` for new CDN nodes. |
| `24` | VLESS gRPC TLS | Xray | `grpc_front` | gRPC has active-probing and fallback limitations; prefer `2` for new deployments. |
| `25` | Trojan gRPC TLS | Xray | `grpc_front` | Use only when Trojan + gRPC is explicitly required; consider `4` or `2`. |
| `26` | VLESS Reality gRPC | Xray / sing-box | `none` | Reality gRPC is an advanced direct path; prefer `1` or `2` for new deployments. |
| `27` | VLESS TCP TLS Vision | Xray | `fallback_backend` | Traditional TLS/fallback migration path; prefer `1` for new direct deployments. |
| `28` | Trojan TCP TLS direct | Xray / sing-box | `none` | Traditional TLS protocol for legacy clients or explicit requirements. |
| `29` | Trojan TCP TLS fallback | Xray | `fallback_backend` | fallback is only valid for TCP+TLS; consider `4` or `1` for new deployments. |
| `30` | Shadowsocks | sing-box | `none` | Advanced compatibility item; not recommended as a default public node. |
| `31` | TUIC | sing-box | `none` | UDP/lossy-network advanced item; new installs are guided toward `3`. |

### Internal Server Capabilities

Internal capabilities only appear in routing, relay, transparent-proxy, access-control, or management menus. They are not public node install inputs: `201` Socks relay, `202` HTTP relay, `203` WireGuard, `204` TUN, `205` Redirect/TProxy, `206` DNS/Direct/Block, and `207` Tunnel/dokodemo-door.

### Known Upstream Capabilities Not Generated By This Project

`301..309` are only shown by `--list-capabilities` and in documentation. They do not create install entries. This group includes Xray Hysteria2 inbound, Hysteria v1, ShadowTLS, mKCP combinations, Cloudflared inbound, Selector, URLTest, Tor outbound, SSH outbound, and pure transport/security description entries.

### Nginx Topology

| `nginx_mode` | Meaning | Applicable capabilities |
| --- | --- | --- |
| `none` | The core listens on the public port directly; node traffic does not install or start Nginx. | Reality Vision, Reality XHTTP, Hysteria2, AnyTLS, NaiveProxy, Reality gRPC, Trojan direct, Shadowsocks, TUIC. |
| `http_front` | Nginx HTTP/1.1 reverse proxy with explicit `Upgrade` / `Connection` handling. | WS / HTTPUpgrade capabilities `21..23`. |
| `grpc_front` | Nginx HTTP/2 + `grpc_pass` reverse proxy. | gRPC TLS capabilities `24..25`. |
| `xhttp_front` | Reserved for explicit XHTTP TLS/CDN/reverse-proxy capabilities; not applied to Reality XHTTP by default. | No default public node currently uses it. |
| `fallback_backend` | Xray fallback backend; only valid for TCP+TLS capabilities. | `27`, `29`. |
| `acme_only` | Nginx may serve certificate issuance or subscription publishing; it does not mean node traffic passes through Nginx. | Certificate and subscription services. |

`utls.fingerprint=chrome` in sing-box subscription output is a compatibility/simulation option, not a censorship-resistance guarantee. Prefer Reality Vision, Reality XHTTP, or NaiveProxy when TLS fingerprint resistance is the goal.

## Reality Semantics

Reality has three concepts that are easy to mix up:

| Concept | Meaning | Where it appears |
| --- | --- | --- |
| 📍 entry | Address the client connects to on your server | subscription `@host`, Clash `server`, sing-box `server` |
| 🎭 Reality target | External real HTTPS site used as the camouflage target | Xray `realitySettings.target`; sing-box `tls.reality.handshake` |
| 🧾 Reality SNI | SNI used during the Reality handshake | Xray `serverNames`; sing-box `tls.server_name`; subscription `sni/servername` |

A common setup is: client entry `node.example.com`, Reality target `www.ibm.com:443`, and Reality SNI `www.ibm.com`.

Reality Vision, Reality XHTTP, and Reality gRPC never request a local TLS certificate. A Reality-only install does not create or remove sites, touch ACME/cron, or stop, start, or reload Nginx. `--reality-domain yes` enables strict-domain mode only for a single Reality Vision `1` selection and validates the entry hostname and DNS; protocol `2`, `26`, or any multi-selection is rejected before dependencies or configuration writes.

Reality entry selection is `--entry-host`, then `--domain`, `/etc/padm/reality_entry_host`, `currentHost`, and finally the public IP. A normal single Reality port is selected as explicit `--port`, previous port, then `443`. Multi-protocol installs keep independent protocol ports and do not inject top-level `--port` into a Reality sub-port. With 443 coexistence enabled, clients keep using the recorded public port while the core reuses the recorded internal port.

When `--reality-target` is omitted, the script opens the target selector. Automatic selection prefers existing A/B measured results; if none exist, it probes built-in candidates; if no usable result is found, it falls back to `www.ibm.com:443`. Reality target measurements are written to `/etc/padm/reality_targets_results.tsv`, including TLS 1.3, `X25519MLKEM768`, certificate-chain length, network match, CDN risk, and check time.

`Protocols & entry` -> `REALITY management` can show the current target, run `xray tls ping`, refresh the target library, run RealiTLScanner, switch from measured results, view PQC/ML-DSA-65 status, and configure 443 coexistence splitting.

> [!WARNING]
> **Scanning risk:** RealiTLScanner is advanced; cloud scanning may cause the VPS to be flagged, so the script asks for confirmation first.

## XHTTP and CDN

After installing `2. VLESS Reality XHTTP`, tune protocol behavior under `Protocols & entry` -> `XHTTP management`:

| Level | Contents |
| --- | --- |
| ✅ Normal settings | View current config, apply scenario presets, switch `auto` / `packet-up` / `stream-up`. |
| 🧪 Advanced settings | Tune XMUX, path/host, header, packet, and stream parameters. |
| ⚠️ Experimental features | Enable or disable split upload/download `downloadSettings`. |

Daily/CDN defaults are `mode=auto`, `xmux.maxConcurrency=16-32`, `hMaxRequestTimes=600-900`, and `hMaxReusableSecs=1800-3000`. Each change is written to a temporary config and validated with Xray first; failed validation rolls back and prints the log path.

XHTTP is generated by Xray in this project. sing-box currently has no XHTTP transport, so the project does not emit sing-box XHTTP client configuration.

`Protocols & entry` -> `CDN entry management` only overrides client-facing subscription entry addresses, such as CDN CNAMEs, preferred IPs, or multiple entry addresses. XHTTP mode, XMUX, path/host, and other protocol parameters stay under `XHTTP management`.

## Traditional TLS and Local Sites

`Sites & certificates` -> `Traditional TLS fallback maintenance` is only for traditional TLS/fallback protocols. When traffic does not match a proxy protocol, the Nginx fallback can serve a local static page or 302 redirect.

This entry provides:

- 🖼️ 20 lightweight static-site templates, with randomized titles, copy, buttons, cards, and accent colors during installation or replacement.
- ↪️ 302 redirect maintenance.
- 🔎 ALPN diagnostics/repair for Xray fallback, `fallbacks[].alpn=h2`, and Nginx h2 fallback matching.
- ✅ `xray -test -confdir /etc/padm/xray/conf` after writes, with automatic rollback on failure.

Reality Vision, Reality gRPC, and Reality XHTTP do not depend on a local static site. Reality camouflage is handled by the external target and SNI. Maintain this entry only when using traditional TLS/fallback protocols such as VLESS TCP TLS Vision, WS TLS, gRPC TLS, or Trojan TLS, or when you really want to host a local website.

## Subscriptions and Users

The subscription system is role-based instead of one flat menu.

| State | Menu shape | What it is for |
| --- | --- | --- |
| 🟡 Uninitialized | `Use this server locally` / `This server is the controller` / `This server is controlled` | A single server can manage local subscriptions directly; choose controller or controlled mode only for multi-server use. |
| 🟢 Controller | `Publish subscriptions` / `Multi-server coordination` / `Controller maintenance & troubleshooting` | Create user subscriptions, publish links, add controlled servers, run sync, and handle quotas. |
| 🔵 Controlled | `Join controller` / `View local status` / `Controlled maintenance & troubleshooting` | Paste a controller invite, provide this server's nodes to the controller, and view WireGuard/sync state. |

Controller and local-only modes now share one `Subscription sync` menu under maintenance: run a full sync, enable/disable automatic sync, set the interval, open status/troubleshooting, or manage usage and quotas. The automatic-sync switch controls both immediate sync after configuration changes and cron; manual full sync remains available when it is off.

- A controller syncs every enabled controlled-server source. There is no separate global remote-sync switch; pause one server through `Add/remove controlled server` -> `Enable/disable controlled server`.
- Public subscriptions are published only after the local host and every enabled source return complete snapshots. If any required source fails, the previous complete public subscription stays in place instead of being overwritten by a partial node set.
- After changing a controlled server's Reality target or other node configuration, enabled automatic sync regenerates local nodes, fetches every enabled source, and publishes the complete group. The outer HTTPS subscription URL stays unchanged and nodes from the other servers remain present.
- Controlled servers do not expose an active-sync menu; they only answer authenticated sync requests from the controller.

Recommended flow for local-only or controller-side shared subscriptions:

1. Open `Publish subscriptions` -> `Install/update subscription service`.
2. Open `Publish subscriptions` -> `Create and publish subscription`, using an ID such as `team-a`.
3. Follow the wizard to select server sources and traffic limit.
4. With automatic sync enabled, saving triggers one full sync. If it is disabled, run a manual full sync later from `Subscription sync`. The managed account `sub_<ID>` is written to the core config.
5. Copy the user subscription link after the full sync completes.

Recommended multi-server flow:

1. On the controller, open `Multi-server coordination` -> `Controller setup wizard`, then use `Add/remove controlled server` -> `Create controlled-server invite` and enter the controlled-server alias once. The controller reserves its WireGuard address automatically.
2. On the controlled server, open `Join controller` and paste the invite. Initialization and controller-peer import complete without an address prompt; copy the resulting join receipt once.
3. Back on the controller, use `Add/remove controlled server` -> `Complete controlled-server join` and paste the receipt. The reserved alias drives the peer, source, and control-token transaction, followed by a health check for that source only.
4. To temporarily exclude one controlled server, use `Enable/disable controlled server`. Disabling preserves its peer, token, and history; the next full sync removes that source's nodes from the public subscription.
5. Pending invites can be viewed or cancelled by alias. Invites and receipts are bearer secrets, so normal status, health output, and pending lists never show their complete values. Cancel and recreate a lost invite.
6. Legacy `main` / `controlled` credentials remain only in explicitly named maintenance actions for existing links; first-time joins accept invites and receipts only. Receipts and legacy controlled credentials contain long-lived control tokens and must travel through a trusted channel.
7. WireGuard uses UDP and the control API uses HTTP only inside the tunnel, so this join flow needs no TLS certificate. Public client subscriptions continue to use HTTPS separately.

State backup and restore only affect `/etc/padm/subscribe_groups/groups.json`. Before restoring a backup or rebuilding state, the script creates a current-state backup and requires typing `yes`; state loading and restore accept only the current exact `version: 2` structure. Legacy structures and states with extra, missing, or invalid fields are rejected rather than rewritten.

## Routing and Access Control

`Routing & access control` manages server-side outbound behavior and access policies. It is not a client configuration tutorial.

| Feature | Notes |
| --- | --- |
| 🧭 Routing tools | WARP WireGuard outbound, IPv6 outbound, Socks5 relay, DNS routing, and DNS/hosts overrides. |
| ⛔ BT download management | Blocks detected bittorrent traffic through protocol sniffing; encrypted, obfuscated, or some uTP cases cannot be fully guaranteed. |
| 🧱 Access control | Domain/IP blocking, direct exceptions, and regional blocking. |

Xray access control uses routing + blackhole/direct; sing-box uses remote rule sets, domain_suffix/domain, and ip_cidr. Direct exceptions are placed before blocking rules and are useful for system updates, certificate issuance, or client services that must stay direct. Regional blocking is dangerous and may affect system updates, certificate issuance, and application connectivity.

> [!NOTE]
> **Safe writes:** Before changing access control, the script snapshots related rule files. It then validates Xray and sing-box configs; failed validation rolls back and prints the log path.

## Cores and Services

The `Cores & services` home view reads only local version, configuration, service, and Xray Geo state. It does not validate configurations or access the network while rendering. The page remains available when neither core is installed, including read-only scans that do not require a local binary. Remote version data is fetched only for an explicit upgrade, rollback, or prerelease trial.

The home view always has six entries:

1. Xray-core lifecycle
2. sing-box lifecycle
3. Service state
4. Logs and diagnostics
5. Xray Geo data
6. Return to the main menu

`Install & reinstall` exists only in the main menu, and there is no separate configuration-health page. Both lifecycle pages use the same order and expose `Check current configuration`, `Scan upgrade risks`, and `Trial the prerelease`. Results are `Passed`, `Needs attention`, `Failed`, or `Unable to check`. The first two actions are read-only and offline; a prerelease trial neither replaces the binary nor operates the service.

Xray's current-configuration check runs the normal and strict stages internally. A normal-stage failure is `Failed`; a strict-only failure is `Needs attention`. sing-box merges its configuration fragments and then runs `sing-box check -c /etc/padm/sing-box/conf/config.json`. Technical stages and log paths appear only in result details.

When upgrading or rolling back a core, the script downloads the target version into a temporary directory and validates the current configuration with the target binary before replacing `/etc/padm/xray/xray` or `/etc/padm/sing-box/sing-box` and restarting the service. If the new core fails to start, it attempts to restore the previous binary.

Nginx can be started, stopped, restarted, or smoothly reloaded only when the current protocol, site, or subscription configuration depends on it. An installed Nginx instance with no current padm dependency is read-only. Protocol, site, and subscription menus continue to own Nginx configuration; the service view owns only state and actions. Xray `geosite.dat` / `geoip.dat` updates, status, and scheduling live under `Xray Geo data`.

## System and Script

`System & script` handles padm itself and host-level helper features:

- 🔄 Update the padm script; if the subscription control service is enabled or running, the update also refreshes and restarts it. A refresh failure does not roll back the script update and prompts you to retry from control-plane maintenance.
- 🧾 Inspect entry validation, version, ref, and manifest.
- 🛡️ Manage Fail2ban protection, including basic SSH and `/s/control/` protection.
- 🚀 Inspect or enable network optimization / BBR.

The recommended network optimization only enables the official `bbr` implementation provided by the current kernel and writes padm's own `/etc/sysctl.d/99-padm-bbr.conf`:

```conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

Disabling it only removes padm's own sysctl file and attempts to restore the previous congestion control and qdisc. It does not modify other user sysctl files.

## Advanced Experiment

`Advanced / dangerous operations` -> `VLESS Encryption experiment` can enable experimental encryption for Xray Reality nodes. The script calls `xray vlessenc` to generate parameters:

- 🧭 Reality Vision: `VLESS Encryption + XTLS Vision`
- 🌐 Reality XHTTP: `VLESS Encryption + XTLS Vision + XHTTP XMUX`

> [!CAUTION]
> **Compatibility:** Default VLESS share links and Mihomo (formerly Clash.Meta) subscriptions include the experimental encryption field and require Mihomo v1.19.13 or later. The sing-box upstream does not support this field yet, so sing-box subscriptions still omit it. This is an advanced experiment and is not recommended as a default for new users.

## Flag Reference

| Flag | Values | Default / behavior | Notes |
| --- | --- | --- | --- |
| `--install-type` | `install`, `custom`, `reality` | Opens the interactive menu when no automation flags are passed; defaults to `custom` when other install flags are passed | Installation type. |
| `--core` | `xray`, `sing-box`, `1`, `2` | `xray` | `1` maps to `xray`, `2` maps to `sing-box`. |
| `--protocols` | comma-separated current public protocol IDs | No fixed default | Custom install protocols, such as `1` or `1,2,21`; old `0..13/20` IDs are deprecated. |
| `--list-protocols` | None | Print and exit | List installable public node capabilities. |
| `--list-capabilities` | None | Print and exit | List public nodes, internal capabilities, and known upstream capabilities. |
| `--show-risky-protocols` | None | Print and exit | List advanced public node capabilities with risk notices. |
| `--domain` | domain | Required or prompted for TLS installs | TLS certificate domain; also the second Reality entry priority, but Reality does not request a certificate for it. |
| `--entry-host` | domain or IP | Before `--domain`, saved entry, `currentHost`, and public IP | Address Reality clients actually connect to. |
| `--reality-target` | `host[:port]` | Opens selector when omitted; fallback `www.ibm.com:443` | Reality camouflage target. |
| `--reality-server-name` | SNI hostname | Defaults to target host | Reality SNI. |
| `--port` | port number | TLS defaults to `443`; single Reality uses explicit port, previous port, then `443` | TLS entry port or single-Reality client port; not injected into Reality sub-ports in multi-selection installs. |
| `--tls-ca` | `letsencrypt`, `zerossl`, `buypass` | `letsencrypt` | Certificate authority. |
| `--dns-api` | `yes`, `no`, `y`, `n` | `no` | Whether to use DNS API certificate issuance. |
| `--dns-api-type` | `cloudflare`, `aliyun`, `1`, `2` | `cloudflare` | DNS API provider. |
| `--dns-api-wildcard` | `yes`, `no`, `y`, `n` | `no` | Whether to request a `*.root-domain` wildcard certificate. |
| `--cloudflare-api-token` | token | Can also use `PADM_CLOUDFLARE_API_TOKEN` | Cloudflare DNS API token. |
| `--cloudflare-zone-id` | zone id | Optional; can also use `PADM_CLOUDFLARE_ZONE_ID` | Sets `CF_Zone_ID` and reduces zone lookup requirements. |
| `--aliyun-api-key` | key | Can also use `PADM_ALIYUN_API_KEY` | Aliyun AccessKey ID. |
| `--aliyun-api-secret` | secret | Can also use `PADM_ALIYUN_API_SECRET` | Aliyun AccessKey Secret. |
| `--reuse-last` | `yes`, `no`, `y`, `n` | `no` | Whether to reuse the previous installation config. |
| `--clean-acme` | `yes`, `no`, `y`, `n` | `no` | Whether to remove acme data when clearing previous config. |
| `--reality-domain` | `yes`, `no`, `y`, `n` | `no` | Strict-domain mode for a single Reality Vision `1` selection only; `--entry-host` has priority over `--domain`. |
| `--subscribe-port` | port number | No fixed default | Subscription publishing service port. |
| `--install-nginx` | `yes`, `no`, `y`, `n` | `no` | Whether to auto-install Nginx when subscription publishing or reverse proxying needs it. |
| `--uuid` | UUID | Randomly generated | Initial user UUID. |
| `--user` | username | Randomly generated | Initial username. |

Treat `bash install.sh --help` as the complete source of truth.

## Validation and Regression

Read-only post-install validation:

```bash
bash shell/validate_install.sh [domain]
```

Check public HTTP/HTTPS/TLS reachability:

```bash
bash shell/validate_install.sh --online example.com
```

Selector-based regressions through the unified dispatcher:

```bash
bash shell/subscription_groups_regression.sh fast
bash shell/subscription_groups_regression.sh platform-hot
bash shell/subscription_groups_regression.sh subscription-output
bash shell/subscription_groups_regression.sh transaction-core
bash shell/subscription_groups_regression.sh remote-control-contract
bash shell/subscription_groups_regression.sh remote-control-smoke
bash shell/subscription_groups_regression.sh subscription-state
```

Focused Cores & services regressions:

```bash
bash shell/subscription_groups_regression.sh ui-full-core
bash shell/subscription_groups_regression.sh ui-full-core-maintenance
bash shell/subscription_groups_regression.sh xray-strict-validation
bash shell/subscription_groups_regression.sh xray-compat-audit
bash shell/subscription_groups_regression.sh xray-compat-trusted-xff
bash shell/subscription_groups_regression.sh xray-configured-validation-path
bash shell/subscription_groups_regression.sh xray-prerelease-dry-run
bash shell/subscription_groups_regression.sh singbox-compat-audit
bash shell/subscription_groups_regression.sh singbox-prerelease-dry-run
bash shell/subscription_groups_regression.sh core-running-service-state
bash shell/subscription_groups_regression.sh service-queue-apply-propagation
bash shell/subscription_groups_regression.sh reload-core-propagation
bash shell/subscription_groups_regression.sh nginx-service-failure
bash shell/subscription_groups_regression.sh nginx-service-refresh
```

Recommended harness behavior checks:

```bash
bash shell/subscription_groups_regression.sh regression-dispatcher-contract
bash shell/subscription_groups_regression.sh regression-all-composition
bash shell/subscription_groups_regression.sh regression-all-child-parallel-budget-composition
bash shell/subscription_groups_regression.sh regression-all-resource-layer-composition
```

To cap concurrency or run heavy suites more conservatively, prefer `PADM_REGRESSION_PARALLEL_JOBS`, `PADM_REGRESSION_CHILD_PARALLEL_JOBS`, and suite-specific `PADM_REGRESSION_*_RESOURCE_PROFILE=all`.

Regression dispatch rules:

| Name | Actual command | Coverage |
| --- | --- | --- |
| Suite / aggregate selector | `bash shell/subscription_groups_regression.sh fast` | Unified dispatch for `fast`, `all`, `platform-hot`, `platform-io`, `subscription-output`, `transaction-core`, `remote-control` plus its `smoke` / `contract` / `deep` layered selectors, `subscription-state*`, and other suite / aggregate selectors. |
| Contract / composition selector | `bash shell/subscription_groups_regression.sh regression-dispatcher-contract` | Verifies registry argument passing, selector composition, concurrency limits and slot refill, interrupt cleanup, exited-child collection, and exactly-once aggregate dispatch. |
| All public selectors | `bash shell/subscription_groups_regression.sh <selector>` | Every public regression entrypoint goes through the same dispatcher. |

Historical grouped scripts are now internal runner / source-only layers and are no longer public command surfaces.

## License

This project is licensed under the [AGPL-3.0 License](../../LICENSE).
