# fix-dbus-and-start

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu-blue)](#requirements)
[![Tests](https://img.shields.io/badge/Tests-bash%20dry--run-brightgreen)](#testing)

一键修复 systemd 用户级 D-Bus session，并启动 `hermes gateway`。

这个项目用于解决服务器上运行 `hermes gateway start` 时，因为用户级 D-Bus session 缺失导致的启动失败，例如：

```text
/run/user/<uid>/bus not found
Cannot autolaunch D-Bus without X11 $DISPLAY
Failed to connect to bus
```

## Features

- 自动安装或确认 `dbus-user-session`、`dbus`
- 支持 root 和非 root 用户的 D-Bus session 修复
- 支持按用户名或 UID 指定目标用户
- 支持 `DRY_RUN=1` 预演模式，便于生产环境变更前检查
- 支持只修复 D-Bus，不启动 `hermes gateway`
- 支持指定 `hermes` 可执行文件路径
- 默认避免非 root 用户场景污染全局 `/etc/environment`
- 附带轻量测试脚本

## Requirements

- Debian / Ubuntu 系 Linux 发行版
- `bash`
- `systemd`
- `apt-get`
- root 权限或 sudo 权限
- 已安装 `hermes`，如果需要脚本最后自动启动 gateway

## Quick Start

推荐先用 `DRY_RUN=1` 看看脚本会做什么：

```bash
curl -fsSL https://raw.githubusercontent.com/brucelau1987cn/hermes-fix/main/fix-dbus-and-start.sh | DRY_RUN=1 sudo -E bash
```

确认无误后正式执行：

```bash
curl -fsSL https://raw.githubusercontent.com/brucelau1987cn/hermes-fix/main/fix-dbus-and-start.sh | sudo bash
```

或者先下载再执行：

```bash
wget -q https://raw.githubusercontent.com/brucelau1987cn/hermes-fix/main/fix-dbus-and-start.sh
chmod +x fix-dbus-and-start.sh
sudo ./fix-dbus-and-start.sh
```

## Usage

默认行为：修复 root 的用户级 D-Bus session，并启动 `hermes gateway`。

```bash
sudo ./fix-dbus-and-start.sh
```

只修复 D-Bus，不启动 `hermes gateway`：

```bash
START_HERMES=0 sudo -E ./fix-dbus-and-start.sh
```

修复指定用户：

```bash
TARGET_USER=ubuntu sudo -E ./fix-dbus-and-start.sh
```

修复指定 UID：

```bash
TARGET_UID=1000 sudo -E ./fix-dbus-and-start.sh
```

修复非 root 用户，并以该用户启动 `hermes gateway`：

```bash
TARGET_USER=ubuntu HERMES_AS_TARGET=1 sudo -E ./fix-dbus-and-start.sh
```

指定 `hermes` 可执行文件路径：

```bash
HERMES_BIN=/usr/local/bin/hermes sudo -E ./fix-dbus-and-start.sh
```

## Configuration

脚本通过环境变量配置。

| Variable | Default | Description |
| --- | --- | --- |
| `TARGET_USER` | `root` | 要修复 D-Bus session 的用户名。 |
| `TARGET_UID` | 自动从 `TARGET_USER` 推导 | 要修复 D-Bus session 的 UID。设置后优先于 `TARGET_USER`。 |
| `START_HERMES` | `1` | 是否在修复完成后启动 `hermes gateway`。设为 `0` 可跳过。 |
| `HERMES_BIN` | `hermes` | `hermes` 命令名或完整路径。 |
| `HERMES_AS_TARGET` | `0` | 非 root 目标用户时，是否用该用户身份启动 `hermes gateway`。 |
| `PERSIST_ENV` | root 目标为 `1`，非 root 目标为 `0` | 是否写入 `/etc/profile.d/dbus-user-session.sh` 和 `/etc/environment`。 |
| `DRY_RUN` | `0` | 预演模式。打印将执行的系统修改，不真正写入、重启或启动。 |
| `RESTART_USER_UNIT` | `1` | 是否重启 `user@<uid>.service`。设为 `0` 时只尝试启动/确认。 |
| `ENABLE_LINGER` | `1` | 是否执行 `loginctl enable-linger <user>`。 |

## What It Does

1. 检查权限和目标用户/UID
2. 安装或确认 `dbus-user-session`、`dbus`
3. 可选执行 `loginctl enable-linger <user>`
4. 重启或启动 `user@<uid>.service`
5. 等待 `/run/user/<uid>/bus` 就绪
6. 设置当前进程的：
   - `XDG_RUNTIME_DIR=/run/user/<uid>`
   - `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/<uid>/bus`
7. 按需持久化环境变量到：
   - `/etc/profile.d/dbus-user-session.sh`
   - `/etc/environment`
8. 可选启动 `hermes gateway`

## Safety Notes

- 这是会修改系统状态的脚本。生产环境建议先运行 `DRY_RUN=1`。
- 默认目标是 root，因为常见故障是 root 启动 `hermes gateway` 时缺少 `/run/user/0/bus`。
- 修复非 root 用户时，请显式设置 `TARGET_USER` 或 `TARGET_UID`。
- 非 root 目标默认不会写入全局环境变量，避免影响其他用户。如确实需要，设置 `PERSIST_ENV=1`。
- 如果你只想验证 D-Bus 修复，不想启动 gateway，请设置 `START_HERMES=0`。

## Testing

本仓库包含轻量测试脚本：

```bash
./tests/run-tests.sh
```

测试内容包括：

- Bash 语法检查
- 配置布尔值解析
- 环境变量持久化策略
- root / 非 root 目标 dry-run 输出
- `DRY_RUN=1` 下不会真实执行系统修改

如果安装了 `shellcheck`，也建议额外执行：

```bash
shellcheck fix-dbus-and-start.sh tests/run-tests.sh
```

## Troubleshooting

### `/run/user/<uid>/bus` 仍然不存在

先只修复 D-Bus 并查看日志：

```bash
START_HERMES=0 sudo -E ./fix-dbus-and-start.sh
journalctl -u user@<uid>.service --no-pager -n 100
```

### 找不到 `hermes`

确认 `hermes` 已安装并在 PATH 中，或者指定完整路径：

```bash
HERMES_BIN=/path/to/hermes sudo -E ./fix-dbus-and-start.sh
```

### 不想重启用户服务

```bash
RESTART_USER_UNIT=0 sudo -E ./fix-dbus-and-start.sh
```

### 非 root 用户启动 gateway 失败

尝试以目标用户身份启动：

```bash
TARGET_USER=ubuntu HERMES_AS_TARGET=1 sudo -E ./fix-dbus-and-start.sh
```

## Development

克隆仓库：

```bash
git clone https://github.com/brucelau1987cn/hermes-fix.git
cd hermes-fix
```

运行测试：

```bash
./tests/run-tests.sh
```

查看 dry-run 行为：

```bash
DRY_RUN=1 START_HERMES=0 sudo -E ./fix-dbus-and-start.sh
```

## License

当前仓库尚未声明许可证。公开复用前，建议补充 `LICENSE` 文件。
