# Docker HTTP 中继

菜单 `17. 路由与出站` 的 `21. HTTP 中继入站` 提供认证参数导入、关闭和脱敏状态。
这是内部能力 `202`，不是公开节点协议，不生成订阅链接。

## 配置

只支持部署中已有的受管 Xray，不自动安装辅助核心。sing-box `v1.14.2` 会用任意
`X-Forwarded-For` 覆盖路由来源，且无关闭选项，无法满足此来源允许名单合同，明确拒绝。
不得把 HTTPUpgrade、NaiveProxy 或 SOCKS 入站当作此能力。

在 Linux 部署主机使用 root 所有、`0600`、单链接的普通 JSON 文件；祖先目录
不能含链接、不能由非 root 写入，最多 `64 KiB`。文件内容为 HTTP 对象本身：

```json
{
  "core": "xray",
  "port": 36080,
  "address_families": ["ipv4"],
  "username": "relay-user",
  "password": "replace-with-a-private-password",
  "source_ips": ["198.51.100.10/32"]
}
```

所有字段必填，不接受额外键。端口为 `1–65535`，必须避开公开入口、内部后端、
统计 API、控制面、HTTP-01、共存入口和宿主已有端口。地址族可用 `ipv4`、`ipv6`
或两者，但必须与宿主实际来源和网络一致。

凭据为 `1–255` 个非空可见 ASCII 字符，不含空格；HTTP Basic 用户名不能含 `:`，
密码可以。`source_ips` 为 `1–256` 条唯一字面 IPv4/IPv6 或 CIDR，不接受域名、
GeoIP、IPv4 前导零或 IPv6 zone。`0.0.0.0/0`、`::/0` 会放开整个对应地址族，
使用者须明确选择允许范围。

```sh
padm-docker edit --http-relay /root/padm-http-relay.json --preview
padm-docker edit --http-relay /root/padm-http-relay.json --confirm PADM-DOCKER-EDIT
padm-docker protocol routing-status
padm-docker edit --http-relay-off --confirm PADM-DOCKER-EDIT
```

v3 规格保存为 `.relay.http`，控制包必须声明 `x-padm-relay-http`。
普通 `edit --spec` 不能改写已有中继的认证或来源，专项操作不能与其它编辑动作组合。
配置、更新和回滚使用当前候选校验、备份及失败恢复流程；关闭只删除 HTTP 中继。

## 行为

只发布独立 TCP 端口，支持普通 HTTP 代理请求和 CONNECT。来源判断使用核心实际
看到的 TCP 来源；来源允许和拒绝规则先于所有全局 Direct/Block、SOCKS、IPv6
及 WARP。允许流量走专属 direct 出站和系统解析，不继承全局 hosts/DNS 分流。
未允许来源不能靠伪造代理头通过。

认证输入只进入私有规格和受管核心配置，普通预览、状态不输出用户名或密码。
中继不参与业务账户、订阅或流量额度；Xray 使用专属等级禁用用户计数，
即使中继用户名与业务统计 ID 相同也不能串入业务流量。业务统计保持原行为。
该入口不能与 TUN/TProxy 的宿主网络模式共存。

HTTP Basic 不是加密传输。此阶段不提供中继入口 TLS，应限定在可信或已加密网络内；
CONNECT 的目标 TLS 不会加密客户端到代理的 Basic 认证头。
来源若已被上游 NAT、代理或 Docker Desktop 宿主回流折叠，只能按实际可见地址判断；
不要将共享网关地址当作所有客户端真实身份。

## 验收边界

定向回归为 `docker-http-relay`、`docker-http-relay-real`、
`docker-http-relay-published-real`，统一由 `shell/regression/run-docker.ps1` 运行。
发布专项用隔离 Linux daemon、生产 Compose 端口和外部 veth 客户端验证 DNAT 来源，
不借真实宿主 Socket 或公网。业务容器维持 UID `10001`、只读根和零 capabilities。

原生 Linux 宿主生命周期、公网/IPv6 发布、arm64 和可信发布仍需独立验收；
`internal-202` 的完整矩阵继续为 `deferred`。SOCKS `201` 仍未交付：
sing-box UDP ASSOCIATE 返回容器私网地址和动态端口，仅发布固定 TCP/UDP 同端口
不能保证回包可达，不能删掉 UDP 语义或伪装为完成。
5B.5b 实测 Xray 26.3.27 固定 UDP 发布可以连通，但来源 IP 一次认证后在当前进程内保留，
全部控制连接关闭后新 UDP socket 仍能无认证转发，不能作为完整 SOCKS 会话实现。
