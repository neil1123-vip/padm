# padm 短链接 Worker

此组件将完整协议链接保存到 Cloudflare KV，并提供短 HTTPS 地址。padm 将短地址生成为终端
字符二维码，适用于完整链接二维码超出显示宽度的场景，无需在 VPS 上另建订阅服务。
在浏览器中打开短地址会显示完整协议的 PNG 二维码；订阅客户端读取时返回协议文本。

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

首次运行时，脚本交互收集 Token 和 Account ID，Token 隐藏输入。
随后用 `age` 口令加密保存凭据，设置口令时需输入两次；直接回车会生成口令，请妥善记录。
设置、确认和解锁口令使用中文提示，输入不会回显。
再次部署只需输入口令解锁，无需重复输入 Token 和 Account ID。日常运行 `padm` 不询问口令。
随后询问可选的自定义域名，例如 `go.example.com`。首次部署直接回车使用 `workers.dev`；
填写时只输入域名，不加 `https://`、路径或端口。
输入格式有误时会提示原因并重新询问，无需重新解锁凭据；回车仍使用原默认值。
域名所属站点须已在同一 Cloudflare 账户激活，建议使用专用子域名。
Wrangler 自动绑定域名、创建 DNS 记录及证书，成功后 padm 使用该域名生成短链二维码。
已有 DNS 或 Worker 绑定冲突时，按终端提示确认或取消。
自动部署可通过环境变量 `CLOUDFLARE_API_TOKEN` 和 `CLOUDFLARE_ACCOUNT_ID` 提供凭据；
同时提供时直接使用，不保存或解锁凭据。已有密文时只设置其中一项会被拒绝，以免混用账号。
使用自定义域名时仍须在交互终端运行；未启用 `workers.dev` 子域名时，按 Wrangler 提示完成设置。

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

在其他电脑部署时，将生成的 `qr-shortener.json` 通过 SSH/SFTP 传入 VPS 的
`/etc/padm/qr-shortener.json`，设置所有者为 root、文件权限为 `600`。
Linux 从配置目录取文件；macOS 从 `.state/qr-shortener.json` 取文件。
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

直接导入节点时，用手机相机扫描终端小二维码并在浏览器打开，保存显示的 PNG，
再使用客户端的图片识别入口导入。图片编码的是完整协议链接。用 v2rayNG 自带扫描器
直接扫终端的短 HTTPS 地址，仍会添加订阅；更新订阅后取得节点。

浏览器访问通过 `Accept: text/html` 返回 PNG；在地址后加 `?format=png` 可强制取图，
加 `?format=text` 可强制获取协议文本。每个码点为 `4 × 4` 像素，四周保留 4 个码点的白边；
图片边长随协议长度变化，最大为 `740 × 740` 像素。单张 PNG 最多容纳 2953 字节的 UTF-8 文本，
超限返回 `422` 并提示改用文本导入。二维码在 Worker 内生成，不调用第三方制码服务。
手机实机导入尚未验证。

## 部署状态与更新

脚本按环境准备、Cloudflare 授权、Worker 部署、保存配置四个阶段显示进度。
失败时保留原始错误并标明中止阶段。脚本自身的输出在重定向、`TERM=dumb` 或非空的
`NO_COLOR` / `PADM_NO_COLOR` 环境变量下禁用颜色。

部署状态保存在脚本所在目录的 `.state/` 中，目录权限为 `700`：

| 文件 | 用途 |
| --- | --- |
| `cloudflare.age` | 口令加密的 Cloudflare Token 和 Account ID，权限为 `600` |
| `api-key` | Worker 写入及删除密钥，权限为 `600` |
| `wrangler.toml` | Worker 配置和账号专属的 KV 绑定 |
| `custom-domain` | 成功部署的自定义域名，后续回车复用，权限为 `600` |
| `worker.js` | 本次部署使用的 Worker 源码 |
| `package.json` / `package-lock.json` | PNG 生成依赖及锁定版本 |
| `qr-shortener.json` | 仅非 Linux 部署生成，用于传入 VPS，权限为 `600` |

重复部署复用 API Key 和 KV 绑定。首次部署前可修改模板 `wrangler.toml` 的 Worker 名称；
后续修改名称应编辑 `.state/wrangler.toml`。自定义域名每次部署都会询问，回车复用已保存值；
也可输入新域名替换。仅在控制台添加的其他自定义域名，应同步写入 `.state/wrangler.toml` 的
`routes`，否则下次部署可能移除这些绑定。
从控制台部署迁入脚本时，先将原密钥保存到 `.state/api-key`，并将含 KV ID 的原配置
保存到 `.state/wrangler.toml`。已有配置但密钥丢失时，脚本停止并要求恢复密钥。
部署或配置保存失败时，不替换已有 VPS 配置。`.state/` 已加入 `.gitignore`，仍需妥善备份和保管。
旧版本的 `.state/vps.env` 在运行配置成功保存后自动删除，不再重复备份环境变量。
解锁失败时保留密文和运行配置；遗忘口令无法恢复密文，可将 `cloudflare.age` 移出
`.state/` 后重新输入凭据。保留 `api-key` 和 `wrangler.toml`，以复用原服务。

每次成功上传协议文本都会创建随机短地址，保存当时的文本副本。节点参数变更后需重新生成，
旧记录不会自动更新或过期。可通过 `DELETE /s/<id>` 或 Cloudflare 控制台删除记录。

## 存储与安全

协议内容以原始文本传输并保存在 Cloudflare KV 中，Cloudflare 及具备相应账号权限的人员
属于信任范围。短链接本身就是读取凭证，持有者可读取完整协议内容。
Worker API Key 仅保护写入和删除，与用于部署的 Cloudflare API Token 相互独立。
Cloudflare 部署凭据以 `age` 口令加密；口令只经终端输入，不保存到磁盘。
Worker 地址和 API Key 保留在权限为 `600` 的运行配置中，便于 padm 自动使用。
`.state/api-key` 同样为明文私有文件；具有 root 或这些文件读取权限的用户可取得运行密钥。

KV 使用最终一致性，新记录及删除操作的跨地区可见性可能延迟超过 60 秒。
新地址暂时无法读取时，可稍后重试；删除记录也不保证所有地区立即失效。
二维码尺寸取决于地址长度，较短的自定义域名可进一步减少显示宽度。

## 控制台配置

此版本依赖 `qr-image`，请使用部署脚本发布，不能仅粘贴 `worker.js` 源码。
脚本创建 KV 并以 `KV` 为变量名绑定，密钥写入 Secret `API_KEY`。
部署后可在 Worker 的 Bindings（绑定）及 Settings（设置）中查看这些配置。

API Key 应为 32–128 个字母、数字、下划线或连字符，可用 `openssl rand -hex 32` 生成。
VPS 配置方式见上文“配置与使用”。

## 开发与验证

Worker 接口使用 `/s/<id>`，`id` 为随机生成的 32 位小写十六进制字符串：

| 方法与路径 | 鉴权 | 成功响应 |
| --- | --- | --- |
| `PUT /s/<id>` | `Authorization: Bearer <API_KEY>` | `201`，正文为短地址 |
| `GET /s/<id>` | 无 | `200`，浏览器请求返回 PNG，其他请求返回原始文本 |
| `GET /s/<id>?format=png` | 无 | `200`，完整协议 PNG；超限返回 `422` |
| `GET /s/<id>?format=text` | 无 | `200`，保存的原始文本 |
| `DELETE /s/<id>` | `Authorization: Bearer <API_KEY>` | `200`，删除对应记录 |
| `GET /` | 无 | `200`，正文为 `ok` |

上传正文必须为非空 UTF-8 文本，大小上限为 128 KiB；格式或空正文错误返回 `400`，
超限返回 `413`，鉴权失败返回 `401`，记录或路径不存在返回 `404`，KV 不可用返回 `503`。

Linux 每次部署都查询 Node.js 官方版本列表，选择最新 LTS；系统工具已是该版本时直接使用，
否则下载对应版本并按官方 `SHASUMS256.txt` 校验 SHA-256，安装到
`.state/node-v<版本>-linux-<架构>/`。已有私有运行时也会检查更新，同版本不重复下载。
Wrangler 使用 `wrangler@latest`，每次优先向 npm 查询最新正式版。
自动更新只作用于本次部署使用的工具，不替换系统 Node.js 或 age；部署成功保存配置后，
已检查更新的工具会清理旧私有版本，当前版本保留；失败时不清理，符号链接及其他目录不删除。
版本查询、下载或校验失败时停止部署，保留已有凭据和 VPS 运行配置。
缺少配套文件时，从 `main` 分支的同一提交下载源码、模板、依赖清单和锁文件。
部署前执行 `npm ci --omit=dev --ignore-scripts`，由 Wrangler 将 PNG 依赖打包到 Worker。
加密或解锁时查询 age 官方最新正式版；系统工具已是该版本时直接使用，否则按发布文件的
SHA-256 校验值下载到 `.state/age-v<版本>/`。已有私有版本同样自动检查更新。
仅通过完整 Cloudflare 环境变量部署、无需加解密时，不检查或安装 age。
PNG 依赖继续按锁文件安装，保证 Worker 打包结果可复现。

仓库根目录通过 PowerShell 7.3+ 和 Docker Desktop 的 Linux 引擎执行定向回归：

```powershell
.\shell\regression\run-docker.ps1 -Selector fast-only-output-rest -Jobs 2
```

回归覆盖最新 LTS 选择、已有部署工具升级、同版本复用及版本信息异常保护；
Worker 鉴权、文本读写、大小限制、错误响应和删除；VPS 上传、失败回退、
订阅地址保留及配置权限；部署首次运行、状态复用、依赖安装、下载与校验失败、
隐藏输入、80 列输出和颜色开关。文档中的一行下载入口也纳入验证。
自定义域名回归覆盖首次绑定、回车复用、凭据已设置及输出重定向时的交互、非法输入、
绑定失败或缺少目标地址时保留原配置。
凭据回归使用真实 `age` 和终端，覆盖首次加密、再次解锁、错误口令、损坏密文、
非法解密内容、非交互环境变量及旧备份清理，并确认 padm 无需解锁即可生成短链。
PNG 回归使用独立识别库解码含中文及长协议链接的图片，检查浏览器/订阅响应、容量限制及旧记录兼容。
测试不调用 Cloudflare，不能替代实际发布、客户端扫码或跨地区 KV 验收。

相关资料：[KV 部署](https://developers.cloudflare.com/kv/get-started/)、
[Secrets](https://developers.cloudflare.com/workers/configuration/secrets/)、
[Wrangler 配置](https://developers.cloudflare.com/workers/wrangler/configuration/)、
[Wrangler 系统要求](https://developers.cloudflare.com/workers/wrangler/install-and-update/)、
[Node.js 版本列表](https://nodejs.org/dist/index.tab)、
[KV 一致性](https://developers.cloudflare.com/kv/concepts/how-kv-works/)。
