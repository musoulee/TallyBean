# TallyBean 开发指引

本文件面向仓库协作者，目标是让你在第一次进入项目时就知道：

- 需要准备哪些环境
- 第一次启动和验证怎么跑
- 改 feature 或 package 时该从哪里下手
- Rust / FRB 相关文件哪些能改、哪些是生成物

## 1. 环境基线

当前仓库的开发基线如下：

| 类别 | 基线 |
| --- | --- |
| Flutter | `3.41.6` |
| Dart | `3.11.4` |
| Rust | `1.92.0` |
| Monorepo 管理 | `melos` |

代码依据：

- Flutter / Dart：本地 `flutter --version`
- Rust：`packages/beancount_bridge/rust/rust-toolchain.toml`
- Melos：根 `pubspec.yaml`

建议本机先确认：

```bash
flutter --version
rustc --version
```

如果你的 `flutter` 不在 PATH，可直接使用绝对路径，例如：

```bash
~/devtools/flutter/bin/flutter --version
```

## 2. 首次启动

在仓库根目录执行：

```bash
# 安装根工程依赖与 Melos
flutter pub get

# 全仓静态检查
flutter pub run melos run analyze

# 全仓测试
flutter pub run melos run test

# 运行应用
flutter run
```

### 集成测试

当前 `integration_test/` 只包含一个启动冒烟用例：

```bash
flutter test integration_test
```

它会验证应用启动后落到“工作区”流程，而不是完整 Android 交互回归。

## 3. 日常开发流程

推荐顺序：

1. 在根目录执行 `flutter pub get`
2. 修改目标 feature 或 package
3. 先跑受影响范围的测试
4. 再跑全仓 `analyze`
5. 最后跑全仓 `test`

### 改 App Feature 时

优先从 `lib/features/<feature>/` 入手：

- `application/`：Riverpod providers、状态编排
- `presentation/`：页面与 widgets

常见还会联动：

- `lib/app/router/`：新增或调整路由
- `lib/shared/`：共享格式化器、异步状态 UI、门禁组件
- `test/`：主工程 widget / feature 测试

### 改 Package 时

先确认修改属于哪个边界：

| 位置 | 负责内容 |
| --- | --- |
| `packages/beancount_domain` | 领域模型、仓储抽象 |
| `packages/beancount_data` | 仓储实现、bridge DTO 到 domain 映射 |
| `packages/workspace_io` | 工作区导入、文件读取、状态持久化 |
| `packages/beancount_bridge` | Rust 解析器、FRB 桥接、bridge facade |
| `packages/tally_design_system` | 主题与共享组件 |

修改 package 后，建议至少跑该包测试，再回到根目录跑全仓验证。

## 4. 验证命令

### 仓库级

```bash
flutter pub run melos run analyze
flutter pub run melos run test
flutter test
flutter test integration_test
```

### 单包验证示例

```bash
cd packages/beancount_domain && dart test
cd packages/workspace_io && flutter test
cd packages/beancount_bridge && flutter test
```

`melos.yaml` 当前只定义了两个脚本：

- `analyze`
- `test`

不要在 README 或其他文档里引用仓库中不存在的 `melos run lint`、`melos bootstrap` 等命令。

## 5. Monorepo 边界

### `lib/` 做什么

`lib/` 是 app 壳层与业务页面：

- `lib/app`：启动、DI、路由、壳层、主题适配
- `lib/features`：按业务域组织页面与 provider
- `lib/shared`：跨 feature 共享的小组件和格式化工具

### `packages/` 做什么

`packages/` 是可独立验证的本地 package 集合。原则上：

- 领域模型与仓储抽象下沉到 `beancount_domain`
- 数据接入与桥接映射放到 `beancount_data`
- 工作区文件和状态管理放到 `workspace_io`
- Rust 解析与 FRB 桥接放到 `beancount_bridge`
- 视觉规范与通用组件放到 `tally_design_system`

如果某段逻辑未来可能被 app 壳层之外复用，优先考虑下沉到 package，而不是继续堆在 `lib/`。

## 6. Rust / FRB 维护入口

### 关键文件

- FRB 配置：`packages/beancount_bridge/flutter_rust_bridge.yaml`
- Rust crate：`packages/beancount_bridge/rust/`
- Dart facade：`packages/beancount_bridge/lib/`

常碰入口：

- Rust API 入口：`packages/beancount_bridge/rust/src/api/mod.rs`
- Rust 解析器：`packages/beancount_bridge/rust/src/ledger/`
- 新引擎实现：`packages/beancount_bridge/rust/src/engine/`
- Dart 运行时包装：`packages/beancount_bridge/lib/src/native/rust_ledger_runtime.dart`

### 生成物约定

以下内容是生成物或本地构建产物，不应手工维护：

- `build/`
- `.dart_tool/`
- `packages/beancount_bridge/**/Flutter/ephemeral/`
- `packages/beancount_bridge/rust/target/`
- FRB 生成文件：`frb_generated*.dart`、`src/frb_generated.rs`

如果这些文件重新出现在 Git 跟踪列表中，优先视为仓库卫生问题，而不是业务改动。

## 7. 常见问题

### 为什么有些页面会直接显示工作区门禁提示？

除 `workspace` 页面外，大部分页面都会先读取 `currentWorkspaceProvider`。当没有当前工作区，或工作区处于 `issuesFirst` 状态时，页面会优先显示 `WorkspaceGateView`。

### 为什么报表或校验结果有时是空的？

`validateWorkspace` 与报表查询依赖已解析的工作区会话。如果没有先经过 `parseWorkspace`，相关结果可能为空或仍停留在旧缓存上。

### `useDemoData` / `DemoBeancountRepository` 还能删吗？

这轮仓库维护不删除。它们仍被测试和 demo 场景使用。

### 集成测试现在覆盖到什么程度？

当前只有 `integration_test/app_smoke_test.dart`，目标是验证应用能启动并进入工作区流程，不等同于完整端到端覆盖。
