# Komga API 验证记录

> 目的：把"客户端对 Komga 的假设"从**文档印象**变成**可复现的实测事实**，并留下防线防止漂移。
> 结论先说：早期实现（连接流程）**没有**跑过真实服务器，只有文档阅读 + 假实现测试。
> 2026-11-17 起补上了真实实例端到端验证，过程中发现 4 个真实缺陷（其中 3 个会直接影响用户），已修复。

## 1. 当时的信息从哪来（诚实交代）

| 来源 | 用途 | 局限 |
|---|---|---|
| `komga/docs/openapi.json`（官方仓库内） | 端点、参数、DTO 字段 | 只有形状，没有语义；实测发现**多处与运行时不符** |
| `komga.org/docs/` | 语义说明、示例 | 版本可能滞后 |
| GitHub 源码阅读 | 推断默认值与约束 | 未执行，等于推测 |

旧实现里 `KomgaUrls` 的注释写着"参数细节来自官方 OpenAPI 1.30.1 实测"——**当时并不准确**，实际是读规格得出的，`urls.dart` 现已改成指向本文件。

为什么当初没实测：本机没有 Docker，也没有跑起 Komga 服务端。实际上 Komga 有单文件 jar，装了 JDK 17 就能跑，不需要 Docker（见 §2）。

## 2. 如何复现（本机已验证）

> 启停现在统一走仓库脚本：`dart run tool/komga.dart start|stop|status`（说明见 `docs/environment-setup.md` §12）。
> 下面是一次性的原始复现命令，保留下来作为**参数、claim 流程、建库扫描**的记录。

```powershell
# 1) 下载服务端（单文件 jar，127 MB）
$dst = 'D:\DevTools\_verify\komga\komga-1.30.1.jar'
Invoke-WebRequest 'https://github.com/gotson/komga/releases/download/1.30.1/komga-1.30.1.jar' -OutFile $dst

# 2) 启动（JDK 17；数据库是 config 目录下的 SQLite）
java -jar $dst --server.port=25600 --komga.config-dir='D:\DevTools\_verify\komga\config'

# 3) 首次启动没有默认账号，必须 claim（email 必须是合法邮箱，否则 400 且 body 为空）
Invoke-WebRequest -Uri 'http://127.0.0.1:25600/api/v1/claim' -Method POST -UseBasicParsing `
  -Headers @{ 'X-Komga-Email' = 'komga@example.com'; 'X-Komga-Password' = 'komga' }

# 4) 建库 → 扫描（放一本 CBZ 到 library 目录）
$basic = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('komga@example.com:komga'))
Invoke-WebRequest 'http://127.0.0.1:25600/api/v1/libraries' -Method POST -Headers @{Authorization=$basic} `
  -Body '{"name":"Verify","root":"D:\DevTools\_verify\komga\library"}' -ContentType 'application/json' -UseBasicParsing
Invoke-WebRequest 'http://127.0.0.1:25600/api/v1/libraries/<libId>/scan' -Method POST -Headers @{Authorization=$basic} -UseBasicParsing
```

站点数据（jar、config、library、脚本）都在 `D:\DevTools\_verify\`，**不进仓库**。仓库里只留两样东西：抓下来的响应 fixture 和官方 OpenAPI 文件。

## 3. 实测结论

### 3.1 认证

| 断言 | 实测 |
|---|---|
| `Authorization: Basic base64(user:pass)` 可用 | 200 |
| `X-API-Key: <key>` 可用于 `/api/v1/*` 与 `/api/v2/users/me` | 200 |
| 错误密码 | 401，body 为 Spring 默认错误页（**不是** Komga 的业务错误体） |
| 首次启动有默认账号 | **没有**。必须 `POST /api/v1/claim`，且该接口仅"无用户"时可用 |
| claim 的 email 校验 | `komga@komga` → **400 且 body 为空**；`komga@example.com` → 200 |
| `GET /api/v2/users/me` 字段 | `id, email, roles, sharedAllLibraries, sharedLibrariesIds, labelsAllow, labelsExclude`，**确实没有 username**（用 email 作展示名是对的） |
| `roles` 实际值 | `ADMIN, FILE_DOWNLOAD, KOBO_SYNC, KOREADER_SYNC, PAGE_STREAMING, USER`（是叠加的，不是单选） |

### 3.2 API Key

| 断言 | 实测 |
|---|---|
| `POST /api/v2/users/me/api-keys`，body `{comment}` | 200，返回 `ApiKeyDto`，`key` 为 32 字符 |
| `comment` 可任意重复 | **不行**。同账号重复 → `400 {"message":"ERR_1034"}`，且没有人类可读文案 |
| `GET /api/v2/users/me/api-keys` 能取回 key | 不能，`key` 被掩码为 `******`（只返回 id/comment/createdDate） |

→ 影响：**同一台服务器第二次登录必然失败**。修复：撞 `ERR_1034` 时换一个带时间戳的 comment 重试一次（`session.dart`）。

### 3.3 库 / 系列 / 书

| 断言 | 实测 |
|---|---|
| `GET /api/v1/libraries` 返回裸数组 | ✅ `[...]`，不是分页对象 |
| `LibraryDto` 关键字段 | `id, name, unavailable` ✅ |
| `GET /api/v1/series` 返回分页对象 | ✅ `{content,totalElements,number,size,totalPages,...}` |
| 分页 `page` 基准 | **0 基**（`number: 0` 表示第一页） |
| `series.name` 是什么 | **服务器上的目录名**（本例 `library`），用户可读标题在 `metadata.title` |
| `metadata.readingDirection` 取值 | `RIGHT_TO_LEFT / VERTICAL / LEFT_TO_RIGHT / WEBTOON`；新建系列默认是**空串 `""`**（不是 null、不是 missing） |
| 规格里 readingDirection 有枚举吗 | **没有**，OpenAPI 只写 `string`——所以客户端必须宽松解析 |
| `PATCH /api/v1/series/{id}/metadata` 可改方向 | ✅ 204；传非法值 400 并给出可选枚举 |
| `BookDto.number` 类型 | **规格写 `string`，实际返回 `int`**（`"number":1`）。只按规格写会解析成空串 |
| `media.mediaProfile` | 普通 CBZ = `DIVINA` |
| `/api/v2/series/{id}` | **404**（v2 没有这个端点，只有 v1） |
| 不存在的系列查书 | 200 + 空页（不是 404） |

### 3.4 页与页图

| 断言 | 实测 |
|---|---|
| `GET /api/v1/books/{id}/pages` | 裸数组，含 `number,fileName,mediaType,width,height,sizeBytes,size` |
| `number` 基准 | **1 基** |
| `pages/{n}?zero_based=false` | `n=1` → 首页 200；`n=0` → **400**；`n=页数` → 200；`n=页数+1` → **400** |
| 不传 `zero_based` | 等价于 `false`（1 基），`pages/1` 可用 |
| `convert` 合法值 | 只有 `jpeg` / `png`；`convert=jpeg` 返回 `image/jpeg` |
| `width` / `height` / `scale` 能降采样吗 | **不能**。三种参数返回的字节 SHA 与不带参数**完全相同**（服务端静默忽略） |
| → 影响 | 降采样必须在客户端做（与既定设计一致，现在有证据） |

### 3.5 缩略图（关键坑）

| 请求 | 结果 |
|---|---|
| `GET /books/{id}/thumbnail` + `Accept: application/json` | **406** `Acceptable representations: [image/jpeg]` |
| 同上 + `Accept: image/jpeg` | 200，`image/jpeg`（约 2.4 KB） |
| `GET /books/{id}/pages/{n}/thumbnail` + `Accept: image/*,image/jpeg` | 200，`image/jpeg`（长边 300px，页码 1 基；`n=0` → **400**） |

→ 影响：旧代码在 Dio 全局 `headers` 里写死 `Accept: application/json`，**所有缩略图/封面都会 406**。修复：全局不设 `Accept`，JSON 请求与图片请求各自声明（`session.dart`）。

### 3.6 阅读进度（跨端同步的核心）

| 请求 | 结果 |
|---|---|
| `PATCH /books/{id}/read-progress {page:1,completed:false}` | 204，回读 `page:1` → **page 是 1 基** |
| `{page:0}` | 400，**body 为空** |
| `{page:99}`（页数 3） | 400，`"Page argument (99) must be within 1 and book page count (3)"` |
| 只发 `{completed:true}` | 204，`page` 保持原值 → 字段可选，支持局部更新 |
| 把 `page` 设为最后一页 | 服务端自动 `completed:true`（即使请求里写 `false`） |
| `DELETE /books/{id}/read-progress` | 204，进度回到 `null` |
| `readProgress` 字段形状 | `{page,completed,readDate,created,lastModified,deviceId,deviceName}` |

→ 影响：`SyncEngine` 用服务端 `lastModified` 做唯一权威是可行的；但要接受"服务端会自行把 completed 置真"。

### 3.7 错误体形态（客户端必须都容忍）

```jsonc
// Spring 默认错误页（401/404/400 都可能）
{"timestamp":"…","status":400,"error":"Bad Request","message":"Page argument (99) …","path":"…"}
// 机器码，无人类文案
{"message":"ERR_1034"}
// 空 body（实测 page=0 的 400）
```

### 3.8 收藏集 / 阅读列表（UI-P3-8）

在本地 1.30.1 实例上创建了一个收藏集与一个阅读列表，抓了四份真实响应：

| 端点 | 真实形状 / 结论 | fixture |
|---|---|---|
| `GET /api/v1/collections?page=0&size=20` | 分页对象；`content[]` 带 `id/name/ordered/seriesIds/createdDate/lastModifiedDate/filtered` | `collections.json` |
| `GET /api/v1/collections/{id}/series?size=20` | 普通 `PageSeriesDto`，元素与 `/series` 完全同形 | `collection-series.json` |
| `GET /api/v1/readlists?page=0&size=20` | 分页对象；`content[]` 带 `id/name/summary/ordered/bookIds/...` | `readlists.json` |
| `GET /api/v1/readlists/{id}/books?size=20` | 普通 `PageBookDto`，元素与系列书列表完全同形 | `readlist-books.json` |

`GET /api/v1/books?search=akira&size=20` 也是普通 `PageBookDto`，`content[]` 带 `seriesTitle`；响应存入 `books-search.json`，用于 P3-9 的全局书搜索。

### 3.9 继续阅读：`IN_PROGRESS` vs `ondeck`（2026-11-20 实测纠偏）

官方 `openapi-1.30.1.json` 对 `/api/v1/books/ondeck` 的声明是：
`Return first unread book of series with at least one book read and no books in progress.`
在本地 1.30.1 实例上用对照组复验了"在读列表"与 `ondeck` 的真实语义：

| 请求 | 真实行为 | fixture |
|---|---|---|
| `GET /api/v1/books/ondeck?size=20`（当 `Akira v01` 处于 `page=1, completed=false` 时） | **返回空列表 `[]`**（因为该系列存在 `IN_PROGRESS` 的书，且未读完过一整本） | `ondeck.json` |
| `GET /api/v1/books/ondeck?size=20`（当 `Frieren v01` 已读完、`Frieren v02` 未读时） | 返回 `Frieren v02`（`readProgress: null`）——即"下一卷待读"，不含半读的书 | `ondeck-next.json` |
| `GET /api/v1/books?page=0&size=20&read_status=IN_PROGRESS&sort=bogusField,desc`（对照组） | `Akira v01 (11-19)` → `Sunny v01 (11-20)`（默认顺序） | — |
| `GET /api/v1/books?page=0&size=20&read_status=IN_PROGRESS&sort=readProgress.readDate,desc` | `Sunny v01 (11-20)` → `Akira v01 (11-19)`（`asc` 对称反转，`pageable.sort.sorted=true`） | `books-in-progress.json` |

→ 影响：客户端"正在读"顶部的继续阅读卡片必须优先查 `GET /api/v1/books?read_status=IN_PROGRESS&sort=readProgress.readDate,desc`（真正的半读书），再用 `/api/v1/books/ondeck` 兜底刚读完上一卷后的下一本未读，并结合本地 Outbox 对未同步项兜底。

→ 影响：收藏集/阅读列表只需要两个新的列表解析器，系列与书不用另写一套；顺序以服务端 `content[]` 顺序为准（`ordered` 标记用户是否手工排序）。

## 4. 由此修掉的缺陷

| # | 缺陷 | 后果 | 位置 |
|---|---|---|---|
| 1 | 全局 `Accept: application/json` | 所有缩略图 406，书架无封面 | `session.dart` `_buildDio` |
| 2 | API Key `comment` 写死 | 同服务器第二次登录 400 失败 | `session.dart` `createApiKey` |
| 3 | `Book.number` 按 `string` 解析 | 服务器给 int，卷号变空串 | `parsers.dart` `_numberString` |
| 4 | 400 未单独建模、不读 body | 页码越界等错误只剩"服务端返回 400" | `errors.dart` `KomgaBadRequestError` |

另外纠正了一处**我自己写错的判断**：曾以为 Dart 的 `DateTime.parse` 不接受 7 位小数时间戳，于是加了截断兜底。实测 `DateTime.tryParse('…9617379Z')` 正常工作（截断到微秒），兜底是死代码，已删除。

## 5. 现在的防线

| 防线 | 内容 |
|---|---|
| `test/fixtures/openapi-1.30.1.json` | 官方 OpenAPI（383 KB，取自 gotson/komga 1.30.1 tag） |
| `test/contract_test.dart` | 15 条：客户端会构造的**每个** URL，其 path/method/查询参数都必须在官方契约中声明 |
| `test/fixtures/*.json` | 真实响应回放（库、系列页、书的页、未读/在读的书、页列表、账号、ondeck、API Key、401/404/400/空 400/ERR_1034） |
| `test/fixtures_test.dart` | 24 条：真实 payload 驱动解析层 + 错误体多形态 + comment 撞车重试 + 容错 |
| `test/session_test.dart` | 请求头按资源类型分离（JSON vs 图片）、字节响应、Basic/X-API-Key |

抓取/更新 fixture：改 `D:\DevTools\_verify\export.ps1`（本机脚本，不入库）后重跑，再把 JSON 覆盖进 `packages/komga_api/test/fixtures/`。

## 6. 仍未验证（已知风险，别当成已验证）

- **墨水屏**（Onyx SDK 反射路径、刷新策略）——没有真机。
- **自签名证书 / TOFU**、反向代理子路径的真实部署（只用 URL 拼装单测覆盖）。
- **KOBO / KOREADER 同步协议**、OPDS（`ReadList` / `Collection` 的只读列表已在 UI-P3-8 接入并抓了真实响应）。
- **大库性能**：分页、缩略图并发、搜索（Lucene）行为只在小数据量下看过。
- **`sort` 参数**格式正确性（无效值也被静默接受，只有 1 个系列时无法判断排序生效）。
- **EPUB / PDF 书**的阅读路径（`mediaProfile` 为 EPUB/PDF 时页图行为）。
- **版本差异**：只测了 1.30.1。老版本（如 1.24）的 `/api/v2/users/me` 与 claim 行为可能不同。
