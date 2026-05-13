# padm

padm is a one-click installation and day-to-day operations script for Xray-core and sing-box. It focuses on deploying usable nodes quickly, delivering client configuration through subscriptions, and keeping common maintenance tasks in clear menu entries.

It supports Reality Vision, Reality XHTTP, traditional TLS compatibility protocols, TLS certificates, subscription publishing, user subscription groups, multi-server synchronization, traffic statistics, access control, and read-only validation.

## New user guide

If this is your first time using the script, start with the simplest path:

1. **Not sure what to choose**: open `Install & reinstall`; the menu explains which option fits direct/CDN/no-domain setups. If unsure, choose `Recommended direct Reality Vision`.
2. **Direct / with a domain**: choose `Install & reinstall` -> `Recommended direct Reality Vision`; use your domain as the entry address when available.
3. **CDN required**: choose `Install & reinstall` -> `Recommended CDN Reality XHTTP`; the script enables XHTTP XMUX, while traditional TLS/WS/gRPC/HTTPUpgrade should only be used for legacy client compatibility.
4. **Without a domain**: choose `Install & reinstall` -> `No-domain Reality`.
5. **After installation**: open `Subscriptions & users` -> `Subscription service` to install/update publishing, then `My Subscription` to view personal links.
6. **Validation**: run `bash shell/validate_install.sh [domain]` on the server for a read-only check.

Avoid advanced entries such as custom protocol combinations, CDN node management, and multi-server synchronization until you know which protocol and network shape your client needs.

## Menu overview

The main menu is grouped by task object. Each feature has one primary home:

| Menu | When to use |
| --- | --- |
| Install & reinstall | Includes new-user choice guidance; create or rebuild nodes: recommended direct, recommended CDN, no-domain Reality, custom install, and traditional TLS compatibility. |
| Subscriptions & users | Subscription service, personal links, creating subscriptions for others, multi-server sync, traffic/quota, and automatic sync. |
| Protocols & entry | Manage REALITY, XHTTP, Hysteria2, Tuic, extra entry ports, and CDN entry addresses. |
| Sites & certificates | Maintain traditional TLS fallback sites, 302 redirects, ALPN diagnostics/repair, and TLS certificates. |
| Routing & access control | Manage server-side outbound routing, BT blocking, domain/IP blocking, direct exceptions, and regional blocking. |
| Cores & services | Manage Xray-core / sing-box lifecycle, config validation, Geo data, service control, and logs. |
| System & script | Update padm and manage network optimization / BBR. |
| Advanced / dangerous operations | Uninstall and experimental high-risk switches such as VLESS Encryption. |

## Features

* **Core lifecycle management**: shows Xray-core / sing-box versions, service state, and config validation results; supports stable/prerelease upgrades, stable rollbacks, service control, logs, and Xray Geo data maintenance.
* **Multi-protocol support**: VLESS, VMess, Trojan, Hysteria2, Tuic, NaiveProxy, AnyTLS, and more.
* **Automatic TLS**: applies for and renews SSL certificates.
* **Parameterized installation**: supports non-interactive installation through command-line options.
* **Interactive management**: Chinese card-style menus for installation, updates, users, ports, certificates, services, and configuration; status, risk, troubleshooting, subscription links, and dry-run plans are shown as status/result cards.
* **Subscriptions**: default, Clash Meta, and sing-box outputs, with optional subscription publishing service.
* **Subscription groups**: `/etc/padm/subscribe_groups/groups.json` is the source of truth for users, servers, sync, traffic, quotas, and backups.
* **Multi-server synchronization**: remote control channel, health checks, dry-run plans, manual sync, and scheduled sync.
* **Traffic routing**: WARP WireGuard outbound, IPv6 outbound, Socks5 relay, DNS routing, and DNS/hosts overrides; sing-box routing uses remote rule sets and domain_suffix.
* **Traditional TLS fallback maintenance**: static site templates, 302 redirects, and ALPN diagnostics/repair for traditional TLS/fallback compatibility.
* **Access control**: unified domain/IP blocking, direct exceptions, and regional blocking; Xray uses routing + blackhole/direct, while sing-box uses remote rule sets, domain_suffix/domain, and ip_cidr.
* **Network optimization**: inspect kernel, congestion control, and qdisc status; enable official-kernel BBR + fq by default and remove only padm's own sysctl drop-in when disabling it.

## Quick start

### Interactive installation

```bash
wget -P /root -N "https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

If the downloaded entry script does not find the local `shell/` modules, it will fetch the full package automatically.

Open the management menu again after installation:

```bash
padm
```

### Non-interactive installation

Show options and examples:

```bash
bash install.sh --help
```

Recommended VLESS Reality Vision install:

```bash
bash install.sh --install-type custom --core xray --protocols 7 --entry-host node.example.com --reality-target www.ibm.com:443 --reality-server-name www.ibm.com --reuse-last no
```

Recommended VLESS Reality XHTTP + CDN install (with XTLS Vision flow and XHTTP XMUX):

```bash
bash install.sh --install-type custom --core xray --protocols 12 --entry-host cdn.example.com --reality-target www.ibm.com:443 --reality-server-name www.ibm.com --reuse-last no
```

NaiveProxy install for TLS fingerprint resistance (requires a real domain and certificate; it is not a no-domain Reality replacement):

```bash
bash install.sh --install-type custom --core sing-box --protocols 10 --domain naive.example.com --port 443 --reuse-last no
```

Traditional TLS install with Cloudflare DNS-01 automation:

```bash
bash install.sh --install-type install --core xray --domain example.com --port 443 --tls-ca letsencrypt --dns-api yes --dns-api-type cloudflare --dns-api-wildcard yes --cloudflare-api-token <token> --cloudflare-zone-id <zone_id> --reuse-last no
```

Use a Cloudflare API token restricted to the target zone. `Zone:DNS:Edit` is required; if `--cloudflare-zone-id` is omitted, allow zone lookup as well so acme.sh can find the zone automatically. To avoid putting tokens in shell history, use `PADM_CLOUDFLARE_API_TOKEN=... PADM_CLOUDFLARE_ZONE_ID=... bash install.sh ... --dns-api yes` instead of command-line token flags.

No-domain Reality install:

```bash
bash install.sh --install-type reality --core xray --reality-target www.ibm.com:443 --reuse-last no --clean-acme no
```

Custom protocol install:

```bash
bash install.sh --install-type custom --core xray --protocols 7 --entry-host node.example.com --reality-target www.ibm.com:443 --reality-server-name www.ibm.com --reuse-last no --clean-acme yes
```

Install or update the subscription publishing service with the dedicated subcommand:

```bash
bash install.sh InstallSubscription --subscribe-port 39778 --install-nginx yes
```

Subscription publishing options can also be appended to protocol installation when needed:

```bash
--subscribe-port 39778 --install-nginx yes
```

## Protocol capability matrix

| Script protocol name | Solves TLS in TLS | Solves fingerprint issue | Built-in multiplexing | CDN support | Recommended use |
| --- | --- | --- | --- | --- | --- |
| VLESS TCP TLS Vision | yes | no | no | no | Legacy TLS compatibility or migration. |
| VLESS Reality Vision | yes | yes | no | no | Default direct-connection choice, with or without a domain; the advanced VLESS Encryption switch adds `VLESS Encryption + XTLS Vision`. |
| VLESS Reality gRPC | no | yes | yes, HTTP/2 | no | Alternative when gRPC/HTTP2 multiplexing is needed without CDN. |
| VLESS Reality XHTTP | yes | yes | yes, XMUX | yes | Preferred CDN choice; the advanced VLESS Encryption switch adds `VLESS Encryption + XTLS Vision + XHTTP XMUX`. |
| NaiveProxy | no | yes | depends on client | no | Prefer when TLS fingerprint resistance is explicitly needed. |
| Hysteria2 | n/a | no | QUIC | no | Mobile, UDP, or lossy-network scenarios. |
| Tuic | n/a | no | QUIC | no | UDP/mobile-network scenarios. |
| AnyTLS | no | protocol-side mitigation | new multiplexing | no | Use only when sing-box AnyTLS is explicitly needed and clients support it. |

`utls.fingerprint=chrome` in sing-box subscription output is a compatibility/simulation option, not a censorship-resistance guarantee. Prefer NaiveProxy, Reality Vision, or Reality XHTTP when TLS fingerprint resistance is the goal. sing-box 1.13+ removed legacy WireGuard outbound and legacy special outbounds, and 1.14 will remove old DNS server formats and legacy `domain_strategy`; padm-generated sing-box WARP, DNS, and direct outbound templates use endpoints, typed DNS servers, and `domain_resolver`.

## XHTTP management

After installing `12. VLESS Reality XHTTP`, open `Protocols & entry` -> `XHTTP management` to tune XHTTP behavior. The menu is split by risk level:

1. **Normal settings**: view the current config, apply scenario presets, switch `auto` / `packet-up` / `stream-up`, and read CDN/H3 notes.
2. **Advanced settings**: tune XMUX, path/host, and header/packet/stream parameters; recommended defaults remain available as the safe baseline.
3. **Experimental features**: enable or disable split upload/download `downloadSettings` for advanced deployments that need an independent download path.

The daily/CDN defaults are `mode=auto`, `xmux.maxConcurrency=16-32`, `hMaxRequestTimes=600-900`, and `hMaxReusableSecs=1800-3000`. Use the single-concurrency preset for benchmarks or troubleshooting; use `packet-up` for compatibility-first paths; consider `stream-up` only after confirming the path supports streaming upload. Every change is written to a temporary config first, validated with Xray, then applied by reloading the core and refreshing subscriptions. Failed validation automatically rolls back and prints the log path.

`Protocols & entry` -> `CDN entry management` only overrides subscription entry addresses: set the client-facing address to a CDN CNAME, preferred IP, or your own domain, and comma-separated entries generate multiple nodes. XHTTP mode, XMUX, path/host, and other protocol parameters stay under `Protocols & entry` -> `XHTTP management` so entry routing and protocol tuning remain separate.

## Advanced VLESS Encryption experiment

Open `Advanced / dangerous operations` -> `VLESS Encryption experiment` to enable experimental encryption for Xray Reality nodes. The script calls Xray's `xray vlessenc` generator and applies these combinations:

- **Direct / regular Reality Vision**: `VLESS Encryption + XTLS Vision`.
- **CDN / Reality XHTTP**: `VLESS Encryption + XTLS Vision + XHTTP XMUX`.

If `12. VLESS Reality XHTTP` is installed, the switch applies `decryption` to the XHTTP config first; otherwise it applies it to `7. VLESS Reality Vision`. The default VLESS share link includes `encryption=...` and `flow=xtls-rprx-vision`; Clash/Mihomo/sing-box subscriptions still omit the experimental encryption field to avoid misleading compatibility assumptions. This remains an advanced experimental option and is not recommended for new users by default.

## Reality concepts

Reality uses three separate concepts:

| Concept | Meaning | Where it appears |
| --- | --- | --- |
| entry | Address the client connects to | subscription `@host`, Clash Meta `server`, sing-box profile `server` |
| Reality target | Real HTTPS site used as the camouflage target | Xray `realitySettings.target`; sing-box `tls.reality.handshake.server/server_port` |
| Reality SNI | SNI used during Reality handshake | Xray `serverNames`; sing-box `tls.server_name`; subscription `sni/servername` |

A common setup is: client entry `node.example.com`, Reality target `www.ibm.com:443`, and SNI `www.ibm.com`.

When `--reality-target` is not provided, the installer opens a Reality target selector. Automatic selection only uses local A/B-rated measured results; if no measured result exists, it falls back to the stable default `www.ibm.com:443`. You can also choose from the built-in candidate pool, enter a custom target, or pick a random candidate. The built-in candidate pool is only a scan source and no longer represents an offline recommendation rank. Non-recommended targets such as Cloudflare, Fastly, Akamai, and Apple are moved to the blacklist and are not scanned or selected randomly.

After installation, open `Protocols & entry` -> `REALITY management` -> `Target Management` to view the current target, run `xray tls ping`, scan and score the target pool, run the RealiTLScanner range selector, switch from measured results, or view PQC/ML-DSA-65 status. Results are stored in `/etc/padm/reality_targets_results.tsv` with target, SNI, IP/ASN, network match, CDN risk, score, `X25519MLKEM768` support, TLS 1.3, certificate chain length, and check time. The scan command also displays total elapsed time. Score `A` means TLS 1.3 + `X25519MLKEM768` are available and the certificate chain length is greater than 3500; `B` means TLS 1.3 + `X25519MLKEM768` are available but the certificate chain length is not greater than 3500 or is unknown; `C` means TLS 1.3 is available but `X25519MLKEM768` was not detected; `FAIL` means no usable TLS 1.3 was detected or the second check failed.

RealiTLScanner is an advanced feature: the script warns that its author recommends running it locally because cloud scanning may flag the VPS. After confirmation, you can choose the default `/24 (254 hosts)`, quick `/28 (14 hosts)`, expanded `/23 (510 hosts)`, `/22 (1022 hosts)`, `/21 (2046 hosts)`, `/20 (4094 hosts)`, `/19 (8190 hosts)`, `/18 (16382 hosts)`, or enter a custom range. During import, it filters blacklisted targets, wildcard certificates, raw IP names, `localhost`, `invalid.invalid`, placeholder CN values, and Cloudflare Origin Certificate names, then imports results only after a second `xray tls ping -ip <scanned-ip> <domain:443>` check.

## Traditional TLS fallback maintenance

Main menu `Sites & certificates` -> `Traditional TLS fallback maintenance` is only for traditional TLS protocols. When traffic does not match a proxy protocol, the Nginx fallback can serve a local static page or 302 redirect. The script includes 20 lightweight templates and randomizes titles, industry copy, buttons, card content, footers, and accent colors during installation or replacement.

The maintenance entry also provides **ALPN diagnostics and repair**: it checks whether the traditional TLS fallback inbound, `fallbacks[].alpn=h2`, and the Nginx h2 fallback match. When an h2 fallback exists, the recommended repair sets the Xray inbound TLS ALPN to `["h2","http/1.1"]`. Manual settings are only for legacy-client troubleshooting. Every write is validated with `xray -test -confdir /etc/padm/xray/conf`; failed validation rolls back automatically and prints `/tmp/padm-alpn-xray-test.log`.

VLESS Reality Vision, Reality gRPC, and Reality XHTTP do not depend on this local static site or ALPN maintenance entry. Reality camouflage is handled by the external `target` and `SNI`; unauthenticated probing traffic is forwarded to the target site. New users installing Reality do not need to configure the toolbox fallback entry first.

For direct personal use, prefer the Reality Vision example. Configure the static site or ALPN only when you keep using traditional TLS/fallback protocols such as VLESS TCP TLS Vision, WS TLS, gRPC TLS, or Trojan TLS, or when you really want to host a local website.

## Access control

Main menu `Routing & access control` -> `Access control` manages domain/IP blocking, direct exceptions, and regional blocking in one place. It can show the current Xray / sing-box rule state, add blocking or direct rules by type, and remove only domain blocking, IP/CIDR blocking, direct exceptions, regional blocking, or all access-control rules.

Domain rules support `geosite:`, `domain:`, `full:`, `keyword:`, and plain domains. Xray plain domains are written as `domain:example.com` instead of the old broad `regexp:.*example.com.*`; sing-box uses `SagerNet/sing-geosite` remote SRS, writes plain domains to `domain_suffix`, and writes `full:` entries to exact `domain` matches. IP rules support IPv4, IPv6, CIDR, and `cn`; `cn` maps to Xray `geoip:cn` or sing-box remote GeoIP SRS.

Direct exceptions are placed before blocking rules and are intended for system updates, certificate issuance, or client services that must stay direct. Regional blocking is a dangerous operation: it can apply `geosite:cn`, `geoip:cn`, or both, and may affect system updates, certificate issuance, and application connectivity. Before writing access-control changes, the script snapshots related rule files; after writing, it validates Xray with `-test` and sing-box with `merge`. Failed validation rolls back automatically and prints `/tmp/padm-access-xray-test.log` or `/tmp/padm-access-sing-box-test.log`.


## Reality 443 coexistence split

A single Reality Vision install usually only needs one entry port, with `443` recommended by default, and it does not require a local camouflage website. Reality camouflage is handled by the external `target` and `SNI`; use “Configure 443 coexistence split” in `Protocols & entry` -> `REALITY management` only when the same server must also host a real website on `443`.

The advanced split mode works as follows:

1. Nginx stream listens on public `443`.
2. Explicit real website domains are forwarded to the website backend, such as `127.0.0.1:8443`.
3. All other SNI values fall through to the Xray Reality backend, such as `127.0.0.1:2443`.
4. Subscription output still uses `entry-host:443`, while Reality SNI remains the camouflage target.

Nginx stream sees the TLS ClientHello SNI, and Reality clients usually send the external camouflage SNI instead of the entry host. Therefore the script only asks which domains are real websites; everything else goes to Reality by default. New users should avoid this mode unless website coexistence on `443` is required.

## Core lifecycle management

Main menu `Cores & services` first shows the current Xray-core / sing-box versions, latest stable and prerelease versions, service state, config validation result, and Xray Geo data state.

When upgrading or rolling back a core, the script downloads the target version into a temporary directory and validates the current configuration with the target binary before replacing `/etc/padm/xray/xray` or `/etc/padm/sing-box/sing-box`. If the new core fails to start, it attempts to restore the previous binary. Xray is validated with `xray -test -confdir /etc/padm/xray/conf`; sing-box is merged first and then checked with `sing-box check -c /etc/padm/sing-box/conf/config.json`.

Xray `geosite.dat` / `geoip.dat` maintenance now lives under “Config validation and data maintenance”. Service start/stop/restart and log entries are also handled from core management.

## Network optimization

Main menu `System & script` -> `Network optimization` shows and manages TCP network optimization status. The status view reports the current kernel, current congestion control, available congestion controls, current default qdisc, whether BBR is available, and whether padm has written `/etc/sysctl.d/99-padm-bbr.conf`.

The recommended action is **Enable official BBR + fq**. The script only enables the `bbr` implementation provided by the current kernel and writes:

```conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

Before writing, it checks whether `bbr` is available; if it is missing, it tries `modprobe tcp_bbr`. If BBR is still unavailable, it reports that the current kernel does not support BBR and does not install third-party kernels or modify bootloader settings. Disabling the option only removes padm's own `/etc/sysctl.d/99-padm-bbr.conf`, tries to restore the previous congestion control and qdisc, and does not modify other user sysctl files.

## Subscription management

Open `Subscriptions & users` in the main menu. It is organized by user task flow:

1. **Subscription service**: install/update subscription publishing and check publishing status. This menu now handles client-facing HTTPS publishing only; it no longer exposes the server-to-server control plane.
2. **My Subscription**: view/refresh personal subscription links, available servers, and personal traffic.
3. **Create subscriptions for others**: create and sync user subscriptions; managed accounts use the `sub_<ID>` prefix.
4. **Multi-server subscriptions**: use a WireGuard control plane to manage remote controlled servers, join credentials, health checks, and sync results. The first release supports a star topology only: one controller manages multiple controlled servers.
5. **Traffic & quotas**: refresh traffic explicitly, view traffic without implicit refresh, and preview/execute quota plans.
6. **Automatic sync & backups**: automatic sync, manual sync, sync plans, and state backup/restore.

Recommended user subscription flow:

1. `Create subscriptions for others` -> `Create and sync subscription`, using an ID such as `team-a`.
2. Follow the wizard to set allowed servers (`main` by default) and traffic limit.
3. Confirm the summary and run sync so `sub_<ID>` is written to the core config.
4. View or refresh the user subscription links.

Recommended multi-server flow:

1. On the controller server, open `Multi-server subscriptions` -> `WireGuard control plane`, initialize this server as the controller, and copy the local controller join credential.
2. On the controlled server, open `Multi-server subscriptions` -> `WireGuard control plane`, initialize this server as controlled, import the controller join credential, then copy the local controlled join credential.
3. Back on the controller server, open `Multi-server subscriptions` -> `Add/remove controlled server`, paste the controlled join credential, and set a local alias.
4. Test the controlled connection, then view the sync plan or run sync.
5. Client subscriptions continue to be published over public HTTPS. The server-to-server control API is only reachable inside the WireGuard network as `http://<wg-ip>:<control-port>/s/control/...`.

Subscription and management output now uses card-style presentation: subscription links show the account, URL, and online QR code; user subscriptions, server sources, health checks, sync plans, quota plans, and traffic statistics are shown as result or plan cards. HTTPS subscription publishing, Reality target warnings, XHTTP advanced parameters, DNS/port/Nginx troubleshooting, and other action-required messages are shown as risk or troubleshooting cards so normal status messages are easier to distinguish from items that need attention.

## Validation

Read-only local validation:

```bash
bash shell/validate_install.sh [domain]
```

Online HTTP/HTTPS/TLS validation:

```bash
bash shell/validate_install.sh --online example.com
```

## License

This project is licensed under the [AGPL-3.0 License](../../LICENSE).
