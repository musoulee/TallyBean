# TallyBean

TallyBean 是一个面向 beancount 账本的 Flutter 移动端工程，采用 `Melos` 维护多 package 仓库，并通过 Rust + Flutter Rust Bridge 实现账本解析与投影。

最后更新：2026-04-19

## 项目定位

- 仓库类型：`Flutter + Melos` Monorepo
- 当前主线：本地工作区导入、账本解析、总览/明细/账户/统计浏览
- 目标读者：参与此仓库协作的开发者
- 开发文档入口：[`docs/development.md`](docs/development.md)

## 当前状态

- 可用链路：导入本地 beancount 工作区、解析账本、浏览核心页面、查看文本视图
- 保留能力：`useDemoData` 与 demo repository 仍用于测试/演示支撑
- 未完成部分：`compose_transaction` 仍是结构骨架，设置页“高级工具”当前仅保留 `周期记账` 占位入口
- 集成测试现状：`integration_test/app_smoke_test.dart` 目前只覆盖应用启动并落到工作区流程的冒烟验证

## 技术栈基线

| 类别 | 组件 |
| --- | --- |
| UI / App | Flutter `3.41.6`, Dart `3.11.4` |
| 状态管理 | `flutter_riverpod`, `riverpod_annotation` |
| 路由 | `go_router` |
| Monorepo | `melos` |
| 原生解析 | Rust `1.92.0` |
| 桥接 | `flutter_rust_bridge 2.11.1` |

版本依据分别来自根 `pubspec.yaml`、`melos.yaml`、`packages/beancount_bridge/pubspec.yaml` 与 `packages/beancount_bridge/rust/rust-toolchain.toml`。

## 3 分钟启动

在仓库根目录执行：

```bash
# 1) 安装依赖
flutter pub get

# 2) 全仓静态检查
flutter pub run melos run analyze

# 3) 全仓测试
flutter pub run melos run test

# 4) 运行应用
flutter run
```

如果本机 `flutter` 不在 PATH，可改用绝对路径，例如 `~/devtools/flutter/bin/flutter pub get`。

## 常用命令

```bash
# 全仓静态检查
flutter pub run melos run analyze

# 全仓测试
flutter pub run melos run test

# 主工程测试
flutter test

# 集成测试（当前为启动冒烟）
flutter test integration_test

# 运行指定 package 的测试示例
cd packages/beancount_bridge && flutter test
```

`melos run` 当前只定义了 `analyze` 和 `test` 两个脚本，详细说明见 [`docs/development.md`](docs/development.md)。

## 仓库结构

```text
.
├── lib/                    # App 主工程：壳层、features、共享 UI
│   ├── app/
│   ├── features/
│   └── shared/
├── packages/               # 本地 package 集合
│   ├── beancount_domain/   # 领域模型与仓储抽象
│   ├── beancount_data/     # 仓储实现与 DTO -> Domain 映射
│   ├── workspace_io/       # 工作区导入、文件读取、状态持久化
│   ├── beancount_bridge/   # Rust 解析器与 Dart facade
│   └── tally_design_system/# 主题与共享组件
├── test/                   # 主工程单元 / widget 测试
├── integration_test/       # 应用级冒烟测试
├── android/ ios/ macos/ linux/ web/ windows/
├── melos.yaml              # workspace 与脚本编排
└── pubspec.yaml            # 主 app 依赖与本地 path 包接入
```

如果你是第一次进仓库，建议先读 [`docs/development.md`](docs/development.md) 里的“日常开发流程”和“Monorepo 边界”两节。

## 开发时最常碰到的入口

- App 启动：`lib/main.dart`
- 壳层与路由：`lib/app/`
- 业务页面：`lib/features/`
- 本地 package 入口：`packages/*/lib/*.dart`
- Rust 解析器：`packages/beancount_bridge/rust/src/`
- 集成测试：`integration_test/app_smoke_test.dart`

## 延伸阅读

- 开发指引：[`docs/development.md`](docs/development.md)
- 集成测试说明：[`integration_test/README.md`](integration_test/README.md)
