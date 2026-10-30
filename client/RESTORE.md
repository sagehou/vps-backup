# 客户端单文件/目录恢复

客户端恢复适用于原 VPS 在线、且仍可访问自己的公共 Restic 仓库的情况。它使用客户端已有的 /scripts/restic-command.sh，不会取得 Gateway 管理凭据。

## 设计

- client/compose.yaml 将宿主机 /data/restic-client/restore 挂载到容器 /restore。
- client/scripts/restore.sh 调用现有认证入口，复用本机 REST 密码和仓库密码。
- 每次恢复都在 /restore 下创建唯一的 restic-restore.* 临时目录，不覆盖原文件。
- client/config/excludes.txt 排除 /data/restic-client/restore，防止恢复暂存内容进入下一次备份。

## 部署更新

在客户端 VPS 更新模板。若模板目录不是 /tmp/vps-backup，请替换为实际路径：

```bash
cd /tmp/vps-backup
git pull --ff-only
install -d -m 0750 /data/restic-client/restore
install -m 0550 /tmp/vps-backup/client/scripts/restore.sh /data/restic-client/scripts/restore.sh
install -m 0640 /tmp/vps-backup/client/config/excludes.txt /data/restic-client/config/excludes.txt
```

编辑生产 /data/restic-client/compose.yaml，在服务的 volumes 下增加：

```yaml
- ./restore:/restore:rw
```

不要覆盖生产 .env、secrets 或其他运行配置。确认 restore 目录由当前容器运行用户可写。然后检查并应用 Compose：

```bash
cd /data/restic-client
docker compose config --quiet
docker compose up -d --force-recreate restic-client
docker compose ps
```

重建客户端容器前，确认没有正在进行的备份任务。

## 恢复流程

### 1. 查看快照

```bash
docker compose exec -T restic-client /scripts/restic-command.sh snapshots --latest 10
```

### 2. 查找快照中的准确路径

```bash
docker compose exec -T restic-client /scripts/restic-command.sh ls <SNAPSHOT_ID>
```

客户端备份脚本从容器 /backup 工作目录使用相对路径备份，因此通常会看到类似 /backup/data/www、/backup/etc/nginx 的路径。必须以实际 ls 输出为准，不要猜测路径。

### 3. 恢复单个目录或文件

```bash
docker compose exec -T restic-client \
  /scripts/restore.sh <SNAPSHOT_ID|latest> '<快照内准确绝对路径>'
```

例如：

```bash
docker compose exec -T restic-client \
  /scripts/restore.sh latest '/backup/data/www'
```

脚本只接受 latest 或十六进制 Snapshot ID，以及快照内的绝对路径。它会创建独立恢复目录并打印容器内路径和宿主机路径。若恢复失败，会保留临时目录供排查。

宿主机恢复结果位于：

```text
/data/restic-client/restore/restic-restore.XXXXXX/
```

Restic 会在该目录下保留快照路径的相对层级；例如恢复 /backup/data/www，通常得到：

```text
/data/restic-client/restore/restic-restore.XXXXXX/backup/data/www/
```

### 4. 校验并复制回正式目录

先比较文件内容、数量或 SHA-256。确认无误后再复制回去，例如：

```bash
rsync -aHAX --numeric-ids \
  /data/restic-client/restore/restic-restore.XXXXXX/backup/data/www/ \
  /data/www/
```

将示例中的临时目录名替换为脚本实际输出的名称。该命令不会删除目标中额外存在的文件。需要完整替换时，先备份/改名原目录，再执行恢复；不要直接把 Restic 的 --target 指向在线业务目录。

恢复后按应用需要检查属主、权限、ACL、扩展属性以及服务状态。

## 何时使用 Gateway 恢复

客户端恢复依赖原 VPS 在线、客户端凭据仍可用、网络可访问公共 Gateway。若原 VPS 整机故障、客户端容器无法启动、凭据丢失，或需要恢复到另一台主机，应使用中央 restic-admin 和 /scripts/run-restic.sh，不要把管理凭据下发到业务 VPS。

## 安全注意

- 不要将恢复目标设置为 /backup 或任何在线业务目录。
- 不要把 /data/restic-client/restore 作为正式备份源。
- 不要把 REST 密码或仓库密码写入命令参数。
- 先恢复到隔离目录、完成校验，再复制回原路径。
