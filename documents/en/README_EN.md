<h1 align="center">padm</h1>

<p align="center"><strong>✨ Xray-core / sing-box node setup and operations</strong></p>
<p align="center">🚀 Node setup · 🔗 Subscription publishing · 🌐 Multi-server coordination · 🧭 Routing and access control · 🔐 Sites and certificates</p>
<p align="center"><a href="../../README.md">🌍 中文</a></p>

<p align="center">
  <a href="#quick-choice">🚀 Quick choice</a> ·
  <a href="#installation">📦 Native installation</a> ·
  <a href="#docker-mode">🐳 Docker mode</a> ·
  <a href="#subscriptions-and-users">🔗 Get a subscription</a> ·
  <a href="#documentation">📚 Documentation</a>
</p>

---

## Quick Choice

For a first native deployment, open `1. 安装与重装` (Install & reinstall) and choose a setup based on your domain and how clients connect. For containers, see [🐳 Docker mode](#docker-mode).

| Scenario | Menu entry | Notes |
| --- | --- | --- |
| 🧭 Direct connection with your own domain | `1. 推荐直连 Reality Vision` | Recommended for a first deployment. Point the domain to this server. |
| 🌐 CDN or reverse proxy | `2. 推荐 CDN Reality XHTTP` | The client needs XHTTP support. |
| 📍 No domain | `3. 无域名 Reality` | Use the server IP or a custom entry host without a local TLS certificate. |
| 🛡️ TLS fingerprint resistance | `4. TLS 指纹抗性 NaiveProxy` | Requires your own domain and a trusted certificate. |
| 🧰 Legacy clients or migration | `6. 传统 TLS 兼容安装` | For clients that require WS/TLS, VMess, Trojan, or similar protocols. |

## Installation

### Interactive Installation

Run this command as root on a Linux server and choose `1. 安装与重装`. Run `padm` anytime to reopen the panel.

```bash
wget -O /root/install.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

For system requirements, module refresh, non-interactive examples, and the flag reference, see the [📦 Native installation and flags guide](native-install.md).

## Docker Mode

🐳 Docker mode runs Xray / sing-box, Nginx, subscriptions, and maintenance tasks in containers. Install it with `install-docker.sh` and manage it with `padm-docker`. Choose one mode per host and plan any migration separately.

### Docker Requirements

Use Linux with root access, a local rootful Docker Engine, and Compose v2 or later on `amd64` or `arm64`. Release verification requires `cosign` with Sigstore bundle v0.3 support. [Full Docker requirements](docker-guide.md#docker-requirements)

<a name="installation-1"></a>

### Installation and Setup

```bash
wget -O /root/install-docker.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install-docker.sh" && chmod 700 /root/install-docker.sh && /root/install-docker.sh install
```

If Docker is missing, the script asks whether to install it from Docker's official repository. In an interactive terminal, installation opens the menu. Choose `1. 安装与重装 → 1. 首次配置` (Install & reinstall → Initial setup) to verify the release and pull the images built by CI.

Run `padm-docker` to reopen the menu. For an unconfigured deployment, run `padm-docker setup` in an interactive terminal to start the wizard directly.

<a name="five-images"></a>
<a name="state-and-daily-control"></a>
<a name="trusted-release-inputs"></a>
<a name="recovery-archives"></a>
<a name="user-traffic-and-quotas"></a>
<a name="updates"></a>
<a name="rollback"></a>
<a name="uninstall"></a>

[🐳 Docker guide](docker-guide.md) · [Daily commands](docker-guide.md#state-and-daily-control) · [Update and rollback](docker-guide.md#updates)

## Subscriptions and Users

📱 For a node on this server, open `3. 协议与入口 → 1. 查看全部协议链接` (Protocols & entry → View all protocol links). Copy a link or scan a QR code. Use an HTTPS subscription when the client needs to refresh its node list.

- **Native.** Open `2. 订阅与用户 → 1. 安装/更新发布服务` to publish. Open `2. 查看当前订阅链接` (View current subscription links), choose the administrator or a shared subscription, and copy the link labeled `默认订阅` (Default subscription).
- **Docker.** After enabling HTTPS publishing, open `订阅与用户 → 订阅管理 → 查看主订阅 HTTPS 链接` (`2 → 2 → 11`) to copy the main subscription link.

On a native controller, the administrator subscription includes available nodes from the local server and all enabled controlled servers. Shared subscriptions publish the node sources selected for each subscription. [🔗 Subscriptions and users guide](subscriptions.md)

## Documentation

| Find out about | Guide |
| --- | --- |
| <a name="system-requirements"></a><a name="main-menu"></a><a name="non-interactive-installation"></a><a name="flag-reference"></a>Native system requirements, main menu, short QR codes, and CLI flags | [📦 Native installation and flags](native-install.md) |
| Docker deployment, daily commands, and supported features | [🐳 Docker guide](docker-guide.md) · [Feature matrix (Chinese)](../docker-feature-matrix.md) |
| <a name="protocol-selection"></a><a name="recommended-public-node-capabilities"></a><a name="advanced-public-node-capabilities"></a><a name="internal-server-capabilities"></a><a name="known-upstream-capabilities-not-generated-by-this-project"></a><a name="nginx-topology"></a><a name="reality-semantics"></a><a name="xhttp-and-cdn"></a><a name="traditional-tls-and-local-sites"></a><a name="advanced-experiment"></a>Protocol IDs, Reality targets, XHTTP, CDN, and traditional TLS | [🧭 Protocols and entry](protocols.md) |
| Administrator and shared subscriptions, quotas, controlled servers, and recovery | [🔗 Subscriptions and users](subscriptions.md) |
| <a name="routing-and-access-control"></a><a name="cores-and-services"></a><a name="xray-primary-core-with-sing-box-auxiliary-core"></a><a name="sing-box-stats-build-and-traffic-recovery"></a><a name="system-and-script"></a><a name="post-install-control-points"></a>Core upgrades, diagnostics, access control, and server maintenance | [⚙️ Operations guide](operations.md) |
| <a name="validation-and-regression"></a>Post-install checks, local regression tests, and CI | [🧪 Validation and regression](regression.md) |
| <a name="runtime-model"></a>Repository layout, sing-box stats builds, and dependency automation | [🛠️ Maintainer guide](maintenance.md) |

## License

📄 padm uses the AGPL-3.0 license. [View license](https://github.com/neil1123-vip/padm/blob/main/LICENSE)
