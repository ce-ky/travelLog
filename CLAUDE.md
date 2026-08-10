# CLAUDE.md — 导航索引

> 目的：把每个功能定位到**具体文件与行号**，改动前直接跳到相关区段，避免整文件通读浪费 token。
> 面向用户的介绍见 [README.md](README.md)。行号会随改动漂移——用作起点，落地前请核对当前内容。

## 架构分层（数据流）

`main.dart:12` 初始化 Supabase → `AuthGate`（登录门）→ `HomeShell`（导航壳）→ 各页面。

- **UI** `lib/screens/`、`lib/widgets/` — 只读 `AppState`，通过它触发变更。
- **状态** `lib/state/app_state.dart` — 唯一 `ChangeNotifier`，持有内存数据、过滤器、派生 getter。
- **数据** `lib/data/` — `TravelRepository` 抽象接口 + Supabase / mock 两个实现。
- **模型** `lib/models/` — 纯数据类。

改数据流：UI 调 `AppState` 方法 → `AppState` 调 `_repo` → 更新内存列表 → `notifyListeners()`。

## 功能 → 位置索引

### 地图（`lib/screens/map_screen.dart`，745 行）
- 状态与缩放阈值：`_MapScreenState` `27`；`_zoom/_recordZoom/_addZoom` 字段 `88-93`；`_collapsed` getter `95`。
- 相机动画：`_animatedMove` `47`；点空白就地新增：`_startAddAt` `99`；保存回调 `_onSaved` `112`；聚焦某旅途 `_fitTrip` `130`。
- 地图主体 `build` `152` — 连线/聚合分组循环 `167-176`；`FlutterMap` `194`；点击处理 `199`；瓦片层 `229`；连线层 `235`；标记层 `237`（聚合分支 `239-257`、单记录分支 `259-284`、就地新增脉冲点 `278`、展开气泡 `286-296`）；放大提示 `_AddHint` 挂载 `314`。
- 自定义绘制组件：`_PulsePin/_PulsePainter`（脉冲点）`396-478`；`_TripCluster`（旅途聚合圆）`480`；`_EntryMarker/_TeardropPainter`（水滴标记）`546-621`；`_ExpandedBubble/_BubblePainter`（点击气泡）`623-745`。

### 新增/编辑记录表单（`lib/screens/entry_form.dart`，715 行）
- `_EntryFormState` `47`；初始化（含自动选旅途）`initState` `67`。
- **50km 自动归入最近旅途**：`_autoSelectKm=50` `77`；`_nearestTripId` `80`；`_tripDistance` `97`。
- 选图 `_pickImage` `133`；选时间 `_pickWhen` `142`；选/切旅途 `_buildTripChips` `167`、`_pickTripFromAll` `196`；选位置 `_pickLocation` `232`；保存 `_save` `237`。
- 布局 `build` `303` — 标准布局 `310` 起、紧凑（地图弹窗）布局 `356` 起、侧栏配置条 `396` 起、类型选择 `433`。
- 内部小组件：`_TapField` `567`、`_ImagePickerField` `612`、`_ImageAction` `694`。

### 旅途列表（`lib/screens/trips_screen.dart`，347 行）
- 列表 `TripsScreen.build` `16`；新建行 `_NewTripRow` `44`；卡片 `_TripCard` `83`。
- 菜单动作枚举 `_TripAction{rename,edit,delete}` `167`；`_TripMenu` `169`；重命名 `_rename` `216`；删除确认 `_confirmDelete` `251`；空/错状态 `278`/`313`。
- 新建/编辑旅途弹窗：`lib/screens/new_trip_sheet.dart` — 入口 `show` `20`；选日期区间 `_pickRange` `76`；仅起始 `_pickStartOnly` `93`；保存 `_save` `103`；加同行人 `_addPerson` `281`。
- 旅途详情：`lib/screens/trip_detail_screen.dart` — `build` `26`、头部 `_TripHeader` `88`、按日期分组列表 `_GroupedList` `134`。

### 浏览（`lib/screens/browse_screen.dart`，53 行 — 壳）
- 模式枚举 `_Mode{type,companion}` `15`；`build` `21` 在两种视图间切换。
- 按类型：`lib/screens/type_list_screen.dart`（遍历 `EntryType.values` `26`）。
- 按同行人：`lib/screens/companions_view.dart` — 列表 `build` `23`；增 `_addPerson` `88`、改名 `_renamePerson` `97`、删 `_deletePerson` `106`、改名对话框 `_nameDialog` `132`；某人详情 `_CompanionDetail` `158`。
- 通用筛选页：`lib/screens/filter_list_screen.dart` — 筛选栏 `_FilterBar` `123`、下拉 `_Dropdown` `169`、分组列表 `_GroupedList` `203`。

### 导航壳 / 桌面布局（`lib/screens/home_shell.dart`，237 行）
- `_HomeShellState` `30`；桌面断点 `_desktopBreakpoint=720` `36`；切页 `_select` `44`；`build` `47`（桌面/移动分支 `92`）；FAB 新增记录 `_createEntry` `114`。
- 桌面头 `_DesktopHeader` `133`；桌面导航栏 `_DesktopNavBar` `168`（**固定 `height:56` 修 bug** `186`）。

### 登录（Supabase Auth）
- 门 `lib/screens/auth_gate.dart` — `_AuthGateState` `27`、`build` `31`。
- 登录页 `lib/screens/auth_screen.dart` — 提交 `_submit` `35`、`build` `74`、提示条 `_Banner` `204`。

### 位置选择器
- `lib/screens/location_picker_screen.dart` — 入口 `show` `19`、`build` `43`。

## 状态层（`lib/state/app_state.dart`，189 行）
- 字段/数据：`13`；加载 `refresh` `31`；`loading/error` getter `27-28`。
- 过滤器：字段 `_typeFilter/_tripFilter/_companionFilter` `50-52`、getter `54-56`；`toggleType` `62`、`setTripFilter` `67`、`setCompanionFilter` `72`、`clearFilters` `77`。
- 派生查询：`allEntries` `58`、`filteredEntries` `88`、`locatedEntries` `110`、`entriesForTrip` `135`、`tripsWithPerson` `156`、`entriesWithPerson` `161`。
- 写操作：`addEntry` `113`、`removeEntry` `118`、`addTrip` `124`、`removeTrip` `129`、`addPerson` `145`、`removePerson` `150`。
- 图片：`imageUrl`（带缓存 `_imageUrls` `170`）`173`、`uploadImage` `177`。

## 数据层（`lib/data/`）
- 接口 `travel_repository.dart` — `TravelSnapshot` `8`、`TravelRepository` `25`（方法 `26-56`）。
- Supabase 实现 `supabase_travel_repository.dart`：`loadAll` `26`、`saveTrip` `68`、`saveEntry` `100`、`deleteTrip` `124`、`savePerson` `133`、`deletePerson` `148`、`deleteEntry` `157`、`uploadImage` `165`、`imageUrl` `185`。
- Mock 实现 `mock_travel_repository.dart`（对应方法 `22-100`）；样例数据 `mock_data.dart`。

## 模型（`lib/models/`）
- `entry.dart` — 字段 `9-26`；`displayTitle` getter `43`；`markerGlyph` `26`。
- `entry_type.dart` — `enum EntryType` `7`；`label` `14`、`icon` `29`、`isImageBacked`（photo/drawing）`45`。
- `trip.dart` `4`（含 `companions`）；`person.dart` `2`；`geo_point.dart` `4`（`latLng` getter `15`）。

## 组件（`lib/widgets/`）
- `entry_card.dart` — `EntryCard` `12`；长按删除按钮 `_DeleteButton` `81`。
- `entry_image.dart` — `EntryImage` `11`；从 storagePath 异步取 URL 并渲染 `build` `30`。

## 关键常量 / 易踩坑（改前必看）
- **缩放阈值**：`_recordZoom=9`（低于→显示旅途聚合，高于→显示单记录）、`_addZoom=15`（低于→点击是放大而非放置）、初始 `_zoom=5`，均在 `map_screen.dart:88-93`。
- **`ui.Path` 命名冲突**：`map_screen.dart:2` 用 `import 'dart:ui' as ui`，绘制用 `ui.Path()`（`593`、`724`），避免与 flutter_map 的 `Path` 混淆。
- **底部导航高度 bug**：桌面栏必须固定 `height:56`（`home_shell.dart:186`），否则贪婪撑满。
- **水滴标记颜色**：白=无图 / 绿=有图，逻辑在 `_EntryMarker`（`map_screen.dart:546`）+ `EntryType.isImageBacked`。
- **50km 归并**：新记录自动归入最近旅途，阈值 `entry_form.dart:77`。

## 后端 / 配置 / 构建
- Supabase 连接：`lib/config/supabase_config.dart`（`url` `14`、`publishableKey` `19`，均 `String.fromEnvironment`，可 `--dart-define` 覆盖）。**仅放 publishable key，勿放 service_role。**
- 迁移：`supabase/migrations/0001_init.sql`、`0002_trip_companions.sql`（按序在 SQL Editor 跑）。
- 保活：`.github/workflows/keepalive.yml`（云端每日 ping）；`scripts/supabase_keepalive.ps1`（本地等效）。
- CI：`.github/workflows/ci.yml`（push/PR 跑 `flutter analyze` + `flutter test`）。
- 测试：`test/widget_test.dart`。
- 运行：见 README；预览/浏览器验证细节见项目记忆 `travel-log-dev-and-preview`。
