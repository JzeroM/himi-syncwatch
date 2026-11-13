# AGENTS.md

## 开发规范

1. 全程中文交流
2. 要求项目功能模块化设计，低耦合度，分布式开发
3. 每次完成一个功能或者修复完一个bug，务必编写相关测试并验证，交付用户之前，确保所有测试完整全部通过
4. 回答用户问题时，使用ask-question标签提问，不用plain text提问
5. 不要把安全隐私类文件传github,比如的github Api不要泄露，因为项目是公开库
6. 版本号各段（major/minor/patch）取值范围 0-99（如 1.2.0；不再出现 1.1.255 这类三位数补丁），构建号 `+N` 保持单调递增以保证 Android versionCode 可覆盖安装
7. 发布基础设施：`deps-mirror` release（存改名副本 `mdk-sdk-windows-x64.7z`）是 Windows 构建依赖，**严禁删除**；清理旧版本时只删 `v*` 标签/Release，勿动 `deps-mirror`
8. **发布说明写简短**：只列出**新增了哪些功能**；修复项一笔带过（统一写「修复一些已知问题」），不写根因分析和实现细节。**不按平台分章节**——相同功能/修复合并成一条，平台差异用括号注明（如「（安卓 TV）」）。`docs/release_notes_by_platform.md` 面向最终用户，不是技术报告

## 构建环境陷阱

### 鸿蒙 SDK 会串改依赖解析（必读）

`flutter_ohos` 的 `pub get` / `analyze` / `build` 会把
`.dart_tool/package_config.json` 里的 `flutter` 指向 `flutter_ohos`。
之后用 **stock Flutter** 跑 `flutter test` / `flutter analyze` 会报一堆：

```
The getter 'hasSelectedState' isn't defined for the type 'SemanticsFlags'
A value of type 'Tristate' can't be assigned to a variable of type 'bool'
```

**这不是代码坏了**，只是两套 SDK 的 `dart:ui` 不兼容。同理，鸿蒙 SDK
编译过的 `build/test_cache` 也会让 stock 测试报诡异编译错误。

**处理**：
- 手工用过鸿蒙 SDK 后，务必用 stock Flutter 重跑 `flutter pub get`
- `scripts/build_ohos_local.sh` 已内置 `trap`：构建结束（成功或失败）自动
  还原 `package_config.json` 并清 `build/test_cache`

### 鸿蒙本地构建所需工具链

`scripts/build_ohos_local.sh` 会自动探测，但需知道这些位置：

| 依赖 | 位置 | 缺失时的报错 |
|---|---|---|
| `npm` | `~/harmonyos-clt/tool/node/bin` | `ProcessException: Failed to find "npm"`（栈全是 flutter_tools 内部帧） |
| `java` | `~/.local/jdk-17.0.21+9-jre/bin` 或 DevEco JDK | `Error Code: 00308018 / spawn java ENOENT` |
| SDK 根 | `~/harmonyos-clt/sdk` | `ohos_pack.sh` 直接退出 |

`OHOS_BASE_SDK_HOME` 与 `DEVECO_SDK_HOME` 需**同时**设置。
