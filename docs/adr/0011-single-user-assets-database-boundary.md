# ADR 0011: 保持单一用户资产库 `komga_native.sqlite` 边界（暂不物理拆分本地编目库）

- **状态**：已采纳（2026-11-26）
- **关联评审 / ADR**：`ADR 0002`、`ADR 0003`、`ADR 0008`、`P2-3`

## 背景

应用当前维护两个物理 SQLite 数据库：

1. **可再生缓存库 `komga_cache.sqlite`（`HttpCacheDatabase`）**：存放 HTTP 响应缓存、整本离线页图 `pinned` 索引与下载队列，可随时清空重建；
2. **用户资产库 `komga_native.sqlite`（`ProgressDatabase`，当前 `schemaVersion = 6`，共 11 张表）**：
   - 用户阅读资产（`apps/app/lib/src/data/progress/user_tables.dart`）：`local_progress`、`pinned_series_rows`、`reading_sessions`、`page_bookmarks_rows`；
   - 本机漫画编目（`apps/app/lib/src/data/local/local_tables.dart`）：`local_series_rows`、`local_books_rows`、`local_pages_rows`、`local_book_chapters_rows`、`local_mounted_roots_rows`、`local_collections_rows`、`local_read_lists_rows`。

随着本地漫画编目能力扩展（挂载目录、章节目录、书签、本地收藏集/阅读列表），架构评审指出一个客观耦合：**本地编目表结构变更仍需递增 `ProgressDatabase.schemaVersion`**，进而触碰存储阅读进度的数据库迁移路径。

## 决策

**现阶段决定暂不将 `local_*` 物理拆分为独立的 `local_catalog.sqlite`，继续保持「用户资产库（`komga_native.sqlite`）与可再生缓存库（`komga_cache.sqlite`）双库分离」的物理形态，同时以逻辑分界与自动化测试兜底风险：**

1. **代码与访问边界严格逻辑隔离**：
   - 表定义物理拆分为 `data/progress/user_tables.dart` 与 `data/local/local_tables.dart`；
   - 数据访问按限界上下文拆分为独立 DAO（`progress_user_dao.dart`、`bookmarks_dao.dart`、`local_catalog_query_dao.dart`、`local_catalog_write_dao.dart`、`local_curation_dao.dart`），彼此不跨上下文拼接裸 SQL；
   - `tool/ci_checks.dart` 在 UI 层（`screens/` 与 `widgets/`）禁止直接导入 `data/progress/**` 与 `data/local/**`（仅白名单放行纯视图模型），防止表结构泄漏至界面层。
2. **迁移安全由全版本测试与 Schema 快照兜底**：
   - `apps/app/test/data/progress_database_full_migration_test.dart` 与 `apps/app/test/data/user_db_migration_test.dart` 覆盖 `v1 → v6` 逐级升级与数据保留校验，确保每次 schema 变更在 CI 中可验证、可回归。

## 理由

1. **跨表原子查询与一致性**：本机源的「继续阅读 / `ondeck` 推导」「书架筛选（未读/在读/已读）」「阅读历史对已移除本机书的标记（`existingLocalBookIds`）」均需联合读取 `local_books_rows` 与 `local_progress` / `reading_sessions`。保持在单库内可直接用单事务与原生 SQL JOIN 完成，避免双库 `ATTACH DATABASE`、跨库外键失效或两阶段提交带来的复杂性。
2. **避免高风险的存量数据热搬迁**：线上已有用户的本机编目（v4–v6）已经落在 `komga_native.sqlite` 中。此时物理拆库需要编写跨文件拷贝、校验、断点续传与失败回滚逻辑，其线上故障面远大于当前单库递增 `schemaVersion` 的可控风险。
3. **资产生命周期对称**：与随时可删的 `komga_cache.sqlite` 不同，本机书库的自定义元数据、本地收藏集/阅读列表与阅读进度/书签/会话统计同属**不可随意清空的用户持久化资产**，在备份/导出与磁盘清理策略上语义一致。

## 已知权衡

- 本地编目新增字段或表时，仍会提升 `ProgressDatabase.schemaVersion` 并要求在迁移测试中补齐对应版本跃迁；
- 批量导入大体积本地漫画目录时，写事务与阅读器翻页写进度共享同一条 SQLite WAL 连接（目前已通过后台连接与防抖落盘缓解）。

## 触发重新评估（物理拆库）的条件

当以下任意条件成立时，应重新开启物理拆分 `local_catalog.sqlite`：

1. **规模与写争用**：本地书库普遍超过 10,000 本书或 `local_pages_rows` 超过 500,000 行，导致批量扫描/导入期间对阅读器翻页进度写入产生可观测锁等待；
2. **独立同步/导出需求**：需要直接以整库文件形式单独同步或备份「纯阅读进度与统计」而不携带本机文件路径索引；
3. **高频重型编目演化**：本机编目需要引入独立重型索引（例如 `FTS5` 全文检索虚拟表或大体积二进制缩略图）且与进度库 schema 演进频率明显分化。
