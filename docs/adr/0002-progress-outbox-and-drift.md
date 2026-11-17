# ADR 0002：进度 outbox 与本地持久化（Drift）

- 状态：已采纳
- 日期：2026-11-17
- 相关：`apps/app/lib/src/data/progress/`、`packages/komga_sync_engine`

## 背景

阅读进度当前是"翻页就 PATCH"：断网、切后台、服务端 5xx 都会让这一页永远丢掉，
而且下一次打开会退回旧位置。`komga_sync_engine` 已经把语义定好了
（同书合并、seq 回执、只信服务端 `lastModified` 对账），但只有内存实现——
一杀进程就全没了。

需要：**离线也不丢进度**、**多设备对账不被设备墙钟带偏**、**将来能缓存内容**。

## 决策

1. 引入 `drift`（含 `path_provider` 取库路径），表结构 v1 只有一张 `local_progress`：
   | 列 | 含义 |
   |---|---|
   | `book_id` | 主键 |
   | `page` / `completed` | 本地已知的最新进度 |
   | `updated_at` | 本地写入时间（只用于展示/诊断，**不参与对账**） |
   | `server_last_modified` | 上次确认的服务端 `lastModified`（对账基准，可空） |
   | `pending_seq` | 非空 = 有未提交更新；提交成功且 seq 未变才清空 |

2. **同书合并**：翻页产生大量更新，只保留最新一条（`insertOnConflictUpdate`）。
3. **seq 用写入时刻的微秒**：单调、无需额外计数表；`ack(bookId, seq)` 只在 seq 相等时清空，
   避免"提交期间又翻页"把新进度一起删掉（与引擎里的 `markAcked` 语义一致）。
4. **PATCH 成功后把 `server_last_modified` 置空**：Komga 的 PATCH 返回 204 无 body，
   拿不到新的服务端时间；宁可"基准未知"，下次 GET 时按 `adoptRemote` 重新建立基准，
   也不要拿设备墙钟冒充服务端时间（那正是多端互相覆盖的根源）。
5. **对账只在拿到服务端数据时做**：`decideSync(base, remote, hasPending)`；
   `pushLocal` 交给 flusher，`adoptRemote` 写回本地，其余不动。
6. **提交失败不删 pending**：网络错误/5xx 保留等待下次触发（进前台、书架刷新、下次翻页）；
   401/403 也保留（换 Key 后还能提交），但要停止本轮重试，避免打爆服务端。

## 备选方案与否决理由

| 方案 | 否决理由 |
|---|---|
| 继续直接 PATCH，失败就算了 | 断网即丢进度；"看完一章退出"这种最常见的路径恰好最脆弱 |
| 把 outbox 写进 secure storage（和偏好共用） | Keychain 不适合高频小写入；也没有查询/事务能力，缓存内容时还得再换一次 |
| 用 shared_preferences | 同上，且是字符串 KV，多设备对账需要结构化查询 |
| 上 `sqflite` 手写 SQL | drift 的类型安全查询、迁移工具体验更好；手写 SQL 在重构时没有编译期保护 |
| 现在就缓存页图/书架 JSON | 内容缓存是另一个量级（缓存键、失效、容量上限），单独一片做，先把"进度不丢"落地 |

## 后果

- `apps/app` 新增依赖：`drift`、`path_provider`；dev：`drift_dev`、`build_runner`、`sqlite3`（测试里开内存库）。
  生成的 `*.g.dart` 入库（Agent 环境不保证随时能跑 codegen）。
- Windows 上 `flutter test` 直接可跑内存库（Flutter 3.50 的 native assets 会构建 sqlite），
  不需要额外的 dll 注入。
- 表结构变更必须写 migration；v1 没有历史数据，暂不引入 schema 测试。
- 断网时阅读、翻页、进度全部可用；联网后自动补交。
  **内容缓存（断网打开书）不在本片**，见 "备选方案" 最后一行。
