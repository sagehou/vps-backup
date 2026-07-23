# VPS Backup

面向多台 Docker Compose VPS 的集中式 restic 备份模板。业务 VPS 仅持有本机 REST 凭据和本机仓库密码，中央节点通过加密的 rclone crypt 后端写入 OneDrive，并使用独立公共网关与管理网关实现追加备份和自动维护。

## 核心特性

- 每台 VPS 使用独立 REST 用户、URL 路径和 restic 仓库密码。
- 公共 `restic-gateway` 启用 `--private-repos` 与 `--append-only`。
- `restic-admin-gateway` 仅位于内部管理 bridge，用于 `forget`、`prune`、`check` 和恢复验证。
- 公共和管理网关可同时在线，不需要为维护停止公共上传。
- 客户端使用 Docker 运行 `restic:latest`，支持 AMD64 与 ARM64。
- 默认备份 `/data`、`/etc`、`/root`，并以不区分大小写的规则排除名称中含 `cache` 的项目。
- systemd timer 自动调度客户端备份和中央维护。
- Traefik 和日志轮转通过不对外发布端口的 `linuxserver/socket-proxy` 访问 Docker API，不再直接挂载 Docker socket。

## 开始使用

完整目录、中央部署、客户端部署、凭据生成、仓库初始化、自动维护、恢复测试和故障排查请阅读：

[多 VPS 集中备份系统执行手册 v1.0](./多VPS集中备份系统执行手册-v1.0.md)

部署前必须完成以下事项：

1. 将所有 `CHANGE_ME` 替换为已确认的实际参数。
2. 从 `central/hosts.example.txt` 创建不会提交到 Git 的生产 `central/hosts.txt`。
3. 创建真实 `.env`、htpasswd、仓库密码和 rclone 配置；这些文件已被 `.gitignore` 排除。
4. 在实际 Traefik 主机验证 socket-proxy、Docker provider 路由发现和日志轮转 `USR1`。
5. 完成至少一次真实备份、快照查询和文件恢复验证。

## 安全边界与已知限制

- 业务 VPS 不应保存 OneDrive OAuth、rclone crypt、中央 rclone 配置或管理凭据。
- 当前架构没有单仓库硬容量配额。被攻陷的客户端可能持续上传垃圾数据，因此必须监控总容量和单仓库增长，并支持快速禁用对应公共用户。
- 为保持配置简单并跟随 `latest` 镜像的原生规则，socket-proxy 启用 `CONTAINERS=1` 和 `ALLOW_RESTARTS=1`。这会向同一 proxy network 内的 Traefik 和 logrotate 开放整个 `/containers` 读取命名空间，以及任意容器的 stop、restart、kill；它仍比直接挂载 Docker socket 少开放大量 API 分组，但不能消除容器读取和可用性风险。
- 项目按既定要求使用 `latest` 镜像。每次部署或更新后应记录实际镜像版本和 digest，并重新运行配置及恢复验证。
- 数据库专用一致性 dump 不在本期通用模板内，需要按具体服务单独设计。

## 目录

```text
central/   中央 rclone/restic 网关、管理脚本和 systemd 单元
client/    业务 VPS restic 客户端、排除规则和 systemd 单元
traefik/   使用 LinuxServer 原生权限开关的 socket proxy Compose 片段
tests/     脚本回归测试
```

仓库仅包含模板和示例，不应提交任何生产凭据或真实主机清单。
