# 需求收敛进度（2026-11 起）

> 需求明细与验收标准见 [requirements-plan-2026-11.md](requirements-plan-2026-11.md)；
> 差距来源见 [competitor-research-2026-11.md](competitor-research-2026-11.md)。
>
> 状态：`TODO` 未开始 / `WIP` 开发中 / `DONE` 已通过门禁 + 设备验证并推送。
> 每行完成后填 commit，便于回溯"哪次改动兑现了哪条需求"。

## W0 正确性

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| FIX-01 | 墨水屏探测贯通阅读器 | P0 | DONE | `20cf264` |
| FIX-02 | 主题/墨水屏/书架视图持久化 | P0 | DONE | `feat(app): 持久化主题/墨水屏/书架视图` |
| FIX-03 | 阅读方向覆盖所有入口 | P0 | TODO | — |
| FIX-04 | 预设应用补齐锁定缩放/去白边 | P0 | TODO | — |
| FIX-05 | 正在读骨架与空态修正 | P0 | TODO | — |
| FIX-06 | 列表层进度与系列名 | P0 | TODO | — |
| FIX-07 | 下载队列持久化 | P0 | TODO | — |
| FIX-08 | 搜索/收藏集/阅读列表分页 | P0 | TODO | — |
| FIX-09 | 版本号/简介按钮/标签溢出 | P0 | TODO | — |

## W1 阅读器

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| QUA-01 | 拆 `reader_screen` + 清理死代码 | P1 | TODO | — |
| RDR-01 | 阅读器页码滑杆 + 剩余页 | P1 | TODO | — |
| RDR-02 | 阅读器目录/章节列表 | P1 | TODO | — |
| RDR-03 | 顶栏 IA + AA 快捷设置 | P1 | TODO | — |
| RDR-04 | 阅读设置分组/重置/适配预览 | P1 | TODO | — |
| RDR-05 | 翻页动画选择 | P1 | TODO | — |
| RDR-06 | 双页分组持久化 | P1 | TODO | — |

## W2 书架/系列

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| LIB-01 | 书架标题/计数/筛选状态/toolbar 收敛 | P1 | TODO | — |
| LIB-02 | 未读角标 + 置顶 | P1 | TODO | — |
| LIB-03 | 书架多选/批量 | P1 | TODO | — |
| LIB-04 | 排序补充 + 保存筛选组合 | P1 | TODO | — |
| SER-01 | 系列书列表排序/筛选 | P1 | TODO | — |
| SER-02 | 系列书多选/批量/标记之前所有 | P1 | TODO | — |
| SER-03 | 系列下载全部/未读 N 本 | P1 | TODO | — |
| UI-01 | 玻璃层级/阴影/字体克制 | P1 | TODO | — |

## W3 搜索/下载/设置

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| SCH-01 | 搜索历史 + 空态 | P1 | TODO | — |
| SCH-02 | 搜索 facets（状态/标签/作者） | P1 | TODO | — |
| SCH-03 | 搜索分页 + 结果系列名 | P1 | TODO | — |
| DLD-01 | 下载设置（仅 Wi-Fi/读完删除/并发） | P1 | TODO | — |
| DLD-02 | 下载队列 UI + 全局反馈 | P1 | TODO | — |
| SET-01 | 设置 IA（Reader/Library/Downloads/History/About） | P2 | TODO | — |

## W4 历史/收藏/备份

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| HIS-01 | 阅读 session 数据模型 | P2 | TODO | — |
| HIS-02 | History 页 + 最近阅读行 | P2 | TODO | — |
| SET-02 | 本地偏好导出/导入 | P2 | TODO | — |
| UI-02 | 收藏集封面拼贴/描述/搜索 | P2 | TODO | — |
| PLT-01 | 平板书架两栏 | P2 | TODO | — |

## W5 深度/平台

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| HIS-03 | Insights（连续天数/热力图/统计） | P2 | TODO | — |
| HIS-04 | 阅读器内阅读时长 | P2 | TODO | — |
| PLT-02 | iPad 默认双页/阅读布局 | P2 | TODO | — |
| I18N-01 | 数据层错误文案本地化 | P2 | TODO | — |
| A11Y-01 | TalkBack/VoiceOver + Dynamic Type 2.0 | P2 | TODO | — |
| UI-03 | 黄金图覆盖补齐 | P2 | TODO | — |

## W6 可选增强

| ID | 需求 | P | 状态 | commit |
|---|---|---|---|---|
| RDR-07 | 点击区预设 + 反转 | P2 | TODO | — |
| RDR-08 | 条漫自动滚动 | P2 | TODO | — |
| SER-04 | 收藏集新建/编辑（API 验证后） | P2 | TODO | — |
| I18N-02 | 语言扩展框架（日/繁中/西/法） | P2 | TODO | — |

---

## 已知取舍

实施过程中如果某条需求与既有约束冲突（例如 Komga 服务端不支持该查询参数），
在本节记录"降级成什么"和"为什么"，不要静默砍功能。

## 实施记录

### FIX-01 墨水屏探测贯通阅读器

- 新增 `effectiveEinkProvider`（`forceEink || einkDetected`）作为唯一来源；
  `KomgaApp`、`ReaderScreen`（配色 / 翻页效果 / 开场 Hero）都读它。
- 新增黄金图 `reader_auto_eink`（只覆盖探测为真、不打开强制开关）与
  `test/providers/effective_eink_test.dart`。
- 顺手把 `ReaderScreen` 里重复的 `settingsProvider` 读取去掉，避免再次出现
  "主题变了、阅读器没变"。

### FIX-02 主题 / 墨水屏 / 书架视图持久化

- 存储从"一个字段一个方法"改成**一份快照** `AppSettings`：
  `themeMode`、`forceEink`、`language`、`haptics`、`view`、`coverSize`、
  `sort`、`readStatus`，外加 `libraryFilters`（每台服务器上次选的库）。
- `SettingsStore.update(mutate)` 做"读出最新 → 只改这几个字段 → 写回"，并在
  `SecureSettingsStore` 里串行化：设置页与书架控制器共用同一个 blob，读改写
  才不会被对方用旧快照覆盖。
- 书架**先恢复再加载**，避免"先按默认排序画一屏、再跳成上次的排序"。
- 存档里的库 id 会先跟当前服务器的库列表核对：不存在就回"全部库"并清掉脏记录；
  库列表取不到（离线）时保留原选择。
- 解码逐字段容错（未知枚举/类型不对只影响该字段），覆盖旧版本只有 `language`
  的存档与非法 JSON。
