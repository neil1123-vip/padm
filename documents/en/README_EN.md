# padm

Xray-core / sing-box one-click installation and operations script. It supports protocol installation, TLS certificates, subscription publishing, user subscription groups, multi-server synchronization, and traffic statistics.

## New user guide

If this is your first time using the script, start with the simplest path:

1. **Direct / with a domain**: choose `2. Custom Protocol Install` -> `Xray-core` -> `7. VLESS Reality Vision`; use your domain as the entry address when available.
2. **CDN required**: choose `12. VLESS Reality XHTTP`; traditional TLS/WS/gRPC/HTTPUpgrade should only be used for legacy client compatibility.
3. **Without a domain**: choose `3. One-click no-domain Reality`.
4. **After installation**: open `7. Subscription Management`, check “My Subscription”, then create user subscriptions if needed.
5. **Validation**: run `bash shell/validate_install.sh [domain]` on the server for a read-only check.

Avoid advanced entries such as custom protocol combinations, CDN node management, and multi-server synchronization until you know which protocol and network shape your client needs.

## Features

* **Multi-core support**: Xray-core and sing-box.
* **Multi-protocol support**: VLESS, VMess, Trojan, Hysteria2, Tuic, NaiveProxy, AnyTLS, and more.
* **Automatic TLS**: applies for and renews SSL certificates.
* **Parameterized installation**: supports non-interactive installation through command-line options.
* **Interactive management**: Chinese menu for installation, updates, users, ports, certificates, services, and configuration.
* **Subscriptions**: default, Clash Meta, and sing-box outputs, with optional subscription publishing service.
* **Subscription groups**: `/etc/padm/subscribe_groups/groups.json` is the source of truth for users, servers, sync, traffic, quotas, and backups.
* **Multi-server synchronization**: remote control channel, health checks, dry-run plans, manual sync, and scheduled sync.

## Quick start

### Interactive installation

```bash
wget -P /root -N "https://raw.githubusercontent.com/neil1123-vip/padm/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

If the downloaded entry script does not find the local `shell/` modules, it will fetch the full package automatically.

Open the management menu again after installation:

```bash
padm
```

### Non-interactive installation

Show options and examples:

```bash
bash install.sh --help
```

Recommended VLESS Reality Vision install:

```bash
bash install.sh --install-type custom --core xray --protocols 7 --entry-host node.example.com --reality-target www.microsoft.com:443 --reality-server-name www.microsoft.com --reuse-last no
```

Recommended VLESS Reality XHTTP + CDN install:

```bash
bash install.sh --install-type custom --core xray --protocols 12 --entry-host cdn.example.com --reality-target www.microsoft.com:443 --reality-server-name www.microsoft.com --reuse-last no
```

Traditional TLS install, for legacy client compatibility or migration:

```bash
bash install.sh --install-type install --core xray --domain example.com --port 443 --tls-ca letsencrypt --dns-api no --reuse-last no --clean-acme yes
```

No-domain Reality install:

```bash
bash install.sh --install-type reality --core xray --reality-target www.microsoft.com:443 --reuse-last no --clean-acme no
```

Custom protocol install:

```bash
bash install.sh --install-type custom --core xray --protocols 7 --entry-host node.example.com --reality-target www.microsoft.com:443 --reality-server-name www.microsoft.com --reuse-last no --clean-acme yes
```

Install or update the subscription publishing service with the dedicated subcommand:

```bash
bash install.sh InstallSubscription --subscribe-port 39778 --http-subscribe yes --install-nginx yes
```

Subscription publishing options can also be appended to protocol installation when needed:

```bash
--subscribe-port 39778 --http-subscribe no --install-nginx yes
```

## Protocol capability matrix

| Script protocol name | Solves TLS in TLS | Solves fingerprint issue | Built-in multiplexing | CDN support | Recommended use |
| --- | --- | --- | --- | --- | --- |
| VLESS TCP TLS Vision | yes | no | no | no | Legacy TLS compatibility or migration. |
| VLESS Reality Vision | yes | yes | no | no | Default direct-connection choice, with or without a domain. |
| VLESS Reality gRPC | no | yes | yes, HTTP/2 | no | Alternative when gRPC/HTTP2 multiplexing is needed without CDN. |
| VLESS Reality XHTTP | yes | yes | yes, XMUX | yes | Preferred CDN choice. |

## Reality concepts

Reality uses three separate concepts:

| Concept | Meaning | Where it appears |
| --- | --- | --- |
| entry | Address the client connects to | subscription `@host`, Clash Meta `server`, sing-box profile `server` |
| Reality target | Real HTTPS site used as the camouflage target | Xray `realitySettings.target`; sing-box `tls.reality.handshake.server/server_port` |
| Reality SNI | SNI used during Reality handshake | Xray `serverNames`; sing-box `tls.server_name`; subscription `sni/servername` |

A common setup is: client entry `node.example.com`, Reality target `www.microsoft.com:443`, and SNI `www.microsoft.com`.

## Traditional TLS fallback static site

Main menu `8. Traditional TLS fallback static site` is only for traditional TLS protocols. When traffic does not match a proxy protocol, the Nginx fallback can serve a local static page or 302 redirect. The script includes 20 lightweight templates and randomizes titles, industry copy, buttons, card content, footers, and accent colors during installation or replacement.

VLESS Reality Vision, Reality gRPC, and Reality XHTTP do not depend on this local static site. Reality camouflage is handled by the external `target` and `SNI`; unauthenticated probing traffic is forwarded to the target site. New users installing Reality do not need to configure menu 8 first.

For direct personal use, prefer the Reality Vision example. Configure the static site only when you keep using traditional TLS/fallback protocols such as VLESS TCP TLS Vision, WS TLS, gRPC TLS, or Trojan TLS, or when you really want to host a local website.

## Reality 443 coexistence split

A single Reality Vision install usually only needs one entry port, with `443` recommended by default, and it does not require a local camouflage website. Reality camouflage is handled by the external `target` and `SNI`; use “Configure 443 coexistence split” in `5. REALITY Management` only when the same server must also host a real website on `443`.

The advanced split mode works as follows:

1. Nginx stream listens on public `443`.
2. Explicit real website domains are forwarded to the website backend, such as `127.0.0.1:8443`.
3. All other SNI values fall through to the Xray Reality backend, such as `127.0.0.1:2443`.
4. Subscription output still uses `entry-host:443`, while Reality SNI remains the camouflage target.

Nginx stream sees the TLS ClientHello SNI, and Reality clients usually send the external camouflage SNI instead of the entry host. Therefore the script only asks which domains are real websites; everything else goes to Reality by default. New users should avoid this mode unless website coexistence on `443` is required.

## Subscription management

Open `7. Subscription Management` in the main menu:

1. **My Subscription**: admin subscription links for personal use and output checks.
2. **User Subscriptions**: create independent user subscriptions. Managed accounts use the `sub_<ID>` prefix after sync.
3. **Servers**: manage local and remote sources. `main` is the local server; remote sources require subscription service and a control token.
4. **Traffic**: refresh and view global, admin, user, and source traffic. The first refresh establishes a counter baseline.
5. **Settings**: install subscription service, configure automatic sync, quota policy, and state backups.

Recommended user subscription flow:

1. Create a user subscription, using an ID such as `team-a`.
2. Set allowed servers: `main`, remote source IDs, or `*` for all servers.
3. Check local and remote sync plans.
4. Run sync, then view subscription links.

## Validation

Read-only local validation:

```bash
bash shell/validate_install.sh [domain]
```

Online HTTP/HTTPS/TLS validation:

```bash
bash shell/validate_install.sh --online example.com
```

## License

This project is licensed under the [AGPL-3.0 License](../../LICENSE).
