# 旅行日志 (TravelLog)

把地点、旅途故事、照片、随笔、画汇总到一个应用里的跨端旅行日志（iOS / Android /
Windows / Web，一套 Flutter 代码）。后端用 **Supabase**（登录 + Postgres + 存储），
支持多设备同步。

## 主要功能

- **地图** — 记录以**水滴形标记**展示（白色=无图，绿色=有图），同一旅途的记录按时间
  连线；缩小时折叠成「旅途」聚合，点击展开；放大到街道级后点空白处即可就地新增记录。
- **旅途** — 卡片列表，可重命名 / 编辑（同行人和时间）/ 删除；点进去看该旅途的记录。
- **浏览** — 按类型筛选，或按同行人浏览（看和每个人一起去过的地方，可增/改名/删同行人）。
- **新增记录** — 类型、照片/画上传、随笔、时间、位置；50 公里内自动归到最近的旅途。

## 运行

需要 [Flutter SDK](https://docs.flutter.dev/get-started/install)。

```bash
flutter pub get
flutter run -d chrome        # 网页
# flutter run -d windows     # Windows 桌面
# flutter run                # 连接的真机 / 模拟器
```

## 后端（Supabase）

连接配置在 `lib/config/supabase_config.dart`，也可在构建时覆盖：

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
```

> 配置里的是 **publishable（客户端）密钥**——设计上就可以随应用分发，数据安全完全由
> 行级安全策略（RLS）保证。**切勿把 `service_role` 密钥放进本仓库。**

数据库表结构在 `supabase/migrations/`，新项目按顺序在 Supabase SQL Editor 里跑这些 SQL。

免费版项目闲置约 7 天会暂停。仓库里的 `.github/workflows/keepalive.yml` 会在云端
**每天自动 ping 一次**保活（不依赖任何机器开机）；`scripts/supabase_keepalive.ps1`
是等效的本地脚本，需要时可手动运行。

## 持续集成

`.github/workflows/ci.yml`：每次 push / PR 自动跑 `flutter analyze` + `flutter test`。

## 目录结构

```
lib/
├── config/       Supabase 连接配置
├── data/         仓库接口 + Supabase / mock 实现
├── models/       Trip、Entry、Person 等数据模型
├── screens/      地图、旅途、浏览、新增表单等页面
├── state/        AppState（ChangeNotifier）
└── widgets/      复用组件
supabase/migrations/   数据库表结构
```
