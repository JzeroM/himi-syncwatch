# MiSans（子集内嵌）

`fonts/MiSans-*.ttf` 为 **MiSans** 字体的子集文件（仅保留 GB2312 全集 +
拉丁 + 常用标点，共约 7500 字符；四个字重 Regular/Medium/Demibold/Bold），
自官方完整包子集化而来，用于全应用默认字体（698 N10-A）。

- 来源：小米科技 MiSans 官方发布 — https://hyperos.mi.com/font/
  （官方包 `MiSans.zip`；本仓库仅存子集，完整包请至官方页面下载）
- 版权：Copyright 小米科技（Xiaomi）
- 许可：**MiSans 知识产权许可协议**（官方页附）——允许任何个人与机构
  免费商用（含 App 内嵌）；**不得**直接售卖字体文件、不得将本字体作为
  商品单独转售或再分发。本仓库以「子集内嵌于开源应用」方式使用，符合
  该许可；字体文件本身不适用本仓库其余代码的许可条款，版权归小米科技。

## 子集化说明

- 工具：fonttools `pyftsubset`（`--layout-features=*` 保留 tnum 等排版特性）
- 字符集：GB2312 全集（6763 汉字 + 682 图形符号）+ ASCII + 常用额外标点
  （破折号/引号/省略号/℃/™/€ 等），见构建脚本 `charset.txt` 生成逻辑
- 生僻字不在子集内 → 由 `fontFamilyFallback` 回落系统字体（苹方 /
  HarmonyOS Sans / 微软雅黑 / Noto Sans SC），观感无感
