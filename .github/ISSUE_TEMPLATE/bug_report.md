---
name: Bug 反馈
about: 报告 padm 安装、订阅、协议或运行时问题
title: '[Bug] '
labels: bug
assignees: ''
---

反馈前请先阅读 README，并在服务器上执行 `bash shell/validate_install.sh [domain]` 做只读验收；如果问题涉及 DNS/HTTP/HTTPS/TLS 探测，请补充 `--online` 输出。

如果低版本升级高版本出现异常，建议先使用 **高级/危险操作 -> 卸载脚本** 卸载后重新安装，再确认是否仍可复现。

## 1. 问题描述

请说明你期望发生什么、实际发生什么，以及是否稳定复现。

## 2. 复现步骤

例如：`padm -> 安装与重装 -> 推荐直连 Reality Vision`，按提示填写 entry、Reality target 和 SNI，安装后进入 `订阅与用户` 查看账号。

```text
请填写完整步骤
```

## 3. 安装失败日志或截图

```text
请粘贴关键日志，避免泄露 token、私钥、完整订阅链接等敏感信息
```

## 4. 系统版本

```text
例如：Debian 13 / Ubuntu 24.04
```

## 5. 脚本版本

```text
请填写 install.sh 显示的版本号
```

## 6. 核心、协议和安装方式

- 核心：

```text
例如：xray-core / sing-box
```

- 安装方式：

```text
例如：推荐直连 Reality Vision / 推荐 CDN Reality XHTTP / 无域名 Reality / 自定义安装 / 传统 TLS 兼容安装
```

- 协议：

```text
例如：7.VLESS Reality Vision / 12.VLESS Reality XHTTP / Hysteria2 / Tuic
```

## 7. 客户端版本

```text
例如：v2rayNG 1.18 / sing-box 1.12 / Clash Meta
```
