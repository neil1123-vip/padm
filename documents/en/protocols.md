# 🧭 Protocols and Entry Points

[🏠 English home](README_EN.md#documentation) · [🌍 中文](../protocols.md)

Choose a protocol for your connection, then adjust Reality, XHTTP, or CDN entry settings under **Protocols & entry**. Use **Sites & certificates** to manage traditional TLS and local sites.

[Protocol selection](#protocol-selection) · [Reality](#reality-semantics) · [XHTTP and CDN](#xhttp-and-cdn) · [Traditional TLS and local sites](#traditional-tls-and-local-sites) · [Advanced experiment](#advanced-experiment)

## Protocol Selection

Choose a protocol for your connection. The numbers in the table are command-line protocol IDs.

| Goal | Recommended protocol | Notes |
| --- | --- | --- |
| New direct setup, own domain, or personal use | `1` VLESS Reality Vision | Current default recommendation; does not depend on a local fallback website. |
| CDN / reverse proxy | `2` VLESS Reality XHTTP | Preferred for new CDN nodes; uses XHTTP and XMUX. In this project XHTTP is Xray-only, and sing-box currently has no XHTTP transport. |
| No domain | No-domain Reality | Choose option `3` in the installation menu to use the server IP or a custom entry address. |
| TLS fingerprint resistance | `5` NaiveProxy | Requires a real domain and certificate; depends on sing-box. |
| UDP, mobile, or lossy network | `3` Hysteria2 | Hysteria2 node traffic does not go through CDN/Nginx; reachable UDP is required, and port hopping can be enabled when needed. |
| Explicit AnyTLS need | `4` AnyTLS | Use only after confirming client support. |
| Compatibility or migration | Advanced protocols `21..31` | Use only for legacy clients, existing CDN setups, traditional TLS, or migration windows. |

The capability registry is the single source of truth for protocol selection, core support, Nginx topology, and subscription output. `--protocols` accepts current public IDs with `category=node`. Subscription sync uses the same public IDs. In the interactive installer, enter the number shown on screen. Menu option `3` opens no-domain Reality, and command-line protocol ID `3` selects Hysteria2.

### Recommended Public Node Capabilities

| ID | Capability | Project core | Nginx mode | UDP | CDN | Recommended use |
| --- | --- | --- | --- | --- | --- | --- |
| `1` | VLESS Reality Vision | Xray / sing-box | `none` | no | no | Default direct-connection choice, with or without a domain. |
| `2` | VLESS Reality XHTTP | Xray | `none` | no | conditional | Preferred for new CDN / reverse-proxy nodes; XHTTP is Xray-only in this project. |
| `3` | Hysteria2 | sing-box | `none` | yes | no | Mobile, UDP, lossy-network, and port-hopping scenarios; node traffic does not pass through CDN/Nginx. |
| `4` | AnyTLS | sing-box | `none` | no | no | Use when sing-box AnyTLS is explicitly needed and clients support it. |
| `5` | NaiveProxy | sing-box | `none` | no | no | Use when TLS fingerprint resistance is explicitly needed and a real domain plus trusted certificate are available. |

### Advanced Public Node Capabilities

Select gRPC, WebSocket, or HTTPUpgrade in the custom installer for compatibility or migration. For new deployments, prefer Reality Vision for direct connections and Reality XHTTP for CDN or reverse proxy connections.

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

Choose the client entry address, external target, and SNI when configuring Reality.

| Concept | Meaning | Where it appears |
| --- | --- | --- |
| 📍 entry | Address the client connects to on your server | subscription `@host`, Clash `server`, sing-box `server` |
| 🎭 Reality target | External real HTTPS site used as the camouflage target | Xray `realitySettings.target`; sing-box `tls.reality.handshake` |
| 🧾 Reality SNI | SNI used during the Reality handshake | Xray `serverNames`; sing-box `tls.server_name`; subscription `sni/servername` |

A common setup is: client entry `node.example.com`, a measured Reality target such as `target.example.com:443`, and Reality SNI `target.example.com`.

Reality Vision, Reality XHTTP, and Reality gRPC never request a local TLS certificate. A Reality-only install does not create or remove sites, touch ACME/cron, or stop, start, or reload Nginx. `--reality-domain yes` enables strict-domain mode only for a single Reality Vision `1` selection and validates the entry hostname and DNS; protocol `2`, `26`, or any multi-selection is rejected before dependencies or configuration writes.

**📍 Entry and port.** Reality entry selection is `--entry-host`, then `--domain`, `/etc/padm/reality_entry_host`, `currentHost`, and finally the public IP. A normal single Reality port is selected as explicit `--port`, previous port, then `443`. Multi-protocol installs keep independent protocol ports and do not inject top-level `--port` into a Reality sub-port. With 443 coexistence enabled, clients keep using the recorded public port while the core reuses the recorded internal port.

**🎭 Select a target.** In the interactive installer, option `1` retests candidates and displays grade A results with `cdn_risk=no`. Option `2` accepts a manual `host[:port]` with port `443` by default. Leave the manual field blank to cancel. Non-interactive installation uses `--reality-target` or the saved target first. When both are absent, padm uses Xray to retest the recommended candidates and randomly selects a grade A result with `cdn_risk=no`. Installation stops if the detector is missing, the scan fails, or no result qualifies.

**🔎 Checks before saving.** Padm checks every A and AAAA address and uses the worst result. Manual selection accepts grades A through C with `cdn_risk=no` and warns for B or C. Checking the current target leaves the decision to switch with you.

- An address in AS13335 or one that responds to a `cloudflare.com` SNI probe is marked `cloudflare_relay`.
- A CNAME to a known CDN edge or an address belonging to a dedicated CDN ASN or organization is marked `cdn_edge`.
- Incomplete DNS, ASN, or TLS checks produce `unknown`.

Padm rejects all three results. The static blocklist excludes `java.com`, `nodejs.org`, `riotcdn.net`, and their subdomains from candidate refreshes, scanner imports, manual and automatic selection, and Docker deployments.

The built-in list contains 25 recommended targets measured at grade A with `cdn_risk=no`. On 2026-11-23, all 25 names resolved only to IPv4 and belonged to distinct ASNs. Installation checks DNS and TLS again from the deployment network. A separate blacklist supplies known CDN and edge proxy domains for runtime filtering, auditing, and display. The keyword filters `dev`, `developer`, and `开发者` are equivalent.

**📊 Target library.** The main Reality result table is a 16-column TSV at `/etc/padm/reality_targets_results.tsv`, with the measured IP's English location in the final column, such as `Los Angeles, United States`; legacy 15-column rows remain supported. Successful IP geolocation results are reused by full IP address. Batch writes query only unique uncached IPs in parallel batches, using `PADM_REALITY_SECONDARY_JOBS` with a default of 8 and a maximum of 16 requests, then commit all results together. If the city is unavailable, the region or country is shown; lookup failures display `Unknown` without affecting scoring or target switching. The table physically retains only targets whose latest state is `cdn_risk=no`, score A, and not matched by the static or custom blacklist. A new B/C/FAIL, risky, or `unknown` result removes the target's old A record; an empty batch write also cleans legacy risky rows. Scoring covers TLS 1.3, `X25519MLKEM768`, and certificate-chain length. Eligible targets are ordered by `same_asn > same_provider > different_network > unknown`, then certificate-chain length and check time.

`Protocols & entry → REALITY management → Target management` can check the current target, run `xray tls ping`, refresh the library, run RealiTLScanner, select a grade A target, and show PQC and ML-DSA-65 status. Refresh **Library + recommended candidates** to retest saved targets and recommended candidates, including recommended candidates previously absent from the library. Choose **Recommended candidates** to retest only that set. A successful switch updates the saved target. Configure 443 coexistence separately under `REALITY management`.

> [!WARNING]
> **Scanning risk:** RealiTLScanner is advanced; cloud scanning may cause the VPS to be flagged, so the script asks for confirmation first.

## XHTTP and CDN

After installing `2. VLESS Reality XHTTP`, tune protocol behavior under `Protocols & entry` -> `XHTTP management`:

| Level | Contents |
| --- | --- |
| ✅ Normal settings | View current config, apply scenario presets, switch `auto` / `packet-up` / `stream-up`. |
| 🧪 Advanced settings | Tune XMUX, path/host, header switches, and four native packet/stream limits. |
| ⚠️ Experimental features | Enable or disable split upload/download `downloadSettings`. |

Daily/CDN defaults are `mode=auto`, `xmux.maxConcurrency=16-32`, `hMaxRequestTimes=600-900`, and `hMaxReusableSecs=1800-3000`. Each change is written to a temporary config and validated with Xray first; failed validation rolls back and prints the log path.

XHTTP is generated by Xray in this project. sing-box currently has no XHTTP transport, so the project does not emit sing-box XHTTP client configuration.

`Protocols & entry` -> `CDN entry management` only overrides client-facing subscription entry addresses, such as CDN CNAMEs, preferred IPs, or multiple entry addresses. XHTTP mode, XMUX, path/host, and other protocol parameters stay under `XHTTP management`.

## Traditional TLS and Local Sites

`Sites & certificates` -> `Traditional TLS fallback maintenance` is only for traditional TLS/fallback protocols. When traffic does not match a proxy protocol, the Nginx fallback can serve a local static page or 302 redirect.

This entry provides:

- 🖼️ Import your own static website first. If no site is ready, initialize one of the `notes`, `photos`, or `docs` layouts, with articles, an about page, local images, and a 404 page.
- ↪️ 302 redirect maintenance.
- 🔎 ALPN diagnostics/repair for Xray fallback, `fallbacks[].alpn=h2`, and Nginx h2 fallback matching.
- ✅ `xray -test -confdir /etc/padm/xray/conf` after writes, with automatic rollback on failure.

Reality Vision, Reality gRPC, and Reality XHTTP do not depend on a local static site. Reality camouflage is handled by the external target and SNI. Maintain this entry only when using traditional TLS/fallback protocols such as VLESS TCP TLS Vision, WS TLS, gRPC TLS, or Trojan TLS, or when you really want to host a local website.

`Sites & certificates` -> `Local static site` maintains the site independently of Xray. Prefer `import`: prepare a complete static website in a separate absolute Linux directory, such as `/srv/own-site/`, and copy its contents unchanged into `nginxStaticPath` (default `/usr/share/nginx/html/`). Source and destination must not overlap. The source must contain a readable `index.html`; paths and file names currently allow only `A-Za-z0-9_./-`, with no dotfiles, symbolic links, hard links, special files, `check`, or `static-site.json`. Import does not rewrite text or resources. Import again after changing the source directory.

Imports and built-in layouts share staging, atomic directory replacement, and rollback on failure. Automatic installation preserves existing or edited pages. Explicit replacement of your own or edited website first saves a persistent private backup under `/etc/padm/static-site-backups/`. Unmodified built-in layouts use only temporary transaction backups for failure recovery; switching them does not create a retained archive each time. Ownership state stays outside the public directory in `/etc/padm/static-site.json`. Installation or later configuration transaction failures restore both the site and its state. Uninstall preserves your own and imported websites; only an unchanged built-in site with matching ownership and content digest is removed. Nginx uses your site's `404.html` when present and its default page otherwise, retaining HTTP 404 in either case.

The built-in layouts accept a site name. Default names and accent colors are fixed, and reinstalling the same layout keeps the saved values. Maintain real articles, images, navigation, and inner pages after installation. To replace content and configuration together, prepare the complete site in a separate directory and import it. Installations of the same layout still share HTML/CSS structure; randomized appearance or different content does not guarantee resistance to identification.

For native Hysteria2 authentication-failure masquerade, use `file:///srv/own-site/` directly for a separate directory containing your website, or an `http://` or `https://` URL to reverse proxy a website you control. `local` uses the current local site; `notes`, `photos`, and `docs` initialize built-in layouts. File directories must meet the index and content restrictions above. Unknown paths in the sing-box file server use Go's default 404 text. With obfuscation enabled, ordinary browsers cannot access this entry over standard HTTP/3. Docker supports managed static content with `local`, using a fixed read-only directory and requiring obfuscation to be disabled. See the [Hysteria2 protocol](https://v2.hysteria.network/docs/developers/Protocol/) and [sing-box Hysteria2 inbound configuration](https://sing-box.sagernet.org/configuration/inbound/hysteria2/) for protocol details.

## Advanced Experiment

`Advanced / dangerous operations` -> `VLESS Encryption experiment` can enable experimental encryption for Xray Reality nodes. The script calls `xray vlessenc` to generate parameters:

- 🧭 Reality Vision: `VLESS Encryption + XTLS Vision`
- 🌐 Reality XHTTP: `VLESS Encryption + XTLS Vision + XHTTP XMUX`

> [!CAUTION]
> **Compatibility:** Default VLESS share links and Mihomo (formerly Clash.Meta) subscriptions include the experimental encryption field and require Mihomo v1.19.13 or later. The sing-box upstream does not support this field yet, so sing-box subscriptions still omit it. This is an advanced experiment and is not recommended as a default for new users.

See the native installation and flag reference for commands and protocol parameters. [📦 Native Installation and Flags](native-install.md)
