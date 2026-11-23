# 🐳 Docker Mode Guide

[🏠 English home](README_EN.md#docker-mode) · [🌍 中文](../docker-guide.md) · [Feature matrix (Chinese)](../docker-feature-matrix.md)

[Docker Requirements](#docker-requirements) · [Installation](#installation) · [Five Images](#five-images) · [State and Daily Control](#state-and-daily-control)

[Trusted Release Inputs](#trusted-release-inputs) · [Recovery Archives](#recovery-archives) · [User Traffic and Quotas](#user-traffic-and-quotas) · [Updates](#updates) · [Rollback](#rollback) · [Uninstall](#uninstall)

Use `install-docker.sh` to install the Docker control bundle and `padm-docker` to manage it. Docker mode runs the cores, Nginx, subscription services, and operations tasks in containers. Choose either Docker or native deployment on each host. Moving between modes requires a separate migration.

## Docker Requirements

| Item | Requirement |
| --- | --- |
| Operating system | A native Linux host and a Docker daemon running Linux containers. Windows, macOS, and Docker Desktop are outside the support scope. |
| Permissions and connection | Root privileges and a rootful Docker Engine on a local Unix socket. Rootless daemons, remote contexts, and user-level sockets are outside the support scope. |
| Compose | Docker Compose CLI plugin (major version v2 or later). |
| Architecture | `amd64` or `arm64`, with matching host and daemon architecture. |
| Host commands | Bash 4+, `jq`, `sha256sum`, `tar`, and either `curl` or `wget`. Release verification and signed updates require `cosign` with Sigstore bundle v0.3 support. CI uses Cosign 3.x. |
| User statistics | A running systemd or cron daemon. sing-box also needs host `nsenter` (usually from `util-linux`) and an HTTP/2-capable `curl`. Configuration and updates stop if these requirements are missing. |
| Kernel capabilities | The regular profiles need no extra capability. WireGuard, Fail2ban, TUN/TProxy, and other `net-*` profiles use `NET_ADMIN`, host networking, or `/dev/net/tun` as specified in the feature matrix. |

**📦 Automatic Docker installation.** If `install-docker.sh install` cannot find `docker`, it asks whether to install Docker Engine, the Compose CLI plugin, and host prerequisites from Docker's official repository. This option supports rootful systemd hosts running Debian, Ubuntu, CentOS, Fedora, and RHEL. Install Docker manually on other distributions.

Declining or leaving the prompt unanswered, reaching end of input, or encountering an installation failure stops setup before it initializes `/etc/padm-docker`. Any completed changes to host packages or repositories stay in place. If Docker is already installed, an unavailable daemon or Compose stops setup. Resolve any existing native deployment or leftover native state before starting the Docker installation.

<a name="installation-1"></a>

## Installation

The installer checks the control bundle's layout and verifies that it matches the entry script. During initial setup, padm verifies the signed release manifest and pulls the images built by CI. These images include Xray, sing-box, Nginx, and other application dependencies. Run the following command on the host to install the control entry.

```bash
wget -O /root/install-docker.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install-docker.sh" && chmod 700 /root/install-docker.sh && /root/install-docker.sh install
```

Installation opens the menu automatically when it succeeds in an interactive terminal. Select `1. Install and reinstall → 1. First configuration` to choose the core, protocols, addresses, and certificates. Run `padm-docker` or `padm-docker menu` to reopen the menu. For a fresh deployment, `padm-docker setup` starts the wizard directly in an interactive terminal.

The wizard supports Xray Reality Vision, XHTTP, and gRPC, along with sing-box Reality Vision, Reality gRPC, Hysteria2, AnyTLS, NaiveProxy, Shadowsocks, and TUIC. Both cores support direct Trojan and VMess HTTPUpgrade TLS. Xray also supports VLESS WS TLS, VMess WS TLS, VLESS or Trojan gRPC TLS, VLESS TCP TLS Vision, Trojan TLS fallback, and the Reality Vision + WS TLS combination.

Use the same menu to reinstall an existing deployment or use the configuration editor to retain its identity. The feature matrix lists the supported cores and combinations for all 16 public protocols, including the available commands to add, edit, copy, rebuild without changing the identity, delete, share, and recover a listener. It also records the coverage for public networks, arm64, and host lifecycle tests. [Feature matrix](../docker-feature-matrix.md#状态定义)

`install --no-menu` disables the automatic menu. A non-interactive invocation without
arguments only prints help without installing Docker, downloading the bundle, or
initializing state. Existing explicit CLI commands remain available.

The Docker home screen shares the native menu's style and eight task groups.

| Number | Menu | Common actions |
| --- | --- | --- |
| `1` | 🚀 Install and reinstall | `1` first configuration, `2` choose cores and protocols again, `3` reinstall from a complete spec |
| `2` | 🔗 Subscriptions and users | `1` accounts, `2` subscriptions, `3` traffic and quotas, `4` control connection, `5` business backup and recovery, `6` HTTPS subscription publishing |
| `3` | 🧭 Protocols and listeners | REALITY, XHTTP, Hysteria2, TUIC, extra ports, and CDN. `8` opens advanced listener management |
| `4` | 🔐 Sites and certificates | `1` traditional TLS fallback, `2` local TLS certificates, `3` local static sites |
| `5` | 🧱 Routing and access control | `1` routing tools, `2` BitTorrent, `3` access control. `1 → 8` opens full routing maintenance |
| `6` | ⚙️ Cores and services | Service status, start, stop, restart, logs, and validation. `7` assesses upgrades, `8` manages Xray Geo data, `9` edits or imports a spec |
| `7` | 🧰 System and scripts | `1` updates, rollback, and deployment maintenance, `2` installation status, `3` Fail2ban |
| `8` | ⚠️ Advanced and dangerous actions | `1` removes services and the control command while retaining data, `2` opens the VLESS Encryption experiment |

Advanced listener management opens at `3 → 8`, full routing management at
`5 → 1 → 8`, and release maintenance at `7 → 1`. SOCKS5 inbound at `5 → 1 → 3 → 2` remains unavailable, with the fixed
cores' authentication and source-restriction limitations shown.
Both modes retain their existing core-upgrade mechanisms; Docker still upgrades and
rolls back a verified release bundle as a unit. The shared style also covers headings,
lists and summary borders in menus, first configuration, TLS management and the editor.
Press Enter or enter `0` to go back at navigation prompts. Prompts with an explicit
default use that default when you press Enter.
Feature-support boundaries and native-host acceptance requirements remain unchanged.

```bash
padm-docker setup
padm-docker validate
padm-docker status
```

If you scan Reality targets, the wizard verifies and prepares the probe image before showing the candidates. After final confirmation, it generates the UUID, Reality parameters, and subscription token, then prepares the candidate configuration and certificates. The wizard requires a trusted `cosign` installation for verification.

WS, HTTPUpgrade, and gRPC over TLS, traditional TLS fallback, Hysteria2, AnyTLS, NaiveProxy, TUIC, and direct Trojan can use managed certificates, an imported full certificate chain and private key, or ACME with DNS-01, HTTP-01 standalone, or TLS-ALPN-01. Private keys and DNS credentials must be regular files readable only by their owner.
Subscription publishing requires at least one Nginx TLS listener using protocol `21–25` or Xray TLS fallback `27/29`
and managed TLS for the same domain; a sing-box-only HTTPUpgrade `23` deployment can qualify.
It reuses the existing Nginx and subscription services, without a separate publishing domain,
certificate, or service. Enabling publication without `21` requires the bundle capability
`x-padm-subscription-nginx-tls`; publication containing `27/29` also requires
`x-padm-subscription-fallback-tls`. Existing subsets with publication disabled remain compatible.
Both fallback HTTP/1.1 and HTTP/2 backends serve the same subscription routes, without
adding public ports or mounting TLS private keys into Nginx.
Share-group HTTPS URLs use the actual public port of the first eligible listener in
`core.protocols`, omitting `443`; a website listener selected for Reality coexistence uses
public port `443`. Plan 4A.7 passed isolated amd64 tests for protocols `22–25`:
main/group HTTPS downloads, strict TLS, and IPv4/IPv6 TCP/UDP clients.
Public-network and native dual-architecture acceptance remain separate.
Menu `2 → 2 → 10/11`, or `subscription content --base` / `subscription links --base`,
prints the deployment's main subscription content or HTTPS URL. Content uses the existing
node renderer, including self-use entries and enabled accounts, and remains available
with publication disabled or Reality-only listeners. HTTPS URLs require enabled publication.
These queries create no share-group state and do not change published files.
Content and URLs contain credentials and should only reach authorized clients.

On a configured deployment, use `2 → 6` to view the HTTPS publishing status, enable publishing, or disable it.

```bash
padm-docker subscription publish status
padm-docker subscription publish enable
padm-docker subscription publish disable
```

Disabling requires confirmation. Scripts can use `disable --yes`. While publishing is disabled, the main and share-group HTTPS URLs stop serving subscriptions. Accounts, share groups, tokens, certificates, and listeners stay in place. Enabling publishing again uses the existing tokens if the deployment meets the publishing requirements. Either change recreates managed containers and may briefly interrupt connections.

If changing the controller fails, configuration recovery may disable peer authorization. Use `padm-docker control peers list` to check.

Xray Reality share URIs include `support-x25519mlkem768=true`; sing-box URIs are unchanged.
Mihomo `v1.19.31` passed direct URI import on isolated Linux amd64 and native ARM64
for Vision and XHTTP with and without VLESS Encryption, and for gRPC with `encryption=none`.
The `v1.19.28` URI importer ignores this field.
The complete input is saved as root-owned `/etc/padm-docker/config/spec.json` with mode `0600`.
Cancellation does not commit; failures restore the previous spec, certificates, and ACME state.
The spec contains secrets and must not be printed or published.

Hysteria2 supports BBR/Brutal, Salamander/Gecko obfuscation, and HTTPS masquerade.
Bandwidth input uses the server perspective; sharing URIs use the client perspective.
During setup, enter `y` for Salamander, `gecko` for Gecko, or `n` to disable obfuscation.
The existing listener's Hysteria2 parameters menu can switch types; a blank password keeps the current value.
Gecko specs require `x-padm-hy2-gecko`; older unobfuscated/Salamander specs remain compatible.
Gecko packet-size options are not exposed, and `local` serving still requires obfuscation to be disabled.
Isolated Linux amd64 checks cover actual IPv4/IPv6 transfers for BBR, Brutal, Salamander, and Gecko.

Menu `4 → 1. Traditional TLS fallback maintenance` manages sites on existing Nginx TLS listeners `21`-`25`, fallback
listeners `27`/`29`, or Hysteria2. Nginx supports a built-in default page, a static
directory, and HTTP/HTTPS 302; Hysteria2 supports managed static content:

```bash
padm-docker edit --site-template notes --preview
padm-docker edit --site-template notes --site-title "My Notes" --preview
padm-docker edit --site-template photos --confirm PADM-DOCKER-EDIT
padm-docker edit --site-template docs --confirm PADM-DOCKER-EDIT
padm-docker edit --site-static /root/public-site --preview
padm-docker edit --site-static /root/public-site --confirm PADM-DOCKER-EDIT
padm-docker edit --site-redirect https://example.com/ --confirm PADM-DOCKER-EDIT
padm-docker edit --site-default --confirm PADM-DOCKER-EDIT
```

The source must be a separate, root-owned directory with a nonempty `index.html`,
not writable by other users. Only common public assets are accepted; managed paths
and their ancestors, hidden/secret files, recognizable PEM private keys, links,
hard links, and special files are rejected. This does not detect every embedded
credential: the directory must contain public content only.
Publication copies content rather than mounting the external source, whose path is
not saved in the spec. Default-page/302 changes and edits without a new source retain
existing static files. The mode applies to all these Nginx listeners without changing
proxy/subscription routes, ports, TLS, or ALPN. Failure and INT/TERM restore content and
spec together; old snapshots without static content retain the current directory.
Deleting the last Nginx listener retains static mode when Hysteria2 remains.
When no site consumer remains, the mode is cleared while static files and other TLS listeners stay.
`status` reports only `site_mode`, not the redirect URL. Old specs remain compatible;
v3 `.site` requires the bundle capability `x-padm-site-content`.
Managed webroot and standalone HTTP-01 are available through certificate management.

Menu `4 → 1 → 8. Built-in static sites` selects `notes`, `photos`, or `docs`. Built-in
themes require an existing v3 Nginx TLS listener (`21`-`25`, including standalone or mixed
sing-box `23`), Xray fallback (`27`/`29`), or sing-box Hysteria2.
Other Reality listeners without a website may coexist. After selecting a theme, enter a
site title or leave it empty for the theme default; `0` returns. CLI `--site-title` requires
`--site-template` and accepts 2–60 characters, rejecting blank titles and control characters.
HTML special characters are escaped. Themes are copied from the
verified control bundle and rejected when the bundled manifest or resources fail
integrity checks. The resulting spec stores only ordinary `site.mode=static`, never
the theme identity or title; select the template again to rename it.
Old bundles keep their existing default, static-directory, and
302 workflows.

For Hysteria2, publish a template or static directory first, then use protocol menu
`4. Hysteria2` to disable obfuscation and select the local site. The CLI uses
`edit --hy2-masquerade <listener-id> local` with `--preview/--confirm PADM-DOCKER-EDIT`.
It validates the published site first and does not create a site or disable obfuscation automatically.
Only managed `data/static` is mounted read-only at `/srv/padm/`; arbitrary `file://`
inputs are rejected. All local listeners share this content with Nginx.
Local requires `site.mode=static` and `obfs=null`; default-page/302 changes or enabling
obfuscation are rejected while it is active. Set masquerade to `off` or HTTPS to
disable local serving; files remain. Hysteria2-only deployments offer static content
without default-page/302, and first setup does not accept local.
Local and Hysteria2-only static preparation require `x-padm-hy2-local-site`.
Old default/HTTPS specs and Nginx static combinations without local keep their
existing bundle compatibility. Website appearance provides no anti-detection proof.

Docker protocol menu items `4. Hysteria2` and `5. TUIC` provide focused edits
for one existing v3 sing-box listener:

```bash
padm-docker protocol hy2-status entry-hy2
padm-docker edit --hy2-bandwidth entry-hy2 brutal 100 50 --preview
padm-docker edit --hy2-bandwidth entry-hy2 bbr --confirm PADM-DOCKER-EDIT
padm-docker edit --hy2-obfs entry-hy2 gecko /root/hy2-password.json --preview
padm-docker edit --hy2-obfs entry-hy2 off --confirm PADM-DOCKER-EDIT
padm-docker edit --hy2-masquerade entry-hy2 https://www.example.com/ --preview
padm-docker edit --hy2-masquerade entry-hy2 off --confirm PADM-DOCKER-EDIT
padm-docker protocol tuic-status entry-tuic
padm-docker edit --tuic-congestion entry-tuic bbr --preview
padm-docker edit --tuic-connection entry-tuic 3s 10s --preview
padm-docker edit --tuic-zero-rtt entry-tuic false --confirm PADM-DOCKER-EDIT
padm-docker edit --tuic-defaults entry-tuic --confirm PADM-DOCKER-EDIT
```

Hy2 rates are server upload/download integers in `1..1000000` Mbps. Brutal menu
defaults are `100/50`; BBR retains the stored rates, and links convert them to the
client direction. Obfuscation accepts `salamander/gecko/off`. Noninteractive enabling
requires a root-owned, mode `0600`, single-link private JSON file with only a
`password` field containing 16–128 letters, digits, `_`, or `-`. Interactive input is
hidden; blank retains the old password or generates one if absent, and `0`/EOF cancels.
Masquerade accepts `off/local/HTTPS_URL`, subject to the local-site prerequisites above.
TUIC durations accept 1–6 positive digits followed by
`ms/s/m/h`; recommended defaults are `cubic/3s/10s/false`. Enabling 0-RTT requires
a menu confirmation of replay risk. These edits cannot combine with spec imports
or other focused edits. Only selected fields change; credentials, TLS, other
listeners, other parameters, quotas, and totals remain fixed. Preview,
confirmation, publication, and recovery reuse the existing transaction.
Full protocol management and host integration combinations remain deferred; TUIC range forwarding is described below.

Docker `Protocols & entry → XHTTP management` manages mode, path/Host, presets,
XMUX, Padding, headers, four native packet/stream limits, and split upload/download for
existing v3 Xray protocol `2` listeners:

```bash
padm-docker protocol xhttp-status entry-xhttp
padm-docker edit --xhttp-headers entry-xhttp true false --preview
padm-docker edit --xhttp-headers entry-xhttp true false --confirm PADM-DOCKER-EDIT
padm-docker edit --xhttp-headers-clear entry-xhttp --confirm PADM-DOCKER-EDIT
padm-docker edit --xhttp-request-headers entry-xhttp '{"X-Trace":"edge value"}' --preview
padm-docker edit --xhttp-request-headers-clear entry-xhttp --confirm PADM-DOCKER-EDIT
padm-docker edit --xhttp-download entry-xhttp 35444 --preview
padm-docker edit --xhttp-download-settings entry-xhttp '{"address":"download.example.net","port":443,"security":"tls","server_name":"tls.example.net","host":"relay.example.net","path":"/down/path","mode":"auto","alpn":["h2"]}' --preview
padm-docker edit --xhttp-download-clear entry-xhttp --confirm PADM-DOCKER-EDIT
padm-docker edit --xhttp-limits entry-xhttp 2000000 20 50 30-40 --preview
padm-docker edit --xhttp-limits-clear entry-xhttp --confirm PADM-DOCKER-EDIT
padm-docker edit --xhttp-mode entry-xhttp stream-up --preview
padm-docker edit --xhttp-path-host entry-xhttp /padm/new-path www.example.com --preview
padm-docker edit --xhttp-advanced entry-xhttp 128-256 2000000 20 50 30-40 true false --preview
padm-docker edit --xhttp-defaults entry-xhttp --confirm PADM-DOCKER-EDIT
```

Menu item `14` sets `auto/packet-up/stream-up`; `15` sets a safe path and nonempty
hostname together. Item `16` sets seven advanced values in this order: Padding,
POST bytes, interval in milliseconds, buffered POST count, stream seconds,
noGRPCHeader, noSSEHeader. It preserves mode and XMUX. Item `17` restores `auto`,
XMUX `16-32/600-900/1800-3000`, Padding `100-1000`, both headers `false`, and limits
`1000000/30/30/20-80`, preserving path/Host. Each focused edit changes only its
selected fields and reuses preview, confirmation, publication, and recovery.

The values are `noGRPCHeader` followed by `noSSEHeader`. `true` removes the
client stream POST gRPC Content-Type or server download SSE Content-Type,
respectively. Packet-up requests already lack that gRPC header. Explicit `false`
is retained; clear deletes both fields and restores defaults. Either explicit
field requires `x-padm-xhttp-headers`. Menu items `10` and `11` set and clear them.
The four limits are `scMaxEachPostBytes`, `scMinPostsIntervalMs`,
`scMaxBufferedPosts`, and `scStreamUpServerSecs`. The first three accept integer
values from `0` through `2147483647`; the last accepts an integer or an ordered
range whose endpoints are in the same bounds. `0` and `0-0` remain in the spec,
server config, and URI, while status reports the core defaults
`1000000/30/30/20-80`. Empty input uses those defaults. Menu items `12` and `13`
set and clear the limits, and explicit fields require `x-padm-xhttp-limits`.
Clear deletes the fields and restores defaults. Other edits retain the limits,
and copies/derivations inherit them. Defaults add no spec or URI fields, and
`limits_explicit` distinguishes explicit values in status.
Other listeners, XMUX, Padding, credentials, subscription/share groups, quotas,
and totals are preserved. Header changes do not establish
camouflage or performance benefits.

Menu item `18` sets the `xhttp.headers` JSON object and `19` deletes it. This
supports client request headers for one existing v3 Xray XHTTP listener, with
1-8 entries. Names use 1-64 letters, digits, or hyphens, start with a letter or
digit, and must be unique without regard to case. Values allow 0-256 printable
ASCII characters. Controls, CR/LF, and non-ASCII are rejected. Reserved names
are Host, Content-Length, Transfer-Encoding, Connection, Keep-Alive,
Proxy-Connection, Upgrade, TE, Trailer, Content-Type, and Referer. Use the
separate Host field; transport-controlled fields cannot be overridden.
Explicit headers require `x-padm-xhttp-request-headers`; status reports
`requestHeaders` and `request_headers_explicit`. URI `extra`, copies, and
derivations retain them, as do presets, advanced edits, and recommended defaults.
Headers appear in share links and subscriptions. They do not configure server
response headers or provide access authentication.

Menu item `20` binds a download port and `21` clears it. First register an extra
port on the same listener through entry port management; it must not be the
default share port. Base ports, default share ports, other listeners' ports,
and unregistered ports are rejected. The edit creates no backend or port
publication. An explicit `xhttp.download_port` requires `x-padm-xhttp-download`.
Status reports `download_port` (`null` by default) and `download_enabled`.
URI `extra.downloadSettings` uses this listener's server and bound port,
automatically following its Reality public key, short ID, SNI, path, Host,
and other XHTTP parameters; download mode is always `auto`. Server configuration
omits this client-only field. Local links, the main subscription, and share groups
use the same output. Presets, advanced edits, and recommended defaults retain
the binding. Copies and derivations keep the source binding but clear it on the
new listener, which needs its own registered extra port.

Menu item `22` or `--xhttp-download-settings <listener ID> <JSON>` sets an explicit
download address and identity in `xhttp.download`. It is mutually exclusive with
`download_port`: setting either form clears the other, and item `21` or
`--xhttp-download-clear` clears both. The complete object requires `address`,
`port`, `security`, `server_name`, `host`, `path`, and `mode`. Address accepts a
hostname or strict IPv4/IPv6; SNI and Host require hostnames, and path follows the
upload rules. Download mode accepts `auto/stream-one/packet-up/stream-up`.
TLS requires `alpn:["h2"]` or `["h3"]`; Reality requires a 43-character base64url
`public_key` and a `short_id` of 1-8 bytes in lowercase hexadecimal. Fields for
the other security type and additional advanced fields are rejected. The object
requires `x-padm-xhttp-download-settings`; status adds `download_settings`
(`null` by default). URI output uses this object's address, security identity,
and three XHTTP fields without inheriting upload advanced parameters. Other
edits retain the object; copies and derivations clear it only on the new
listener, and server configuration omits these client fields.
This manages client metadata only. An external frontend must already exist and
relay to the same XHTTP handler and authentication. It does not construct a
TLS/H3/CDN topology or connect unrelated backends without shared sessions.
The four `sc*` parameters exposed by the current native menu are covered.
On Debian 13 amd64, formal `3.41.5` passed bidirectional SHA256 integrity checks
over ordinary bridge with fixed Xray `26.3.27` and Mihomo `v1.19.28`:
packet-up and stream-up, each at 1 MiB and 8 MiB. The 16 KiB limit applies
to each packet-up POST body; it does not limit stream-up bodies.
On 2026-10-25, formal `3.41.6` with fixed Xray on the same amd64/IPv4/bridge
environment passed independent decryption of raw captures using TLS keylogs.
The 1 MiB, 8 MiB, and 60-second observation cases recorded `65/513/206`
packet-up POSTs and `1/1/1` stream-up POSTs. Positive POSTs ended in both
directions with HTTP `200`; wrong UUIDs produced no origin transactions.
Each mode completed 12 round trips on one business connection, with about
60 seconds observed and business spans of 56.017/56.026 seconds.
Those formal counts cover only the fixed production Xray combination, not
throughput or sustained stability. On 2026-10-26, a local Docker Linux run also
tested 1 MiB real echoes for fixed Xray Reality/TLS and Mihomo Reality across
packet-up and stream-up: each packet-up recorded 65 POSTs and each stream-up
recorded one. The Mihomo cancellation lifecycle and a synthetic server-first-FIN
parser negative control passed. This is not VPS/public Mihomo acceptance.
Formal native h3/CDN, other environments and full management remain `deferred`.
See the [native acceptance record](../docker-native-acceptance-2026-10-18.md)
for the exact scope and evidence.

The same site menu offers ALPN diagnostics, recommended repair, and three manual orders
for fallback listeners `27`/`29`:

```bash
padm-docker protocol alpn-status
padm-docker protocol alpn-status entry-fallback
padm-docker edit --alpn entry-fallback h2,http/1.1 --preview
padm-docker edit --alpn entry-fallback http/1.1,h2 --confirm PADM-DOCKER-EDIT
padm-docker edit --alpn entry-fallback http/1.1 --confirm PADM-DOCKER-EDIT
```

The recommended order is `h2,http/1.1`. Manual choices persist in optional
`fallback_tls.alpn`, keeping the core configuration and share links in sync.
Explicit values require bundle capability `x-padm-fallback-alpn`; old specs keep
their default behavior. Diagnostics report configured/runtime ALPN, fallback/Nginx
consistency, and `repairable`, not a live TLS negotiation result. A nonrecommended
order matching the manual spec is not corruption.
Repair tolerates only the selected inbound's ALPN field drift, checking both full
account input and runtime configuration. Other listeners, accounts, routes,
fallbacks, Nginx, or orchestration drift remain rejected. Preview/cancellation does
not write live files; health failure and INT/TERM restore the original state,
including any pre-repair ALPN drift.

On October 24, 2026, formal `3.41.5` passed 13 native stages on Debian 13 amd64,
ordinary bridge and public IPv4 TCP: both fallback listeners' three ALPN orders,
all three site themes, an escaped title, and a 302 redirect. Independent checks
confirmed 57 positive cases, 35 refusals, main/group HTTPS subscriptions, 88 ALPN
checks and resource-body hashes. Original WS, file permissions and timers were
restored before precise cleanup. IPv6, UDP, reboot and other clients remain outside
this evidence; see the [native acceptance record](../docker-native-acceptance-2026-10-18.md).

The same VPS then upgraded to formal `3.41.6` through Cosign verification and the
official `update` command. Native WS checks passed before and after the upgrade:
two positive cases and two refusals. The URI, business files and permissions,
timers and traffic totals were preserved; only spec release/images changed.
Rollback point `update.SR95Tw` remains. This release includes the fix for valid
unsorted share-group listener lists; other environment checks remain open.

Formal `3.41.6` then passed four bounded TLS stages: 13 native positive cases and
8 refusals, plus 6 positive and 3 refused manual HTTPUpgrade controls. Four main/group
subscription downloads and four wrong-token refusals passed, including a share group
created from seven valid unsorted listeners. Protocol 23 native URI import in Mihomo
`v1.19.28` remains unsuccessful. Fixed source and three offline fake-identity controls
with the same binary locate the cause: the importer retains `network=httpupgrade`,
but only `network=ws` selects the upgrade path, so it falls through to plain TCP/TLS.
Production URIs remain unchanged; manual controls do not count as native import success.

On 2026-10-25, the same release passed seven TLS entry combinations using fixed
Xray `26.3.27/d2758a0` with explicit URI-to-config conversion. Original WS, combined
entries, pure sing-box 23 and restored WS passed 19 positive cases and 11 authentication
refusals, plus four strict HTTPS subscription downloads, four wrong-token 404s,
two group business checks and 11 wrong-SNI refusals. Positive URIs came from actual
downloads; only connection addresses and ports were mapped. Four archives and four
physical tampering controls passed offline verification; original materials, permissions,
timers and traffic totals were preserved, and test resources were removed.
This is converted interoperability, not native Xray URI import, and does not remove
the Mihomo HTTPUpgrade limitation. Transparent proxying stays disabled; other
environments and complete management remain unverified.

Routing checks on the same bundle verified the original WS and 15 business stages:
50 positive cases and 31 refusals across selective/global SOCKS5 TCP on both cores
and post-resolution blocking on sing-box, including authentication refusal, upstream
unavailability and recovery. Finalization failed on changed Docker veth addresses,
so the original run remains failed. Original files and timers were restored; a
separate WS probe passed one positive case, one refusal and strict website TLS/200.
Test resources were then removed precisely.

A separate five-stage check on the same release passed pure sing-box routing with
Nginx website and subscription publication: 8 positive cases and 7 refusals,
including one positive and one refused manual HTTPUpgrade control. Main/group
HTTPS downloads and wrong-token refusals passed; all five website bodies matched
the actual Nginx inline return. Actual client inputs, recovery and precise cleanup
were independently checked. Earlier failures remain; system-resolver fallback and
native HTTPUpgrade import are not proved by this check.

A separate four-stage system-resolver fallback check on the same release passed
6 positive cases and 4 refusals. Two random names first completed business requests
through the actual container hosts file; adding only exact DNS selectors then
produced core-ended SERVFAIL and dropped-query failures, with no system fallback
or origin arrival. Client timeouts never counted as refusals. An unmatched name
passed before and after both failures. Container hosts and host resolver files
were restored. Three earlier evidence or ordering failures remain archived; this
check covers fixed-client IPv4 TCP, without extending UDP or reboot support.

A separate four-stage UDP check passed 9 positive cases and 7 refusals for TUIC,
SS2022 base/default-alias ports, alias removal and WS recovery. Eleven valid UDP
nonces arrived exactly once; three refused nonces never reached the origin.
Independent checks matched 22 actual client configurations/URIs and the running
binary. Original files and timers were restored and test resources removed.
Earlier failures remain archived. Hy2 probes were not repeated; automatic
hopping, IPv6 and reboot remain outside this evidence.

A subsequent combined routing/UDP check completed one actual VPS reboot. Four
stages (original WS, before reboot, after reboot, restored WS) passed 14 positive
cases and 10 refusals. Pure sing-box hosts/DNS, post-resolution IP blocking,
authenticated SOCKS5 TCP routing, and IPv4 UDP on TUIC and SS2022 base/default-alias
ports recovered naturally with the same managed container identities and a changed
boot ID. Six TCP origin nonces and 18 valid UDP nonces arrived exactly once; six
refused UDP nonces never arrived. Independent offline checks of all four archives,
24 separate captures and 10 artifact-tampering controls passed. Original files,
timers and WS were restored, and test resources were removed. Three earlier failed
runs remain archived. Transparent proxying stayed disabled; this does not prove
enabled-transparent reboot, SOCKS UDP, IPv6, automatic hopping, other clients or
completion of the overall plan.

Select `9=Shadowsocks` after choosing sing-box for SS2022 multi-user AES-128.
It publishes TCP and UDP on the same port for either address family and needs no TLS.
Confirmation generates independent server/user keys; UUID is the shared traffic identity.
`ss://` links percent-encode the combined password according to SIP002.
Quota exhaustion removes the runtime inbound; lifting the quota restores the original keys.
Select `10=TUIC` for a single UDP listener with dual-stack support and managed TLS.
UUID is the user ID, password, and traffic identity. Congestion control supports
`cubic`, `bbr`, and `new_reno`; editor item `14` changes congestion, authentication
timeout, heartbeat, and 0-RTT. Defaults are `cubic`, `3s`, `10s`, and disabled 0-RTT.
`tuic://` uses `h3`, native UDP relay, and strict TLS verification. A single dual-stack listener can use the range-forwarding manager below.

Complete v3 `configure` specs may include `accounts` to append 1-256 independent
accounts without replacing the original self-use credentials. Each account requires
`id`, `name`, `enabled`, `uuid`, `password`, `shadowsocks_password`, and `listeners`.
The lowercase UUID `id` is the stable traffic identity; authentication UUID/password
are independent, and `listeners` references existing listener IDs. An SS2022 user key
is required only when associated with Shadowsocks; otherwise it must be `null`.
Identities and credentials of the same kind must be unique and must not reuse self-use
credentials or an SS server key. Naive uses the stable ID as username; TUIC uses the
authentication UUID and independent password. Traffic and quota aggregate by stable
ID across cores. Disabling retains identity and totals but removes runtime authentication
and output nodes; credential rotation and configuration restoration do not reset or
roll back accumulated traffic. Both cores' `config/*/users.base` retain disabled
credentials and are root-owned `0600`, like the complete spec. Runtime configs strip
private account metadata. Bundles without `x-padm-accounts` reject these specs during
configuration, update, and restoration. The menu and `padm-docker account` now support
listing, creation, name/listener editing, copying, enable/disable, deletion, and credential
rotation. Each change uses a private draft, candidate validation, backup, and health-check
transaction; untouched accounts, totals, and quotas remain unchanged, while copies receive
new stable identities and credentials. Ordinary output includes self-use and enabled
accounts under the deployment-wide token, not independent share subscriptions. Share groups,
per-account publishing authorization, pure-content copy, and business backup/restore are
available through the account and subscription workflows; host integration and the
complete multi-server lifecycle remain deferred.

Use menu `6 → 9` or `padm-docker edit` to change public ports,
server addresses, address families, node names, Reality targets/SNI, WS paths, or
subscription enablement. It uses a private draft, a value-redacted diff, and candidate
validation before confirmation and commit. Unselected listeners, UUIDs, keys, tokens,
certificates, host integrations, and accumulated traffic remain unchanged.
The menu can copy or delete an existing protocol listener by listener ID; the primary
core must retain at least one listener. Reality can be copied to the other core.
Hysteria2, AnyTLS, NaiveProxy, Shadowsocks, and TUIC can only be copied within sing-box.
An existing v3 deployment can add supported protocols through menu `3 → 8 → 14` or
`edit --protocol-add`, reusing the source identity and explicitly authorized accounts.
Adding the first TLS listener also requires its domain and managed certificate.
Shadowsocks method, server key, UUID, and existing listener identity remain frozen.
Ordinary editing and `--spec` still reject manual key changes; use the focused
self-use user-key or server-key rotation below.
Deleting the last secondary-core listener disables that core; existing listener ownership cannot change.
Copies reuse the original credentials. Listeners with the same
UUID share accumulated traffic and quota rather than creating separate users.
Add and delete operations must be confirmed in separate transactions so a replacement
cannot bypass existing identity or internal-port protections.
An older deployment without `config/spec.json` requires its complete original spec;
missing fields, additional accounts, custom routes/sites, or mismatched mount roots
reject editing rather than reconstructing an invented spec from runtime summaries.

Docker menu `3 → 8 → 19. Shadowsocks self-use user-key rotation` or these commands
rotate only `shadowsocks.user_password` on one existing v3 sing-box protocol `30` listener:

```bash
padm-docker edit --rotate-ss-user <listener-id> --preview
padm-docker edit --rotate-ss-user <listener-id> --confirm PADM-DOCKER-EDIT
```

The server key, UUID, other listeners (including those sharing the UUID), independent
account keys, quotas, and accumulated traffic remain preserved. After release verification,
trusted ops OpenSSL generates a canonical Base64 16-byte key, trying at most 32 times and
rejecting collisions with existing SS server, self-use, and independent account keys.
Secrets stay out of process arguments and logs. The main subscription and selected self-use
URI update; independent account share-group content stays unchanged. Clients must reimport
the URI; draining existing connections is not promised. This edit cannot combine with
other focused edits or `--spec`, and adds no schema or capability marker.
The focused contract, Docker amd64 dual-stack TCP/UDP probes, and all 61 integrated
contracts passed; complete management stays `deferred`.
See [plan 3D.24](../docker-menu-parity-plan.md#3d24-shadowsocks-逐入口自用用户密钥轮换).

Menu `3 → 8 → 20. Shadowsocks server-key rotation` or `edit --rotate-ss-server <listener-id>`
reuses the same focused transaction and preview/confirmation options, changing only the selected
listener's `shadowsocks.server_password`. Self-use and independent account user keys, UUIDs,
other listeners, share authorizations/tokens, quotas, and accumulated traffic stay unchanged.
The main subscription and every account URI for that listener change, so all its clients must
reimport them. Other listeners sharing the UUID are not rotated; draining existing connections
is not promised. Ordinary `--spec` key freezing remains. Verified release `3.41.5` passed
native public IPv4 TCP testing on Debian 13 amd64 with ordinary bridge networking:
fixed Mihomo `v1.19.28` imported the original SIP002 URIs, with 17 positive and 9 rejected
cases across five phases. An independent offline verifier checked both listeners, self-use
and independent accounts, exact field preservation, traffic totals, and original WS restoration.
This evidence excludes UDP, IPv6, reboot, and draining existing connections; host integrations
and full management remain outside scope. See
[plan 3D.25a](../docker-menu-parity-plan.md#3d25a-两类-ss-密钥轮换原生验收).

```bash
padm-docker edit
padm-docker edit --spec /root/original-spec.json --preview
padm-docker edit --spec /root/original-spec.json --confirm PADM-DOCKER-EDIT
```

Advanced listener management at `3 → 8` lists stable listener IDs, cores, protocols, addresses/ports,
and address families. It displays all or selected share links and opens the existing
editor for changes, copies, or deletion. `protocol links` writes only URIs to stdout,
including when HTTPS subscription publishing is disabled. It does not enable publishing,
change the managed spec, or collect traffic. Missing full input or runtime drift rejects
the read; local links contain user credentials and must not be published.

```bash
padm-docker protocol list
padm-docker protocol links
padm-docker protocol links vless-reality
```

Extra entry port management at `3 → 6` adds, removes and replaces extra published ports for existing listeners.
Optional v3 `port_aliases` contains up to 16 `{listener_id, public_port}` entries.
Each alias retains the listener's TCP/UDP transports, address families, authentication,
account identity and traffic counters. TLS still terminates at the existing Nginx frontend;
bridge Reality 443 aliases expose the same complete SNI frontend, not an isolated branch.
No extra core, certificate, host privilege or arbitrary destination forwarding is added.

```bash
padm-docker protocol port-alias-status
padm-docker edit --port-alias entry-reality 8444 --preview
padm-docker edit --port-alias entry-reality 8444 --confirm PADM-DOCKER-EDIT
padm-docker edit --port-alias-replace entry-reality 8444 8445 --preview
padm-docker edit --port-alias-replace entry-reality 8444 8445 --confirm PADM-DOCKER-EDIT
padm-docker edit --port-alias-default entry-reality 8445 --confirm PADM-DOCKER-EDIT
padm-docker edit --port-alias-default entry-reality base --confirm PADM-DOCKER-EDIT
padm-docker edit --port-alias-remove entry-reality 8445 --confirm PADM-DOCKER-EDIT
```

Replacement requires an existing alias and a different, nonconflicting new port.
It preserves alias order, the default-share marker and all other spec fields.
Replacing a selected alias updates its links in the same transaction;
preview, cancellation and failed application leave the current deployment unchanged.
Share links retain the original public port unless an existing alias is selected.
The selected alias stores `share_default: true`, at most once per listener. Local URIs,
the main subscription and share groups use the same selected port without adding nodes
or changing accounts or credentials. `base` or deleting the selected alias restores the
original public entry, including the SNI frontend on port 443 during Reality coexistence,
not the private backend. Other listeners, including TCP/UDP uses of the same number,
remain unchanged. Conflicting published TCP or UDP ports are rejected; separate
TCP and UDP uses of the same number are allowed. WS/SSH Fail2ban, TUN/TProxy and host-network
coexistence reject aliases for now; existing WireGuard/control-plane Fail2ban can coexist with aliases.
Ordinary spec editing cannot add or replace aliases;
deleting a listener removes its aliases, while copying does not inherit them.
Older control bundles without `x-padm-port-aliases` reject alias-bearing configuration,
updates and restoration. Default-share markers also require `x-padm-port-alias-default`;
rollback to an older bundle that ignores the selection is rejected.
IPv4/IPv6 publishing is verified in an isolated amd64 Linux daemon;
public hosting, native hosts and arm64 remain unverified;
the complete internal capability `207` stays `deferred`.

The port-hopping manager at `3 → 8 → 11` configures, starts, stops, clears and shares active Hy2/TUIC range DNAT.
Optional v3 `port_hopping` stores `{listener_id, range_start, range_end, ipv4, ipv6}`
in the specification, deployment record and Compose `x-padm-port-hopping` metadata.
The current scope is one sing-box core,
one dual-stack Hy2 or TUIC listener, an existing traffic directory, no host integrations and
no additional running services. An inactive ACME profile may remain defined.
Aliases, the control plane, HTTP relay, HTTP-01 and enabled subscriptions are rejected.
The range must exclude the target public port, and both addresses must be canonical
native IPv4/IPv6 addresses assigned to the host.
TUIC hopping configurations require bundle capability `x-padm-port-hopping-tuic`;
old bundles retain compatibility with the original Hy2 subset.

Saving does not enable rules; run `start` explicitly. Startup checks the configuration
and actual container, collects cumulative traffic and applies quotas; an independent
supervisor maintains the dual-family rules. Run `stop` and confirm cleanup before editing
or clearing the settings. `restart/update/rollback/down/uninstall` use supervisor coordination;
unconfirmed shutdown or handoff refuses further changes and preserves cumulative traffic
and failure evidence. INT/TERM during initialization stops further writes and reaps direct
children. The session is removed only after resource verification and a clean shutdown
receipt; earlier interruption retains unverified evidence and blocks ordinary changes.
Startup/restart share a 120-second progress budget; update/rollback share 840 seconds
across handoff. Expiry stops authorization and successful acknowledgements and requests
TERM for the original Bash. Shutdown shares one 90-second wait budget; timeout retains
unverified evidence without forced KILL or automatic takeover. Active sessions have no
lifetime limit. These budgets bound supervisor progress and waiting, not kernel cleanup.
Replace the listener and addresses below with local values:

```bash
padm-docker edit --port-hopping entry-hy2 30000 30001 198.18.1.1 2001:db8:1::1 --preview
padm-docker edit --port-hopping entry-hy2 30000 30001 198.18.1.1 2001:db8:1::1 --confirm PADM-DOCKER-EDIT
padm-docker port-hopping status
padm-docker port-hopping start
padm-docker port-hopping share
padm-docker port-hopping share 30001
padm-docker port-hopping stop
padm-docker edit --port-hopping-clear --confirm PADM-DOCKER-EDIT
```

`up`, Docker daemon restarts, systemd and whole-machine reboots do not automatically
restore supervision. SIGKILL, noncooperative replacement and unknown remnants preserve
evidence without automatic takeover. Conflict checks cannot exclude simultaneous outside
rule changes.
SIGKILL of the lock-owning Bash was verified on isolated amd64: the child exits and
removes dual-family NAT/state, while its exited container, owner, stage and deployment
lock remain. Status, stop, start and lifecycle operations refuse takeover.
Menu `8`, "Verify and clean up a residual session", previews before asking for confirmation.
The equivalent commands are:

```bash
padm-docker port-hopping recover --preview
padm-docker port-hopping recover --confirm PADM-DOCKER-HOPPING-RECOVER
padm-docker port-hopping start
```

`recover` accepts only a managed terminal state in the same boot and namespace realm
after both original manager and Bash process generations have ended. The bound stage path,
child, target and root/data/net projection must match, as must the deployment lock;
the exact child container must have exited with code `0`, the hopping state must be absent,
and neither NAT family may retain session resources. A live owner, unknown record,
nonzero exit or any drift refuses cleanup and preserves the evidence.
Verification and cleanup hold directory descriptors and reject replacement during this operation.
Existing evidence does not record historical stage/session inodes or detect an earlier rebuild
with identical contents; the cooperative lock does not defend against arbitrary privileged replacement.
Preview returns `state:"recoverable"`; confirmed cleanup returns `state:"stopped"`.
Both preserve the complete range in `saved`. Cleanup retains the saved specification,
accounts and traffic totals, and does not delete conntrack. Explicit `start` creates
a fresh process generation and challenge. Old JSON, environment variables or tuples
do not authorize cleanup; deleting owner/lock evidence cannot force recovery.

If an old deployment lacks `config/spec.json`, first match the retained complete original
input against the actual deployment:

```bash
padm-docker edit --spec /root/padm-original.json --confirm PADM-DOCKER-EDIT
```

Then save the hopping range and run `start` explicitly. Missing input or mismatched account
identity refuses adoption. Adoption preserves `users.base`, the running account
configuration and cumulative traffic; saving the range does not enable rules.
It does not reconstruct a complete specification from runtime configuration or environment
variables. Unattended recovery remains `deferred`.
On Linux amd64, TUIC recovery and the Hy2 automatic hopping/recovery chain passed
in 53.793 and 105.324 seconds; all 57 contract groups passed in 428.109 seconds,
including 141 supervisor checks. For recovery changes, prefer
`docker-port-hopping-recovery-real` with Jobs 2, focused on TUIC cleanup and reactivation.
Use `docker-port-hopping-auto-real` for Hy2 automatic hopping.

`share` emits a link only when the active target matches the saved specification;
it does not write static subscriptions. Without an argument, Hy2 uses a range URI,
while TUIC uses a normal `tuic://` link for the first port. `share <port>` or menu
item `7` emits a normal single-port link for either protocol within the active range,
preserving authentication and TLS. TUIC range DNAT lets clients choose any port;
the fixed sing-box TUIC client lacks `server_ports`/`hop_interval`, so no nonstandard
range URI or automatic client hopping is offered. A Hy2 sing-box client using
`server_ports` and `hop_interval=5s` passed dual-family requests across both ports
in the same process on isolated Linux amd64. The shared Hy2 URI generator emits equal
`upmbps/downmbps` and `up/down` values in the client direction, fixing lost Brutal
bandwidth during Mihomo raw URI import.
The `docker-port-hopping-share-real` selector (Jobs 2) uses official Mihomo
`v1.19.28` to import the original share URIs: Hy2 Brutal + Salamander/Gecko range hopping
and normal TUIC links for both range endpoints, with dual-family HTTP,
wrong-account rejection and clean shutdown. Stop probes include the actual bandwidth
and obfuscation settings, prove successful connections before stopping, then use fresh
processes to verify rejection. The client is a test dependency only. Each of the three
scenarios uses a separate netns, daemon and data directory, running within the entrypoint Jobs limit.
Hy2 uses the client's native default 30-second random port selection, observing
for at most 300 seconds and stopping once both families have used both ports.
These fixed-client imports and actual connections passed on local Linux amd64;
the implementation plan records the evidence.
Other client imports, native hosts, arm64, public networks,
automatic TUIC client hopping, old-session drainage and complete Hy2/TUIC hopping remain `deferred`.

CDN entry management at `3 → 7` overrides client connection addresses for
existing `2` Reality XHTTP and `21/22/23/24/25` WS/HTTPUpgrade/gRPC TLS listeners in local links, the main subscription
and share groups. Optional v3 `cdn_entries` contains up to 16 `{listener_id, addresses}`
records, each with 1–16 unique IP addresses or domain names. URLs, ports, whitespace
and empty items are rejected. Without an override, links use the original server.
Multiple addresses produce nodes in input order with `-1`, `-2` name suffixes.
Accounts, effective share ports, SNI, Host, paths or gRPC serviceName and `h2` remain unchanged; HTTPS subscription
URLs retain the original TLS domain.

```bash
padm-docker protocol cdn-status
padm-docker edit --cdn-entry entry-ws edge.example.com,203.0.113.8 --preview
padm-docker edit --cdn-entry entry-ws edge.example.com,203.0.113.8 --confirm PADM-DOCKER-EDIT
padm-docker edit --cdn-entry entry-grpc edge.example.com,203.0.113.8 --preview
padm-docker edit --cdn-entry-clear entry-ws --confirm PADM-DOCKER-EDIT
```

Clearing restores the original address. Listener deletion removes its override;
copying does not inherit it. Changes use the existing candidate, confirmation and
failure recovery transaction, which recreates services on commit. Ordinary spec
editing cannot replace CDN overrides. Bundles without `x-padm-cdn-entry-addresses`
reject configuration, updates and restoration containing the field.
Overrides for `24/25` also require `x-padm-cdn-grpc-tls`; protocol `2` requires
`x-padm-cdn-xhttp` and changes only the upstream connection address, preserving Reality
identity and any independent download address. Older bundles can still handle the original
three override types and gRPC TLS listeners without overrides.
Protocol `2` still needs an upload address that accepts Reality handshakes. To use a CDN's
HTTPS/H3 edge for downloads, set the download address, TLS identity, and `alpn:["h3"]` with
`--xhttp-download-settings` and route the download frontend to the same XHTTP handler as the upload.
Reality gRPC and other TCP/UDP protocols remain outside this scope.
The native CDN menu points to this download setting for H3.
See the [Docker deferred ledger](../docker-deferred-status-2026-11-04.md) for tested combinations.

Newly generated `21/22/23` TLS frontends reject an incorrect Host. Without CDN
fields, the complete legacy Nginx output remains valid for reads and edit baselines;
the next confirmed configuration edit generates the new output. CDN fields require
the new output. Partial Host-gate removal or other manual drift is rejected.
Listeners `24/25` retain managed Nginx HTTP/2 gRPC proxying and strict TLS identity.
The WS Host/path gates do not apply to gRPC. The v3.44.12 managed Xray VLESS gRPC
workflow passed public acceptance on Cloudflare over IPv4.

`--preview` does not commit, collect traffic, or start/stop application services.
Validation still verifies the release, pulls images, and runs candidate checks.
`edit` verifies the current deployment version rather than latest by default; it also
accepts the same-version release asset options below.
First configuration writes `schema_version: 3`; `configure` and backup restoration
continue to accept v1/v2. Editing first verifies the original spec against the deployment,
then migrates only the private draft to v3 without changing managed state before confirmation.
V3 records each listener's `core` and `core.secondary_type` (`null` for a single core),
with up to 16 listeners across both cores. V2 remains single-core.
Both cores support Reality Vision/gRPC, VMess HTTPUpgrade TLS, and direct Trojan.
Xray also supports Reality XHTTP, VLESS and VMess WS TLS, gRPC TLS, and traditional
TLS fallback. sing-box also supports Hysteria2, AnyTLS, NaiveProxy, Shadowsocks,
and TUIC.
The wizard offers either primary-core order, with a Reality listener on the secondary core.
Initial WS TLS on a secondary Xray core requires a complete v3 spec; existing Xray WS listeners can still be copied.
Dual-core deployments currently require ordinary bridge networking and no host integrations.
Single-core deployments containing Hysteria2, AnyTLS, NaiveProxy, Shadowsocks, or TUIC
also reject host integrations for now.
Each listener keeps its `listener_id`;
migration preserves `vless-reality` / `vless-ws`, while new listeners use `entry-*`.
Each WS listener gets independent `websocket.backend_port` and `websocket.tls_port`
values without renumbering existing internal ports. Listener identities, public ports,
and internal listeners in the same container network namespace must not conflict.
For an existing managed deployment, `edit --spec` supports these listener changes
through the same preview, validation, and confirmation flow.
Deleting the last eligible publishing listener (`21–25/27/29`) disables subscription publishing. The spec retains TLS
while traditional TLS fallback, Hysteria2, AnyTLS, NaiveProxy, TUIC, or direct Trojan remains; otherwise it sets `tls` to `null`,
while retaining TLS/ACME files and the token. Shadowsocks does not require TLS.
All 16 public protocols support installation, adding and editing listeners, copying,
deletion, rebuilding with the same identity, and sharing within their core and configuration
limits. [Public protocol matrix](../docker-feature-matrix.md#公网协议)
In a deployment with WS Fail2ban, ordinary edits can still add or remove unprotected
VLESS WS TLS listeners (`21`) and change their public ports. Ordinary edits preserve the
identity, core, address family, public and internal TLS ports, and domain of each protected
listener. Use Fail2ban menu item `20` to migrate the public port of an eligible protected listener.
3A.3 has passed local dual-core transaction, PTY, traffic, update/rollback, and Linux permission regressions. Real signed releases,
application images, and dual-architecture client connectivity remain unverified.

Docker menu `8 → 2. VLESS Encryption experiment` manages one existing schema 3
Xray Reality Vision (protocol `1`) or Reality XHTTP (protocol `2`) listener:

```bash
padm-docker protocol encryption-status
padm-docker protocol encryption-status <listener-id>
padm-docker edit --vless-encryption <listener-id> enable --preview
padm-docker edit --vless-encryption <listener-id> enable --confirm PADM-DOCKER-EDIT
padm-docker edit --vless-encryption <listener-id> disable --confirm PADM-DOCKER-EDIT
```

The optional `vless_encryption` object stores `decryption/encryption`; omission means
`none`. The fixed server/client forms are `mlkem768x25519plus.native.600s.<seed>` and
`mlkem768x25519plus.native.0rtt.<public>`. Trusted Xray generation is followed by
ML-KEM-768 pair validation through Python/OpenSSL inside ops. Private files use `0600`;
secrets stay out of command arguments, previews, status, and logs. Ordinary edits and
same-core copies preserve the object; copies to unsupported cores or protocols are rejected.
Enabling an enabled listener or disabling a disabled listener returns `15`.
Rotate by disabling and enabling again, then reimport the sharing URI after every change.
Updates/rollbacks with experimental configuration reject bundles lacking
`x-padm-vless-encryption`. Fixed Xray `26.3.27` and Mihomo `v1.19.28` passed the
Linux amd64 experiments and the released `3.41.5` public-network enable/disable
matrix on Debian 13 amd64, including listener isolation, invalid-identity rejection,
and restoration. A real host reboot with both bridge listeners encrypted also passed:
the original containers started automatically, retaining the same URIs, material permissions,
schedules, and traffic totals. Other clients, algorithms, arm64, and encrypted reboots
with other topologies remain unverified. The complete feature remains `deferred`; see
[acceptance evidence in plan 5C.10](../docker-menu-parity-plan.md#5c10-vless-encryption-有限实验管理).

For offline use, provide all three assets from the same Release:

```bash
padm-docker setup --manifest /root/release-manifest.json \
  --bundle /root/release-manifest.sigstore.json \
  --control-bundle /root/padm-docker-bundle.tar.gz
```

Non-interactive deployments can still use `configure --spec /root/padm-docker-config.json`
with the same release options. `release` emits verified `release` and `images` inputs, not
a signature proof; `configure` re-verifies the original assets. Replace example fields with
actual parameters, and match every release field and image to the verified manifest.
Updates and rollbacks preserve the complete spec; corrupt or mismatched specs are rejected
before stopping the current services.
V3 editing also requires both the installed control scripts and trusted release assets
for the deployed version to support v3. Refresh to published v3-capable control scripts
first when they do not. The spec's `schema_version` and runtime `formats.config`
are versioned separately; the latter remains `1`.

To pin the control script version, use `install --ref <40-character commit SHA>`. A CI release provides `release-manifest.json`, its Cosign signature in a Sigstore v0.3 bundle (`release-manifest.sigstore.json`), and `padm-docker-bundle.tar.gz`. Updates verify the manifest signature and check the control bundle against the SHA-256 digest recorded in the manifest.

Automatic releases require unpublished changes to installation entrypoints, runtime scripts, Docker configuration, image inputs, or version locks on `main`. Docker tests, release scripts, and CI changes also trigger `Release` checks; without pending runtime changes, only Docker contract tests run, with no version bump, image build, or published assets. After a failed release, pushing a test or CI fix resumes the unpublished runtime changes. Documentation-only changes do not trigger a run. PR `Docker CI` first runs independent actionlint and Shell syntax gates, then selects `ci-pr` or the full `ci` native regression profile from the changed paths before building images; `Release` runs the full gate and read-only checks of the locked base image indexes for both architectures and Debian snapshot metadata before bumping the version. Apt verifies snapshot signatures during the actual build. After the version commit, the current Release run hands off to a new run so the same version is not built twice. Release runs process the latest `main` serially and publish only after all three assets are uploaded and their digests verified. Run `Release` manually to retry or explicitly publish; PRs and manual image validation use `Docker CI`.

CI decides which images to rebuild from each image directory, shared build definitions, and the lock values it consumes. Unchanged images keep the `tag@sha256` from the previous verified manifest, so their tags may precede the current script version; they only go through manifest, platform digest, and signature verification. Each changed image is built once per architecture, tested by its exact digest, then merged and signed. Without a trustworthy baseline, CI rebuilds all images. SBOM, provenance, and image signatures stay in the OCI registry; diagnostic JSON files remain in Actions artifacts for 7 days instead of being duplicated as Release attachments.

The example file contains placeholder digests, keys, and tokens and must not be used as-is. Production image references must use the version tag and digest from a CI Release, for example `ghcr.io/neil1123-vip/padm-xray:3.1.9@sha256:<digest>`; do not use `latest` or hand-edit an unpublished tag on the host.

## Five Images

All five images are defined by Dockerfiles in this repository. Each runtime uses a digest-pinned Debian 13 `distroless/static` base, with glibc, libraries, and tools exported as needed from a fixed Debian snapshot and official build images. Base digests, the snapshot, upstream versions, and architecture checksums are locked in `versions.lock`, then CI builds multi-architecture `amd64/arm64` images. CA certificates, time zones, NSS, licenses, and a BusyBox diagnostic shell remain; package managers are excluded. Xray retains the complete Geo data. One image may be reused by multiple Compose services, while long-running responsibilities remain separate containers. See the [distroless acceptance record](../docker-distroless-baseline.md) for measured sizes and local verification limits.

| Image | Responsibility | Host integration |
| --- | --- | --- |
| `padm-xray` (`xray`) | Xray-core, Geo data, and core configuration validation. | Regular bridge container. |
| `padm-sing-box` (`sing-box`) | sing-box, configuration validation, and its protocol runtime. | Regular bridge container. |
| `padm-nginx` (`nginx`) | TLS, WebSocket, reverse proxy, and static entry. | Publishes only the selected entry ports. |
| `padm-ops` (`ops`) | ACME, subscription control, Geo/sync, and other operations, run as long-lived or one-shot Compose services as appropriate. | No Docker Socket. |
| `padm-net` (`net`) | WireGuard, Fail2ban, TUN/TProxy, and port/firewall integration tools. | Uses `NET_ADMIN`, host networking, or `/dev/net/tun` only in explicit `net-*` profiles. |

The `net` image contains the feature tools, but WireGuard, forwarding, TUN, and firewall objects still belong to the host kernel. These privileged profiles are disabled by default. Regular services do not use `privileged`, `SYS_ADMIN`, or the Docker Socket.

## State and Daily Control

The Docker deployment stores its state in `/etc/padm-docker`. The host's `padm-docker` command manages the deployment through Docker CLI and Compose. Application containers run without access to the Docker socket. The native deployment uses its own state root at `/etc/padm`.

| Path | Purpose |
| --- | --- |
| `/etc/padm-docker/mode` | 🏷️ `docker` mode marker used for mutual exclusion and uninstall protection. |
| `/etc/padm-docker/bundle` | 🔗 Atomic pointer to the currently verified control bundle. |
| `/etc/padm-docker/deployment.json` | 🧾 Current release, profiles, ports, and five image digests. |
| `/etc/padm-docker/compose.json`, `images.env` | 🐳 Current Compose configuration and pinned image references. |
| `/etc/padm-docker/config/`, `data/`, `secrets/`, `backups/` | 💾 Configuration, runtime data, secrets, and update/uninstall backups. |

Menu entry points and feature support are tracked in the feature matrix and `docker/contracts/features.json`. Update both when adding a Docker feature. [Feature matrix](../docker-feature-matrix.md)

### Common Commands

| Command | Purpose |
| --- | --- |
| `padm-docker status` | View deployment, container, and protocol status. |
| `padm-docker logs` | View service logs. |
| `padm-docker validate` | Validate the current configuration. |
| `padm-docker assess` | Assess upgrade compatibility. |
| `padm-docker up`, `padm-docker down`, `padm-docker restart` | Start, stop, or restart services. |
| `padm-docker update` | Verify the release and update the images and host control scripts. The update attempts recovery on failure. [Updates](#updates) |
| `padm-docker rollback` | Restore the most recent managed update snapshot. [Rollback](#rollback) |
| `padm-docker uninstall` | Remove project containers and the control command while retaining configuration, data, backups, and images. [Uninstall](#uninstall) |

Menu `7 → 3. Fail2ban protection` provides status, single-IP unban, WS site-scan
enabling/disabling and settings for managed Fail2ban:

```bash
padm-docker fail2ban status
padm-docker fail2ban unban 192.0.2.7
padm-docker fail2ban unban 2001:db8::7
padm-docker fail2ban enable 443,8443 6 600 3600 --preview
padm-docker fail2ban enable 443,8443 6 600 3600 --confirm PADM-DOCKER-EDIT
padm-docker fail2ban settings 443,8443 8 900 7200 --confirm PADM-DOCKER-EDIT
padm-docker fail2ban disable --preview
padm-docker fail2ban disable --confirm PADM-DOCKER-EDIT
padm-docker fail2ban verify-source entry-ws 203.0.113.7
padm-docker edit --fail2ban-port entry-ws 8443 --preview
padm-docker edit --fail2ban-port entry-ws 8443 --confirm PADM-DOCKER-EDIT
```

Fail2ban submenu item 20 migrates a protected WS public port through
`edit --fail2ban-port <listener ID> <new public port>`. It requires exactly one direct WS 21
listener, one Fail2ban integration and one protected port. The new port must differ; aliases,
Reality stream coexistence, SSH/control or other host integrations and combined edits are rejected.
Only the listener public port and jail port change. Other specification fields stay fixed;
ordinary imports and general port edits still reject this transition. The transaction verifies
old jail cleanup, obtains fresh source proof for every address family on the new port, then starts
protection. Rollback also requires a new challenge on the old port. Accounts, certificates,
internal ports and SQLite ban history remain; clients must use the new public port.
Preview does not switch services.
The WS jail runs as `0:10001` to read managed Nginx logs; directory and file permissions
remain `0750/0640`. The exact legacy Compose body without `user` is accepted only for
ownership cleanup and managed migration. Normal startup requires the new body.
Deployments combining legacy WS and control protection must disable WS through the old
managed entry point before upgrading.

Fail2ban submenu item 12 and `padm-docker fail2ban ssh preflight [--json]`
provide a read-only host check. The usual Linux/root and local rootful Docker
preflight applies; an installed deployment is not required. Default `sshd -T`
ports must match actual TCP listeners explicitly owned by `sshd`. The command
only lists current-boot `sshd`/`sshd-session` journal or fixed `/var/log/auth.log` and `/var/log/secure`
candidates, without printing authentication messages, accounts or source addresses.
File candidates must be root-owned regular files without symlink components or
group/other write permission. Missing tools, port mismatch or no candidate returns `10`.
JSON declares `scope=host-preflight-only`, `source_verified=false`,
`runtime_configuration_verified=false` and `jail_ready=false`. Default configuration
does not verify a running instance using `-f/-p/-o` or socket activation;
equal ports do not verify bind addresses or address families. Historical logs are
not fresh source proof. This check saves no credential, changes no configuration
or firewall rule, and does not enable an SSH jail.

Fail2ban submenu item 13 verifies a live external source for an explicit host SSH endpoint:

```bash
padm-docker fail2ban ssh verify-source 198.51.100.10 2222 203.0.113.7
```

The target must be configured on the host and the independent client must use the same
address family. Host/Docker addresses, loopback, mapped and unscoped link-local
addresses are rejected. The host needs `python3`, `ip`, `ss` and `journalctl`.
After `source-challenge` prints a random username, run on the external client:

```bash
python3 -B docker/lib/ssh-source-client.py 198.51.100.10 2222 padm-source-<48-hex-nonce> /client/known_hosts
```

Install `python3-paramiko` from the client's official package source. `known_hosts`
must already contain the endpoint's trusted host key (`[IP]:port` for a nonstandard
port). The client checks that key, makes one credentialless `auth_none` request,
and holds the unauthenticated connection for 25 seconds. A normal `ssh` command
disconnects after authentication failure and cannot replace this client.
Within 30 seconds, the host binds a post-cursor trusted journal emitter to its
master and live socket, checking both endpoints, the source port, boot/process
generation and socket inode/fd before printing `source-verified`.
Only a unique host `sshd` listener with a direct child emitter is accepted;
when the emitter shares its socket with privsep children, each child must have the
dedicated `sshd` UID, a safe executable, a direct parent relationship, matching
boot/netns, valid timing, the same inode/fd and a stable process generation.
Other owners, file tags, old records, closed sockets or identity drift are rejected.
The result is not saved or reusable across transactions.
`source_verified=true` describes this observation; `runtime_configuration_verified`
and `jail_ready` remain `false`. This command does not enable SSH protection.

Fail2ban submenu item 14 verifies a live source for an explicit systemd service:

```bash
padm-docker fail2ban ssh verify-unit sshd.service 198.51.100.10 2222 203.0.113.7
```

Use the same external challenge client described above. The host additionally needs
`systemctl` and readable cgroup v2. The service name must match its actual `Id`;
an alias pointing to another service is rejected. The unit witness requires the fresh master to be the selected
systemd service's MainPID, fixes its current invocation/cgroup and checks all TCP
listeners in both address families. Socket activation, wildcard listeners, extra
listeners/masters, unreadable owners and generation changes are rejected. Success
returns `scope=ssh-unit-source-only`, `source_verified=true` and `unit_verified=true`;
`runtime_configuration_verified` and `jail_ready` remain `false`. It proves only this
live connection, not historical logs or continuous collector/jail readiness, and
does not start or stop the host SSH service.

Fail2ban submenu items 15–19 manage a dedicated SSH service:

```bash
padm-docker fail2ban ssh status
padm-docker fail2ban ssh unban 203.0.113.7
padm-docker fail2ban ssh enable sshd-padm.service 198.51.100.10 2222 6 600 3600 --preview
padm-docker fail2ban ssh enable sshd-padm.service 198.51.100.10 2222 6 600 3600 --confirm PADM-DOCKER-EDIT
padm-docker fail2ban ssh settings sshd-padm.service 198.51.100.10 2222 8 900 7200 --confirm PADM-DOCKER-EDIT
padm-docker fail2ban ssh disable --confirm PADM-DOCKER-EDIT
```

This requires native Linux root, systemd/cgroup v2 and a dedicated OpenSSH service
with no existing sessions and no reload. Enable it from a console or another management
channel. Only MainPID and one explicit TCP listener are accepted; existing children,
socket activation, aliases, wildcard/multiple listeners and untrusted journal identities
are rejected. The collector accepts only fresh trusted `Failed password ... ssh2` events.
Other authentication formats, historical logs, restored bans and SSH/control INPUT
coexistence are unsupported.

A managed transient collector starts before `net-fail2ban-ssh`. The jail disables
automatic restart and reads a private collector directory through a read-only mount.
A verified batch refreshes a `0600` guard; expiry after 10 seconds or source generation
loss stops the jail and removes only its owned rules. Status/unban verify the current
unit, container, action and guard. Stop proves jail exit and clean rules before retiring
the collector; unknown residue is retained. Update, rollback and business restore reject
enabled SSH protection; disable it through the managed entry first. The host SSH service
itself is never started or stopped by these commands.
Isolated amd64 systemd/OpenSSH/Fail2ban startup, authentication bans, blocked connections,
unban, stop and source-loss cleanup passed. Native hosts, arm64, public networks,
whole-machine restart and complete uninstall still require acceptance.

Status and unban access only the fixed `padm-nginx` jail in a running `net-fail2ban`
container whose spec, image, labels and mounts match the current deployment. They
do not start services, change configuration or add bans. Unban accepts one literal
IPv4/IPv6 address, not a hostname, CIDR, zone, arbitrary jail or bulk unban;
the menu requires confirmation. Missing, stopped or mismatched deployments are
rejected, and backend failures return nonzero.
Before maintenance, Fail2ban's native read-only protocol checks loaded actions,
public parameters and effective property caches inside the verified container.
Action, address-family parameter or property-cache drift, extra actions and audit
failures are rejected with status `15`. A second read-only gate verifies private
runtime state and both firewall families before the unban client can run.
This is not atomic against concurrent
privileged changes and does not defend against malicious Python actions, private
execution-cache tampering or modified Fail2ban code. Stop the service and inspect
such changes manually.

`enable` requires a managed spec without Fail2ban; `settings` requires it to be enabled.
The four arguments are protected public WS ports, retry threshold (1–20),
find window (60–86400 seconds) and ban duration (60–604800 seconds).
At most 16 ports are accepted, all belonging to existing direct protocol 21 WS listeners;
port aliases and coexistence entries are rejected. Enabling twice never resets settings.
The enabling menu defaults are `6 / 600 / 3600`; settings must be entered explicitly.
Both actions reuse narrow spec editing and the configuration transaction, changing only
the Fail2ban integration while preserving other integrations, accounts and persistent data.
They do not directly reload a running jail. Preview and cancellation do not start or stop
services; confirmed settings changes require new source challenges too.

Disabling reuses configuration editing and its existing spec migration, removing only the Fail2ban
integration; other integrations and business data remain unchanged. Preview and
cancellation do not stop the container. After confirmation, the old owner is audited
and only that container is stopped, without removing its exit evidence. New configuration
is installed only after normal exit and proof that private state and both owned firewall
families are empty. Timeout, abnormal exit, ownership drift or residual rules reject
the commit and retain old configuration and recovery evidence. The service may already
be stopped; inspect the original owner manually, never delete state to force progress.
A later startup failure restores the existing configuration snapshot while preserving
SQLite ban history; old kernel rules are not copied. `disable` accepts only preview or
the fixed confirmation token, and rejects an integration that is not enabled.

The source-check menu and `verify-source <WS listener ID> <external IPv4/IPv6>`
are read-only on-site diagnostics. Request the fresh challenge URI from the expected
external client within 30 seconds using the displayed domain and public port.
Verification binds the real Nginx source, internal port and container startup identity;
forwarded headers and historical logs are not evidence. Local, container and gateway
sources, port aliases sharing an internal listener, and coexistence entries are rejected.
The result is not stored as an enabling credential and does not start Fail2ban or change
configuration or firewall rules. Configure, update, up/restart and rollback first audit
and stop the previous owner and prove cleanup, then start non-jail runtime services.
Every protected port and family receives a fresh challenge. The batch snapshots must
still match before starting only the jail with `--no-deps`; recovery also requires new
challenges. Missing inputs or failed proof leave the jail stopped and preserve recovery evidence.
The menu collects expected external addresses after confirmation. Noninteractive commands
can set `PADM_DOCKER_FAIL2BAN_SOURCE_IPV4` and `PADM_DOCKER_FAIL2BAN_SOURCE_IPV6`;
these are expected sources, not authorization, and the external client must still respond
to each new URI. Disable also collects sources needed if restoring the previous configuration.
Preview and cancellation do not require a challenge response.
Docker automatic restart is disabled for `net-fail2ban`; after daemon restart, use the
management entry point for new proof. Update old `unless-stopped` deployments first.
Restoring a verified old backup normalizes only that policy without modifying the backup.
Protected Nginx cannot use standalone HTTP-01 stop/start; use webroot. TLS reload also
requires current source inputs and challenges, so unattended rotation without inputs fails closed.
The 30 seconds is a log collection window; a blocked Docker log or address query can make
the command take longer, and timeout still fails closed. The check proves consistency of
the disk configuration, container metadata and observed request, not every byte loaded in
an Nginx worker after a privileged change, and it is not the enabling transaction gate.

Fail2ban uses private schema 2 `data/net/fail2ban/fail2ban.state`, a random chain
and full-token markers on hooks, bans and the final RETURN. Startup, every action
and shutdown verify ownership and delete exact rules, never flush a fixed chain.
Legacy `ports=` state, fixed `padm-f2b` chains, foreign references and shadowed
hooks are rejected. Do not delete state to force a retry: stop the previous owner
and inspect its resources on native Linux first.
Dual-stack WS protection connects Nginx to the existing owned IPv6 network,
avoiding source loss through an IPv4 bridge proxy. Update old dual-stack Compose
through the normal configure/upgrade transaction; do not bypass body checks.
Real dual-stack sources, automatic log bans, packet drops and unban recovery passed
in isolated Linux amd64. In-transaction multi-port, dual-stack enabling has passed;
SSH/control protection, native hosts, arm64, reboot/uninstall and
complete management still require 5C acceptance.

The existing TProxy profile records its random chain, rule token, mark, route table
and routing identity in private `data/net/transparent/tproxy.state`. Preflight checks
the current owner and candidate conflicts without changing resources. Startup failure
and normal shutdown delete exact resources, never flush a whole chain or route table.
Legacy two-field state, the fixed `padm-tproxy` chain, unknown random chains and
foreign resource drift are rejected with recovery evidence retained. The routing table
and policy preference are exclusive, not shared. Do not delete the state to force a retry:
stop the previous owner and inspect its actual resources on native Linux first.
A SIGKILL that leaves an empty chain without token rules requires manual ownership
verification.

TProxy/Redirect disables Docker automatic restart for `net-transparent`. After a daemon
or host restart, use the managed entry point to run preflight and start it again.
Legacy `unless-stopped` deployments can still be audited for stop and cleanup, and
updated under compatible control bundles. Restoring a legacy backup normalizes this
policy while preserving the original backup. While transparent proxying is enabled,
both current and target bundles must declare `x-padm-transparent-managed-restart`.
Disable the integration before upgrading or reverting a bundle without this capability.
An old CLI update process does not reload new code, so disable it before the first
migration too. Setting `restart=no` alone does not disable the integration in the specification.
Manage TProxy through menu `5 → 1 → 8 → 43`, or:

```bash
padm-docker protocol tproxy-status
padm-docker edit --tproxy-enable 31298 129 --tproxy-family dual
padm-docker edit --tproxy-settings 31299 131
padm-docker edit --tproxy-settings 31299 131 --tproxy-output-uid 65534
padm-docker edit --tproxy-settings 31299 131 --tproxy-output-all
padm-docker edit --tproxy-settings 31299 131 --tproxy-output-off
padm-docker edit --tproxy-off
```

This manages existing Reality deployments with one Xray or sing-box core and no
other host integration. It captures TCP/UDP in `PREROUTING` with `ipv4`, `ipv6`
or `dual`. Enable defaults to IPv4; settings changes retain the current family
when omitted. Menu options 5/6 and `--tproxy-output-uid` optionally capture TCP/UDP
connections initiated by one local UID in `1–2147483647`, excluding managed UID `10001`.
Root core traffic, service replies and local destinations keep their original path.
OUTPUT defaults to off; settings changes retain the UID when omitted.
`--tproxy-output-off` keeps PREROUTING active. This mode needs owner/conntrack/MARK,
schema 4 ownership of both chains, and the `x-padm-tproxy-output-uid` bundle marker.
Menu option 7 or `--tproxy-output-all` captures whole-host initiated TCP/UDP,
including root, and excludes UID selection. The core runs as `0:10001`;
GID `10001`, local destinations and service replies bypass capture. Other processes
in that group also bypass capture. Omitted settings retain the current OUTPUT mode.
This uses schema 5 with `output_all=true` and the shared
`x-padm-transparent-output-all` bundle marker. Management checks the actual core
identity as well as rule ownership. Each selected family requires
host forwarding and its TPROXY target; preflight does not change sysctl.
IPv4 schema 2 state remains compatible. IPv6/dual use schema 3 and one token
binds each family's resources. Drift in either family preserves all resources
and recovery state. The core uses host networking, root and `NET_ADMIN`.
Changes audit and normally stop the previous container, prove its rules are gone,
then use the existing configuration transaction. Preview and cancellation keep the
running service. Status reports the specification; use `validate` for health.
Real TCP/UDP forwarding and clean shutdown passed for both cores and all three
families in isolated Linux amd64. Native host reboot, arm64, public-network and
complete 5C acceptance remain pending.

Manage Redirect TCP through menu `5 → 1 → 8 → 47`:

```bash
padm-docker protocol redirect-status
padm-docker edit --redirect-enable 31298 --redirect-family dual
padm-docker edit --redirect-settings 31299 --redirect-output-uid 65534
padm-docker edit --redirect-settings 31299 --redirect-output-all
padm-docker edit --redirect-settings 31299 --redirect-output-off
padm-docker edit --redirect-off
```

This supports existing Reality `1/2/26` listeners on one Xray or sing-box core,
including multiple listeners on that core, without another host integration or
secondary core. Redirect captures TCP only; UDP keeps its original route.
Choose TProxy for transparent TCP/UDP. Families are `ipv4/ipv6/dual`, defaulting
to IPv4; settings changes retain the family when omitted. Optional OUTPUT
captures TCP initiated by one UID with the same limits as TProxy. It defaults
to off and retains the old UID when omitted. Local destinations, service replies
and root core traffic bypass capture.
Menu option 7 or `--redirect-output-all` captures whole-host initiated TCP,
including root; core GID `10001`, local destinations and replies bypass capture.
UDP keeps its original route. UID selection and whole-host mode are exclusive;
omitted settings retain the mode. Core identity and the shared bundle marker
follow the TProxy whole-host rules.
The core uses host networking, root and `NET_ADMIN`. Each selected family needs
NAT REDIRECT; OUTPUT also needs owner/conntrack. Preflight does not change sysctl.
Private `redirect.state` binds both families and PREROUTING/OUTPUT chains to one
random token. All resources are audited before exact removal; any drift retains
all resources and state. No chain flush or conntrack deletion is performed.
Enable, settings and disable use the existing candidate and failure recovery
transaction. Old bundles require `x-padm-redirect`.
Real TCP capture, unchanged UDP paths and production Compose removal passed for
both cores and all three families in isolated Linux amd64. Whole-host state uses
schema 2 with `output_all=true`; schema 1 remains compatible. Native host, arm64,
public network, reboot and complete uninstall remain pending.

Manage TUN through menu `5 → 1 → 8 → 44`:

```bash
padm-docker protocol tun-status
padm-docker edit --tun-enable
padm-docker edit --tun-off
```

This is limited to a managed IPv4 deployment with one sing-box core, one Reality
listener and no other host integration. The fixed `padm-tun` interface uses
`198.18.0.1/30` and captures global host IPv4 TCP/UDP; IPv6 is rejected.
The core uses host networking, root, `NET_ADMIN` and `/dev/net/tun`, with automatic
container restart disabled. Private `tun.state` binds the container ID, start time,
network namespace, interface and complete rule/route ownership. Stop, restart,
configuration changes and recovery audit the owner, normally stop the core and
prove restoration of the baseline before removing ownership evidence.
Candidate checks read the live owner through a read-only mount. Abnormal exits,
residual resources and drift preserve the scene; they are never adopted or cleaned
automatically. Bundles without the TUN management capability reject activation
and recovery. Deleting state does not bypass these checks.
Isolated Docker Linux amd64 acceptance passed; native hosts, arm64, public networks,
whole-host reboot and complete uninstall remain unverified.

Multi-server control now has a separate private read-only API and a controlled-node sync
transaction foundation.
Authorization is bound to the controlled source address; expiration, rotation and revocation
take effect on the next request. The public subscription server is unchanged.
The v3 managed spec records source identities, listener mappings, revision/content digest,
and the complete managed-account snapshot. Sync replaces only controller-owned accounts and
preserves local accounts. Identical revisions and content do not recreate services;
version conflicts, credential collisions and ownership drift are rejected, and failed
application restores the previous spec and configuration. Ordinary configuration cannot
change sync ownership, and managed accounts must be changed on the controller.
4C.3a hardens the existing WireGuard runtime: preflight, health and revocation verify the
interface index, public key and random alias. Revocation uses a root-private startup snapshot.
An external replacement or active legacy marker is never adopted or deleted automatically;
stop the old container normally before upgrading. A matching name or public key is not ownership.
4C.3b adds a dedicated `control-health --state PATH`: it safely reads state, checks the actual
interface address and connects directly to the private service with bounded timeouts.
It verifies the fixed unauthenticated rejection without sending a token or depending on invitation expiry.
4C.3c adds controller desired-account state to candidate, backup, update and recovery transactions.
Account order or local listener mappings do not increment the revision; content changes do,
and restoring old content publishes a newer revision rather than moving backwards.
The separate Compose `control` service uses host networking, UID `10001`, no capabilities or
published ports, and a read-only `config/control` mount; it depends on WireGuard health.
Ordinary configuration cannot change controller identity, listener or authorization.
Focused fixtures cover candidate generation, installation, recovery and
permissions; core/host actions are stubbed, not real two-node acceptance.
`padm-docker control status [--json]` and the Control connection menu expose redacted role state.
Controller initialization requires an already healthy managed single-peer WireGuard deployment.

4C.7 adds a separate single-Peer preparation and start/stop workflow. In the Control connection
menu, item `18` opens status/public key, local preparation, Peer configuration, start and temporary stop.
Prepare an identity on each node, exchange only public keys, then configure the sole Peer.
For the node using `10.77.0.1`:

```bash
padm-docker wireguard prepare --address 10.77.0.1 --listen-port 51820 --yes
padm-docker wireguard status
padm-docker wireguard peer --peer-address 10.77.0.2 --peer-public-key '<PEER_PUBLIC_KEY>' --endpoint 192.0.2.2:51820 --yes
padm-docker wireguard start --yes
padm-docker wireguard stop --yes
```

Reverse `.1/.2` on the other node and use that node's actual Peer public key and reachable endpoint.
Both tunnel addresses must be RFC1918 IPv4 `/32`, with exactly one Peer. `--endpoint` is optional
and accepts `IPv4:port` or `[IPv6]:port`. Use a compressed lowercase global unicast or unique local
IPv6 address. Both the endpoint port and the local listen port must be `1024–65535`.
Set a reachable IPv4 endpoint before downgrading to a release that supports only IPv4 endpoints.
Preparation and Peer configuration require an installed deployment without WireGuard or control roles.
The private directory is `0700 root:root`, files are `0600 root:root`, and commands expose only public
identity/status data. Existing keys, Peer configuration and unknown contents are never replaced.
Existing manual configurations continue to use the complete-spec workflow.
Writes require interactive confirmation or explicit `--yes`.

The first `wireguard start` adds the integration through the existing configuration transaction
and may update and check all deployment services. Subsequent registered `start/stop` operations
touch only the precisely audited WireGuard container. `stop` is temporary and preserves its spec
and container; ordinary `up/restart` can start it again. A `control` or `control_sync` dependency
blocks an independent stop. The existing owner/preflight/run/cleanup/health runtime is reused,
and ownership drift is rejected. Focused checks and isolated Linux amd64 production CLI tests passed,
including preparation from a standalone deployment, bidirectional encrypted traffic and exact-container restart.
Multiple Peers, role disaster recovery, native dual-architecture,
host-reboot and public-network acceptance remain outside this checkpoint.

After the managed connection is healthy, initialize the controller:

```bash
padm-docker control init --address 10.77.0.1 --port 18443 --peer-address 10.77.0.2 --yes
```

The addresses must match the live interface and the unique peer's `/32` AllowedIPs.
Initialization creates no keys, interfaces or routes, refuses an existing role, and leaves authorization disabled.
Controller health checks the installed service; status exposes no tokens, accounts or digests.
Invitation and credential rotation use the same command; rotation immediately invalidates the previous token:

```bash
padm-docker control invite --output /root/padm-control-invite.json --expires-in 86400 --yes
padm-docker control revoke --yes
```

The `0600 root:root` invitation contains private addresses, both identities, expiry and the sole raw token.
The lifetime range is `60–604800` seconds, with `86400` seconds as the default.
Its absolute output path must be outside the managed deployment; every parent must be root-owned,
not group/other-writable and not a symlink. Existing files, directories and links are never overwritten;
choose a new filename for rotation. Output, logs and process arguments omit the token; the spec stores only its hash.
Revocation works even when the network is down and repeated revocation does not rebuild services.
It atomically disables API authorization before updating the spec; repeat `revoke` after an interruption
to finish the spec update without restoring the old authorization.
Redacted status includes the authorization switch and expiry.
For v1, recovery, failed-transaction rollback and explicit version rollback disable authorization to prevent old tokens
from becoming valid again; generate a new invitation afterwards. An atomically delivered invitation remains
even if configuration fails, but is not proof of active authorization; check `control status`.
On the controlled node, first start a healthy managed single-peer WireGuard deployment and securely
transfer the invitation into a root-private directory. The controller must be the peer's unique `/32`
AllowedIPs, the local interface address must match `peer_address`, and the route from that source to
the controller must use `wg-padm`. The Control connection menu also exposes join and manual sync:

```bash
padm-docker control join --invite /root/padm-control-invite.json --listener entry-reality --yes
padm-docker control sync --invite /root/padm-control-invite.json
```

Repeat `--listener` to map multiple existing entries, or enter comma-separated listener IDs
in control menu `2 → 4 → 5` (up to 16). Empty segments and invalid IDs are rejected.
Join confirms once and initializes identity,
mapping and the initial account sync in one transaction. Failure preserves the original role, accounts
and traffic; retrying the same revision/content does not rebuild services. Identity and WireGuard addresses
are then fixed; a different invitation cannot reclaim them. Ordinary sync retains the committed mapping and API port.
Control menu `2 → 4 → 15` or this command reauthenticates the same connection and replaces its mapping:

```bash
padm-docker control remap --invite /root/padm-control-invite.json --listener entry-secondary --yes
```

Disable automatic sync first, then enable it again with the same connection's invitation after committing.
Revision, digest and the previous managed snapshot remain checked; local accounts and traffic are preserved.
Control menu `2 → 4 → 16/17` updates and reconnects the API port for the same identity:

```bash
# Disable automatic sync on the controlled node and control log scheduling and control-plane Fail2ban on the controller.
padm-docker control set-port --port 19443 --yes
padm-docker control invite --output /root/padm-control-new-port.json --yes
# Transfer the new invitation securely to the controlled node, then run the following command.
padm-docker control reconnect --invite /root/padm-control-new-port.json --yes
```

Only ports `1024–65535` are accepted. Identities, WireGuard keys and addresses, listener mapping and
traffic totals remain unchanged. Reconnect authenticates the invitation and checks revision, digest and
the previous managed snapshot; it can also apply a newer controller account revision. Retrying the same
port and revision does not rebuild services. Failures and INT/TERM use the existing recovery transaction;
explicit rollback cannot cross API ports. The old API port closes after switching. Run a fresh controller
`source-check` before enabling source-dependent protection or log scheduling, and import the new invitation
when enabling controlled auto-sync again. Control-role address changes and multiple peers remain unsupported.

4C.8 adds explicit controller rebinding on the same WireGuard tunnel through control menu `2 → 4 → 19`:

```bash
padm-docker control sync-schedule disable --yes
padm-docker control rebind --invite /root/padm-new-controller.json --yes
```

The new invitation must authenticate. Rebinding replaces the previous controller's managed accounts
and may change its API port; WireGuard keys/addresses, listener mappings, local accounts and traffic
totals remain unchanged. The previous managed snapshot and all account mappings are checked first.
An existing account ID must keep its authentication identity; credentials cannot collide across IDs.
Only a changed controller/node identity resets the upstream revision/digest baseline. Same-identity
retries retain version checks. The existing lock, private invitation snapshot, health checks and
failure/INT/TERM recovery transaction apply. Repeating the same invitation and revision is idempotent.
Ordinary sync/reconnect reject the previous controller's invitation; a later explicit rebind can
deliberately switch back. Enable auto-sync again with the new invitation after committing.
Focused client, transaction and control-menu checks and isolated amd64 dual-deployment production
CLI/Compose tests passed, including real traffic, health-failure recovery and preserved totals.
Control-role address migration is described in 4C.11 below; multiple Peers and role disaster recovery remain deferred.

4C.9 adds `wireguard migrate` and WireGuard submenu item `6` for a healthy registered single-Peer
deployment prepared by 4C.7, without `control` or `control_sync`:

```bash
padm-docker wireguard migrate --listen-port 51821 --yes
padm-docker wireguard migrate --endpoint 192.0.2.2:51821 --yes
padm-docker wireguard migrate --address 10.78.0.1 --peer-address 10.78.0.2 --rotate-key --yes
padm-docker wireguard status
```

Optional `--address`, `--listen-port`, `--peer-address`, `--peer-public-key` and `--endpoint`
can be combined; omitted fields stay unchanged, and endpoint `none` removes the endpoint.
`--rotate-key` generates a new local key pair in the trusted net image.
Apply changes explicitly on both nodes and exchange new public keys. Temporary disconnection
is expected; local health does not prove remote connectivity. An unchanged configuration avoids
service recreation. Changes use the existing full configuration transaction and recreate deployment services.
Only the canonical private three-file directory is accepted. The existing key pair and precise runtime
owner are checked before staging. Private candidates remain root `0700/0600`; the original directory
is replaced only after the audited interface stops. Failure and INT/TERM restore its original inode.
Directory or runtime ownership drift preserves recovery evidence. Ordinary configuration ignores
injected migration input, and ordinary recovery cannot replace keys across a migration.
Focused checks and isolated amd64 dual-deployment production CLI tests passed, including changes
on both nodes, encrypted traffic after failure recovery and unchanged-configuration checks.
4C.10 also supports a controller or joined controlled node with fixed local/Peer tunnel addresses.
Both original and candidate inputs must match the role's registered addresses. Keys, listen ports
and endpoints can change while role identity, sync version, accounts, listeners and totals stay unchanged.
Disable controller log scheduling and control Fail2ban, or controlled auto-sync, before migration.
Unfinished source challenges are rejected. Successful migration keeps the invitation usable; enabling
protection again runs a fresh source check. Controller failure or INT/TERM recovery revokes Peer
authorization and requires a new invitation. Focused and isolated amd64 dual-deployment checks passed,
including encrypted traffic, the original invitation, fresh source proof and failure recovery.
4C.11 extends the same command/menu to linked controller or joined controlled-node address changes.
The canonical tunnel and the role's local/Peer addresses commit together. Identity, API port, accounts,
sync revision/digest and traffic totals stay unchanged. Disable the same scheduling/protection first.
Controller address changes revoke the old invitation; update both nodes, issue a new invitation,
sync and verify a fresh source. Failure or INT/TERM restores the old addresses and keys while keeping
controller authorization revoked. Ordinary rollback rejects snapshots from a different control tuple.
Focused and isolated Linux amd64 dual-daemon tests cover migration, encrypted traffic, invitation
revocation, same-version sync, lower-version rejection and health-failure recovery.
For an enabled canonical WireGuard deployment without controller/controlled roles,
menu `2 → 4 → 18 → 7–10` and `wireguard peers list/add/update/remove` manage individual Peers:

```bash
padm-docker wireguard peers list
padm-docker wireguard peers add --peer-address 10.77.0.3 --peer-public-key "$PEER_PUBLIC_KEY" --endpoint 192.0.2.3:51820 --yes
padm-docker wireguard peers update --peer-address 10.77.0.3 --endpoint none --yes
padm-docker wireguard peers remove --peer-address 10.77.0.3 --yes
```

Each Peer has a unique RFC1918 IPv4 `/32` and public key. Arbitrary routes, hooks and
duplicate addresses/keys are rejected; the existing 4096-byte configuration limit remains.
The update address selects an existing Peer; omitted fields stay unchanged and `none`
clears the endpoint. Removing the last Peer is rejected. The existing full configuration
transaction preserves identity/key bytes and handles failure/INT/TERM; service recreation
may briefly interrupt connections. Collection changes for v1 controllers or controlled nodes remain rejected.
Without a control role, menu `2 → 4 → 18 → 6` or the following command can migrate local fields
while preserving every Peer address, public key and endpoint:

```bash
padm-docker wireguard migrate --address 10.78.0.1 --listen-port 51821 --rotate-key --yes
```

At least one local field must be explicit. With multiple Peers, `--peer-address`,
`--peer-public-key` and `--endpoint` are rejected; no Peer is implicitly selected.
Update each remote node after changing the local address or key; temporary disconnection is expected.
Health failure and INT/TERM reuse the existing private-directory rollback. Control-role scope stays unchanged.
Empty-target recovery accepts canonical Peer collections
only when no control role is configured, as described below.
Native-host/arm64/public-network acceptance remains deferred;
limited controller recovery with a new identity is described below.

An existing v1 controller can explicitly upgrade through menu `2 → 4 → 20` and register another node:

```bash
padm-docker control upgrade --yes
padm-docker wireguard peers add --peer-address 10.77.0.3 --peer-public-key "$PEER_PUBLIC_KEY" --endpoint 192.0.2.3:51820 --yes
padm-docker control peers add --peer-address 10.77.0.3 --yes
padm-docker control peers list
padm-docker control invite --peer-id "$PEER_ID" --output /root/padm-peer-3.json --yes
padm-docker control source-check --peer-id "$PEER_ID"
padm-docker control revoke --peer-id "$PEER_ID" --yes
padm-docker control peers remove --peer-id "$PEER_ID" --yes
```

Use the generated `PEER_ID` from the redacted list; menu `21–23` lists, registers and removes nodes.
V2 requires an explicit ID for invitations, revocation and source checks even with one remaining node.
Upgrade preserves identities, authorization, revision, accounts and totals; old invitations remain valid.
HTTP, invitation and controlled-node formats stay v1. Each node uses its own invitation and the existing
join/sync workflow; both its actual source and token must match. The API port and account revision remain
shared, and a port change requires each node to reconnect. Each source may have one processing request
and one handoff waiting at most `100 ms`, both counted toward the overall limit of eight.
The listener never waits for handoff; each connection has a total deadline of five seconds.
Controller configuration transactions may briefly interrupt all connections. V2 rollback preserves an old
authorization only when identity, listener and the complete Peer record are unchanged in every trusted
plan; changed or unprovable authorizations are disabled. Revoke before removal and retain at least one node.
V2 update/rollback requires `x-padm-control-peers=true` in the target bundle; older single-Peer bundles
are rejected before switching.
V2 controllers may maintain unregistered WireGuard Peers. Revoke and remove a control registration before
updating/removing its WireGuard entry. V2 identity/address/key migration and control-plane Fail2ban
remain unsupported; disable the latter before upgrading. New-identity controller recovery is described below.
See the [implementation plan](../docker-menu-parity-plan.md) for focused and three-node evidence;
native hosts, arm64, public networks, reboot and trusted releases still require separate acceptance.

After control-token rotation, securely transfer
the new invitation and sync again. Every manual sync reads a root-private invitation outside the managed
directory, with the same parent-directory restrictions; expired or revoked credentials fail.
The raw token is not stored in specs, backups, arguments, environment or ordinary logs. The capability-free
client binds its private source address and connects directly, without proxies, redirects or public fallback.
Status exposes connection metadata, not remote health. Existing controlled nodes can enable checks
every five minutes from the control menu or these commands:

```bash
padm-docker control sync-schedule enable --invite /root/padm-control-invite.json --yes
padm-docker control sync-schedule status
padm-docker control sync-schedule disable --yes
```

Scheduling is off by default. Enabling or replacing credentials imports a validated invitation without
applying accounts. The root-private `secrets/control-sync/` stores this host's invitation and fixed
identity, connection and entry mapping; configuration and business backups exclude it.
Disabling removes the persistent token. Import a rotated invitation with the same `enable` command.
Expired, revoked or unreachable authorization prevents a commit but still allows status and disabling.
The fixed job runs `control auto-sync`, exits `12` on deployment-lock contention, and skips normally
stopped services without starting them. Scheduled execution starts 15 seconds after each five-minute
boundary, avoiding the fixed start second of minute-by-minute traffic collection. A long transaction
can still skip an attempt; the direct CLI tries the lock once without waiting or retrying. Exact
legacy schedules owned by this deployment migrate; edited or foreign jobs are rejected. Starting
services reinstalls the job. Updates, rollbacks and
restores retain local registration and reject incompatible bundles or identity drift before stopping.
Only existing single-peer controlled connections are supported; multiple peers, role rebinding and
WS/SSH protection requiring fresh external source proof are rejected.
New control APIs write both managed
`logs/control/auth.log` and stdout, recording only a UTC timestamp
with milliseconds, status, and the actual socket source, target and port. Forwarding headers are ignored;
request paths, headers, accounts, credentials and exception text are never logged.
The API responds only after safe-file checks, a complete write and synchronization succeed;
an invalid log or unprovable socket source stops the API. Configuration restore never overwrites log
history, and first creation preserves existing content. Connection closure is separate from authentication
failure. Exact managed legacy restores may retain stdout-only logging without claiming the new capability.
New controllers can run `padm-docker control source-check` to register a random challenge for up to
30 seconds, then run the printed `control source-probe` command on the managed Peer. The probe binds
its WireGuard source address without reading an invitation or sending a token. Only a 401 matching
the root-owned registration, actual socket and controller state writes `logs/control/source.receipt`;
ordinary access logs never record the nonce. Exit or interruption removes only this transaction's
unchanged registration. Old receipts are not reusable evidence; configuration or container-generation
changes reject the proof. Foreign or changed registrations are preserved and rejected. No jail is enabled.
The control menu's manual authentication-log rotation, or `padm-docker control log-rotate --yes`,
rotates `auth.log` at 10 MiB and retains two fixed archives, `auth.log.1` and `auth.log.2`.
The API holds a read-only cooperative lock on root-owned `auth.lock`; rotation does not restart the API,
use copytruncate, or rotate or replace source receipts. Legacy deployments without the lock must
complete a normal upgrade first. The control menu can enable or disable hourly checks, also available
through `control log-schedule enable|disable --yes`; `control log-schedule status` reports the
registration and actual job state separately. Scheduling is off by default. Its root-private
`data/control-log/schedule.json` stays on this host and is excluded from business backups.
Stopping services removes the job but retains the setting; starting services reinstalls it.
`control auto-log-rotate` rechecks the setting and managed controller under the deployment lock,
skips normally stopped services, and exits `12` on lock contention for the next scheduled attempt.
Invalid sources or registrations are rejected. While enabled, updates and rollbacks reject an
older control bundle without this capability before switching; disable the schedule first.
10 MiB is a check threshold, not a live size limit. Failed recovery preserves its private directory
and rejects further takeover.
After a forced kill or power loss, inspect the retained evidence manually; do not delete residual
files or recreate a missing active log to bypass the check.
INT/TERM waits for the rotation container to finish and be removed before releasing the deployment lock;
if the Docker daemon is unavailable, the lock is retained until it recovers.
The isolated control Fail2ban backend provides a `padm-control` jail, separate SQLite database and
random owner. It bans INPUT TCP `NEW` connections only to one RFC 1918 IPv4 /32 and port on an actual
`wg-padm` interface, leaving the WS dual-stack DOCKER-USER resources unchanged. Its process runs as
`0:10001` with only `NET_ADMIN` and read-only trusted logs. The Fail2ban maintenance menu now provides
separate control-plane status, IPv4 unban, enable/disable and settings:

```bash
padm-docker fail2ban control status
padm-docker fail2ban control unban 10.77.0.2
padm-docker fail2ban control enable 6 600 3600 --preview
padm-docker fail2ban control enable 6 600 3600 --confirm PADM-DOCKER-EDIT
padm-docker fail2ban control settings 8 900 7200 --confirm PADM-DOCKER-EDIT
padm-docker fail2ban control disable --confirm PADM-DOCKER-EDIT
```

The independent `fail2ban-control` integration stores only retry, find-time and ban-time settings;
its target and port come from `control.listen`. It requires a managed controller and WireGuard,
but the Peer's API authorization may be disabled. After confirmation, one deployment lock covers
old-jail shutdown and clean-resource proof, ordinary-service startup, a fresh Peer source challenge,
configuration and container-generation rechecks, and jail startup with `--no-deps`.
Recovery must obtain a new challenge. Ordinary 401s, historical logs/receipts and an independent
`source-check` are not enable credentials; do not start the backend manually to bypass this gate.
Both jails disable automatic restart. After a daemon restart, use the management entry point for
a fresh proof; failed cleanup retains ownership state and rules.
The backend fixture is `docker-control-fail2ban-real`; transaction acceptance reuses
`docker-control-two-deployment-real`. SSH, native-host systemd/reboot/uninstall, public-network and
arm64 acceptance remain pending.
Legacy internal roles without connection metadata
remain compatible but cannot use external sync; old bundles cannot restore the new connection spec.
Explicit `rollback` checks controlled identity, listener mapping and connection before sampling, creating a
backup or stopping services. It rejects lower sync revisions and requires matching digest and managed accounts
at the same revision. Compatible release snapshots with unchanged sync state can still be restored.
Controlled specs require a bundle declaring sync rollback protection, so older unprotected scripts are rejected.
Failed or interrupted join/sync transactions still restore their pre-transaction state without inventing
upstream revisions locally. Multiple Peers, role rebinding, arbitrary historical-account restoration and
complete network management are not provided; the limited 4C.7 workflow above passed focused and isolated amd64 CLI tests.
4C.4a verifies real WireGuard handshakes and encrypted traffic between two independent network
namespaces in an isolated Linux container. The production API and capability-free client cover join
planning, idempotency, credential rotation, expiration/revocation, revision conflicts and network recovery.
The dedicated `docker-control-two-node-real` regression adds `NET_ADMIN`/`SYS_ADMIN` only to its
isolated test container, still with `network none`, no published ports and no host networking.
Production permissions are unchanged. 4C.4a does not execute Compose apply/restore.
The 4C.4b `docker-control-two-deployment-real` regression uses two independent Docker Engines,
PID/mount/network namespaces and real cron. It exercises production join/sync CLI transactions,
real WS/TLS client traffic, account and cumulative-traffic preservation, network/revision conflicts,
rotation/revocation, and health-failure/INT/TERM recovery.
Only this exact selector runs a privileged isolated test container with a dedicated Linux data volume;
there is no host Socket, published port or production Compose override.
Nodes start from a `local-test-only-not-release-verified` installed fixture, not trusted first configuration.
Full role migration and disaster recovery need a separate contract.
Multi-server support remains `deferred`.
See the [4C implementation checkpoints](../docker-menu-parity-plan.md#4c-多服务器控制后端).

Certificate and ACME tasks are dispatched to the `ops` image by the same host command:

```bash
padm-docker tls manage
padm-docker tls validate --domain example.com
padm-docker tls install --domain example.com --cert /path/fullchain.pem --key /path/privkey.pem
padm-docker acme <issue|renew> --domain example.com --email admin@example.com --dns <dns_provider> --credentials /path/credentials
padm-docker acme schedule enable --domain example.com --email admin@example.com --dns <dns_provider> --credentials /path/credentials
padm-docker acme <issue|renew> --domain example.com --email admin@example.com --standalone
padm-docker acme schedule enable --domain example.com --email admin@example.com --standalone
padm-docker acme issue --domain example.com --email admin@example.com --alpn
padm-docker acme schedule enable --domain example.com --email admin@example.com --alpn
padm-docker edit --http01 enable --preview
padm-docker edit --http01 enable --confirm PADM-DOCKER-EDIT
padm-docker acme <issue|renew> --domain example.com --email admin@example.com --webroot
padm-docker acme schedule enable --domain example.com --email admin@example.com --webroot
padm-docker acme schedule status
padm-docker acme schedule disable --domain example.com
padm-docker acme auto-renew
```

Menu `4 → 2. Local TLS certificate management` lets you inspect and validate certificates,
import replacements, and issue or renew certificates through DNS-01, HTTP-01 standalone,
HTTP-01 webroot, or TLS-ALPN-01. It also manages the HTTP-01 listener and automatic renewal.
Use item `10` to migrate the listeners to a new TLS domain.
No deployment lock is held before final confirmation. Configured deployments use their recorded
ops image; `--ops-image` cannot substitute a different image.
After checking validity dates, hostname and key match, rotation runs `nginx -t`, reloads and
checks health. Failure or interruption restores both certificates and ACME accounts, preserving
other domains and cumulative traffic. Domains without consumers are only stored or validated,
without changing listeners or the spec. Core-side TLS only handles same-domain managed `.crt/.key`
pairs referenced by the configuration, through a read-only `/etc/padm/secrets/tls` mount.
All consumers are validated first, then affected cores are recreated or Nginx is reloaded with
per-service health checks. Recovery attempts every consumer without reverting cumulative traffic.
Standalone HTTP-01 uses port `8080` in the non-root ops container and temporarily publishes dual-stack host
TCP `80`. The domain must resolve to this host and public port `80` must be reachable.
It does not change firewall rules or provide TLS-ALPN-01. Actual container labels, image,
mounts, deployment and published ports must agree before stopping anything.
Only this deployment's originally running port `80` owners are paused. HTTPS in the same
container is briefly interrupted; unrelated `443` services are not stopped.
Success, failure and signals restore the original containers. Originally stopped TLS consumers
remain stopped. acme.sh decides whether renewal is due, including ARI, before ports are published
or services paused. Failed restoration retains container IDs in the private candidate's
`challenge.json` and prevents starting another domain.
Webroot requires an existing managed Nginx listener `21`-`25`/`27`/`29` and explicit v3
`.tls.http01=true`; old specs do not automatically expose port `80`.
A dedicated dual-stack `80:8088` HTTP vhost serves only standard challenge token paths
for the current TLS domain, independently of site, redirect, proxy and subscription rules.
Nginx mounts the stable `data/acme-webroot` read-only. Ops writes only this run's exclusive
`active/` directory, removed on completion or interruption without replacing the mount root,
pausing Nginx or publishing temporary ports. The root is `0750 10001:10001`; links, special
files, externally writable parents and unfinished challenges are rejected.
Failed cleanup retains the candidate and challenge and prevents processing another domain.
Issuing a certificate never implicitly enables the listener.
Use `edit --http01 disable --confirm PADM-DOCKER-EDIT` to disable it.
Enabled webroot renewal blocks disabling, domain changes, deleting the last Nginx listener
or rolling back to a snapshot without HTTP-01; disable that domain's renewal first.
Renewal that is not due creates no challenge directory and changes no services.
Automatic renewal requires an existing managed ACME account for the domain and matching
challenge method; imported certificates alone are insufficient. DNS renewal stores `NAME=value`
credentials and renewal inputs in host-only `secrets/renewal/<domain>/`, with root-owned
`0700` directories and `0600` files. Credentials reach the tool through standard input, not
schedules, arguments, or Docker environment metadata.
Standalone registration stores schema `2` and webroot schema `3`, both without credentials.
DNS retains schema `1`. Bundles must support the highest enabled registration schema;
disabling renewal transactionally removes the domain's registration so compatible older bundles can be used again.
All domains share one daily 03:17 task: a systemd timer with up to five minutes of random delay,
or a running cron daemon. The backends are mutually exclusive, repeated enablement creates
no extra job, and certificates that are not due are skipped normally.
`down` and uninstall remove the job but retain private inputs; `up` reinstalls it.
Updates and rollbacks preserve the latest inputs and reject incompatible older control bundles
while renewal is enabled. External tasks with the same name are never overwritten.
This foundation does not establish support for new protocols or full management.
Linux amd64 and emulated arm64 tests cover dual-core TLS fixtures, WS client traffic and
rotation recovery; all TLS probes verify the test CA and hostname.
Additional amd64 and emulated arm64 tests generate sing-box clients from actual HTTPS
subscriptions and verify both cores' Reality Vision handshakes, five traffic paths and recovery.
Isolated endpoint mapping does not establish public ingress, third-party import UI
or compatibility with other targets.
Real DNS, full host restarts, native arm64 and trusted releases remain unverified.
See the [real TLS acceptance baseline](../docker-tls-real-baseline.md) for evidence and limits.
Isolated systemd/cron probes, backend migration and container restarts are verified,
but do not replace host reboot or real DNS acceptance.

Configuration changes generate and validate a candidate, check ports and Compose, back up the current state, and then run health checks. A failure leaves the old configuration in place. The installed host command is `/usr/local/bin/padm-docker`; the bundle, configuration, data, secrets, logs, and backups live below the state root in `bundle/`, `config/`, `data/`, `secrets/`, `logs/`, and `backups/`.

## Trusted Release Inputs

The first-configuration wizard verifies release inputs automatically. To inspect a release independently or prepare non-interactive configuration, check the signed release, its control bundle, and all five digest-pinned images:

```bash
padm-docker release
padm-docker release --manifest /path/release-manifest.json \
  --bundle /path/release-manifest.sigstore.json --control-bundle /path/padm-docker-bundle.tar.gz
```

On success, stdout contains only JSON with `release` and `images`. It is emitted after signature verification, archive validation, and all image pulls succeed; progress and errors use stderr. This command does not generate a complete spec or credentials, switch installed control scripts, or start or reconfigure services. Image pulls do update the host Docker cache; local release assets do not imply offline image availability. The JSON output is not a signature proof: subsequent configuration must still check the original manifest and Sigstore bundle.

`cosign` must support Sigstore bundle v0.3. A missing tool stops the command without bypassing verification or automatically installing host tools. Install it from an independently trusted package source or verify its provenance using Sigstore's official release instructions, then retry. An unverified manifest cannot choose the trusted publisher identity or verifier source.

## Recovery Archives

Menu `7 → 1 → 6/7` exports managed inputs and verifies archives.
The host requires Python 3:

```bash
padm-docker backup export /root/padm-recovery.tar
padm-docker backup verify /root/padm-recovery.tar
```

Export holds the deployment lock, checks the current spec against deployment metadata,
and writes a version 1 USTAR archive with a path, size, mode and SHA-256 manifest.
Publication is atomic, mode `0600`, and never overwrites an existing target. The destination
directory must belong to root and have no group or other write access. Inputs include
specs, generated configurations, deployment and image references, actual Geo files,
accounts and saved traffic, website/subscription content, TLS/ACME and renewal inputs,
WireGuard keys, control state/private sync registration and the Reality target library.
The archive contains credentials. Export preserves saved counters and raw baselines without
collecting traffic. It rejects changes to selected files during export. Runtime owners,
sessions, challenges, locks, logs, host rules/schedules, image layers, old backups and the
control bundle are excluded; obtain fixed versions and images from trusted releases separately.

`verify` needs no Docker, installed deployment or root. It neither extracts nor writes
temporary files. The archive must be a private regular file owned by the current user,
with one hard link. Streaming checks reject unsafe paths, links/special members, duplicates,
missing/extra members, unsupported versions, unsafe modes and corruption.
This stage accepts ASCII USTAR paths only: at most 255 bytes per path, 100 per basename,
16,384 entries, 512 MiB per file and 2 GiB total payload; limits fail without truncation.
Integrity does not establish provenance, business consistency or restore readiness.

Maintenance menu `7 → 1 → 8` and this command provide a limited restore preview:
Both preview and apply (`7 → 1 → 9`) accept either the default release or matching
manifest, Sigstore bundle and control-bundle files; paths containing spaces are preserved.

```bash
padm-docker restore preview /root/padm-recovery.tar
padm-docker restore preview /root/padm-recovery.tar --manifest /root/release-manifest.json --bundle /root/release-manifest.sigstore.json --control-bundle /root/control.tar.gz
```

The target must contain only an installed control skeleton: configuration, data, secrets,
logs and backups must be empty, with no containers from the same project. The supported scope
accepts same-architecture v3 ordinary deployments and managed or bridge-reachable host-website Reality coexistence with cores,
manual TLS, static sites, account/share identities, saved traffic, Reality target libraries,
limited Geo, ACME, renewal and canonical WireGuard inputs described below.
Controllers require the explicit new-identity workflow below. Other host integrations,
automatic-sync authorization, host-network coexistence and unhandled ACME combinations remain rejected.
Dangling references in disabled share groups are also rejected.
WireGuard requires the complete canonical `identity.json`, `private.key` and `wg-padm.conf`,
with `root:root` ownership, directory mode `0700` and file mode `0600`; a trusted net image also
checks the private/public key pair. Nodes without a control role accept a nonempty Peer collection;
joined controlled nodes still require a single Peer; controllers use the explicit rebuild below.
Controlled-node automatic sync must be disabled, with no archived `secrets/control-sync`.
All Peer addresses, public keys and endpoints, local keys, applicable control identity, connection,
managed snapshot, revision, accounts and totals are preserved. On a controlled node, obtain a fresh
invitation and sync manually afterward; the revision floor is retained.
Stop the old node and confirm its interface has disappeared before recovery; never run duplicate WireGuard identities.
Host interfaces, ifindex, aliases, runtime ownership and source challenges are regenerated after fresh checks.
Rollback removes private material only after both containers and the interface are confirmed absent;
failed probes or residual interfaces preserve evidence for `restore recover`.
An existing `.tls.http01=true` is preserved with a newly generated empty challenge root
and dual-stack `80:8088`. ACME accounts and renewal accept only the restricted combinations below;
old challenge files are not restored, and the existing target port-ownership checks still apply.
Single sing-box dual-stack Hy2/TUIC deployments may restore the saved `port_hopping` spec.
The restored state is `stopped`; old supervisors, rules and runtime state are not restored.
An explicit `port-hopping start` must pass fresh checks on the target host before enabling it.
Reality recovery only accepts `data/reality-targets/results.tsv` (15/16-column TSV) and
`blocked.tsv` (four `|`-separated columns), limited to 16 MiB per file. All records are validated
before copying the original bytes, preserving empty columns, duplicates and custom block reasons.
Directories use `0700 root:root` and files use `0600 root:root`. Recovery does not refresh records
over the network or establish that historical scores or handshakes remain valid.
Geo recovery requires an Xray-containing deployment and a fixed-version managed library with
a boolean `state.enabled`. It preserves the original bytes of
`config/xray/geo/state.json`, `geoip.dat` and `geosite.dat`, with each data file limited to 128 MiB.
Archive manifest and state data digests are checked before network-disabled Xray parsing validation.
Recovery does not download Geo data. With `enabled=true`, it installs the target host's daily
automatic-update schedule after installation and health checks succeed. With `enabled=false`,
the data remains in use, but recovery does not install or take over an existing Geo schedule.
Preview does not install schedules.
Renewal recovery accepts `enabled=false` DNS, standalone, webroot or ALPN registrations and DNS
credentials, preserving original bytes and `0700/0600 root:root` permissions without installing
a renewal schedule. Disabled or absent registrations do not take over existing external renewal
tasks. Non-DNS registrations must not contain credentials.
ACME recovery accepts only acme.sh `3.1.6`, one domain and EC-P256 account and domain keys.
Standalone HTTP-01 on `8080` requires a matching schema `2` registration and `.tls.http01` disabled.
Managed webroot requires a matching schema `3` registration, `.tls.http01` enabled and an existing
Nginx TLS listener `21`-`25`/`27`/`29`. Its path is fixed at `/var/lib/padm/acme-webroot`;
self-listening port fields and custom paths are rejected.
TLS-ALPN-01 requires matching schema `4`/`alpn` registration, `Le_Webroot='alpn'`
and `Le_TLSPort='8443'`, with no `Le_HTTPPort`. A valid HTTP-01 listener may coexist;
future renewal still rechecks port `443` ownership.
DNS-01 accepts only schema `1`/`dns_acmedns`, `Le_Webroot='dns_acmedns'`, and preregistered
`ACMEDNS_USERNAME`, `ACMEDNS_PASSWORD`, `ACMEDNS_SUBDOMAIN` and `ACMEDNS_BASE_URL`.
All four values must exactly match private `credentials.env`; the URL must be canonical HTTPS,
and self-listening ports are rejected. The external acme-dns registration and DNS CNAME must
remain valid; recovery does not rebuild that service or register interactively.
Recovery parses data without executing
archived shell, rebuilds exactly nine files and discards only known CSR/transient material.
Unknown configuration, hooks, other DNS providers, SAN/RSA/EAB and custom execution paths are rejected.
A network-disabled trusted ops container verifies private/public key, ordered certificate
chain and fixed TLS-output bindings before preserving the account and domain keys.
Only a matching verified standalone, webroot, ALPN or `dns_acmedns` registration may also use `enabled=true`, with no other domain in
the renewal registry. After candidate installation
and health checks succeed, applicable schedules are installed in traffic, Geo, then renewal order.
Other enabled DNS providers and all other ACME combinations remain rejected.
Preview does not install schedules. An empty `data/acme` remains compatible but cannot authorize
enabled renewal. Focused validation, enabled recovery followed by real renewal against a local
CA, and the 34-check daily `docker-contracts` integration gate have passed.
Public-CA and native-host validation remain separate.
Managed Reality coexistence regenerates stream
configuration from the spec and reports public port `443`; archived Nginx stream files are
not executed. Bridge-reachable host-website recovery preserves domains, upstream address and port,
accepting only host-gateway or routable IP addresses. Loopback, host networking and unhandled
host-main inputs remain rejected. The host operator must still provide the website service,
content and its certificates; this archive does not restore them.
Release version, signature identity, manifest hash and every image must exactly match an
independently verified release; supply matching assets explicitly for an older archive.
Preview creates private `0700` staging, may pull digest-pinned images and runs candidate
validation containers. It regenerates configuration from the spec rather than executing
archived Compose, image environment files or scripts. Saved totals, quotas and historical
traffic keys remain; old baselines are cleared and over-quota accounts are disabled in the
candidate. Staging is cleaned on success, failure or interruption. No deployment or schedule
is installed. Unlike `backup verify`, preview is not completely read-only.
The same supported scope can be applied from menu `7 → 1 → 9`; older archives still require matching release assets:

```bash
padm-docker restore apply /root/padm-recovery.tar --confirm PADM-DOCKER-RESTORE
padm-docker restore recover
```

For a controller, shut down and isolate the old host first, then use maintenance
menu `7 → 1 → 11/12` or:

```bash
padm-docker restore preview /root/padm-recovery.tar --rebuild-controller
padm-docker restore apply /root/padm-recovery.tar --rebuild-controller --confirm PADM-DOCKER-RESTORE-CONTROLLER-ISOLATED
```

This requires a same-architecture v3 empty target, complete canonical WireGuard inputs and
matching original spec/published state. V1 still requires a single Peer; v2 preserves its nonempty
control Peer collection and all WireGuard entries, with every registered address matched.
Control-log registration, source evidence, historical
logs and persistent sync authorization are rejected. Accounts, totals, API port and WireGuard
keys/addresses are preserved; controller and all Peer identities are regenerated, every old authorization
is disabled/expired, and revision starts at zero. Issue a new invitation for each Peer and explicitly run
`control rebind` on each controlled node. Ordinary identity, revision and credential-collision
checks remain enforced. A new identity cannot revoke a surviving old copy, so isolation is
required; preserving the old controller identity or replacing an existing deployment is unsupported.

Before the first business write, the transaction persists trusted candidate shutdown inputs,
empty-directory metadata and schedule snapshots. Installation, health, traffic, Geo or renewal scheduling
failures and INT/TERM roll back this restore. After registration, SIGKILL recovery can continue
with menu `7 → 1 → 10` or `restore recover`. Ordinary deployment operations refuse pending cleanup.
Failed recovery preserves evidence; external schedule changes are rejected rather than overwritten.
Traffic, Geo and renewal have separate private persistent snapshots. Rollback checks all registered
external schedules for drift before restoring renewal, Geo and traffic in reverse installation order.
When recovery must write systemd units, the unit directory and private deployment staging
must share a filesystem so complete files can be replaced atomically. Cross-filesystem
unit writes are rejected before external schedule changes; cron-only recovery is unaffected.
Committed transactions only clean staging on retry and do not stop the deployment.
Commit metadata and schedule source/build staging use fixed private paths inside the registration.
Partial writes or a hard kill can be cleaned by rollback or committed-cleanup retries; partial metadata never proves a commit.
Preparation creates private registration before creating the exact registered extraction and
candidate directories. After a hard kill during initial metadata publication, extraction or candidate
generation, `restore recover` verifies the original empty skeleton, paths and permissions before cleanup.
Preparation recovery does not execute unvalidated Compose or change external schedules; unknown staging or tampering is rejected.
Existing-deployment replacement, other persistent inputs, role migration, native fresh-host checks
and complete disaster recovery remain deferred.

## User Traffic and Quotas

The Docker menu exposes `2. Subscriptions & users → 3. Traffic and quotas`.
Saved-counter display does not collect implicitly. Collection also checks quotas;
quota changes and resets require one confirmation, and reset retains the limit.
Enter `0` for unlimited, or an empty value or `r` to return; use the exact displayed
account ID. Collection, core restarts, locking and recovery retain CLI semantics.
Failure may occur after sampling or quota state has been saved.

`configure` and `update` configure user statistics for the active core and install a host collection task that runs every minute. The task prefers `padm-docker-traffic.timer`, with a running cron daemon as the fallback. Both Xray and sing-box accumulate upload and download bytes by stable account ID. The same UUID across protocol inbounds shares one total, while display names are preserved separately.

```bash
padm-docker traffic collect
padm-docker traffic show
padm-docker traffic limit <account-id> 100
padm-docker traffic limit <account-id> 0
padm-docker traffic reset <account-id>
```

`collect` samples traffic and applies quotas immediately; `show` displays saved counters and the account IDs used by the other commands. `limit` uses GiB, with `0` meaning unlimited, and applies to upload plus download. `reset` clears the accumulated usage, keeps the limit, and restores users whose quota is available again. Disabling or restoring users validates the new configuration and restarts only the affected core, briefly interrupting its existing connections.

The complete user configuration is kept in `config/<core>/users.base`; users over quota are removed only from the runtime configuration. Totals, limits, and sampling baselines are stored in `/etc/padm-docker/data/traffic/state.json` and survive core restarts, configuration regeneration, and version rollback. Collection failures preserve existing totals. Quotas are checked every minute, so usage may exceed the limit by one sampling interval plus scheduling delays. Traffic not yet sampled before an unexpected exit cannot be recovered.

Dual-core collection samples and rechecks both cores before writing totals once.
The same UUID shares one quota across cores. Both candidates are validated before quota application;
a restart failure or interruption attempts to restore all core configurations without reverting totals.

sing-box collection requires host `nsenter` and an HTTP/2-capable `curl`, which access `127.0.0.1:10087` inside the container network namespace. Xray uses its in-container stats command at `127.0.0.1:10085`. Stats ports are not published publicly, and containers do not mount the Docker Socket. `down` and `uninstall` remove the collection schedule; `up` and `restart` restore it.

## Updates

Updates accept only a signed CI Release manifest. The default command reads the latest Release manifest, a Cosign-signed Sigstore bundle v0.3, and the control bundle; local or HTTPS assets can be supplied explicitly:

```bash
padm-docker update
padm-docker update \
  --manifest <URL|file> \
  --bundle <URL|file> \
  [--control-bundle <URL|file>]
```

`padm-docker update` updates all five images and the host control scripts together; a separate `install` is no longer needed. The transaction verifies the manifest, validates and stages the control bundle, pre-pulls all five digest-pinned images, validates the current configuration, saves a `backups/update.*` snapshot, switches image references and the atomic control bundle pointer, and waits for Compose health checks. Pull or validation failures leave the current deployment unchanged. A switch, startup, health-check, or collection-schedule failure attempts to restore the old configuration, image references, and control scripts. Production hosts never build images online. To publish a new version, update the lock inputs and let CI publish a Release, then run `padm-docker update` on the production host.

Older versions without control script self-updates need a one-time transition: download `/root/install-docker.sh` again, run `bash /root/install-docker.sh install --ref <40-character commit SHA of this release>`, then run `padm-docker update`. Subsequent updates need only `padm-docker update`.

## Rollback

```bash
padm-docker rollback
```

Rollback uses only the most recent managed `update.*` snapshot and moves back one version, also restoring its recorded control scripts. Legacy snapshots without a control bundle pointer restore only deployment configuration and images, without guessing an old script version. It fails rather than guessing at an arbitrary historical version when no valid snapshot exists. Once user statistics are enabled, a sing-box rollback target must include `with_v2ray_api`; incompatible targets are rejected before stopping the current deployment to preserve quota enforcement. If rollback itself fails, the command attempts to restore the current version and keeps the backup path for diagnosis.
The control bundle must declare support for the snapshot's spec version. A v2 snapshot
cannot use a v1-only bundle, and a v3 snapshot cannot use a v1/v2-only bundle.
Valid older single-core snapshots remain restorable; unused core services are removed and accumulated traffic is retained.

## Uninstall

```bash
# Stop services and remove the Docker CLI while retaining state, data, backups, and images.
padm-docker uninstall

# Remove the five images pinned by digest in the deployment record and retain the state directory.
padm-docker uninstall --remove-images

# Create a final backup and delete /etc/padm-docker. This irreversible operation requires explicit confirmation.
padm-docker uninstall --purge --confirm PADM-DOCKER-PURGE
```

Normal uninstall removes only this project's Compose containers, network, and CLI link. It does not run a global `docker prune` or delete another Compose project or user volume; Docker Engine, the Compose plugin, and repository files installed by the bootstrap are not removed by `padm-docker uninstall`. `--purge` deletes only the managed state root with a valid Docker mode marker; do not use it when the data must be retained.
