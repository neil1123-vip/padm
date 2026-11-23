# 🔗 Subscriptions and Users

[🏠 English home](README_EN.md#documentation) · [🌍 中文](../subscriptions.md)

Use `Subscriptions & users` (`订阅与用户`) in the native installation to publish HTTPS subscriptions, manage shared subscriptions and traffic quotas, and connect controlled servers over WireGuard. [🐳 Docker Guide](docker-guide.md)

[Subscription menu](#subscription-menu) · [Links and formats](#links-and-formats) · [Create shared subscriptions](#create-shared-subscriptions) · [Connect a controlled server](#connect-a-controlled-server) · [Sync and recovery](#sync-and-recovery) · [Subscription and control URLs](#subscription-and-control-urls)

## Subscription menu

Both the local and controller home screens provide the following options. Installing or updating the publishing service runs a full sync. Once you see `订阅已发布` (Subscription published), open the link list.

| Menu | Purpose |
| --- | --- |
| 📦 `1. 安装/更新发布服务` | Install or update the publishing service. Set up public HTTPS and sync subscriptions. |
| 🔗 `2. 查看当前订阅链接` | View published links. Choose an administrator or shared subscription and copy a link in the format you need. |
| 👥 `3. 分享订阅` | Create, edit, enable, or disable shared subscriptions. |
| 📊 `4. 流量与限额` | View saved usage, set traffic quotas, and handle subscriptions over quota. |
| 🔄 `5. 立即完整同步` | Run a full sync now. Sync accounts on the local server and all enabled sources, then update the published subscriptions. |
| 🧰 `6. 订阅同步` | Set up automatic sync and its interval, view sync status, troubleshoot failures, and manage backups. |

| Role | Home screen | When to use it |
| --- | --- | --- |
| 🟡 Uninitialized | The local subscription home includes publishing, links, sharing, usage, and sync. It also lets you enable the controller role or join a controller. | For a single server, install the publishing service. Choose a controller or controlled role when you need multiple servers. |
| 🟢 Controller | The controller home adds controlled-server management and local control-plane maintenance to the publishing options. | Publish administrator and shared subscriptions, add controlled servers, sync, and manage quotas. |
| 🔵 Controlled | The controlled server home shows join, status, credential, and control-plane actions. | Paste a controller invite, provide this server's nodes to the controller, and check WireGuard and sync status. |

## Links and formats

Open `2. 查看当前订阅链接` (View current subscription links) from the subscription home. Choose the administrator subscription or a shared subscription, then copy the link labeled `默认订阅` (Default subscription). If the result also contains Clash Meta or sing-box links, you can copy the one that matches your client.

- 👤 **Administrator subscription.** In local mode, it includes nodes from the local protocol configuration. In controller mode, it also includes available nodes returned by enabled controlled servers. The local administrator account is independent of `user_groups` and shared quotas. The controller provisions separate administrator credentials for each enabled controlled server.
- 👥 **Shared subscriptions.** Each subscription publishes from its selected node sources. Enter `*` when selecting sources to include the local server and all enabled controlled servers.

## Create shared subscriptions

1. From the local or controller subscription home, select `1. 安装/更新发布服务` (Install or update the publishing service). If public publishing is already set up, go directly to `3. 分享订阅` (Shared subscriptions).
2. With no shared subscriptions, the menu opens the creation wizard. If subscriptions already exist, choose `+ 新建分享订阅` (Create shared subscriptions). IDs can contain English letters, digits, underscores, and hyphens, with up to 64 characters per ID. For example, use `team-a`. Separate IDs with commas to create several at once.
3. Choose the node sources and traffic quota. Press Enter to select the local source (`main`), or enter `*` to select all sources. For the quota, press Enter or enter `0` for unlimited traffic.
4. Save to run a full sync and write the managed account to the core configuration. Account names start with `sub_` and encode the subscription ID. After sync, copy the link from the subscription details or from `2. 查看当前订阅链接` on the subscription home.

`分享订阅` (Shared subscriptions) and `流量与限额 → 管理分享订阅与额度` (Traffic and quotas → Manage shared subscriptions and quotas) open the same list and details. Both show saved usage and let you change quotas, enable or disable subscriptions, and sync a selection. You can correct invalid entries in the current field. The script writes the draft when you save it.

## Connect a controlled server

1. On the controller, choose `启用主控协同` (Enable controller coordination), then open `管理被控服务器 → 创建被控邀请` (Manage controlled servers → Create invite) and enter the controlled server's alias. The controller reserves its WireGuard address.
2. On the controlled server, choose `接入主控` (Join controller) and paste the invite. The script uses the address in the invite and imports the controller peer. Copy the join receipt once the step completes.
3. Back on the controller, select `管理被控服务器 → 完成被控接入` (Manage controlled servers → Complete join) and paste the receipt. The script adds the peer, server source, and control token under the reserved alias, then runs a full sync.

If the server you want to join already has public publishing or a managed sync job, follow the prompts to stop publishing or disable automatic sync first. The local or controller home offers `9. 停用发布服务` (Disable the publishing service) when publishing is configured. This stops public clients from refreshing subscription links and keeps saved subscription and node configuration.

🔒 Send invites, receipts, and legacy controlled-server credentials through a trusted channel. Invites and receipts grant access to anyone who has them. Receipts and legacy controlled-server credentials contain long-lived control tokens. Look up or cancel pending invites by alias. If you lose an invite, cancel it and create a new one. Use invites and receipts for initial setup and legacy `main` and `controlled` credentials to maintain existing connections. WireGuard uses UDP, and the control API uses HTTP inside the tunnel. Client subscriptions still use public HTTPS.

## Sync and recovery

- Choose a server under `管理被控服务器 → 管理已接入服务器` (Manage controlled servers → Manage connected servers) to update its credentials, enable or disable it, check its connection, run a full sync, or remove it. Disabling a server removes its remotely managed accounts and keeps its peer, token, and history. Enabling, disabling, updating credentials, and removing a server each trigger a sync.
- A full sync updates local configuration first, then processes controlled-server snapshots. With a successful local sync and valid remote results, it publishes data from sources that succeeded and reports any source failures as a partial failure. If a remote-only subscription has no available nodes, padm reuses its previous output when it has a nonempty default subscription. Without that output, the publication attempt fails and padm keeps the existing public files. A failed local sync or invalid overall remote result keeps the entire previous public publication.
- After a node configuration changes, the controlled server notifies the controller over WireGuard. When automatic sync is on, the controller regenerates local nodes, fetches enabled sources, and updates the existing HTTPS links. If notification fails, run `立即完整同步` (Full sync now) on the controller. The automatic sync switch controls scheduled sync and sync after node changes. Manual changes to shared subscriptions and controlled-server settings still trigger a sync and retain your automatic sync setting.

**💾 State backups.** Use `订阅同步 → 状态备份与恢复` (Subscription sync → State backup and restore) to manage `/etc/padm/subscribe_groups/groups.json`. To restore a backup or rebuild state, enter `yes` when prompted. The script backs up the current state before applying either action.

The state file uses a single root group object with `version: 6` and separate Xray and sing-box traffic baselines. The script calculates totals on demand. Versions 2 through 5 migrate atomically on first read, with backups named `groups-pre-v3-migration-*` through `groups-pre-v6-migration-*`. A version 5 aggregate baseline stays in use until the first new-format traffic sample. State files must contain one group and satisfy the field validation for a supported version.

## Subscription and control URLs

- 🌍 Clients use public HTTPS paths such as `/s/default/...`, `/s/clashMeta/...`, `/s/clashMetaProfiles/...`, and `/s/sing-box/...`.
- 🔒 The controller uses `/s/control/...` over the private WireGuard connection for server-to-server control.

See the native operations guide for configuration paths and host service management. [⚙️ Service and System Operations](operations.md)
