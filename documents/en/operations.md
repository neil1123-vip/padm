# ⚙️ Service and System Operations

[🏠 English home](README_EN.md#documentation) · [🌍 中文](../operations.md)

Manage routing, core versions, services, and host settings in the native edition. For Docker deployment and maintenance, see the [Docker Guide](docker-guide.md).

[Routing and access control](#routing-and-access-control) · [Cores and services](#cores-and-services) · [System and script](#system-and-script) · [Post-install control points](#post-install-control-points)

## Routing and Access Control

### Native routing and access rules

🧱 Open `Routing & access control` to configure server-side outbound traffic and access rules.

| Feature | Notes |
| --- | --- |
| 🧭 Routing tools | WARP WireGuard outbound, IPv6 outbound, SOCKS5 relay, DNS overrides, and DNS/hosts overrides. |
| ⛔ BT download management | Uses protocol sniffing to block detected BitTorrent traffic. Encrypted, obfuscated, and some uTP traffic can evade detection. |
| 🧱 Access control | Domain and IP blocking, direct exceptions, and regional blocking. |

Xray uses routing with blackhole and direct outbounds. sing-box uses remote rule sets, `domain_suffix`, `domain`, and `ip_cidr`. Direct exceptions take priority over blocking rules and can allow connections for system updates, certificate issuance, or other services that need direct access.

> [!WARNING]
> Regional blocking may disrupt updates, certificate issuance, or application traffic. On Xray, switching to global WARP, IPv6, or SOCKS5 outbound also removes existing BT blocks and access control rules.

> [!NOTE]
> Padm snapshots the relevant files before changing access rules and validates the core configuration afterward. A validation failure restores the previous configuration and shows the log path.

### Docker routing workflows

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
Menu `5 → 1 → 3 → 1`, options `6/7/8`, and `--socks5-domains-add/remove/replace` edit only
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

Menu `5 → 3`, options `6/13/14`, accepts CSV directly to set, append or remove manual
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

Menu `5 → 3`, option `17`, and `--block-ips-replace <old rule> <new rule>` replace one
literal IP/CIDR rule in an existing nonempty manual list. Status is shown before the
two inputs; blank, `0` or EOF cancels either step. Both strings are kept verbatim,
including IPv6 spelling and CIDR host bits. The complete old string must exist once;
the new string cannot duplicate any current item, including the old one. Replacement
preserves position and all other configuration. CSV, GeoIP, domain and generated
regional rules are rejected. Preview, confirmation and recovery use the existing transaction.

Menu `5 → 1 → 4`, option `2`, accepts a literal UDP DNS server IP, a port (blank defaults
to `53`), and domain-rule CSV. `--dns-rules <IP> <port> <CSV>` creates or replaces
the same DNS object using existing CSV normalization and transaction checks;
private JSON through `--dns` and all other routing policies remain available.
In `5 → 1 → 4`, options `4/5` or `--dns-domains-add/--dns-domains-remove <CSV>` change the
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

Menu `5 → 1 → 5`, option `4`, and `edit --hosts-replace <existing exact FQDN> <new literal IP>`
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

Menu `5 → 1 → 5`, options `5/6`, and `edit --hosts-add <exact FQDN> <literal IP>` /
`--hosts-remove <exact FQDN>` add or remove one exact mapping. Add can create a missing
hosts map, but any existing key returns `15` regardless of its value; use replacement
to change an address. The merged map is limited to 256 keys. Remove requires an existing
key; missing keys or disabled hosts return `15`. Removing the last key disables hosts
and removes routing only if no other policy remains. ASCII lowercase normalization,
untrimmed input and verbatim addresses retain their existing boundaries. Other mappings,
the full configuration, share URIs, subscriptions and cumulative traffic are preserved.
Focused Linux amd64 and menu PTY verification passes; integrated Docker contracts pass (53/53).
Complete native hosts migration, region policy and conflict detection remain deferred.

Menu `5 → 1 → 5 → 2` and interactive `edit --hosts-input` accept one literal IPv4/IPv6
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
single-rule replacement. Menu `5 → 1 → 4 → 6` handles DNS; `5 → 3 → 15/16` handles Direct/Block;
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

Menu `5 → 1 → 6 → 1` or terminal command `padm-docker edit --http-relay-input`
accepts the relay port, address families, hidden username/password and required source CSV.
It requires an existing Xray and confirmation after candidate validation.
Empty input or EOF cancels; password `0` is valid, while `0` in other fields returns.
There is no permissive source default; the private JSON CLI and support boundaries remain.
Menu `5 → 1 → 6`, options `4–7`, manages an existing Xray HTTP relay through
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
remain deferred. See [Docker HTTP relay (Chinese)](../docker-http-relay.md).

Menu `5 → 3`, options `2/4`, replaces Direct or Block domain rules using comma-separated
input. `--direct-domains <CSV>` and `--block-domains <CSV>` use the same normalization:
trim whitespace, lowercase, preserve first-occurrence order while deduplicating, and
prefix bare domains with `domain:`. They replace the whole group rather than append
to historical rules. Empty/invalid items or more than 256 unique rules are rejected;
use the corresponding off command to clear the group. Private JSON imports through
`--direct/--block` remain available, and ordinary `--spec` editing still freezes routing.
In `5 → 3`, options `9/10` or `--direct-domains-add/--block-domains-add` append rules.
existing order is retained, then previously unseen rules are added in input order.
A missing group is created; more than 256 unique rules after merging is rejected.
Repeated additions do not duplicate rules, but confirmation still uses the deployment
transaction and may update rollback metadata.
In the same menu, options `11/12` or `--direct-domains-remove/--block-domains-remove` remove exact
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

Menu `5 → 3 → 19/20` and `--block-ips-resolve/--block-ips-literal` switch an existing
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

Menu `5 → 2`, options `2–3`, enables or disables detected BitTorrent blocking.
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

Menu `5 → 3`, option `8`, provides a CN regional preset: `domain` matches `geosite:cn`,
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

## Cores and Services

⚙️ The **Cores & services** home view shows local versions, configuration paths, service status, and Xray Geo data. The home view is available before a core is installed, including diagnostics that can run without a local binary. Open **Upgrade / switch version** to fetch the remote version list.

| Menu | Purpose |
| --- | --- |
| `1. Xray-core lifecycle` | Switch versions, validate configuration, and check upgrade risks. |
| `2. sing-box lifecycle` | Switch versions, validate configuration, and check upgrade risks. |
| `3. Service status` | View, start, stop, or restart cores and any Nginx service padm uses. |
| `4. Logs and diagnostics` | Read core logs and validate Nginx configuration. |
| `5. Xray Geo data` | View or update `geosite.dat` and `geoip.dat`, or schedule updates. |
| `0. Return to the main menu` | You can also press Enter to return. |

### Xray primary core with sing-box auxiliary core

📶 After installing Xray, open `Protocols & entry → Hysteria2 management` or `Protocols & entry → TUIC management` to install sing-box as an auxiliary core. The auxiliary core has its own configuration fragments and service. Subscription and status pages read both cores.

A full sing-box install through **Install & reinstall** switches the primary core and removes Xray. The `--core` flag accepts one core, either `xray` or `sing-box`.

When reinstalling auxiliary Hysteria2 or TUIC, press Enter once to reuse all users, ports, and network settings for that protocol. Choose `n` to review fields individually. You can keep existing users while updating ports or network settings. Cancellation or a failed preflight leaves both cores and their other protocols running as before.

Hysteria2 defaults to Brutal fixed bandwidth. Enter upload and download rates from the client's perspective. Under BBR, clients adapt bandwidth without fixed rates. sing-box subscriptions publish port hopping as a `server_ports` range.

Optional `salamander` and `gecko` obfuscation settings appear in Clash Meta and sing-box subscriptions and Hysteria2 URIs. During reinstall, press Enter to keep the existing mode and obfuscation or type `off` to disable obfuscation.

### Configuration Checks and Version Switching

**Checks and diagnostics** runs local configuration validation followed by known upgrade-risk scans. Possible results are **Passed**, **Needs attention**, **Failed**, and **Unable to check**. The script runs any available risk checks even if configuration validation fails or a core binary is unavailable.

**Upgrade / switch version** lists the 20 most recent stable and prerelease versions. Enter a number to choose a version or press Enter for the latest stable release. Enter `0` or end input to cancel. For a prerelease, padm uses the target binary to check the configuration before asking for installation confirmation. Use the installation checks after switching versions. [Validation and Regression](regression.md)

- **Xray.** Runs normal and strict validation. A failure in the normal stage is **Failed**. A failure only in the strict stage is **Needs attention**.
- **sing-box.** Merges configuration fragments into a temporary file, then runs `sing-box check -c <temporary-config>`. If there are no fragments, it validates the existing merged configuration.

Configuration checks are read-only. Compatibility notices are reported separately. The result details show the technical stages and log paths.

The sing-box compatibility scan reports the installed version and checks fragments first or the existing merged configuration if no fragments are present. Each diagnostic category appears once. Legacy WireGuard and special outbounds, old DNS server formats, and `domain_strategy` appear as historical notices. Notices for fields deprecated in 1.14 indicate migration before 1.16. For TUN `stack`, the notice identifies deprecation in 1.15 and removal in 1.17. Invalid JSON or a failed scan shows **Failed**. The installed core's merge and check stages determine whether it accepts the current configuration. Upgrade and installation preflight retain strict scans, migration checks, and rollback on failure.

Padm downloads the target version into a temporary directory and validates the current configuration before replacing `/etc/padm/xray/xray` or `/etc/padm/sing-box/sing-box` and restarting. If the new core fails to start, padm attempts to restore the previous binary.

The service menu can start, stop, restart, and smoothly reload Nginx when a current protocol, site, or subscription depends on it. For other Nginx instances, it displays status. Configure Nginx through the protocol, site, or subscription menu that owns the setting.

### sing-box Stats Build and Traffic Recovery

The native sing-box primary and auxiliary cores and the Docker `padm-sing-box` image default to a CI build from upstream source. It retains the upstream build tags and adds `with_purego,with_v2ray_api` for per-user traffic statistics, including Hysteria2 and TUIC. The native version menu also offers a local build for eligible upstream versions without a published stats package. Docker uses the pinned image.

`with_grpc` selects the full gRPC transport. The default gRPC lite transport supports this project's Reality gRPC configuration. `with_v2ray_api` independently enables per-user statistics. Hysteria2 and TUIC also work without the full gRPC transport.

`versions.lock` pins the Docker stats package version and the SHA256 digests for both architectures. Official package digests are kept separately to verify the Cronet source. `padm-docker update` updates the images and host control bundle together and initializes statistics. For older versions without self-update, use a freshly downloaded installer for the one-time transition so it includes the shared modules. The transition preserves protocol configuration. Available protocols follow the Docker feature matrix. [Docker Updates](docker-guide.md#updates)

📊 If native sing-box reports `v2ray api is not included in this build`, or statistics configuration was removed to restore connectivity, follow these steps:

1. Update padm from **System & script**.
2. Open `Cores & services → sing-box lifecycle → Upgrade / switch version`. Press Enter for the latest stable version or enter a version number.
3. Confirm that **sing-box user statistics capability** is supported and the service is running, then run **Checks and diagnostics**.

After an upgrade, padm restores `14_stats_api.json` from existing protocol users and reloads the core. The stats API listens on `127.0.0.1:10087`. Existing ports, certificates, and credentials are preserved. A failure to restore statistics triggers an attempt to roll back the core and configuration. Reusing a previous installation configuration also updates an old core that lacks statistics support. New traffic is attributed to existing accounts. Traffic from periods without collection cannot be recovered.

Padm prefers a published `sing-box-v<upstream-version>` archive from this repository and checks its digest, version, and `with_v2ray_api` build tag. If the stats package is explicitly unavailable, you can choose to build it on native Linux amd64 or arm64. Padm resolves the upstream commit, downloads that exact source, verifies the required Go toolchain, uses the CI build settings, and extracts verified `libcronet.so` from the upstream package. The toolchain and build caches stay under `/etc/padm/cache/sing-box-build`, leaving the system Go installation available.

The existing service runs during the build. Padm checks the resulting version, statistics support, and current configuration before proceeding. Cancellation leaves the existing core installed. Network, rate limit, digest, or version validation errors stop the operation. Older source versions without the required build files are rejected.

## System and Script

🧰 Open **System & script** for padm updates, installation status, host protection, and network settings.

- 🔄 **Update padm.** When the subscription control service is enabled or running, the update also refreshes and restarts it. If refreshing fails, padm keeps the script update and prompts you to retry from control-plane maintenance.
- 🧾 **Check installation status.** Inspect the entry script, version, ref, and module manifest.
- 🛡️ **Fail2ban protection.** Native deployments include SSH, `/s/control/`, and optional site-scan protection. Docker provides WS, control-plane, and dedicated SSH service protection. Full native-host acceptance remains pending for the Docker variant.
- 🚀 **Network optimization.** Inspect host networking, enable BBR + fq, or remove padm's saved settings.

Enabling BBR + fq uses the BBR implementation from the current kernel and writes these settings to `/etc/sysctl.d/99-padm-bbr.conf`.

```conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

**Remove padm's BBR configuration** deletes that file and attempts to restore the previous congestion control and queue discipline.

## Post-Install Control Points

📂 Use these native installation paths to find configuration and state for troubleshooting or backups.

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

See the build and dependency workflows in the [Maintainer Guide](maintenance.md).
