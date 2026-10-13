# padm 短链接 Worker

此组件将完整协议链接保存到 Cloudflare KV，并提供短 HTTPS 地址。padm 将短地址生成为终端
字符二维码，适用于完整链接二维码超出显示宽度的场景，无需在 VPS 上另建订阅服务。
短地址返回协议文本，客户端可将其作为订阅地址使用。

## 快速部署

以 root 登录 VPS，执行以下命令下载并运行部署脚本：

```bash
mkdir -p -m 700 /root/padm-shortlink && wget -O /root/padm-shortlink/deploy.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/tools/shortlink-worker/deploy.sh" && test -s /root/padm-shortlink/deploy.sh && chmod 700 /root/padm-shortlink/deploy.sh && bash /root/padm-shortlink/deploy.sh
```

下载入口使用 `main` 分支版本。未发布到该分支的版本，应从本地仓库根目录运行：

```bash
bash tools/shortlink-worker/deploy.sh
```

部署需要以下条件：

- Linux x86_64 或 ARM64、glibc 2.35+，支持 `apt-get`、`dnf` 或 `yum`；建议使用
  Debian 12+、Ubuntu 22.04+ 或 Rocky/AlmaLinux 10+。
- root 或 sudo 权限，用于安装依赖及保存 padm 配置。
- Cloudflare API Token，具备目标账号的 `Workers Scripts Edit` 和 `Workers KV Storage Edit`
  权限；Account ID 可从 Cloudflare 账号概览获取。

脚本交互收集 Token 和 Account ID，Token 隐藏输入且不写入部署状态目录。
自动部署可通过环境变量 `CLOUDFLARE_API_TOKEN` 和 `CLOUDFLARE_ACCOUNT_ID` 提供凭据。
未启用 `workers.dev` 子域名时，按 Wrangler 提示完成设置。

缺少 `wget` 时，Debian/Ubuntu 可执行
`apt-get update && apt-get install -y ca-certificates wget`；Rocky/AlmaLinux 可执行
`dnf install -y ca-certificates wget`。下载失败或文件为空时不会启动部署。
此脚本仅部署短链服务，padm 本身需按 [安装说明](../../README.md#安装) 安装。

Alpine、Debian 11、Ubuntu 20.04 和 Rocky/AlmaLinux 9 不满足脚本的 glibc 要求。
可在兼容系统上部署后，将生成的配置传入 VPS。macOS 部署需自行准备 Node.js 22+、
npm 和 openssl，由 Wrangler 处理授权。

## 配置与使用

Linux 部署成功后，脚本原子写入 `/etc/padm/qr-shortener.json`，文件权限为 `600`。
设置 `PADM_INSTALL_DIR` 时，配置写入该目录。已安装的 padm 自动读取配置，重新连接 SSH 后仍生效：

```bash
padm
```

配置仅作为 JSON 数据解析。文件必须为非符号链接的普通文件，由 root 或当前运行用户拥有，
且没有组及其他用户权限。配置无效或上传失败时，padm 提示原因并使用完整协议链接生成二维码。
已有 HTTP/HTTPS 订阅地址保持原样。

在其他电脑部署时，可通过 SSH/SFTP 将 `.state/vps.env` 传入 VPS 的私有目录，
保持文件权限为 `600`，在运行 padm 的 shell 中通过 `source` 加载。
使用 Cloudflare 控制台部署时，可在该 shell 中手动设置：

```bash
export PADM_QR_SHORTENER_URL="https://worker.example.com"
read -rsp "Worker API Key: " PADM_QR_SHORTENER_API_KEY
printf '\n'
export PADM_QR_SHORTENER_API_KEY
padm
```

将示例域名替换为实际 Worker 地址，仅填写 HTTPS 域名及可选端口，不附加路径、查询参数或用户名。
两个环境变量应同时设置；设置任意一个后，padm 不再从配置文件补齐另一个。
环境变量仅作用于当前 shell 及其子进程。停用时删除自动配置，并清除已设置的环境变量。
控制台部署不会安装 VPS 的 `qrencode`，需自行安装。

v2rayN/v2rayNG 使用短地址时，将其添加为订阅并更新。扫码自动添加订阅的行为取决于客户端版本
及扫码入口，客户端实机兼容性尚未验证。Worker 返回协议文本，不执行 HTTP 重定向。

## 部署状态与更新

脚本按环境准备、Cloudflare 授权、Worker 部署、保存配置四个阶段显示进度。
失败时保留原始错误并标明中止阶段。脚本自身的输出在重定向、`TERM=dumb` 或非空的
`NO_COLOR` / `PADM_NO_COLOR` 环境变量下禁用颜色。

部署状态保存在脚本所在目录的 `.state/` 中，目录权限为 `700`：

| 文件 | 用途 |
| --- | --- |
| `api-key` | Worker 写入及删除密钥，权限为 `600` |
| `wrangler.toml` | Worker 配置和账号专属的 KV 绑定 |
| `worker.js` | 本次部署使用的 Worker 源码 |
| `vps.env` | VPS 环境变量配置备份，权限为 `600` |

重复部署复用 API Key 和 KV 绑定。首次部署前可修改模板 `wrangler.toml` 的 Worker 名称；
后续修改名称或域名配置应编辑 `.state/wrangler.toml`。
从控制台部署迁入脚本时，先将原密钥保存到 `.state/api-key`，并将含 KV ID 的原配置
保存到 `.state/wrangler.toml`。已有配置但密钥丢失时，脚本停止并要求恢复密钥。
部署或配置保存失败时，不替换已有 VPS 配置。`.state/` 已加入 `.gitignore`，仍需妥善备份和保管。

每次成功上传协议文本都会创建随机短地址，保存当时的文本副本。节点参数变更后需重新生成，
旧记录不会自动更新或过期。可通过 `DELETE /s/<id>` 或 Cloudflare 控制台删除记录。

## 存储与安全

协议内容以原始文本传输并保存在 Cloudflare KV 中，Cloudflare 及具备相应账号权限的人员
属于信任范围。短链接本身就是读取凭证，持有者可读取完整协议内容。
Worker API Key 仅保护写入和删除，与用于部署的 Cloudflare API Token 相互独立。

KV 使用最终一致性，新记录及删除操作的跨地区可见性可能延迟超过 60 秒。
新地址暂时无法读取时，可稍后重试；删除记录也不保证所有地区立即失效。
二维码尺寸取决于地址长度，较短的自定义域名可进一步减少显示宽度。

## 控制台部署

1. 在 Workers & Pages 创建 Worker，粘贴 `worker.js` 的完整源码并部署。
2. 在 Workers KV 创建 namespace，并在 Worker 的 Bindings 中以 `KV` 为变量名绑定。
3. 在 Settings → Variables and Secrets 添加 Secret `API_KEY`，保存并重新部署。

API Key 应为 32–128 个字母、数字、下划线或连字符，可用 `openssl rand -hex 32` 生成。
VPS 配置方式见上文“配置与使用”。

## 开发与验证

Worker 接口使用 `/s/<id>`，`id` 为随机生成的 32 位小写十六进制字符串：

| 方法与路径 | 鉴权 | 成功响应 |
| --- | --- | --- |
| `PUT /s/<id>` | `Authorization: Bearer <API_KEY>` | `201`，正文为短地址 |
| `GET /s/<id>` | 无 | `200`，正文为保存的原始文本 |
| `DELETE /s/<id>` | `Authorization: Bearer <API_KEY>` | `200`，删除对应记录 |
| `GET /` | 无 | `200`，正文为 `ok` |

上传正文必须为非空 UTF-8 文本，大小上限为 128 KiB；格式或空正文错误返回 `400`，
超限返回 `413`，鉴权失败返回 `401`，记录或路径不存在返回 `404`，KV 不可用返回 `503`。

部署脚本固定使用 `wrangler@4.149.0`。Linux 优先复用 Node.js 22+ 和 npm；缺少可用运行时
则下载 Node.js `22.23.3`，校验固定 SHA-256 后安装到 `.state/`，不替换系统 Node.js。
缺少配套源码或模板时，从 `main` 分支的同一提交下载 `worker.js` 和 `wrangler.toml`。

仓库根目录通过 PowerShell 7.3+ 和 Docker Desktop 的 Linux 引擎执行定向回归：

```powershell
.\shell\regression\run-docker.ps1 -Selector fast-only-output-rest -Jobs 2
```

回归覆盖 Worker 鉴权、文本读写、大小限制、错误响应和删除；VPS 上传、失败回退、
订阅地址保留及配置权限；部署首次运行、状态复用、依赖安装、下载与校验失败、
隐藏输入、80 列输出和颜色开关。文档中的一行下载入口也纳入验证。
测试不调用 Cloudflare，不能替代实际发布、客户端扫码或跨地区 KV 验收。

相关资料：[KV 部署](https://developers.cloudflare.com/kv/get-started/)、
[Secrets](https://developers.cloudflare.com/workers/configuration/secrets/)、
[Wrangler 配置](https://developers.cloudflare.com/workers/wrangler/configuration/)、
[Wrangler 系统要求](https://developers.cloudflare.com/workers/wrangler/install-and-update/)、
[Node.js 校验值](https://nodejs.org/dist/v22.23.3/SHASUMS256.txt)、
[KV 一致性](https://developers.cloudflare.com/kv/concepts/how-kv-works/)。
