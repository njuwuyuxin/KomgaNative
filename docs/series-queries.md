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

## 阅读状态：`read_status=UNREAD|READ|IN_PROGRESS`

| 请求 | `totalElements` | 返回系列 |
|---|---|---|
| `read_status=UNREAD` | 2 | Sunny v01（1/1 未读）、Vagabond v01（1/1 未读） |
| `read_status=READ` | 3 | Frieren、Verify Series #1、Akira v01 |
| `read_status=IN_PROGRESS` | 0 | （该测试库当时没有"读了一部分"的系列） |

结论：三种枚举都被接受；`UNREAD` 只返回**一本都没读过**的系列
（不是"存在未读书"的系列）。`IN_PROGRESS` 的完整语义（部分读）没有在这个库里
造出数据验证——UI 文案只说"在读"，不承诺具体判定边界。

## 客户端落地

- `packages/komga_domain/lib/src/queries.dart`：`SeriesSort` / `SeriesReadStatus`（语言无关的枚举）
- `packages/komga_api/lib/src/urls.dart`：`sortWireValue` / `readStatusWireValue`
  ——**wire 值只在这里出现一次**
- `test/contract_test.dart`：把带 `sort` / `read_status` 的 URL 拿去和 OpenAPI 比对参数名
- `test/fixtures/series-read-status-unread.json`：上表第一条 UNREAD 的**真实响应**，
  由 `fixtures_test.dart` 驱动解析并断言"返回的系列确实都是未读"
