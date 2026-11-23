# 📦 Native Installation and Flags

[🏠 English home](README_EN.md#documentation) · [🌍 中文](../native-install.md)

Use `install.sh` to deploy the native version on Linux. The download command is on the [English home page](README_EN.md#installation). For containers, see the [Docker guide](docker-guide.md).

[System requirements](#system-requirements) · [Interactive installation](#interactive-installation) · [Main menu](#main-menu) · [Short-link QR codes](#short-link-qr-codes) · [Non-interactive installation](#non-interactive-installation) · [Flag reference](#flag-reference)

## System Requirements

🐧 The native version detects Debian, Ubuntu, RHEL, CentOS, AlmaLinux, Rocky Linux, Oracle Linux, Fedora, and Alpine, then uses `apt`, `yum`, or `apk` as appropriate.

| Item | Requirement |
| --- | --- |
| Permission | root or equivalent privileges. |
| Architecture | `x86_64/amd64`, `aarch64/arm64`. |
| Basic commands | Downloading the entry script requires `curl` or `wget`. The wget fallback needs `timeout` to limit total duration. Full bundle refresh needs `tar`. |
| Common dependencies | The script installs or uses `jq`, `nginx`, `acme.sh`, WireGuard tools, Fail2ban, and related tools as features require. |
| Service management | Core services prefer systemd. Alpine/OpenRC has its own service path. Subscription control on the controller or a managed server requires systemd and `python3`. |

> [!IMPORTANT]
> On RHEL-family distributions and Fedora, the native installer stops when SELinux is Enforcing and asks you to adjust its mode before running the installer again.

## Interactive Installation

On first run, if the entry script detects missing `shell/`, `documents/`, `assets/`, or a module manifest mismatch, it downloads the full repository archive and restores the module bundle.

To force a module refresh, run the installer with the refresh flag.

```bash
wget -O /root/install.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh" && chmod 700 /root/install.sh && PADM_FORCE_SCRIPT_MODULE_REFRESH=1 /root/install.sh
```

Use `padm` to reopen the panel after installation.

```bash
padm
```

## Main Menu

Run `padm` to open the native management panel. The header shows the script version, core service status, and installed protocols.

| Menu | What you can do |
| --- | --- |
| 🚀 `1. Install & reinstall` | Choose a recommended setup, install custom protocols, or reinstall the core. |
| 🔗 `2. Subscriptions & users` | Publish subscriptions, set quotas, and sync with managed servers. |
| 🧭 `3. Protocols & entry` | View local links and QR codes, or manage protocols, ports, and CDN addresses. |
| 🔐 `4. Sites & certificates` | Manage static sites, traditional TLS fallback, ALPN, and local certificates. |
| 🧱 `5. Routing & access control` | Configure routing, BT restrictions, blocking rules, and direct exceptions. |
| ⚙️ `6. Cores & services` | Switch versions, control services, inspect logs, and update Xray Geo data. |
| 🧰 `7. System & script` | Update padm, inspect its installation, configure Fail2ban, and manage BBR. |
| ⚠️ `8. Advanced & dangerous operations` | Uninstall padm or enable experimental VLESS Encryption. |

📱 Open `3. Protocols & entry → 1. View all protocol links` to generate links and QR codes for the current local configuration. The `qrencode` output is limited to 80 columns. Copy the full link if QR generation fails or the output is too wide. If the terminal renders black and white half-block characters as double-width, configure it to render them as single-width.

## Short-Link QR Codes

📱 If a QR code for the full link is too wide, deploy the Cloudflare Worker to display a shorter HTTPS QR code. Run the following command as root on a Linux host with glibc 2.35 or later, such as Debian 12 or Ubuntu 22.04.

```bash
mkdir -p -m 700 /root/padm-shortlink && wget -O /root/padm-shortlink/deploy.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/tools/shortlink-worker/deploy.sh" && test -s /root/padm-shortlink/deploy.sh && chmod 700 /root/padm-shortlink/deploy.sh && bash /root/padm-shortlink/deploy.sh
```

Enter the Cloudflare API token and account ID when prompted. The script installs dependencies, deploys the Worker, and saves its configuration. It encrypts deployment credentials with an `age` passphrase and prompts for it on redeployment. An existing padm installation uses the short links automatically.

Cloudflare KV stores the protocol link. Treat the short link as a node credential. Open the short link with your phone camera, save the full protocol QR code as a PNG, and import it through your client. v2rayNG treats a scanned short HTTPS URL as a subscription. [Worker requirements, permissions, and deployment options (Chinese)](https://github.com/neil1123-vip/padm/blob/main/tools/shortlink-worker/README.md)

## Non-Interactive Installation

Run the help command to see all available flags.

```bash
bash install.sh --help
```

Replace `target.example.com` with a Reality target that passes the live checks.

**🧭 Direct Reality Vision**

```bash
bash install.sh --install-type custom --core xray --protocols 1 --entry-host node.example.com --reality-target target.example.com:443 --reality-server-name target.example.com --reuse-last no
```

**🌐 CDN Reality XHTTP**

```bash
bash install.sh --install-type custom --core xray --protocols 2 --entry-host cdn.example.com --reality-target target.example.com:443 --reality-server-name target.example.com --reuse-last no
```

**📍 No-domain Reality**

```bash
bash install.sh --install-type reality --core xray --reality-target target.example.com:443 --reuse-last no
```

**🛡️ NaiveProxy**

```bash
bash install.sh --install-type custom --core sing-box --protocols 5 --domain naive.example.com --port 443 --reuse-last no
```

On the command line, pass comma-separated public protocol IDs, for example `--protocols 1,2,21`. The interactive installer accepts the consecutive numbers shown in the current menu, also separated by commas. The old `0..13/20` protocol IDs are deprecated. Reselect the current protocols before reinstalling or adjusting an old setup.

**🔐 Traditional TLS compatibility with Cloudflare DNS-01**

Set `PADM_CLOUDFLARE_API_TOKEN` and `PADM_CLOUDFLARE_ZONE_ID` to the target zone's credentials in your environment. Scope the token to that zone with `Zone:DNS:Edit`. Pass the values explicitly or let padm read them from the environment.

```bash
bash install.sh --install-type install --core xray --domain example.com --port 443 --tls-ca letsencrypt --dns-api yes --dns-api-type cloudflare --dns-api-wildcard yes --cloudflare-api-token "$PADM_CLOUDFLARE_API_TOKEN" --cloudflare-zone-id "$PADM_CLOUDFLARE_ZONE_ID" --reuse-last no
```

To use the environment variables directly, omit the credential flags.

```bash
bash install.sh --install-type install --core xray --domain example.com --dns-api yes --dns-api-type cloudflare
```

**🔗 Install or update HTTPS subscription publishing for an existing node**

```bash
bash install.sh InstallSubscription --domain subscribe.example.com --subscribe-port 39778 --install-nginx yes
```

Subscription publishing uses its own TLS domain and certificate. padm reuses a usable certificate for that domain. If one is missing, padm uses HTTP-01 by default. For DNS-01, pass `--dns-api yes` and the provider settings and credentials. Renew any custom certificate separately.

After this command completes, open `订阅与用户 → 5. 立即完整同步` (Subscriptions & users → Full sync now) to generate or refresh the published links.

## Flag Reference

📋 Use `bash install.sh --help` for the full flag list. The table covers common installation and publishing options.

| Flag | Values | Default / behavior | Notes |
| --- | --- | --- | --- |
| `--install-type` | `install`, `custom`, `reality` | Opens the menu without automation flags. With other install flags, defaults to `custom`. | Installation type. |
| `--core` | `xray`, `sing-box`, `1`, `2` | `xray` | `1` maps to `xray`, `2` maps to `sing-box`. |
| `--protocols` | comma-separated current public protocol IDs | No fixed default | Custom install protocols such as `1` or `1,2,21`. IDs `0..13/20` are deprecated. |
| `--list-protocols` | None | Print and exit | List installable public node capabilities. |
| `--list-capabilities` | None | Print and exit | List public nodes, internal capabilities, and known upstream capabilities. |
| `--show-risky-protocols` | None | Print and exit | List advanced public node capabilities with risk notices. |
| `--domain` | domain | Required or prompted for TLS installs | TLS certificate domain. Reality also accepts it as a client entry address. |
| `--entry-host` | domain or IP | Before `--domain`, saved entry, `currentHost`, and public IP | Address Reality clients actually connect to. |
| `--reality-target` | `host[:port]` | When omitted, padm reuses or selects a target according to the installation mode. | Reality target. Explicit values must also pass the live risk checks. |
| `--reality-server-name` | SNI hostname | Defaults to target host | Reality SNI. |
| `--port` | port number | TLS defaults to `443`. A single Reality protocol uses the explicit port, previous port, then `443`. | TLS entry port or client port for a single Reality protocol. In multi-protocol installations, each protocol uses its own port. |
| `--tls-ca` | `letsencrypt`, `zerossl`, `buypass` | `letsencrypt` | Certificate authority. `buypass` requires DNS API to be disabled. |
| `--dns-api` | `yes`, `no`, `y`, `n` | `no` | Whether to use DNS API certificate issuance. |
| `--dns-api-type` | `cloudflare`, `aliyun`, `1`, `2` | `cloudflare` | DNS API provider. |
| `--dns-api-wildcard` | `yes`, `no`, `y`, `n` | `no` | Whether to request a `*.root-domain` wildcard certificate. |
| `--cloudflare-api-token` | token | Can also use `PADM_CLOUDFLARE_API_TOKEN` | Cloudflare DNS API token. |
| `--cloudflare-zone-id` | zone id | Optional; can also use `PADM_CLOUDFLARE_ZONE_ID` | Sets `CF_Zone_ID` and reduces zone lookup requirements. |
| `--aliyun-api-key` | key | Can also use `PADM_ALIYUN_API_KEY` | Aliyun AccessKey ID. |
| `--aliyun-api-secret` | secret | Can also use `PADM_ALIYUN_API_SECRET` | Aliyun AccessKey Secret. |
| `--reuse-last` | `yes`, `no`, `y`, `n` | Reuse existing config by default. Press Enter to keep it in interactive mode. | `no` re-enters installation settings and users without clearing the existing installation, certificates or subscriptions. |
| `--clean-acme` | `yes`, `no`, `y`, `n` | Ignored | Reserved for legacy scripts. Reinstallation preserves ACME certificates and account settings. |
| `--reality-domain` | `yes`, `no`, `y`, `n` | `no` | Strict-domain mode applies to a single Reality Vision `1` selection. `--entry-host` takes precedence over `--domain`. |
| `--subscribe-port` | port number | No fixed default | Subscription publishing service port. |
| `--install-nginx` | `yes`, `no`, `y`, `n` | `no` | Whether to auto-install Nginx when subscription publishing needs it. |
| `--uuid` | UUID or password | Generated for a new user. Reuse keeps the existing credential. | Password-only custom protocols accept a plain password. VLESS, VMess, and TUIC require a UUID. With reuse enabled, an explicit value must match an existing user before installation. |
| `--user` | username | Generated for a new user. Reuse keeps the existing username. | Initial username. When supplied with `--uuid` during reuse, both must identify the same existing user. To create a new user, pass `--reuse-last no`. |

[🧭 Protocols and entry](protocols.md) · [🔗 Subscriptions and users](subscriptions.md)
