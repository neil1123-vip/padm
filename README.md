<h1 align="center">padm</h1>

<p align="center"><strong>✨ Xray-core / sing-box 节点安装与运维</strong></p>
<p align="center">🚀 节点安装 · 🔗 订阅发布 · 🌐 多服务器协同 · 🧭 分流与访问控制 · 🔐 站点与证书</p>
<p align="center"><a href="documents/en/README_EN.md">🌍 English</a></p>

<p align="center">
  <a href="#快速选择">🚀 快速选择</a> ·
  <a href="#安装">📦 原生安装</a> ·
  <a href="#docker-版">🐳 Docker 版</a> ·
  <a href="#订阅与用户">🔗 获取订阅</a> ·
  <a href="#文档导航">📚 文档导航</a>
</p>

---

## 快速选择

原生版首次安装时，打开 `1. 安装与重装`，按域名和连接方式选择。容器部署见 [🐳 Docker 版](#docker-版)。

| 场景 | 菜单入口 | 说明 |
| --- | --- | --- |
| 🧭 用自有域名直连 | `1. 推荐直连 Reality Vision` | 首次安装推荐。域名需解析到本机。 |
| 🌐 经 CDN 或反代连接 | `2. 推荐 CDN Reality XHTTP` | 客户端需支持 XHTTP。 |
| 📍 没有域名 | `3. 无域名 Reality` | 使用服务器 IP 或自定义入口，无需本机 TLS 证书。 |
| 🛡️ 需要 TLS 指纹抗性 | `4. TLS 指纹抗性 NaiveProxy` | 需要自有域名和可信证书。 |
| 🧰 兼容旧客户端或迁移 | `6. 传统 TLS 兼容安装` | 适用于需要 WS/TLS、VMess 或 Trojan 等协议的场景。 |

## 安装

### 交互式安装

在 Linux 服务器上以 root 运行，在菜单中选择 `1. 安装与重装`。安装后可随时运行 `padm` 返回管理面板。

```bash
wget -O /root/install.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

系统要求、模块刷新、非交互安装和命令行参数见 [📦 原生版安装与参数](documents/native-install.md)。

## Docker 版

🐳 Docker 版用容器运行 Xray / sing-box、Nginx、订阅和运维任务。通过 `install-docker.sh` 安装，日常使用 `padm-docker`。原生版与 Docker 版需择一部署，迁移需单独安排。

### Docker 版要求

需要 Linux、root、本机 rootful Docker Engine、Compose v2+，支持 `amd64` / `arm64`。发布验签需要支持 Sigstore bundle v0.3 的 `cosign`，缺少时停止。完整依赖见 [Docker 指南的系统要求](documents/docker-guide.md#docker-版要求)。

### 安装与配置

```bash
wget -O /root/install-docker.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install-docker.sh" && chmod 700 /root/install-docker.sh && /root/install-docker.sh install
```

缺少 Docker 时，脚本会询问是否从官方软件源安装。在交互终端中安装成功后，菜单会自动打开。进入 `1. 安装与重装 → 1. 首次配置` 部署服务。首次配置会验签并拉取 CI 构建的镜像。

以后运行 `padm-docker` 可打开菜单。尚未部署服务时，也可在交互终端运行 `padm-docker setup` 直接进入首次配置。

<a name="日常管理"></a>

日常管理、状态路径、更新和回滚见 [🐳 Docker 版使用指南](documents/docker-guide.md)。

## 订阅与用户

📱 直接导入本机节点时，打开 `协议与入口 → 查看全部协议链接`，复制链接或扫描二维码。要让客户端定期刷新，用 HTTPS 订阅。

<a name="-选订阅和链接格式"></a><a name="-创建分享订阅"></a><a name="-接入被控服务器"></a><a name="-同步与恢复"></a>

- **原生版。** 从 `订阅与用户 → 安装/更新发布服务` 发布订阅，再打开 `查看当前订阅链接`。选中管理员或分享订阅，然后复制「默认订阅」。
- **Docker 版。** 配置 HTTPS 发布后，从 `订阅与用户 → 订阅管理 → 查看主订阅 HTTPS 链接` 复制链接，对应编号 `2 → 2 → 11`。

原生版主控的管理员订阅汇总本机和已启用被控的可用节点。分享订阅按所选节点范围发布。 [🔗 订阅与用户指南](documents/subscriptions.md)

## 文档导航

| 想了解什么 | 文档 |
| --- | --- |
| <a name="系统要求"></a><a name="主菜单"></a><a name="短链二维码"></a><a name="非交互安装"></a><a name="参数参考"></a>原生版的系统要求、主菜单、短链二维码、非交互安装和参数 | [📦 原生版安装与参数](documents/native-install.md) |
| Docker 部署、日常命令和功能支持范围 | [🐳 Docker 版使用指南](documents/docker-guide.md) · [功能对照表](documents/docker-feature-matrix.md) |
| <a name="协议选择"></a><a name="推荐公网节点能力"></a><a name="高级公网节点能力"></a><a name="内部服务端能力"></a><a name="上游已知但本项目暂不生成的能力"></a><a name="nginx-拓扑"></a><a name="reality-语义"></a><a name="xhttp-与-cdn"></a><a name="传统-tls-与本机站点"></a><a name="高级实验"></a>协议编号、Reality 目标站、XHTTP、CDN 和传统 TLS | [🧭 协议与入口](documents/protocols.md) |
| 管理员与分享订阅、流量额度、接入被控和同步恢复 | [🔗 订阅与用户](documents/subscriptions.md) |
| <a name="路由与访问控制"></a><a name="核心与服务"></a><a name="xray-主核心与-sing-box-辅助核心"></a><a name="-配置检查与版本切换"></a><a name="sing-box-统计版与流量恢复"></a><a name="系统与脚本"></a><a name="安装后的控制点"></a>核心升级、日志诊断、访问控制、安装路径和宿主维护 | [⚙️ 服务与系统运维](documents/operations.md) |
| <a name="验收与回归"></a><a name="-安装后验收"></a><a name="-windows-本机回归"></a><a name="-并发快照与结果"></a><a name="-linux-与-ci"></a>部署验收、本机回归和 CI | [🧪 验收与回归](documents/regression.md) |
| <a name="运行模型"></a><a name="-统计版构建与依赖更新"></a><a name="-github-actions-依赖维护"></a>仓库结构、统计版构建和依赖维护 | [🛠️ 维护者指南](documents/maintenance.md) |

## 许可证

📄 本项目采用 AGPL-3.0。 [查看许可证](https://github.com/neil1123-vip/padm/blob/main/LICENSE)
