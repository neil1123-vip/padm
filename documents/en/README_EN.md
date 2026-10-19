<h1 align="center">padm</h1>

<p align="center"><strong>✨ One workflow for Xray-core / sing-box installation and long-term operations</strong></p>
<p align="center">🚀 Node setup · 🔗 Subscription publishing · 🌐 Multi-server coordination · 🧭 Routing · 🔐 Certificates · ⚙️ Core upgrades</p>
<p align="center"><a href="../../README.md">🌍 中文</a></p>

<p align="center">
  <a href="#quick-choice">🚀 Quick choice</a> ·
  <a href="#installation">📦 Installation</a> ·
  <a href="#docker-mode">🐳 Docker mode</a> ·
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

`target.example.com` in the commands below is only a placeholder. Replace it with a Reality target that passes the live checks.

Recommended direct Reality Vision:

```bash
bash install.sh --install-type custom --core xray --protocols 1 --entry-host node.example.com --reality-target target.example.com:443 --reality-server-name target.example.com --reuse-last no
```

Recommended CDN Reality XHTTP:

```bash
bash install.sh --install-type custom --core xray --protocols 2 --entry-host cdn.example.com --reality-target target.example.com:443 --reality-server-name target.example.com --reuse-last no
```

No-domain Reality:

```bash
bash install.sh --install-type reality --core xray --reality-target target.example.com:443 --reuse-last no
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

## Docker Mode

Docker mode isolates the cores, Nginx, subscription services, and operations tasks from the host system. It has a separate, mutually exclusive entry path: native mode uses `install.sh` / `padm`, while Docker mode uses `install-docker.sh` / `padm-docker`. Neither mode automatically mixes with, migrates, or takes over the other deployment.

### Installation

The Docker entry installs and verifies the Docker control bundle. If Docker is missing, `install` asks for explicit confirmation before bootstrapping Docker Engine and the Compose CLI plugin (v2 or later). It does not run `docker build` on production hosts or install Xray, sing-box, Nginx, or their application dependencies on the host. Images are prebuilt and published by this repository's CI; complete first configuration in the menu:

```bash
wget -O /root/install-docker.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install-docker.sh" && chmod 700 /root/install-docker.sh && /root/install-docker.sh install
```

Installation opens the menu automatically when it succeeds in an interactive terminal.
After installation, run `padm-docker` or `padm-docker menu` for status, start/stop/restart,
and logs. Select `1. Install & reinstall → First configuration` to choose the core, protocols, addresses, and certificates.
The wizard covers Xray Reality Vision/XHTTP/gRPC and WS TLS, and sing-box
Reality Vision/gRPC, Hysteria2, AnyTLS, NaiveProxy, Shadowsocks, and TUIC.
It never overwrites an existing deployment; use the editor below instead. Full protocol management remains deferred.
`install --no-menu` disables the automatic menu. A non-interactive invocation without
arguments only prints help without installing Docker, downloading the bundle, or
initializing state. Existing explicit CLI commands remain available.

The home screen shares the native menu's style and eight task groups:

| Number | Menu | Common actions |
| --- | --- | --- |
| `1` | Install & reinstall | First configuration, core/protocol reselection, full-spec reinstall |
| `2` | Subscriptions & users | `1` accounts, `2` subscriptions, `3` traffic/quotas, `4` control connection, `5` business backup |
| `3` | Protocols & entry | REALITY, XHTTP, Hysteria2, TUIC, extra ports and CDN; `9` advanced listener management |
| `4` | Sites & certificates | `1` TLS fallback/sites, `2` local TLS certificates |
| `5` | Routing & access control | `1` routing tools, `2` BitTorrent, `3` access control |
| `6` | Cores & services | Status, start/stop/restart, logs and validation; `7` upgrade assessment, `8` Geo, `9` editor |
| `7` | System & script | `1` existing release maintenance, `2` installation status, `3` Fail2ban |
| `8` | Advanced/dangerous actions | `1` uninstall while retaining data, `2` VLESS Encryption experiment |

Specialized pages retain their existing action numbers: the old protocol menu `9`
is now `3 → 9`, the full routing menu `17` is `5 → 1 → 9`, and maintenance menu `18`
is `7 → 1`. SOCKS5 inbound at `5 → 1 → 3 → 2` remains unavailable, with the fixed
cores' authentication and source-restriction limitations shown.
Both modes retain their existing core-upgrade mechanisms; Docker still upgrades and
rolls back a verified release bundle as a unit. The shared style also covers headings,
lists and summary borders in menus, first configuration, TLS management and the editor.
Specialized action numbers, input order, defaults, hidden credentials, confirmations and
transactions remain unchanged, as does noninteractive `--preview` output.
Feature-support boundaries and native-host acceptance requirements remain unchanged.

```bash
padm-docker setup
padm-docker validate
padm-docker status
```

Only the final confirmation permits release verification, UUID/Reality/token generation,
and candidate configuration or certificate preparation. Missing `cosign` stops the operation;
the wizard neither installs an untrusted verifier nor allows verification to be skipped.
WS TLS, Hysteria2, AnyTLS, NaiveProxy, and TUIC can use managed certificates, an imported full certificate chain and private key,
or DNS-01/HTTP-01 standalone. Private keys and DNS credentials must be regular files readable only by their owner.
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
Public frontend and host/arm64 acceptance, performance benefits, and full management remain `deferred`.

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
An existing v3 deployment can add supported protocols through menu `3 → 9 → 14` or
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

Docker menu `3 → 9 → 19. Shadowsocks self-use user-key rotation` or these commands
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

Menu `3 → 9 → 20. Shadowsocks server-key rotation` or `edit --rotate-ss-server <listener-id>`
reuses the same focused transaction and preview/confirmation options, changing only the selected
listener's `shadowsocks.server_password`. Self-use and independent account user keys, UUIDs,
other listeners, share authorizations/tokens, quotas, and accumulated traffic stay unchanged.
The main subscription and every account URI for that listener change, so all its clients must
reimport them. Other listeners sharing the UUID are not rotated; draining existing connections
is not promised. Ordinary `--spec` key freezing remains. Current verification is recorded in
plan 3D.25; host integrations and full management remain outside this scope.

```bash
padm-docker edit
padm-docker edit --spec /root/original-spec.json --preview
padm-docker edit --spec /root/original-spec.json --confirm PADM-DOCKER-EDIT
```

Advanced listener management at `3 → 9` lists stable listener IDs, cores, protocols, addresses/ports,
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

The port-hopping manager at `3 → 9 → 11` configures, starts, stops, clears and shares active Hy2/TUIC range DNAT.
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
three override types and gRPC TLS listeners without overrides. Reality gRPC and other TCP/UDP
protocols remain outside this scope; external CDN, TLS/H3 and download services must already exist.
The native CDN menu provides H3 guidance rather than a separate parameter switch.
Public passthrough and complete environment acceptance remain `deferred`.

Newly generated `21/22/23` TLS frontends reject an incorrect Host. Without CDN
fields, the complete legacy Nginx output remains valid for reads and edit baselines;
the next confirmed configuration edit generates the new output. CDN fields require
the new output. Partial Host-gate removal or other manual drift is rejected.
Listeners `24/25` retain managed Nginx HTTP/2 gRPC proxying and strict TLS identity.
The WS Host/path gates do not apply to gRPC. Public CDN provider passthrough still
requires separate acceptance.

`--preview` does not commit, collect traffic, or start/stop application services.
Validation still verifies the release, pulls images, and runs candidate checks.
`edit` verifies the current deployment version rather than latest by default; it also
accepts the same-version release asset options below.
First configuration writes `schema_version: 3`; `configure` and backup restoration
continue to accept v1/v2. Editing first verifies the original spec against the deployment,
then migrates only the private draft to v3 without changing managed state before confirmation.
V3 records each listener's `core` and `core.secondary_type` (`null` for a single core),
with up to 16 listeners across both cores. V2 remains single-core.
Xray supports Reality Vision/XHTTP/gRPC and WS TLS; sing-box supports Reality
Vision/gRPC, Hysteria2, AnyTLS, NaiveProxy, Shadowsocks, and TUIC.
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
Nginx-side rotation and managed core-side TLS foundations are implemented.
Reality XHTTP/gRPC, Hysteria2, AnyTLS, NaiveProxy, Shadowsocks, and TUIC basic listeners
are implemented; remaining protocol types and full protocol management remain deferred.
WS listeners managed by Fail2ban cannot yet be added, deleted,
or assigned a different public port; those changes require coordinated firewall rules.
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
`x-padm-vless-encryption`. Linux amd64 experiments passed with fixed Xray `26.3.27`
and Mihomo `v1.19.28`; other clients, algorithms, public networks, native hosts, and
arm64 remain unverified. The complete feature remains `deferred`; see
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

To pin the control script version, change `install` to `install --ref <40-character commit SHA>`; do not treat `latest` as a production lock. A CI Release provides `release-manifest.json`, a Cosign-signed Sigstore bundle v0.3 (`release-manifest.sigstore.json`, with the signature embedded), and `padm-docker-bundle.tar.gz`; updates verify the bundle signature and digests.

Automatic releases require unpublished changes to installation entrypoints, runtime scripts, Docker configuration, image inputs, or version locks on `main`. Docker tests, release scripts, and CI changes also trigger `Release` checks; without pending runtime changes, only Docker contract tests run, with no version bump, image build, or published assets. After a failed release, pushing a test or CI fix resumes the unpublished runtime changes. Documentation-only changes do not trigger a run. PR `Docker CI` first runs independent actionlint and Shell syntax gates, then selects `ci-pr` or the full `ci` native regression profile from the changed paths before building images; `Release` runs the full gate and read-only checks that the locked APK versions exist in both Alpine architectures before bumping the version. After the version commit, the current Release run hands off to a new run so the same version is not built twice. Release runs process the latest `main` serially and publish only after all three assets are uploaded and their digests verified. Run `Release` manually to retry or explicitly publish; PRs and manual image validation use `Docker CI`.

CI decides which images to rebuild from each image directory, shared build definitions, and the lock values it consumes. Unchanged images keep the `tag@sha256` from the previous verified manifest, so their tags may precede the current script version; they only go through manifest, platform digest, and signature verification. Each changed image is built once per architecture, tested by its exact digest, then merged and signed. Without a trustworthy baseline, CI rebuilds all images. SBOM, provenance, and image signatures stay in the OCI registry; diagnostic JSON files remain in Actions artifacts for 7 days instead of being duplicated as Release attachments.

The example file contains placeholder digests, keys, and tokens and must not be used as-is. Production image references must use the version tag and digest from a CI Release, for example `ghcr.io/neil1123-vip/padm-xray:3.1.9@sha256:<digest>`; do not use `latest` or hand-edit an unpublished tag on the host.

### Five Images

All five images are defined by Dockerfiles in this repository. The current baseline builds them from a locked Alpine 3.24.1 base image; its digest, upstream versions, and architecture checksums are locked in `versions.lock`, then CI builds multi-architecture `amd64/arm64` images. One image may be reused by multiple Compose services, while long-running responsibilities remain separate containers.

| Image | Responsibility | Host integration |
| --- | --- | --- |
| `padm-xray` (`xray`) | Xray-core, Geo data, and core configuration validation. | Regular bridge container. |
| `padm-sing-box` (`sing-box`) | sing-box, configuration validation, and its protocol runtime. | Regular bridge container. |
| `padm-nginx` (`nginx`) | TLS, WebSocket, reverse proxy, and static entry. | Publishes only the selected entry ports. |
| `padm-ops` (`ops`) | ACME, subscription control, Geo/sync, and other operations, run as long-lived or one-shot Compose services as appropriate. | No Docker Socket. |
| `padm-net` (`net`) | WireGuard, Fail2ban, TUN/TProxy, and port/firewall integration tools. | Uses `NET_ADMIN`, host networking, or `/dev/net/tun` only in explicit `net-*` profiles. |

The `net` image contains the feature tools, but WireGuard, forwarding, TUN, and firewall objects still belong to the host kernel. These privileged profiles are disabled by default. Regular services do not use `privileged`, `SYS_ADMIN`, or the Docker Socket.

### State and Daily Control

The Docker state root is fixed at `/etc/padm-docker`; Docker mode never reads or overwrites the native `/etc/padm` state. Common commands are:

```bash
padm-docker status
padm-docker up
padm-docker down
padm-docker restart
padm-docker logs
padm-docker validate
```

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
Manage TProxy through menu `5 → 1 → 9 → 43`, or:

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

Manage Redirect TCP through menu `5 → 1 → 9 → 47`:

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

Manage TUN through menu `5 → 1 → 9 → 44`:

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
and accepts a literal IPv4 address; both its port and the local listen port must be `1024–65535`.
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
# 被控端先停用自动同步；主控端先停用控制日志调度和控制面 Fail2ban。
padm-docker control set-port --port 19443 --yes
padm-docker control invite --output /root/padm-control-new-port.json --yes
# 将新邀请安全传至被控端，再执行：
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
padm-docker edit --http01 enable --preview
padm-docker edit --http01 enable --confirm PADM-DOCKER-EDIT
padm-docker acme <issue|renew> --domain example.com --email admin@example.com --webroot
padm-docker acme schedule enable --domain example.com --email admin@example.com --webroot
padm-docker acme schedule status
padm-docker acme schedule disable --domain example.com
padm-docker acme auto-renew
```

Menu `4 → 2. Local TLS certificate management` validates certificates, imports replacements, or runs DNS-01/HTTP-01 standalone/webroot issue/renew.
It also explicitly enables/disables the HTTP-01 listener and manages automatic renewal.
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

### Trusted Release Inputs

The first-configuration wizard verifies release inputs automatically. To inspect a release independently or prepare non-interactive configuration, check the signed release, its control bundle, and all five digest-pinned images:

```bash
padm-docker release
padm-docker release --manifest /path/release-manifest.json \
  --bundle /path/release-manifest.sigstore.json --control-bundle /path/padm-docker-bundle.tar.gz
```

On success, stdout contains only JSON with `release` and `images`. It is emitted after signature verification, archive validation, and all image pulls succeed; progress and errors use stderr. This command does not generate a complete spec or credentials, switch installed control scripts, or start or reconfigure services. Image pulls do update the host Docker cache; local release assets do not imply offline image availability. The JSON output is not a signature proof: subsequent configuration must still check the original manifest and Sigstore bundle.

`cosign` must support Sigstore bundle v0.3. A missing tool stops the command without bypassing verification or automatically installing host tools. Install it from an independently trusted package source or verify its provenance using Sigstore's official release instructions, then retry. An unverified manifest cannot choose the trusted publisher identity or verifier source.

### Recovery Archives

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

### User Traffic and Quotas

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

### Updates

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

### Rollback

```bash
padm-docker rollback
```

Rollback uses only the most recent managed `update.*` snapshot and moves back one version, also restoring its recorded control scripts. Legacy snapshots without a control bundle pointer restore only deployment configuration and images, without guessing an old script version. It fails rather than guessing at an arbitrary historical version when no valid snapshot exists. Once user statistics are enabled, a sing-box rollback target must include `with_v2ray_api`; incompatible targets are rejected before stopping the current deployment to preserve quota enforcement. If rollback itself fails, the command attempts to restore the current version and keeps the backup path for diagnosis.
The control bundle must declare support for the snapshot's spec version. A v2 snapshot
cannot use a v1-only bundle, and a v3 snapshot cannot use a v1/v2-only bundle.
Valid older single-core snapshots remain restorable; unused core services are removed and accumulated traffic is retained.

### Uninstall

```bash
# Stop and remove the Docker control command; keep state, data, backups, and images
padm-docker uninstall

# Keep the state root and remove only the five exact digest images recorded by deployment
padm-docker uninstall --remove-images

# Create a final backup, then delete /etc/padm-docker (irreversible; explicit confirmation required)
padm-docker uninstall --purge --confirm PADM-DOCKER-PURGE
```

Normal uninstall removes only this project's Compose containers, network, and CLI link. It does not run a global `docker prune` or delete another Compose project or user volume; Docker Engine, the Compose plugin, and repository files installed by the bootstrap are not removed by `padm-docker uninstall`. `--purge` deletes only the managed state root with a valid Docker mode marker; do not use it when the data must be retained.

## System Requirements

padm is designed for Linux servers. The code detects Debian, Ubuntu, RHEL/CentOS/AlmaLinux/Rocky/Oracle Linux, Fedora, and Alpine, then uses `apt`, `yum`, or `apk` as appropriate.

| Item | Requirement |
| --- | --- |
| Permission | root or equivalent privileges. |
| Architecture | `x86_64/amd64`, `aarch64/arm64`. |
| Basic commands | Entry download needs at least `curl` or `wget`; the wget fallback also needs `timeout` to bound total duration. Full bundle refresh needs `tar`. |
| Common dependencies | The script installs or uses `jq`, `nginx`, `acme.sh`, WireGuard tools, Fail2ban, and related tools as features require. |
| Service management | Core services prefer systemd; Alpine/OpenRC paths are handled separately. The controller/controlled subscription control service currently requires systemd and `python3`. |

### Docker Requirements

| Item | Requirement |
| --- | --- |
| Operating system | Linux; the Docker daemon must run Linux containers. Windows, macOS, and Docker Desktop are outside the initial support scope. |
| Permission and connection | root, a rootful Docker Engine, and the local rootful Unix socket; rootless daemons, remote contexts, and user sockets are unsupported. |
| Compose | Docker Compose CLI plugin (major version v2 or later). |
| Architecture | `amd64` or `arm64`, with matching host and daemon architecture. |
| Host commands | Bash 4+, `jq`, `sha256sum`, `tar`, and either `curl` or `wget`; trusted release inputs and signed updates also require Cosign with Sigstore bundle v0.3 support (CI currently uses 3.x). If Docker is missing, `install-docker.sh install` asks whether to install Engine, the Compose CLI plugin, and the host prerequisites from Docker's official repository. |
| User statistics | A running systemd or cron daemon. sing-box also needs host `nsenter` (usually from `util-linux`) and an HTTP/2-capable `curl`. Configuration and updates stop if these requirements are missing. |
| Kernel capabilities | The regular profiles need no extra capability. WireGuard, Fail2ban, TUN/TProxy, and other `net-*` profiles require the capability, host networking, or `/dev/net/tun` specified by the support matrix. |

On the first `install-docker.sh install`, if the `docker` command is missing, the script asks whether to install Docker Engine and the Compose CLI plugin from Docker's official repository. A no/empty answer, EOF, or an installation failure stops before `/etc/padm-docker` is initialized. Host package or repository changes that already completed are not removed implicitly. The prompt is only for a missing command; an existing Docker installation with an unavailable daemon or Compose still fails without reinstalling. Automatic installation currently covers rootful systemd hosts running Debian, Ubuntu, CentOS, Fedora, or RHEL; install Docker manually on other distributions. The script does not install Xray, sing-box, Nginx, or other application dependencies on the host, and it never runs `docker build`. If a native installation is active, present, or leaves ambiguous residue, the Docker entry refuses to proceed; there is no implicit migration between modes.

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

padm is not one giant Bash file. It is a pair of independent entry paths plus a modular runtime:

1. The native entry is `install.sh`, and the Docker entry is `install-docker.sh`; they maintain `/etc/padm` and `/etc/padm-docker` separately and never migrate or mix deployments.
2. Module refresh atomically replaces `shell/`, `documents/`, `assets/`, `README.md`, and `.padm-module-manifest`; on failure it tries to restore the previous module bundle.
3. `shell/core/bootstrap.sh` assembles the runtime by loading platform, runtime, protocol, Reality, service, routing, TLS, subscription, and menu modules.
4. The interactive menu and formal subcommands share the same module set. Formal subcommands include `RenewTLS`, `UpdateGeo`, `SyncSubscriptionGroups`, `SubscriptionControl`, and `InstallSubscription`.
5. The Docker control bundle lives under `docker/`; the host-side `padm-docker` calls Docker CLI and Compose directly, and containers never mount the Docker Socket.
6. For troubleshooting, identify the real control point first: entry script, module load order, state file, generated config, and validation command, not just menu copy.

| Path | Purpose |
| --- | --- |
| `install.sh` | 🚪 Repository entry script; handles self-refresh, argument parsing, formal subcommands, and first-run module bootstrap. |
| `install-docker.sh` | 🐳 Independent Docker entry; installs and refreshes the Docker control bundle without building images. |
| `padm-docker` | 🎛️ Installed host-side Docker command; controls the fixed `padm-docker` Compose project. |
| `docker/` | 📦 Dockerfiles, Compose, manifests, configuration contracts, and lifecycle implementation. |
| `shell/core/` | ⚙️ Platform detection, runtime helpers, protocol templates, Reality/TLS/routing/service/menu logic. |
| `shell/subscription/` | 🔗 Subscription publishing, subscription-group state, user accounts, WireGuard control plane, remote sync, and traffic accounting. |
| `shell/regression/` | 🧪 `framework/` provides the environment, runners, and registry; `cases/` loads fixtures, stubs, and test functions once; `suites/` only registers selectors, groups, and compositions. |
| `shell/subscription_groups_regression.sh` | 🧪 The single public regression dispatcher for suite, aggregate, contract, and composition selectors. |
| `shell/validate_install.sh` | ✅ Read-only post-install validation script. |
| `documents/` | 📚 Example configuration and the English README. |
| `assets/` | 🖼️ Three local static-site themes for Nginx or native Hysteria2. |

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

Docker deployment state sources:

| Path | Purpose |
| --- | --- |
| `/etc/padm-docker/mode` | 🏷️ `docker` mode marker used for mutual exclusion and uninstall protection. |
| `/etc/padm-docker/bundle` | 🔗 Atomic pointer to the currently verified control bundle. |
| `/etc/padm-docker/deployment.json` | 🧾 Current release, profiles, ports, and five image digests. |
| `/etc/padm-docker/compose.json`, `images.env` | 🐳 Current Compose configuration and pinned image references. |
| `/etc/padm-docker/config/`, `data/`, `secrets/`, `backups/` | 💾 Configuration, runtime data, secrets, and update/uninstall backups. |

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

A common setup is: client entry `node.example.com`, a measured Reality target such as `target.example.com:443`, and Reality SNI `target.example.com`.

Reality Vision, Reality XHTTP, and Reality gRPC never request a local TLS certificate. A Reality-only install does not create or remove sites, touch ACME/cron, or stop, start, or reload Nginx. `--reality-domain yes` enables strict-domain mode only for a single Reality Vision `1` selection and validates the entry hostname and DNS; protocol `2`, `26`, or any multi-selection is rejected before dependencies or configuration writes.

Reality entry selection is `--entry-host`, then `--domain`, `/etc/padm/reality_entry_host`, `currentHost`, and finally the public IP. A normal single Reality port is selected as explicit `--port`, previous port, then `443`. Multi-protocol installs keep independent protocol ports and do not inject top-level `--port` into a Reality sub-port. With 443 coexistence enabled, clients keep using the recorded public port while the core reuses the recorded internal port.

When `--reality-target` is omitted, the script opens the target selector. Automatic selection prefers measured results with `cdn_risk=no` and score A. Only a fresh sing-box install without an Xray detector may fall back to a transient `no + C` result whose TLS 1.3 handshake was verified by OpenSSL during the current probe; that result is not written to the main result table. Installation stops instead of writing an untested fallback when no acceptable result exists. Manual targets resolve every A/AAAA address, score each address, and use the worst score: any address in AS13335 or able to answer a `cloudflare.com` SNI probe is marked `cloudflare_relay`; a DNS CNAME pointing at a known CDN edge hostname, or a known dedicated CDN ASN/organization, is marked `cdn_edge`; both are rejected. Incomplete DNS, ASN, or TLS probing is marked `unknown` and rejected. Manual selection accepts only `no + A/B/C`, with an explicit warning for B/C. Checking the currently installed target only warns and never switches the configuration silently. `java.com`, `nodejs.org`, `riotcdn.net`, and their subdomains are statically excluded from candidate refreshes, scanner imports, and automatic selection.

The built-in candidate pool physically contains only 37 entries that do not match known CDN/edge-proxy or static risks. The 154 CDN/edge-proxy domains from the original 194-entry audit remain in a separate blacklist list for runtime filtering, audit, and blacklist display, but are no longer emitted by the candidate pool. Unknown or TLS-failed entries in the pool still require live checks and are never selected automatically. The four entries with explicit direct-connection evidence and the default recommendation are `www.gnu.org`, `www.debian.org`, `www.ubuntu.com`, and `mariadb.org`. Candidate filtering is keyword-based; `dev`, `developer`, and `开发者` are aliases for the same filter.

The main Reality result table is a 16-column TSV at `/etc/padm/reality_targets_results.tsv`, with the measured IP's English location in the final column, such as `Los Angeles, United States`; legacy 15-column rows remain supported. Successful IP geolocation results are reused by full IP address. Batch writes query only unique uncached IPs in parallel batches, using `PADM_REALITY_SECONDARY_JOBS` with a default of 8 and a maximum of 16 requests, then commit all results together. If the city is unavailable, the region or country is shown; lookup failures display `Unknown` without affecting scoring or target switching. The table physically retains only targets whose latest state is `cdn_risk=no`, score A, and not matched by the static or custom blacklist. A new B/C/FAIL, risky, or `unknown` result removes the target's old A record; an empty batch write also cleans legacy risky rows. Scoring covers TLS 1.3, `X25519MLKEM768`, and certificate-chain length. Eligible targets are ordered by `same_asn > same_provider > different_network > unknown`, then certificate-chain length and check time.

`Protocols & entry` -> `REALITY management` can show the current target, run `xray tls ping`, refresh the target library, run RealiTLScanner, switch from measured results, view PQC/ML-DSA-65 status, and configure 443 coexistence splitting. The refresh menu now selects the scope: the default retests the library and recommended candidates, including every `recommended=yes` candidate not yet present in the results file; select `All candidates` to cover every built-in or managed candidate. The results list and detail view share one selection and confirmation flow, without replacing the current target state on cancellation or a failed switch.

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

## Subscriptions and Users

The subscription system is role-based; local and controller home screens keep `Subscriptions & users`, `Subscription sync`, and role-specific coordination/control entries. Low-frequency maintenance actions live inside the relevant group.

| State | Menu shape | What it is for |
| --- | --- | --- |
| 🟡 Uninitialized | `Use this server locally` / `This server is the controller` / `This server is controlled` | A single server can manage local subscriptions directly; choose controller or controlled mode only for multi-server use. |
| 🟢 Controller | The controller home exposes subscriptions and users, sync, and `Coordination & control` | Create user subscriptions, publish links, add controlled servers, run sync, and handle quotas. |
| 🔵 Controlled | The controlled home directly exposes join, status, credential, and control-plane actions | Paste a controller invite, provide this server's nodes to the controller, and view WireGuard/sync state. |

Controller and local-only home screens share one `Subscription sync` menu: run a full sync, enable/disable automatic sync, set the interval, open status/troubleshooting, or manage state backups. Usage and quotas live in `Subscriptions & users`, so each task has one primary entry. The automatic-sync switch controls both immediate sync after configuration changes and cron; manual full sync remains available when it is off.

The `Subscriptions & users` entry is the single place for link refresh, shared-subscription creation/maintenance, and usage/quota access. Admin self-use subscriptions remain derived from the local protocol configuration; they are not stored in `user_groups`, do not use shared quotas, and are never pushed to controlled servers.

- A controller syncs every enabled controlled-server source. There is no separate global remote-sync switch; pause one server through `Coordination & control` -> `Controlled servers` -> `Enable/disable controlled server`.
- Sync completes the local configuration first, then handles controlled-server snapshots per source. When the local host succeeds and the remote sync result is valid, the public subscription is published from the successful sources and failed sources are omitted; the overall run is marked partial. If a remote-only user has no available source, that user's previous output is retained. A local failure or an invalid remote result keeps the whole public subscription unchanged.
- After changing a controlled server's Reality target or other node configuration, the controlled server notifies the controller over WireGuard; with automatic sync enabled, the controller regenerates local nodes, fetches enabled sources, and publishes the available sources. The outer HTTPS subscription URL stays unchanged and nodes from other successful servers remain present.
- Controlled servers do not expose an active-sync menu; if the change notification fails, run “Full sync now” on the controller.

Recommended flow for local-only or controller-side shared subscriptions:

1. From the local or controller home, open `Subscriptions & users` -> `Publish service`.
2. In the same menu, open `Create shared subscription`, using an ID such as `team-a`.
3. Follow the wizard to select server sources and traffic limit.
4. With automatic sync enabled, saving triggers one full sync. If it is disabled, run a manual full sync later from `Subscription sync`. The managed account `sub_<ID>` is written to the core config.
5. After the full sync completes, open `Subscriptions & users` -> `Refresh and view subscription links` and copy the user link.

Recommended multi-server flow:

1. On the local server, open `Enable controller coordination`, then use `Coordination & control` -> `Controlled servers` -> `Create controlled-server invite` and enter the controlled-server alias once. The controller reserves its WireGuard address automatically.
2. On the controlled server, open `Join controller` and paste the invite. Initialization and controller-peer import complete without an address prompt; copy the resulting join receipt once.
3. Back on the controller, open `Coordination & control` from the controller home, then use `Controlled servers` -> `Complete controlled-server join` and paste the receipt. The reserved alias drives the peer, source, and control-token transaction, followed by a health check for that source only.
4. To temporarily exclude one controlled server, use `Enable/disable controlled server`. Disabling preserves its peer, token, and history; the next full sync removes that source's nodes from the public subscription.
5. Pending invites can be viewed or cancelled by alias. Invites and receipts are bearer secrets, so normal status, health output, and pending lists never show their complete values. Cancel and recreate a lost invite.
6. Legacy `main` / `controlled` credentials remain only in explicitly named maintenance actions for existing links; first-time joins accept invites and receipts only. Receipts and legacy controlled credentials contain long-lived control tokens and must travel through a trusted channel.
7. WireGuard uses UDP and the control API uses HTTP only inside the tunnel, so this join flow needs no TLS certificate. Public client subscriptions continue to use HTTPS separately.

`Subscription sync` -> `State backup and restore` only affects `/etc/padm/subscribe_groups/groups.json`. Restoring a backup or rebuilding state first requires typing `yes`; only after confirmation does the script create a current-state backup. The current exact structure is a single-root `version: 6` object, with no persisted `groups[]`, `active_group`, or traffic summary fields, and it stores separate Xray and sing-box traffic baselines. Older `version: 2`, `3`, `4`, and `5` states are migrated atomically on first read. A v5 aggregate baseline is kept as a compatibility baseline until the first new-format sample replaces it with per-core baselines. The old file is backed up as the corresponding `groups-pre-v3-migration-*`, `groups-pre-v4-migration-*`, `groups-pre-v5-migration-*`, or `groups-pre-v6-migration-*`; multi-group, other legacy, and states with extra, missing, or invalid fields are rejected.

## Routing and Access Control

Docker menu `5 → 1 → 3 → 1 → 1` accepts global or domain-selective authenticated SOCKS5 TCP input.
The same terminal workflow is available through `padm-docker edit --socks5-input`.
Username and password input is hidden and credentials stay out of process arguments and previews.
Empty input or EOF cancels; password `0` is valid, while `0` in other fields returns.
The validated candidate still requires confirmation; this entry cannot be combined with `--preview` or `--confirm`.
For automation, continue to use the file-based CLI.
Use a root-owned, mode `0600`, single-link JSON file in a root-owned directory with no
group/other writable ancestors, for example
`{"server":"192.0.2.10","port":1080,"username":"user","password":"secret"}`.
This address is a format example, not a working server. Symlinks, special files and
`/tmp` ancestors are rejected; the maximum size is 64 KiB.
The upstream must be a routable IPv4/IPv6 literal; credentials must contain 1–255
visible ASCII characters without spaces or controls.

```bash
padm-docker edit --socks5 /root/padm-socks5.json --preview
padm-docker edit --socks5 /root/padm-socks5.json --confirm PADM-DOCKER-EDIT
padm-docker protocol routing-status
padm-docker edit --socks5-domains 'example.net,full:exact.example.com,keyword:video,geosite:cn' --preview
padm-docker edit --socks5-domains 'example.net,full:exact.example.com,keyword:video,geosite:cn' --confirm PADM-DOCKER-EDIT
padm-docker edit --socks5-domains-add 'full:next.example.net' --preview
padm-docker edit --socks5-domains-remove 'full:exact.example.com' --confirm PADM-DOCKER-EDIT
padm-docker edit --socks5-domains-replace 'full:exact.example.com' 'full:next.example.net' --preview
padm-docker edit --socks5-global --confirm PADM-DOCKER-EDIT
padm-docker edit --socks5-off --confirm PADM-DOCKER-EDIT
```

Optional v3 `.routing.socks5` requires the bundle capability `x-padm-routing-socks5`;
old specs remain direct. Both cores send client TCP destination traffic through the
authenticated upstream without direct fallback on failure. Client UDP destination traffic
is explicitly blocked, independently of UDP-based Hysteria2/TUIC ingress carrying TCP.
The private JSON may also include a canonical `domains` array, or rules can be replaced
after enabling the upstream: `full:` matches an exact domain, `domain:` a domain and its
subdomains, `keyword:` a safe ASCII substring, and `geosite:` an explicit category, up to
256 rules. CSV input trims whitespace, lowercases and deduplicates in first-seen order;
bare domains get `domain:`, but category names are never guessed.
Matcher types use OR: matching TCP uses SOCKS5, matching UDP is blocked, and unmatched
TCP/UDP is direct. IP traffic without a usable supplied or sniffed domain is also direct;
this is not enforced global proxying. `--socks5-global` removes only the rules.
Menu `5 → 1 → 3 → 1`, options `34/35/36`, and `--socks5-domains-add/remove/replace` edit only
an existing nonempty domain-selective list; disabled and global modes are rejected.
Additions normalize and deduplicate in first-seen order, with at most 256 merged rules.
Removal matches complete normalized rules, rejects the whole batch if any item is missing,
and preserves remaining order. Removing the last rule disables the entire SOCKS5 outbound;
enabling it again requires reimporting private credentials and never happens by switching to global.
Single-rule replacement keeps the position and rejects CSV, missing old rules, duplicate new rules
and identical values. Nonempty edits change only `domains`; `server/port/username/password`,
other routing policies and settings are frozen. Only last-rule removal may delete the whole subitem.
These menu actions show routing status first; failed status, empty input, `0` and EOF cancel
before editing. The independent CLI confirms once. Full-list replacement and global switching
remain available. Both core generators and the existing transaction are reused, with no new
schema, capability marker or host privilege.
The focused SOCKS5 list contract, menu PTY checks and all 49 integrated contracts pass.
Domain mode additionally requires `x-padm-routing-domains`. Xray uses managed or bundled
Geo data; sing-box downloads selected categories directly from the fixed SagerNet source.
Missing resources or failed downloads reject candidate startup and restore the old configuration.
Status includes `mode` and `domain_rules` without credentials; sniffing selects the route
without replacing the destination address.
Reality handshakes, statistics APIs, control services, Nginx, ACME and host traffic are
outside this scope. No new listener, host privilege or firewall rule is added; TUN/TProxy
combinations are not enabled. Changes use the existing candidate/backup/recovery transaction.
Status and previews omit credentials, but private specs, core configurations and backups
retain them. SOCKS5 authentication is not encrypted; use a trusted upstream network.
Docker also provides independent DNS/hosts, domain Direct/Block and literal-destination
IP/CIDR/`geoip:cn` policies. Direct domain exceptions have priority; default IP policies do
not resolve domain targets just to match an IP or recheck addresses after DNS/hosts.
These changes retain the same private-input and deployment transaction boundaries.
SOCKS ingress, public WARP acceptance and complete routing management remain deferred.

Menu `5 → 3`, options `14/26/27`, accepts CSV directly to set, append or remove manual
IP-block rules. The matching CLI options are `--block-ips-csv`,
`--block-ips-add-csv` and `--block-ips-remove-csv`. Each item is trimmed, with IPv6
spelling and CIDR host bits preserved; empty items, duplicates, invalid rules and more
than 256 items reject the entire input. Blank input, `0` or EOF cancels the menu action.
CSV uses the same validation, preview, confirmation and recovery transaction and preserves
the existing resolved-domain blocking mode.
`--block-ips` and `--block-ips-add/--block-ips-remove <private JSON file>` retain the
`{"ips":[...]}` format and root-owned `0600` file requirements. Append retains existing
order, then adds unseen strings in input order, with at most 256 rules after merging.
Remove requires every complete requested string to exist in the manual list; a missing
item rejects the whole operation. CIDR containment, IPv6 spelling and host bits are not
normalized or merged. Empty arrays, duplicate items and invalid rules are rejected before
merging. Removing the last manual rule preserves region-generated `geoip:cn` and other routes.
Preview and cancellation leave the deployment unchanged.

```bash
padm-docker edit --block-ips-add /root/padm-block-ips.json --confirm PADM-DOCKER-EDIT
padm-docker edit --block-ips-remove /root/padm-block-ips.json --confirm PADM-DOCKER-EDIT
padm-docker edit --block-ips-csv '192.0.2.8,2001:DB8::/32,geoip:cn' --preview
padm-docker edit --block-ips-add-csv '198.51.100.17/24' --confirm PADM-DOCKER-EDIT
padm-docker edit --block-ips-remove-csv '198.51.100.17/24' --confirm PADM-DOCKER-EDIT
padm-docker edit --block-ips-replace '198.51.100.0/24' '203.0.113.17/24' --preview
```

Menu `5 → 3`, option `33`, and `--block-ips-replace <old rule> <new rule>` replace one
literal IP/CIDR rule in an existing nonempty manual list. Status is shown before the
two inputs; blank, `0` or EOF cancels either step. Both strings are kept verbatim,
including IPv6 spelling and CIDR host bits. The complete old string must exist once;
the new string cannot duplicate any current item, including the old one. Replacement
preserves position and all other configuration. CSV, GeoIP, domain and generated
regional rules are rejected. Preview, confirmation and recovery use the existing transaction.

Menu `5 → 1 → 4`, option `6`, accepts a literal UDP DNS server IP, a port (blank defaults
to `53`), and domain-rule CSV. `--dns-rules <IP> <port> <CSV>` creates or replaces
the same DNS object using existing CSV normalization and transaction checks;
private JSON through `--dns` and all other routing policies remain available.
Menu options `28/29` and `--dns-domains-add/--dns-domains-remove <CSV>` change the
domain list of an existing DNS route while keeping its server and port. Additions
retain existing order and append unseen normalized rules, with a 256-rule limit.
Removal requires every complete normalized rule to exist; any missing item rejects
the whole operation. Removing the last rule disables that DNS route and preserves
other routing policies. Both actions reject a missing DNS route. Repeated additions
still use the confirmation transaction and may update rollback metadata.

```bash
padm-docker edit --dns-rules 192.0.2.53 53 'example.net,full:exact.example.org' --preview
padm-docker edit --dns-domains-add 'full:updates.example.net' --preview
padm-docker edit --dns-domains-remove 'full:updates.example.net' --confirm PADM-DOCKER-EDIT
```

Menu `5 → 1 → 5`, option `37`, and `edit --hosts-replace <existing exact FQDN> <new literal IP>`
replace one existing hosts value. They do not add, remove or edit mappings in batches.
Only ASCII letters in the key are lowercased; whitespace is not trimmed. The address
is kept verbatim, including IPv6 spelling and case. Whitespace, a trailing newline,
CSV, domain-rule prefixes and invalid addresses return `2`; a missing key, disabled
hosts or an identical address string returns `15`. Only the selected value may change;
other mappings, routing and the full configuration are frozen. Share URIs, subscriptions
and cumulative traffic are retained. Status is shown before either menu input; failed
status, blank input, `0` and EOF cancel. The CLI confirms once and reuses the existing
preview, candidate and health-failure/signal recovery transaction.
Private JSON full-map import through `--hosts` remains available. No schema, capability
marker, host privilege or state is added. This is a limited management enhancement;
complete native hosts migration remains deferred. The focused DNS/hosts and menu
contracts and integrated Docker contracts pass (49/49).

Menu `5 → 1 → 5`, options `38/39`, and `edit --hosts-add <exact FQDN> <literal IP>` /
`--hosts-remove <exact FQDN>` add or remove one exact mapping. Add can create a missing
hosts map, but any existing key returns `15` regardless of its value; use replacement
to change an address. The merged map is limited to 256 keys. Remove requires an existing
key; missing keys or disabled hosts return `15`. Removing the last key disables hosts
and removes routing only if no other policy remains. ASCII lowercase normalization,
untrimmed input and verbatim addresses retain their existing boundaries. Other mappings,
the full configuration, share URIs, subscriptions and cumulative traffic are preserved.
Focused Linux amd64 and menu PTY verification passes; integrated Docker contracts pass (53/53).
Complete native hosts migration, region policy and conflict detection remain deferred.

Menu `5 → 1 → 5 → 8` and interactive `edit --hosts-input` accept one literal IPv4/IPv6
and a CSV list of exact FQDNs, replacing the whole hosts map after confirmation.
Existing keys are removed. Domain whitespace is trimmed, ASCII letters lowercased
and duplicates removed; 1–256 distinct exact domains are accepted. Rule prefixes,
wildcards and empty items are rejected. The IP is kept verbatim and checked by the
full specification validator. Blank input, `0` or EOF cancels. This requires a TTY
and rejects `--preview`/`--confirm`. Private JSON import, single-key editing,
permissions and recovery remain available; support status stays deferred.

```bash
padm-docker edit --hosts-input
padm-docker edit --hosts-replace Exact.Example.NET 2001:0DB8::10 --preview
padm-docker edit --hosts-replace exact.example.net 192.0.2.11 --confirm PADM-DOCKER-EDIT
padm-docker edit --hosts-add new.example.net 2001:DB8::11 --preview
padm-docker edit --hosts-remove new.example.net --confirm PADM-DOCKER-EDIT
```

Existing DNS, Direct, Block, selective IPv6 and selective WARP domain lists support
single-rule replacement. Menu `5 → 1 → 4 → 30` handles DNS; `5 → 3 → 31/32` handles Direct/Block;
IPv6 option `7` and WARP option `10` handle their existing selective lists. Each shows
the current rules before asking for one old rule and one replacement:

```bash
padm-docker edit --dns-domains-replace 'full:old.example.net' 'full:new.example.net' --preview
padm-docker edit --direct-domains-replace 'domain:old.example.net' 'domain:new.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --block-domains-replace 'keyword:oldword' 'keyword:newword' --preview
padm-docker edit --ipv6-domains-replace 'full:old.example.net' 'full:new.example.net' --preview
padm-docker edit --warp-domains-replace 'full:old.example.net' 'full:new.example.net' --preview
```

Both values must be single rules, without commas. After normalization, the old rule
must exist exactly once and the new rule must differ from every current item, including
the old rule. Complete strings are matched; `full:` and `domain:` are distinct.
Replacement preserves the item's position, DNS server/port, WARP private fields and
all other configuration. Missing lists and global WARP/IPv6 modes are rejected.
Preview, cancellation and failure/signal recovery use the existing transaction.
Complete region and other rule management remain deferred.

Menu `5 → 1 → 7 → 1` or terminal command `padm-docker edit --http-relay-input`
accepts the relay port, address families, hidden username/password and required source CSV.
It requires an existing Xray and confirmation after candidate validation.
Empty input or EOF cancels; password `0` is valid, while `0` in other fields returns.
There is no permissive source default; the private JSON CLI and support boundaries remain.
Menu `5 → 1 → 7`, options `4–7`, manages an existing Xray HTTP relay through
`edit --http-relay-port <port>` and `--http-relay-sources`,
`--http-relay-sources-add`, or `--http-relay-sources-remove <CSV>`.
CSV trims item whitespace, deduplicates in first-occurrence order and retains literal
IP/CIDR spelling. Additions preserve existing order; removal requires every exact item
to exist. Empty results, missing items, unchanged values, invalid addresses, more than
256 sources and conflicting ports are rejected. Credentials, core, address families,
other configuration and cumulative business traffic are preserved. Status failure,
blank input, `0` and EOF return to the menu; the CLI confirms once and reuses candidate,
backup and health-failure/signal recovery. Only an already managed Xray is supported.
Native host, public network, arm64 and trusted-release acceptance for complete `202`
remain deferred. See [Docker HTTP relay](../docker-http-relay.md).

Menu `5 → 3`, options `10/12`, replaces Direct or Block domain rules using comma-separated
input. `--direct-domains <CSV>` and `--block-domains <CSV>` use the same normalization:
trim whitespace, lowercase, preserve first-occurrence order while deduplicating, and
prefix bare domains with `domain:`. They replace the whole group rather than append
to historical rules. Empty/invalid items or more than 256 unique rules are rejected;
use the corresponding off command to clear the group. Private JSON imports through
`--direct/--block` remain available, and ordinary `--spec` editing still freezes routing.
Menu options `22/23` and `--direct-domains-add/--block-domains-add` append instead:
existing order is retained, then previously unseen rules are added in input order.
A missing group is created; more than 256 unique rules after merging is rejected.
Repeated additions do not duplicate rules, but confirmation still uses the deployment
transaction and may update rollback metadata.
Menu options `24/25` and `--direct-domains-remove/--block-domains-remove` remove exact
normalized rules. Every requested rule must already exist in the selected manual list;
otherwise the whole operation is rejected. Remaining order is preserved, and the empty
manual group is removed. Region policy, IP/CIDR rules, and other routing entries are unchanged.
The read-only `direct_block_overlaps` status field lists exact manual Direct/Block
intersections in Direct order. Direct still wins; domain containment, category membership
and generated region rules are not inferred, and overlap does not make a configuration invalid.

The same status also returns `domain_rule_overlaps`, sorted by the complete rule string.
Each item contains `rule`, `policies` in Direct → Block → IPv6 → WARP → SOCKS5 order,
and the first policy as `winner`. It includes region default/custom Direct exceptions
and the `geosite:cn` Block rule generated by domain/both mode; duplicate sources within
one policy count once, and global exits are excluded. `winner` describes precedence
among policies with that identical selector, not the final route of actual traffic.
Containment, category membership, literal IP/BT rules and HTTP relay routing are outside
this diagnostic. SOCKS5 proxies TCP and rejects UDP. The status is read-only; complete
conflict detection remains deferred.

`domain_rule_coverages` reports label-boundary containment across `full:` and
`domain:` rules from different policies. `domain_rule_keyword_coverages` separately
reports `full:`, `domain:` or `keyword:` text containing another policy's `keyword:`
text, such as `full:ads.example.net` covered by `keyword:ads`, or `keyword:advert`
covered by `keyword:ad`. Both use `narrow_rule`, `broad_rule`, `policies` and `winner`,
sorted by the two rules; same-policy containment is omitted. They compare normalized
strings, exclude GeoSite membership and DNS results, and do not predict the final route
or reject configurations. Single sing-box deployments can explicitly enable resolved IP
blocking as described below. Xray remains deferred: `IPOnDemand` alone does not bind
the proxy's actual connection address or guarantee rejection on DNS failure.

Menu `5 → 3 → 45/46` and `--block-ips-resolve/--block-ips-literal` switch an existing
manual IP list between resolved and default literal-only matching. Resolved mode requires
one sing-box core and no secondary core; WARP and `.routing.ipv6` egress policies are supported.
Destination IPs may still be IPv4 or IPv6. Optional v3
`.routing.block_ips.resolve_domains:true` requires the bundle capability
`x-padm-routing-block-ips-resolve`; older bundles reject it. Returning to literal mode
removes the field.
WARP/IPv6 combinations also require `x-padm-routing-block-ips-resolve-egress`;
older bundles supporting only basic resolved mode reject combinations. Resolution selects
exact hosts, configured DNS, then local; IP rejection
runs again before routing, and proxies receive the checked literal address. DNS failure
is rejected without remote fallback. Direct exceptions retain precedence.
Routes retain selective IPv6, selective WARP, explicit SOCKS, then global egress precedence.
Each selected path resolves with its egress address family, checks the IP, then routes
immediately using that checked address.
Unchanged modes and missing lists return `15`. The list, other configuration and traffic
totals are preserved through the existing preview and recovery transaction. Status adds
`block_ips.resolve_domains:true` only in resolved mode. Xray, complete regional policies
and host firewall filtering remain deferred. WARP combinations use a local encrypted Peer
test; Cloudflare account provisioning and public egress still need acceptance.
Replacing or editing the list preserves resolved mode; removing the final item or
disabling the list also removes the mode.

```bash
padm-docker edit --block-ips-resolve --preview
padm-docker edit --block-ips-resolve --confirm PADM-DOCKER-EDIT
padm-docker edit --block-ips-literal --confirm PADM-DOCKER-EDIT
```

```bash
padm-docker edit --direct-domains 'example.org,full:exact.example.net' --preview
padm-docker edit --block-domains 'keyword:example,geosite:cn' --confirm PADM-DOCKER-EDIT
padm-docker edit --direct-domains-add 'full:updates.example.org' --preview
padm-docker edit --block-domains-add 'domain:ads.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --direct-domains-remove 'full:updates.example.org' --preview
padm-docker edit --block-domains-remove 'domain:ads.example.net' --confirm PADM-DOCKER-EDIT
```

Menu `5 → 2`, options `16–17`, enables or disables detected BitTorrent blocking.
Optional v3 `.routing.block_bt:true` requires `x-padm-routing-block-bt`; disabling
removes the field, while `false` and other values are rejected.
Only traffic the core identifies as plaintext `bittorrent` is blocked.
Encrypted/obfuscated BT, DHT and some uTP are not guaranteed, and UDP recognition
differs between cores. This is not blanket BT or port filtering.
Direct domain exceptions still take priority; detected BT is rejected before
SOCKS, DNS or hosts handling without replacing the destination.

```bash
padm-docker edit --block-bt --preview
padm-docker edit --block-bt --confirm PADM-DOCKER-EDIT
padm-docker edit --block-bt-off --confirm PADM-DOCKER-EDIT
```

Enabling adds `block_bt:true` to `routing-status`; disabling preserves all other
routing policies and traffic totals. The existing candidate, backup and recovery
transaction is reused, with no new listener, host privilege or firewall rule.

Menu `5 → 3`, option `18`, provides a CN regional preset: `domain` matches `geosite:cn`,
`ip` matches literal destination IPs against `geoip:cn`, and `both` combines them.
Optional v3 `.routing.region` stores `mode` and `allow_domains`, with the separate
`x-padm-routing-region` capability marker. Default Direct exceptions match each domain
and its subdomains: `dl.google.com`, `apple.com`, `bing.com`, `microsoft.com`,
`gstatic.com`, `xn--ngstr-lra8j.com`, `googleapis.com` and `googleapis.cn`.
Custom exceptions use the existing four domain-rule types. All exceptions follow
Direct precedence over domain/IP/BT blocking and SOCKS5, not just the regional preset.

```bash
padm-docker edit --region both --region-allow 'example.com,full:api.example.net' --preview
padm-docker edit --region domain --confirm PADM-DOCKER-EDIT
padm-docker edit --region ip --region-allow '' --confirm PADM-DOCKER-EDIT
padm-docker edit --region-mode domain --preview
padm-docker edit --region-allow-add 'example.com,full:api.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --region-allow-remove 'full:api.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --region-allow-replace 'full:api.example.net' 'full:next.example.net' --preview
padm-docker edit --region-off --confirm PADM-DOCKER-EDIT
```

`--region` replaces the mode and custom exceptions rather than accumulating old modes;
omitted custom exceptions become an empty list. Menu options `1`–`3` explicitly say
that custom exceptions are replaced and empty input clears them. Option `9` or
`--region-mode <both|domain|ip>` changes only an existing `region.mode`, preserving
custom exceptions, all eight defaults and other configuration. A disabled policy or
identical mode returns `15`; other mode values return `2`. Existing presets can add
or remove custom Direct exceptions from the regional menu. Additions normalize rules,
preserve first occurrence order and keep the custom list at most 256 entries. Removal
matches complete normalized rules and rejects the entire batch if any item is missing.
Removing the last custom entry keeps the mode and an empty list; all eight default
exceptions and other policies remain unchanged. Regional submenu option `7` replaces
one existing custom exception in place; option `8` shows routing status. Replacement
first shows status and requires one exact normalized old match and a new rule absent
from the custom list. Identical values, CSV, missing old rules, disabled policies and
empty custom lists are rejected. Order, mode, all eight defaults and other settings
are preserved; default exceptions cannot be replaced. Failed status, empty input,
`0` and EOF cancel before editing. Disabling removes only
the preset, preserving identical manually configured CN rules, Direct exceptions
and other routing policies. Status reports `region.mode`, `allow_domains` and
`default_allow_domains` separately. IP mode does not resolve domain targets early or
recheck their resolved addresses. Existing CN resource and download-failure gates
remain in force; this is not final destination-IP filtering or complete regional management.

Menu `5 → 1 → 2` manages IPv6 domain egress. Optional v3 `.routing.ipv6`
stores `mode` and `domains`, gated separately by `x-padm-routing-ipv6`.
Selective mode uses the existing four domain-rule types; global mode changes
only the default outbound and does not remove other policies.

```bash
padm-docker edit --ipv6 selective --ipv6-domains 'example.com,full:api.example.net' --preview
padm-docker edit --ipv6-domains-add 'full:updates.example.net' --preview
padm-docker edit --ipv6-domains-remove 'full:updates.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --ipv6 global --confirm PADM-DOCKER-EDIT
padm-docker edit --ipv6-off --confirm PADM-DOCKER-EDIT
```

IPv6 submenu options `5/6` and `--ipv6-domains-add/--ipv6-domains-remove <CSV>` change
an existing selective list. Missing or global IPv6 policies are rejected. Additions
normalize rules, preserve order and deduplicate, with a 256-rule merged limit.
Removal requires every complete normalized rule to exist or rejects the whole batch.
Removing the last rule disables IPv6 without switching to global mode; other routes
and traffic totals are preserved.

Direct exceptions and domain/IP/BT blocking precede selective IPv6, which precedes
SOCKS5. Global IPv6 preserves explicit SOCKS5 rules, but cannot share the default
outbound with global SOCKS5. Matched domains use only AAAA addresses, without
falling back to A addresses; the system resolver may still query A records.
Existing hosts and split-DNS sources remain in use; IPv4-only hosts are rejected
on this path rather than falling back to another source. This is not an IPv4
firewall and does not convert literal IPv4 destinations.
Disabling removes only the IPv6 item and preserves other routes, credentials and
traffic totals. Core containers retain their normal privileges and attach to a
separate owned IPv6 bridge without changing the existing default network,
Docker daemon or host interfaces. The host still needs working IPv6 routing and
egress. TUN/TProxy host-network mode, complete WARP and native-host acceptance
remain outside this stage.

Menu `5 → 1 → 1 → 1` and interactive `edit --warp-input` collect existing WARP Peer
parameters directly. The private key is hidden and reaches the private candidate
only through stdin. Empty input, EOF or `0` cancels. This entry requires a TTY,
rejects `--preview`/`--confirm` and asks for one final confirmation.
The submenu also disables or displays WARP egress and manages an existing
configuration's domains, global mode and tunnel address family. Options `6/7`
do not guarantee the public egress address family. Optional v3
`.routing.warp` has its own `x-padm-routing-warp` gate. The existing `--warp <JSON>`
CLI remains available: the file must be root-owned, `0600`, at most 64 KiB, with
the same single-link and safe ancestor-directory requirements as other routing
inputs. Private keys never appear in command arguments, previews or routing status.
The seven fields are `mode` (`selective` or `global`), `family` (`ipv4` or `ipv6`),
`private_key`, `peer_public_key`, `ipv6_address`, `reserved` and `domains`.
Keys are canonical 32-byte Base64; `reserved` contains three integers from
`0` to `255`. Selective mode requires 1–256 unique rules using the four existing
domain-rule types; global mode requires an empty `domains` array.

```bash
padm-docker edit --warp-input
padm-docker edit --warp /root/warp.json --preview
padm-docker edit --warp /root/warp.json --confirm PADM-DOCKER-EDIT
padm-docker edit --warp-domains 'example.com,full:api.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --warp-domains-add 'full:updates.example.net' --preview
padm-docker edit --warp-domains-remove 'full:updates.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --warp-global --confirm PADM-DOCKER-EDIT
padm-docker edit --warp-family ipv6 --confirm PADM-DOCKER-EDIT
padm-docker edit --warp-off --confirm PADM-DOCKER-EDIT
```

Daily edits require an existing valid WARP configuration. Domain replacement selects
selective mode, global mode clears domains, and family changes only the address family.
Keys, Peer, tunnel address and reserved bytes remain unchanged. These actions are mutually
exclusive; preview/cancellation does not commit, and conflicting default egress is rejected.
WARP submenu options `8/9` and `--warp-domains-add/--warp-domains-remove <CSV>` change
an existing selective list and reject missing or global WARP configurations. They
use stable normalized additions, a 256-rule merged limit and exact batch removal.
While rules remain, mode, family, keys, Peer, tunnel address and reserved bytes are
preserved. Removing the last rule disables WARP and removes its current private
configuration, so enabling it later requires entering or importing it again. It never switches
implicitly to global mode.
Supply parameters from an existing WARP account; no account registration or
third-party registration-tool installation is performed. The Peer is fixed at
`162.159.192.1:2408` and MTU at `1280`. `family` selects one local tunnel address
and the address family used to resolve matched domains: `172.16.0.2/32` for IPv4
or the imported `ipv6_address/128` for IPv6. Resolution does not fall back to the
other family. This does not guarantee the public egress address family or convert
literal destination IPs. Both cores explicitly use userspace
WireGuard without host interfaces, additional privileges, devices or ports.
Direct, domain/IP/BT Block and selective IPv6 precede WARP; selective WARP
precedes SOCKS5. Global WARP preserves explicit IPv6/SOCKS5 rules but cannot
coexist with another global default outbound. Existing hosts and split-DNS
sources remain in use. Disabling removes only WARP and preserves other rules
and traffic totals. Both cores passed isolated local encrypted-Peer TCP/UDP,
DNS-source, no-direct-fallback and disable/restore checks. The fixture records
nonzero reserved bytes before adapting the header for a standard kernel Peer;
this is not Cloudflare service acceptance. Cloudflare account validity, public
UDP and public egress still require separate acceptance.

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

### Xray primary core with sing-box auxiliary core

The project supports keeping Xray as the primary core while enabling sing-box incrementally as an auxiliary core:

1. Install Xray from `Install & reinstall` first.
2. Open `Protocol & entry`, enter `Hysteria2` or `Tuic`, and choose `Install`.
3. sing-box is installed separately with its own config fragments and service. Xray's configuration and service remain in place, while subscription and status pages read both cores.

This is not a `--core both` mode; `--core` still accepts only `xray` or `sing-box`. Running a full sing-box installation from `Install & reinstall` switches the primary core and removes Xray. The currently exposed auxiliary-core incremental entries are Hysteria2 and Tuic.

Hysteria2 installation keeps the server, Clash Meta, and sing-box subscription parameters aligned. Brutal fixed bandwidth is the default, entered from the client's perspective: download is server to client and upload is client to server. BBR omits fixed bandwidth so clients use adaptive BBR. Port hopping is emitted as a `server_ports` range in sing-box subscriptions. Obfuscation is optional and supports `salamander` and `gecko`; it is emitted to Clash Meta, sing-box, and Hysteria2 URIs with the matching password. Pressing Enter during reinstall keeps the existing mode and obfuscation, while `off` disables obfuscation.

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

### sing-box Stats Build and Traffic Recovery

Native sing-box installations, as either the primary or auxiliary core, and the Docker `padm-sing-box` image use this repository's CI build from upstream source. It keeps the upstream default build tags and adds `with_purego,with_v2ray_api` for per-user traffic statistics, including Hysteria2 and TUIC. Servers download Linux amd64 / arm64 packages or images without compiling locally.

`with_grpc` selects the full gRPC transport implementation. Without it, the default gRPC lite implementation still supports this project's Reality gRPC configuration. User statistics are enabled independently by `with_v2ray_api`; Hysteria2 and TUIC do not depend on `with_grpc` either.

Docker pins the stats archive version and both architecture SHA256 values in `versions.lock`. Official archive digests are kept separately to verify the Cronet source during stats builds. Docker includes the user collection and quota management described above. `padm-docker update` updates images and the host control bundle together and initializes statistics. Older versions without self-updates need the one-time transition described under Updates, using a freshly downloaded entry to avoid the old `padm-docker install` omitting new shared modules. Existing protocol configuration is preserved, and available protocol entries still follow the Docker support matrix. The following menu steps apply to native deployments.

If an older core reports `v2ray api is not included in this build`, or connectivity was restored by removing the stats configuration, perform these steps on the server running sing-box:

1. Update padm from `System & script`.
2. Open `Cores & services` -> `sing-box lifecycle` -> `Upgrade stable` to install a published stats build.
3. Confirm that `sing-box user statistics capability` is supported and the service is running, then run `Check current configuration`.

After a successful upgrade, the script restores `14_stats_api.json` from the existing protocol users and reloads the core. The stats API listens only on `127.0.0.1:10087`; existing ports, certificates, and user credentials are retained. Failed stats restoration triggers an attempt to roll back the core and configuration. Reusing a previous installation configuration also converts an older core that lacks stats support. Traffic from periods without collection cannot be recovered; new traffic is attributed to the existing accounts.

Stable upgrades, prerelease trials, and rollbacks select only published `sing-box-v<upstream-version>` releases from this repository. Installation verifies the asset digest, actual version, and `with_v2ray_api` tag. An unavailable package or failed check stops before replacing the current core.

Maintainers can run the `Build sing-box Traffic Stats` Actions workflow, leaving `version` empty to use `versions.lock` or specifying an upstream tag such as `v1.14.0`. On `main`, only stats build files, stats decoders, image checks, or relevant lock inputs enter build preparation; unrelated lock changes are skipped. Build logic, Alpine runtime dependencies, or upstream digests for the same version changing, as well as manual runs, revalidate published versions without replacing published assets. Daily checks and lock upgrades to published versions can still reuse packages. Both architectures must pass native startup, Naive/Cronet loading, actual Hysteria2/TUIC transfers, and per-user stats checks, then build the actual Dockerfile with the candidate package and locked Alpine dependencies and pass image smoke checks before publication. Releases contain binary archives, corresponding source, and `SHA256SUMS`; binary archives include `LICENSE` and build information. Stats releases do not take over padm's latest release marker. Wait for a successful workflow publication before the first installation.

`Refresh Upstream Versions` checks the latest official stable sing-box release daily at 03:17 UTC (GitHub scheduling may be delayed), and can also be run manually. It calls the stats workflow above for both architectures when the stats release is missing; daily checks reuse complete published releases. It refreshes the Docker lock and opens or updates the same PR, preserving manual commits, merging `main`, and pushing normally. Conflicts, multiple matching PRs, or concurrent branch updates fail explicitly. Even without lock changes, it checks Docker CI for the PR's current commit, dispatching missing or approval-blocked checks while preserving genuine test failures. A stats build failure keeps the workflow failed but still allows dependency lock updates for published versions, so unavailable old APKs do not block their own repair; failed candidates never enter the lock. Automatic refresh selects only published stable stats releases from this repository, excluding drafts and prereleases. Update PRs still require merging, and Docker CI checks the stats tag, API startup, and Cronet loading on both architectures before allowing image publication. Prereleases can still be built manually by specifying `version` in the stats workflow.

## System and Script

`System & script` handles padm itself and host-level helper features:

- 🔄 Update the padm script; if the subscription control service is enabled or running, the update also refreshes and restarts it. A refresh failure does not roll back the script update and prompts you to retry from control-plane maintenance.
- 🧾 Inspect entry validation, version, ref, and manifest.
- 🛡️ Manage Fail2ban protection: native deployments include SSH and `/s/control/`; Docker provides WS, control-plane and dedicated SSH service protection, with full native-host acceptance pending.
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
| `--reality-target` | `host[:port]` | Opens selector when omitted; fails without an acceptable safe result | Reality camouflage target; explicit values also require live risk validation. |
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
| `--reuse-last` | `yes`, `no`, `y`, `n` | Reuse existing config by default; Enter keeps it in interactive mode | `no` re-enters installation settings and users without clearing the existing installation, certificates or subscriptions. |
| `--clean-acme` | `yes`, `no`, `y`, `n` | Ignored | Kept only for legacy script compatibility; reinstallation always preserves ACME certificates and account configuration. |
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

All regressions use the selector dispatcher and fall into three levels:

For Direct/Block CSV or Docker menu dispatch changes on Windows, run
`.\shell\regression\run-docker.ps1 -Selector docker-routing-domains-workflow`
and `docker-menu` first. The focused selector reuses the transaction assertions;
it does not replace Schema, generator, other routing matrices, or real traffic checks.
For extra listener ports, use `docker-entry-port-alias` and `docker-menu-port-alias`.
For multiple-listener or dual-core topology changes, use `docker-phase3-entries-topology`;
for protocol, TLS, or reinstallation management changes, use `docker-phase3-entries-management`.
`docker-phase3-entries` runs both groups in parallel. Complete contracts and CI cover the same leaves.
The menu selector reuses every alias PTY assertion; `docker-menu` retains the full set.

| Level | Command | Purpose |
| --- | --- | --- |
| Fast feedback | `bash shell/subscription_groups_regression.sh fast` | Representative checks after small changes; use `fast-full` for the complete fast set. |
| Main product regression | `bash shell/subscription_groups_regression.sh all` | The main validation set for larger changes; schedules core product suites within a resource budget, but is not the union of every public selector. |
| Focused checks | `bash shell/subscription_groups_regression.sh <selector>` | Adds protocol, deep rollback, or harness checks according to the changed area. |

The PR native gate uses `ci-pr` as its default fast set; subscription or harness changes are promoted to `ci`, while the main-branch release gate always uses the full `ci` set. Both selectors default to 3 top-level workers; set `PADM_REGRESSION_CI_PARALLEL_JOBS` or the Docker CI manual input to choose 2 through 4 when needed. Release static checks, native regressions, and release preparation use the same commit, so later pushes to main cannot replace the validated candidate source. After pushing a version-only commit, the same Release run builds and publishes that commit without dispatching another run or repeating native regressions. Only workflow revision changes or a competing main update require redispatch.

`all` runs `subscription`, `ui`, `transaction-core-main`, `routing`, `runtime`, `remote-control-smoke`, and both remote-control contracts within one resource budget. Add the full `transaction-core`, `fast-full`, `protocol-capabilities`, `remote-control-deep`, and harness contracts when relevant.

Common product-focused selectors:

```bash
bash shell/subscription_groups_regression.sh protocol-capabilities
bash shell/subscription_groups_regression.sh platform-hot
bash shell/subscription_groups_regression.sh platform-smoke
bash shell/subscription_groups_regression.sh fast-full
bash shell/subscription_groups_regression.sh subscription-output
bash shell/subscription_groups_regression.sh transaction-core
bash shell/subscription_groups_regression.sh core-safety-rollback
bash shell/subscription_groups_regression.sh routing-safety
bash shell/subscription_groups_regression.sh subscription-safety
bash shell/subscription_groups_regression.sh transaction-system
bash shell/subscription_groups_regression.sh remote-control-smoke
bash shell/subscription_groups_regression.sh remote-control-contract
bash shell/subscription_groups_regression.sh remote-control-deep
bash shell/subscription_groups_regression.sh subscription-state
bash shell/subscription_groups_regression.sh ui-full-core
bash shell/subscription_groups_regression.sh ui-full-core-maintenance
```

Harness-focused selectors:

```bash
bash shell/subscription_groups_regression.sh regression-dispatcher-contract
bash shell/subscription_groups_regression.sh regression-case-loader-contract
bash shell/subscription_groups_regression.sh framework-parallel-selector-list-with-jobs
bash shell/subscription_groups_regression.sh targeted-batch-helpers
```

To cap concurrency or run heavy suites more conservatively, prefer `PADM_REGRESSION_PARALLEL_JOBS`, `PADM_REGRESSION_CHILD_PARALLEL_JOBS`, and suite-specific `PADM_REGRESSION_*_RESOURCE_PROFILE=all`. `shell/regression/protocol_capabilities.sh` remains only as a compatibility forwarder that preserves the original success marker.

The main entrypoint assembles regressions in the fixed `framework/`, `cases/load.sh`, then `suites/` order. Cases load once; the historical source-only grouping layer is gone.

## License

This project is licensed under the [AGPL-3.0 License](../../LICENSE).
