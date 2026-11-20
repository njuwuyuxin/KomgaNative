# ADR 0005：按系列记住阅读设置存哪里

- 状态：采纳（2026-11-19）
- 相关：UI-P3-2、[docs/reader.md](../reader.md)、`apps/app/lib/src/data/reader_prefs.dart`

## 背景

P3-2 要"按系列记住阅读设置"：同一个系列（例如日漫）用自己的模式/方向/适配/背景，
其他系列继续用全局设置。需要决定：

1. 存 Drift 表；
2. 存现有的 secure storage JSON（`komganative.reader.v1`）；
3. 每系列一个 preset。

数据量级：一个系列一条记录，每条只有 6 个字段（模式、亮度、常亮、适配、方向、背景）。
没有按字段查询/排序的需求，只在进阅读器时按 seriesId 取一条。

## 决定

**存现有 secure storage JSON 的 `seriesOverrides` 字段**：
`seriesId → ReaderConfig`（独立纯配置值对象，见 `reader_config.dart`）。读取走 `ReaderPrefs.forSeries(seriesId)`（直接返回 `seriesOverrides[seriesId] ?? global`）；
打开"按系列记住"时把当前生效 `ReaderConfig` 快照进这个 map，关闭时删掉该 key。

不新增 Drift 表，也不新增依赖。

## 理由

- **没有查询需求**：读取是"按 seriesId 一次取一条"，不需要 SQL、索引、join；
  Drift 的收益（查询/迁移/事务）在这里用不上。
- **已有存储与迁移路径**：`ReaderPrefs.fromJson` 本来就逐字段容错；旧存档没有
  `seriesOverrides` 时按空 map 处理，不需要版本号迁移。
- **原子性足够**：设置改动是低频用户操作，整份 JSON 重写一次（几 KB）比开事务便宜。
- **无递归与拷贝漂移**：`ReaderConfig` 只含纯阅读配置参数，`ReaderPreset` 与 `seriesOverrides` 直接持有 `ReaderConfig`，无需 `configOnly()` / `withConfig()` 原型裁剪。

## 代价

- 没做跨设备同步（和全局阅读偏好一样，本来就是本机设置；同步的只有阅读进度）。
- 没做容量上限/清理：理论上读过的系列越多，JSON 越大。实际一个系列约 100 字节，
  1000 个系列约 100 KB，仍在 secure storage 可接受范围；真到需要按"最近使用"淘汰时，
  再迁 Drift 并写新 ADR。
- 写入是整个 JSON 覆盖，不是字段级更新；多端同时改同一账号的本地设置不会合并
  （本机单用户，不存在这个场景）。

## 备选方案

- **Drift 表**：查询能力用不上，增加表结构/迁移/DAO，收益低于成本。
- **每系列一个 preset**：预设是"用户命名的配置"，系列覆盖是"隐式的当前值"；
  两者语义不同，混在一起会让预设列表被系列名污染。
- **写进 Komga 服务端**：Komga 没有"每系列阅读器偏好"字段；不要为了客户端设置改服务端模型。

## 验收

- `data/reader_prefs_test`：系列覆盖 JSON 往返、`forSeries` 优先级、覆盖不递归。
- `reader_series_prefs_test`：开关打开后只写系列覆盖、全局不变；关闭后覆盖删除。
- 面板开关 `reader-series-remember`；`reader_settings@*` 基线包含它。
