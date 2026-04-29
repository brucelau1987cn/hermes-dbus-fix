# fix-dbus-and-start

一键修复 systemd 用户 D-Bus session，并启动 `hermes gateway`。

适用场景：服务器上 `hermes gateway start` 因为缺少用户级 D-Bus session 失败，例如找不到 `/run/user/<uid>/bus`。

## 用法

一键运行：

```bash
curl -fsSL https://raw.githubusercontent.com/brucelau1987cn/hermes-fix/main/fix-dbus-and-start.sh | sudo bash
```

或先下载再执行：

```bash
wget -q https://raw.githubusercontent.com/brucelau1987cn/hermes-fix/main/fix-dbus-and-start.sh
chmod +x fix-dbus-and-start.sh
sudo ./fix-dbus-and-start.sh
```

## 常用参数

默认会修复 root 的 D-Bus session，并启动 `hermes gateway`。

```bash
# 预演模式：打印会执行的系统修改，不真正写入/重启/启动
DRY_RUN=1 sudo -E ./fix-dbus-and-start.sh

# 指定修复非 root 用户的 D-Bus session
TARGET_USER=ubuntu sudo -E ./fix-dbus-and-start.sh

# 指定 UID
TARGET_UID=1000 sudo -E ./fix-dbus-and-start.sh

# 修复非 root 用户，并以该用户启动 hermes
TARGET_USER=ubuntu HERMES_AS_TARGET=1 sudo -E ./fix-dbus-and-start.sh

# 非 root 用户也写入全局环境变量（默认不写，避免污染其他用户）
TARGET_USER=ubuntu PERSIST_ENV=1 sudo -E ./fix-dbus-and-start.sh

# 只修复 D-Bus，不启动 hermes
START_HERMES=0 sudo -E ./fix-dbus-and-start.sh

# hermes 不在 PATH 时指定路径
HERMES_BIN=/usr/local/bin/hermes sudo -E ./fix-dbus-and-start.sh

# 不重启 user@UID.service，只尝试启动/检查
RESTART_USER_UNIT=0 sudo -E ./fix-dbus-and-start.sh
```

## 做了什么

1. 检查 root 权限和目标用户/UID
2. 安装或确认 `dbus-user-session`、`dbus`
3. 尝试 `loginctl enable-linger <user>`，让用户服务能在无登录时运行
4. 重启或启动 `user@<uid>.service`
5. 等待 `/run/user/<uid>/bus` 就绪
6. 设置当前进程的 `XDG_RUNTIME_DIR` 和 `DBUS_SESSION_BUS_ADDRESS`
7. 按需持久化环境变量到：
   - `/etc/profile.d/dbus-user-session.sh`
   - `/etc/environment`
8. 启动 `hermes gateway`

## 注意

- 该脚本主要面向 Debian/Ubuntu 系统，依赖 `apt-get` 和 `systemd`。
- 默认修复 root 的用户级 D-Bus。修复其他用户时，请显式设置 `TARGET_USER` 或 `TARGET_UID`。
- 只有 root 目标默认写入全局环境变量。非 root 目标如需写入，请加 `PERSIST_ENV=1`。
- 如果机器上没有安装 `hermes`，脚本会在修复 D-Bus 后提示缺少命令并退出。
- `DRY_RUN=1` 可以先预览会执行的修改，适合生产机器变更前检查。
- 对生产机器执行前，建议先用 `START_HERMES=0` 验证 D-Bus 修复结果。
