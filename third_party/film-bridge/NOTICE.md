# film-bridge（移植署名）

`lib/services/bridge_parsers.dart` 中的标题归一化（normalizeTitle）、bigram
Dice 相似度（titleSimilarity）、JSON-LD 评分抽取（aggregateRating）与豆瓣
subject 候选抽取算法，移植自：

- **Film Bridge · 影评桥** — https://github.com/niall133/film-bridge
- 版本：v1.0.12（以移植时点为准）
- 版权：Copyright (c) 2025 niall133
- 许可：MIT License（见同目录 LICENSE）

移植说明：JavaScript 改写为 Dart，保留算法语义；适配 Flutter 侧无浏览器
DOM 的 HTTP HTML 解析场景（JSON-LD 抽取不依赖 DOM）。本项目其余代码许可
见仓库根 README，与 MIT 兼容。
