# 第三方组件：EvolveUI

- **来源**: https://github.com/sudoevolve/EvolveUI
- **上游 commit**: `11f904c`（2026-11 取样）
- **许可证**: MIT（见 `LICENSE`）

## 挪用清单

| 本地路径 | 上游路径 | 改动 |
|---|---|---|
| `src/qml/evolveui/ETheme.qml` | `components/ETheme.qml` | **未修改** |
| `src/qml/evolveui/EButton.qml` | `components/EButton.qml` | **未修改** |
| `src/qml/evolveui/ESlider.qml` | `components/ESlider.qml` | **未修改** |
| `src/qml/evolveui/ECard.qml` | `components/ECard.qml` | **未修改** |
| `src/qml/evolveui/ELoader.qml` | `components/ELoader.qml` | **未修改** |
| `assets/fonts/loader.gif` | `fonts/loader.gif` | **未修改** |
| `assets/fonts/fontawesome-free-6.7.2-desktop/otfs/*` | `fonts/fontawesome-free-6.7.2-desktop/otfs/*` | **未修改**（FontAwesome 6 Free，OFL 许可见同目录 `LICENSE.txt`） |

## 集成约定（为什么不改源码也能用）

1. **主题/图标字体按上游约定用「上下文链」注入**：组件内未声明的
   `theme`（ETheme 实例）与 `iconFont`（FontLoader）由 `Main.qml` 根级
   `id` 提供——与上游 `Main.qml` 的用法完全一致。QML 未限定名会沿
   实例化上下文链向上解析，故组件零修改即可复用。
2. **资源路径与上游一致**：组件内硬编码的
   `qrc:/new/prefix1/fonts/...`（FontAwesome / loader.gif）通过 CMake
   `qt_add_resources(PREFIX "/new/prefix1")` 原样注册，组件零修改。
   `ETheme.backgroundImage` 指向的示例图片未挪用（播放器窗口不需要，
   属性仅在未使用时保持悬空 URL）。
3. **EButton 尺寸档位不改源码的用法**：`implicitHeight/Width` 在实例上
   覆盖、`size` 档位只取其字号（xs/s/m/l/xl = 12/16/20/24/32），
   见 `src/qml/ControlButton.qml` 的封装。

## 未挪用部分

上游 `components/` 其余组件（含 `EMusicPlayer`/`EPlaylist`/`MusicWindow`
等依赖 C++ `AudioMetadata`/`MusicLibrary` 的音乐组件）、`pages/` 演示页、
`core/` C++ 代码、`scaffold/`/`tools/` 脚手架均未引入。

## 升级方法

```sh
git clone https://github.com/sudoevolve/EvolveUI /tmp/EvolveUI
cd /tmp/EvolveUI && git checkout <new-commit>
# 用 components/ 下同名文件覆盖 src/qml/evolveui/，fonts/ 覆盖 assets/fonts/
# 核对本文件的「未修改」结论仍成立（diff 一下）
```
