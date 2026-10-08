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
bash install.sh --install-type reality --core xray --reality-target target.example.com:443 --reuse-last no --clean-acme no
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
and logs. Select first configuration to choose the core, protocols, addresses, and certificates.
The wizard covers Xray Reality Vision/XHTTP/gRPC and WS TLS, and sing-box
Reality Vision/gRPC, Hysteria2, AnyTLS, NaiveProxy, Shadowsocks, and TUIC.
It never overwrites an existing deployment; use the editor below instead. Full protocol management remains deferred.
`install --no-menu` disables the automatic menu. A non-interactive invocation without
arguments only prints help without installing Docker, downloading the bundle, or
initializing state. Existing explicit CLI commands remain available.

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
Subscription publishing still requires Xray, WS TLS, and managed TLS.
The complete input is saved as root-owned `/etc/padm-docker/config/spec.json` with mode `0600`.
Cancellation does not commit; failures restore the previous spec, certificates, and ACME state.
The spec contains secrets and must not be printed or published.

Menu item `16` manages sites on existing Nginx TLS listeners `21`-`25` or fallback
listeners `27`/`29`. It supports a built-in default page, a static directory, and HTTP/HTTPS 302:

```bash
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
Deleting the last Nginx listener clears the site mode but retains static files and other TLS listeners.
`status` reports only `site_mode`, not the redirect URL. Old specs remain compatible;
v3 `.site` requires the bundle capability `x-padm-site-content`.
Managed webroot and standalone HTTP-01 are available through certificate management.

The same menu offers ALPN diagnostics, recommended repair, and three manual orders
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
`tuic://` uses `h3`, native UDP relay, and strict TLS verification. Port hopping remains unavailable.

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
per-account publishing authorization, pure-content copy, and business backup/restore remain
unavailable.

Use the menu's configuration editor or `padm-docker edit` to change public ports,
server addresses, address families, node names, Reality targets/SNI, WS paths, or
subscription enablement. It uses a private draft, a value-redacted diff, and candidate
validation before confirmation and commit. Unselected listeners, UUIDs, keys, tokens,
certificates, host integrations, and accumulated traffic remain unchanged.
The menu can copy or delete an existing protocol listener by listener ID; the primary
core must retain at least one listener. Reality can be copied to the other core.
Hysteria2, AnyTLS, NaiveProxy, Shadowsocks, and TUIC can only be copied within sing-box.
Adding these protocol types to an existing deployment requires a complete v3 `configure` spec.
Shadowsocks method, keys, UUID, and existing listener identity remain frozen during editing.
Deleting the last secondary-core listener disables that core; existing listener ownership cannot change.
Copies reuse the original credentials. Listeners with the same
UUID share accumulated traffic and quota rather than creating separate users.
Add and delete operations must be confirmed in separate transactions so a replacement
cannot bypass existing identity or internal-port protections.
An older deployment without `config/spec.json` requires its complete original spec;
missing fields, additional accounts, custom routes/sites, or mismatched mount roots
reject editing rather than reconstructing an invented spec from runtime summaries.

```bash
padm-docker edit
padm-docker edit --spec /root/original-spec.json --preview
padm-docker edit --spec /root/original-spec.json --confirm PADM-DOCKER-EDIT
```

The protocol/listener menu lists stable listener IDs, cores, protocols, addresses/ports,
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
Deleting the last WS listener disables subscription publishing. The spec retains TLS
while Hysteria2, AnyTLS, NaiveProxy, or TUIC remains; otherwise it sets `tls` to `null`,
while retaining TLS/ACME files and the token. Shadowsocks does not require TLS.
Nginx-side rotation and managed core-side TLS foundations are implemented.
Reality XHTTP/gRPC, Hysteria2, AnyTLS, NaiveProxy, Shadowsocks, and TUIC basic listeners
are implemented; remaining protocol types and full protocol management remain deferred.
WS listeners managed by Fail2ban cannot yet be added, deleted,
or assigned a different public port; those changes require coordinated firewall rules.
3A.3 has passed local dual-core transaction, PTY, traffic, update/rollback, and Linux permission regressions. Real signed releases,
application images, and dual-architecture client connectivity remain unverified.

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
Initialize a controller only on an already healthy managed single-peer WireGuard deployment:

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
Recovery, failed-transaction rollback and explicit version rollback disable authorization to prevent old tokens
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

Repeat `--listener` to map multiple existing entries. Join confirms once and initializes identity,
mapping and the initial account sync in one transaction. Failure preserves the original role, accounts
and traffic; retrying the same revision/content does not rebuild services. Identity, connection addresses
and mapping are then fixed; a different invitation cannot reclaim them. After rotation, securely transfer
the new invitation and sync again. Every sync explicitly reads a root-private invitation outside the managed
directory, with the same parent-directory restrictions; expired or revoked credentials fail.
The raw token is not stored in specs, backups, arguments, environment or ordinary logs. The capability-free
client binds its private source address and connects directly, without proxies, redirects or public fallback.
Status exposes connection metadata, not remote health. Legacy internal roles without connection metadata
remain compatible but cannot use external sync; old bundles cannot restore the new connection spec.
Explicit `rollback` checks controlled identity, listener mapping and connection before sampling, creating a
backup or stopping services. It rejects lower sync revisions and requires matching digest and managed accounts
at the same revision. Compatible release snapshots with unchanged sync state can still be restored.
Controlled specs require a bundle declaring sync rollback protection, so older unprotected scripts are rejected.
Failed or interrupted join/sync transactions still restore their pre-transaction state without inventing
upstream revisions locally. Automatic sync, role rebinding, arbitrary historical-account restoration and
a WireGuard connection wizard are not provided.
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

Main menu item 8 validates certificates, imports replacements, or runs DNS-01/HTTP-01 standalone/webroot issue/renew.
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

### User Traffic and Quotas

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
| Basic commands | Entry download needs at least `curl` or `wget`; full bundle refresh needs `tar`. |
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

Docker menu `17. Routing and outbound` provides authenticated SOCKS5 TCP outbound.
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
padm-docker edit --socks5-off --confirm PADM-DOCKER-EDIT
```

Optional v3 `.routing.socks5` requires the bundle capability `x-padm-routing-socks5`;
old specs remain direct. Both cores send client TCP destination traffic through the
authenticated upstream without direct fallback on failure. Client UDP destination traffic
is explicitly blocked, independently of UDP-based Hysteria2/TUIC ingress carrying TCP.
Reality handshakes, statistics APIs, control services, Nginx, ACME and host traffic are
outside this scope. No new listener, host privilege or firewall rule is added; TUN/TProxy
combinations are not enabled. Changes use the existing candidate/backup/recovery transaction.
Status and previews omit credentials, but private specs, core configurations and backups
retain them. SOCKS5 authentication is not encrypted; use a trusted upstream network.
SOCKS ingress, domain routing, DNS/WARP and the remaining routing policies are still deferred.

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

All regressions use the selector dispatcher and fall into three levels:

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
