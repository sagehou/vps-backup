# rclone 存储后端与迁移约定

本项目把 restic 与实际云存储提供商解耦。公共/管理网关只引用一个固定的 rclone crypt remote；Google Drive、OneDrive、S3/B2、WebDAV 等 provider remote 保留明确的提供商名称，便于排障和迁移。

## 固定命名

生产 `.env` 固定为：

```dotenv
RCLONE_REMOTE=backup-crypt:restic
```

crypt remote 固定叫 `backup-crypt`：

```ini
[backup-crypt]
type = crypt
remote = backup-gdrive:backups
password = <obscured crypt password>
password2 = <obscured crypt salt>
```

底层 provider remote 不要求统一名称，建议使用一眼可识别的命名：

```text
backup-gdrive
backup-onedrive
backup-s3
backup-b2
backup-webdav
```

这样上层始终是：

```text
restic clients
  -> restic-gateway
  -> backup-crypt:restic
  -> <provider-remote>:backups
```

切换存储提供商时，客户端 URL、REST 用户、restic 仓库密码和仓库内容格式都不需要变化。

## 配置新的 provider remote

所有 rclone 配置操作都通过中央项目的工具容器执行：

```bash
cd /data/restic-gateway
docker compose --profile tools run --rm rclone-config listremotes
docker compose --profile tools run --rm rclone-config config
```

如果 `rclone.conf` 已启用配置加密，Compose 会通过 `RCLONE_PASSWORD_COMMAND` 从 `secrets/rclone-config-password` 读取密码。正常使用 `rclone config` 时无需先移除配置加密。

如果确实需要手工追加明文 section，可在停掉两个 gateway 后临时执行：

```bash
docker compose stop restic-gateway restic-admin-gateway
docker compose --profile tools run --rm rclone-config config encryption remove
# 编辑 rclone/rclone.conf
docker compose --profile tools run --rm rclone-config config encryption set
docker compose --profile tools run --rm rclone-config config encryption check
docker compose up -d restic-gateway restic-admin-gateway
```

从 `encryption remove` 到 `encryption set` 之间配置文件是明文，操作完成后应立即恢复加密。

创建 provider remote 后，验证基础读写能力和目标目录：

```bash
docker compose --profile tools run --rm rclone-config lsd backup-gdrive:
docker compose --profile tools run --rm rclone-config mkdir backup-gdrive:backups
docker compose --profile tools run --rm rclone-config lsd backup-gdrive:backups
```

不同 backend 的 API 配额、限流、对象语义和一致性行为可能不同，因此“rclone 能列目录”不等于已经完成生产验收。

## 创建固定的 crypt remote

首次部署时创建 `backup-crypt`，让它指向 provider 的 `backups` 目录：

```ini
[backup-crypt]
type = crypt
remote = backup-gdrive:backups
# 其余 crypt 参数按实际配置保存
```

验证：

```bash
docker compose --profile tools run --rm rclone-config lsd backup-crypt:
```

网关只能引用 crypt remote：

```dotenv
RCLONE_REMOTE=backup-crypt:restic
```

不要让 `restic-gateway` 直接指向未加密的 provider remote。

## 从旧后端迁移到新后端

迁移已有仓库时，应复制 crypt **底层已经加密的对象**，不要从旧 crypt remote 复制到新 crypt remote。这样不会经历解密再重新加密，也不会改变现有 restic 仓库。

以下示例从 OneDrive 迁移到 Google Drive：

```text
旧底层：backup-onedrive:backups
新底层：backup-gdrive:backups
固定 crypt：backup-crypt
```

### 1. 暂停自动维护

先暂停可能删除或重打包对象的任务，但可以继续让业务 VPS 备份到旧后端：

```bash
systemctl stop restic-maintenance.timer restic-check.timer
```

### 2. 初次全量复制

```bash
cd /data/restic-gateway
docker compose --profile tools run --rm rclone-config copy \
  backup-onedrive:backups \
  backup-gdrive:backups \
  --transfers 4 \
  --checkers 8 \
  --fast-list \
  --stats 30s \
  -P
```

`copy` 可以重复执行，适合长时间 seed；迁移期间旧仓库仍可继续接收新的客户端备份。

### 3. 最终停写并补齐

```bash
docker compose stop restic-gateway restic-admin-gateway

docker compose --profile tools run --rm rclone-config copy \
  backup-onedrive:backups \
  backup-gdrive:backups \
  --transfers 4 \
  --checkers 8 \
  --fast-list \
  -P
```

先检查最终 `sync` 会执行什么：

```bash
docker compose --profile tools run --rm rclone-config sync \
  backup-onedrive:backups \
  backup-gdrive:backups \
  --fast-list \
  --dry-run
```

确认目标目录只包含本项目备份数据且删除列表符合预期后，再去掉 `--dry-run`。

### 4. 比较底层对象

```bash
docker compose --profile tools run --rm rclone-config size backup-onedrive:backups
docker compose --profile tools run --rm rclone-config size backup-gdrive:backups

docker compose --profile tools run --rm rclone-config check \
  backup-onedrive:backups \
  backup-gdrive:backups \
  --size-only
```

对象数和总大小应与预期一致。

### 5. 切换 `backup-crypt`

保留原 crypt password、salt、文件名加密和目录名加密参数，只修改底层 `remote`：

```ini
[backup-crypt]
type = crypt
remote = backup-gdrive:backups
# password/password2/filename options 保持原值
```

如果旧配置仍叫 `backup-onedrive-crypt`，迁移时把该 section 的 crypt 参数原样复制到 `[backup-crypt]`，不要生成新的 crypt password 或 salt。

验证新的 crypt 能解开旧密文：

```bash
docker compose --profile tools run --rm rclone-config lsd backup-crypt:restic
```

然后确保中央 `.env` 使用：

```dotenv
RCLONE_REMOTE=backup-crypt:restic
```

重新启动 gateway：

```bash
docker compose up -d restic-gateway restic-admin-gateway
```

### 6. restic 级验收

先查询一台已有仓库：

```bash
docker compose exec -T restic-admin /scripts/run-restic.sh <host> snapshots
```

再手动执行完整性检查：

```bash
systemctl start restic-check.service
journalctl -u restic-check.service -f
```

检查通过后再执行维护流程，验证新 backend 的写入、删除和 prune：

```bash
systemctl start restic-maintenance.service
journalctl -u restic-maintenance.service -f
```

最后恢复 timer。若 timer 只是 `stop` 而没有 `disable`：

```bash
systemctl start restic-maintenance.timer restic-check.timer
```

如果此前使用过 `disable --now`：

```bash
systemctl enable --now restic-maintenance.timer restic-check.timer
```

确认：

```bash
systemctl list-timers --all | grep restic
```

旧后端建议保留至少若干完整备份周期作为静态回滚副本。切换后如果新后端已经产生新快照，直接切回旧后端会丢失这段期间的新数据；回滚前应先反向补齐增量。

## 管理任务的本地运行目录

`restic-admin` 以非 root UID/GID `10001:10001` 运行。必须显式提供可写 cache，否则 restic 可能退回尝试创建 `/.cache` 并报 `permission denied`。

模板使用：

```yaml
RESTIC_CACHE_DIR: /cache
```

并挂载：

```yaml
- ./cache/restic:/cache:rw
```

`restic-check.service` 和 `restic-maintenance.service` 在每次启动前都会确保以下目录存在且属于 `10001:10001`：

```text
/data/restic-gateway/cache/restic
/data/restic-gateway/locks
```

这同时避免因为 `locks/admin.lock` 的父目录不存在导致 `flock` 在真正执行 restic 前直接失败。
