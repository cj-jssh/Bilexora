/// 应用常量
class AppConstants {
  AppConstants._();

  /// 应用名称
  static const String appName = 'Bilexora';

  /// 内容数据文件版本
  static const int contentDatVersion = 1;

  /// Content.dat 魔数
  static const String contentDatMagic = 'BILXDATA\n';

  /// 最大缓存章节数
  static const int maxCachedChapters = 10;

  /// 预加载窗口大小
  static const int preloadWindow = 2;

  /// 阅读进度保存延迟（毫秒）
  static const int progressSaveDelay = 500;

  /// 默认翻译 Layer ID
  static const int defaultTranslationLayerId = 1;
  static const String defaultTranslationLayerName = 'Machine Translation';
  static const String defaultTranslationProvider = 'machine';
}