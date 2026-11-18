# 系列查询参数验证（排序 / 阅读状态）

> 目的：书架上的"排序"和"未读/在读/已读"筛选必须**真的**被服务端支持。
> 假实现只能证明"我把参数发出去了"，不能证明 Komga 认这些值。
> 本文记录 2026-11-17 对真实 Komga **1.30.1** 实例的验证。

## 环境

- 服务端：`komga-1.30.1.jar`，`http://127.0.0.1:25600`
- 账号：`komga@example.com`（本机测试库）
- 认证：用 Basic 调 `POST /api/v2/users/me/api-keys` 建一把临时 Key，
  之后所有请求带 `X-API-Key`（与客户端的正式用法一致）

```powershell
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('komga@example.com:komga'))
$key = (Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:25600/api/v2/users/me/api-keys' `
  -Headers @{ Authorization = "Basic $b64" } -ContentType 'application/json' `
  -Body '{"comment":"KomgaNative verify E2 2026-11-17"}').key
$hk = @{ 'X-API-Key' = $key }
```

## 排序：`sort=property,asc|desc`

| 请求 | 结果（系列标题顺序） |
|---|---|
| `GET /api/v1/series?size=20&sort=metadata.titleSort,asc` | Akira v01 → Frieren → Sunny v01 → Vagabond v01 → Verify Series #1 |
| `GET /api/v1/series?size=20&sort=metadata.titleSort,desc` | 与 asc 完全相反 |
| `GET /api/v1/series?size=5&sort=createdDate,desc` | Frieren → Verify Series #1 → Vagabond v01 → Sunny v01 → Akira v01 |
| `GET /api/v1/series?size=5&sort=readProgress.lastModified,desc` | Akira v01 → Sunny v01 → Vagabond v01 → Verify Series #1 → Frieren |

结论：

- `sort` 是**数组**参数（OpenAPI 里 `type: array`），单个 `property,asc` 写法服务端接受；
- 上述四个取值都返回 200，且顺序符合语义（标题排序正反序对称，最近阅读与最近添加各成一套顺序）。

### 为什么排序项没有继续加（UI-P2-7 的取舍）

计划里还想补"按书籍数量 / 按发行日期"。没有加，原因有二：

1. OpenAPI 只规定 `sort` 的**格式**是 `property(,asc|desc)`，**没有列出可排序属性清单**，
   没法从规格反推合法属性名；
2. 排序属性是查询/实体层的名字，**不等于 DTO 字段名**——已验证的 `createdDate` 在
   `SeriesDto` 里对应的字段叫 `created`。所以"字段在 DTO 里存在"不能证明它能排序。

`booksCount` / `booksMetadata.releaseDate` 看起来能排，但没有运行中的 Komga 可以验证：
写错了用户点下去要么 400、要么顺序诡异。按"API 真值规则"（`AGENTS.md`）不猜。
有服务器时按上面的表格补两行实测，再往 `SeriesSort` 里加即可。

契约测试目前钉的是**格式**（`komga_api/test/contract_test.dart`：每个排序都能解析成
`属性[,asc|desc]`、方向只有 asc/desc）；属性名的正确性靠这张实测表。

## 阅读状态：`read_status=UNREAD|READ|IN_PROGRESS`

| 请求 | `totalElements` | 返回系列 |
|---|---|---|
| `read_status=UNREAD` | 2 | Sunny v01（1/1 未读）、Vagabond v01（1/1 未读） |
| `read_status=READ` | 3 | Frieren、Verify Series #1、Akira v01 |
| `read_status=IN_PROGRESS` | 0 | （该测试库当时没有"读了一部分"的系列） |

结论：三种枚举都被接受；`UNREAD` 只返回**一本都没读过**的系列
（不是"存在未读书"的系列）。`IN_PROGRESS` 的完整语义（部分读）没有在这个库里
造出数据验证——UI 文案只说"在读"，不承诺具体判定边界。

## 系列级标记已读/未读

OpenAPI 里 `/api/v1/series/{seriesId}/read-progress` 声明了两个操作：

- `POST`：`summary: Mark series as read`，返回 204；
- `DELETE`：`summary: Mark series as unread`，返回 204。

对真实实例（`Verify Series #1`，1 本书 3 页）验证：

| 请求 | 之后 `booksReadCount` | 书上的 `readProgress` |
|---|---|---|
| `POST /api/v1/series/0S8NJYAVNZ9DJ/read-progress` | 1/1 | `completed=true`, `page=3`（= 该书页数，不是 1） |
| `DELETE /api/v1/series/0S8NJYAVNZ9DJ/read-progress` | 0/1 | `null`（不是 `completed=false`） |

这就是"整系列标记"不需要逐本请求的证据。客户端对应：

- `KomgaSession.markSeriesRead` / `markSeriesUnread` / `markBookUnread`；
- `contract_test.dart` 覆盖 `POST`/`DELETE` 的 series read-progress 与 `DELETE` 的 book read-progress；
- 写服务端之后，`ProgressStore.forceAdopt` 会把本地 outbox 里同一本书的旧进度覆盖掉，
  否则"刚标记未读、书架却还显示读过"。

## 客户端落地

- `packages/komga_domain/lib/src/queries.dart`：`SeriesSort` / `SeriesReadStatus`（语言无关的枚举）
- `packages/komga_api/lib/src/urls.dart`：`sortWireValue` / `readStatusWireValue`
  ——**wire 值只在这里出现一次**
- `test/contract_test.dart`：把带 `sort` / `read_status` 的 URL 拿去和 OpenAPI 比对参数名
- `test/fixtures/series-read-status-unread.json`：上表第一条 UNREAD 的**真实响应**，
  由 `fixtures_test.dart` 驱动解析并断言"返回的系列确实都是未读"
