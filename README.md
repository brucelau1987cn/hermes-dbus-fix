# fix-dbus-and-start

一键修复 D-Bus user session 并启动 hermes gateway。

## 用法

```bash
# 一键运行
curl -sL https://raw.githubusercontent.com/brucelau1987/hermes-fix/main/fix-dbus-and-start.sh | bash
```

或先下载再执行：

```bash
wget -q https://raw.githubusercontent.com/brucelau1987/hermes-fix/main/fix-dbus-and-start.sh
chmod +x fix-dbus-and-start.sh
./fix-dbus-and-start.sh
```

## 做了什么

1. 安装 `dbus-user-session`
2. 重启 `user@0.service`
3. 等待 `/run/user/0/bus` 就绪
4. 设置 `XDG_RUNTIME_DIR` 和 `DBUS_SESSION_BUS_ADDRESS` 环境变量（持久化）
5. 启动 `hermes gateway`
