/// Anime4K 档位与着色器链组装（694 S1，纯函数可单测）。
///
/// 借鉴 NeoPlayer v1.7.4 的「模式 × 质量」语义（A/A+/B/B+/C/C+/ArtCNN ×
/// Fast/Balanced/High），**链的组装为本项目自写表**；着色器资产为
/// bloc97/Anime4K（MIT）与 Artoriuz/ArtCNN（MIT）vendor 原样，
/// 见 `third_party/anime4k/NOTICE.md`。
///
/// 链语义（mpv `glsl-shaders` 有序执行，超分在前、修复在后、钳制收尾）：
///
/// | 模式 | 链 |
/// |---|---|
/// | A  | AutoDownscalePre_x2 → Upscale_CNN_x2 → Restore_CNN |
/// | A+ | AutoDownscalePre_x2 → Upscale_CNN_x2 → Restore_CNN_Soft |
/// | B  | AutoDownscalePre_x2 → Upscale_Denoise_CNN_x2 → Restore_CNN |
/// | B+ | AutoDownscalePre_x2 → Upscale_Denoise_CNN_x2 → Restore_CNN_Soft |
/// | C  | A 的链 → Clamp_Highlights |
/// | C+ | B+ 的链 → Clamp_Highlights |
/// | ArtCNN | ArtCNN 端到端（Fast=C4F16，其余=C4F32） |
///
/// 质量档决定 CNN 尺寸后缀（Fast=S / Balanced=M / High=L）。
library;

/// Anime4K 模式（off = 关闭）。
enum Anime4KMode {
  off('off', '关闭', ''),
  a('a', 'A · 标准', '2x 超分 + 线条修复'),
  aPlus('a_plus', 'A+ · 标准柔和', '2x 超分 + 柔和修复（少锐化）'),
  b('b', 'B · 抗噪', '2x 超分 + 降噪 + 线条修复'),
  bPlus('b_plus', 'B+ · 抗噪柔和', '2x 超分 + 降噪 + 柔和修复'),
  c('c', 'C · 高画质', '抗噪链 + 高光钳制（更完整）'),
  cPlus('c_plus', 'C+ · 高画质柔和', '抗噪柔和链 + 高光钳制'),
  artCnn('artcnn', 'ArtCNN', 'ArtCNN 端到端超分（画质最好，耗电最高）');

  const Anime4KMode(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;

  static Anime4KMode fromId(String? id) => Anime4KMode.values.firstWhere(
        (m) => m.id == id,
        orElse: () => Anime4KMode.off,
      );
}

/// 质量档（决定 CNN 尺寸 S/M/L；ArtCNN 档映射 C4F16/C4F32）。
enum Anime4KQuality {
  fast('fast', '快速', 'S'),
  balanced('balanced', '均衡', 'M'),
  high('high', '高画质', 'L');

  const Anime4KQuality(this.id, this.label, this.sizeTag);

  final String id;
  final String label;
  final String sizeTag;

  static Anime4KQuality fromId(String? id) => Anime4KQuality.values.firstWhere(
        (q) => q.id == id,
        orElse: () => Anime4KQuality.balanced,
      );
}

/// 着色器链组装（文件名，见 `third_party/anime4k/glsl/`）。
class Anime4KShaderCatalog {
  Anime4KShaderCatalog._();

  /// 组装有序着色器链（off → 空）。
  static List<String> chain(Anime4KMode mode, Anime4KQuality quality) {
    if (mode == Anime4KMode.off) return const [];
    if (mode == Anime4KMode.artCnn) {
      return [
        quality == Anime4KQuality.fast
            ? 'ArtCNN_C4F16.glsl'
            : 'ArtCNN_C4F32.glsl',
      ];
    }
    final q = quality.sizeTag;
    final soft = mode == Anime4KMode.aPlus ||
        mode == Anime4KMode.bPlus ||
        mode == Anime4KMode.cPlus;
    // C+ = B+ 的链 + Clamp（B+ 含 Denoise），故 denoise 含 cPlus。
    final denoise = mode == Anime4KMode.b ||
        mode == Anime4KMode.bPlus ||
        mode == Anime4KMode.cPlus;
    final clamp = mode == Anime4KMode.c || mode == Anime4KMode.cPlus;

    final upscale = denoise
        ? 'Anime4K_Upscale_Denoise_CNN_x2_$q.glsl'
        : 'Anime4K_Upscale_CNN_x2_$q.glsl';
    final restore = soft
        ? 'Anime4K_Restore_CNN_Soft_$q.glsl'
        : 'Anime4K_Restore_CNN_$q.glsl';

    return [
      // 上游推荐：x2 超分链前置 AutoDownscale（显示端 <2x 时先降采样，
      // 不浪费 GPU 也避免过冲）。
      'Anime4K_AutoDownscalePre_x2.glsl',
      upscale,
      restore,
      if (clamp) 'Anime4K_Clamp_Highlights.glsl',
    ];
  }

  /// 链内全部着色器文件名（供资产完整性测试遍历）。
  static List<String> get allFileNames => [
        'Anime4K_AutoDownscalePre_x2.glsl',
        'Anime4K_Clamp_Highlights.glsl',
        for (final q in const ['S', 'M', 'L']) ...[
          'Anime4K_Upscale_CNN_x2_$q.glsl',
          'Anime4K_Upscale_Denoise_CNN_x2_$q.glsl',
          'Anime4K_Restore_CNN_$q.glsl',
          'Anime4K_Restore_CNN_Soft_$q.glsl',
        ],
        'ArtCNN_C4F16.glsl',
        'ArtCNN_C4F32.glsl',
      ];
}
