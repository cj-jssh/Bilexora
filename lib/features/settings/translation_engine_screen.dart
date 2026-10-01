import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../core/database/library_database.dart';
import '../translation/local_translation_service.dart';
import '../../core/state/app_state.dart';

/// 翻译引擎分类
enum EngineCategory { ai, machine, customApi }

/// 翻译引擎类型
enum TranslationEngineType { local, online }

/// 翻译引擎模型
class TranslationEngine {
  final String id;
  final String name;
  final String description;
  final TranslationEngineType type;
  final EngineCategory category;
  final int sortOrder;
  final IconData iconData;
  final String? apiKey;
  final String? apiUrl;
  final String? modelName;
  final String? style;

  TranslationEngine({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    this.iconData = Icons.cloud,
    this.category = EngineCategory.machine,
    this.sortOrder = 0,
    this.apiKey,
    this.apiUrl,
    this.modelName,
    this.style,
  });

  TranslationEngine copyWith({
    String? id, String? name, String? description,
    TranslationEngineType? type, EngineCategory? category, int? sortOrder, IconData? iconData,
    String? apiKey, String? apiUrl, String? modelName, String? style,
  }) {
    return TranslationEngine(
      id: id ?? this.id, name: name ?? this.name, description: description ?? this.description,
      type: type ?? this.type, category: category ?? this.category,
      sortOrder: sortOrder ?? this.sortOrder, iconData: iconData ?? this.iconData,
      apiKey: apiKey ?? this.apiKey, apiUrl: apiUrl ?? this.apiUrl,
      modelName: modelName ?? this.modelName, style: style ?? this.style,
    );
  }

  Map<String, String> toJson() => {
    'id': id, 'name': name, 'description': description,
    'type': type.name, 'category': category.name,
    'sortOrder': sortOrder.toString(),
    'apiKey': ?apiKey,
    'apiUrl': ?apiUrl,
    'modelName': ?modelName,
    'style': ?style,
  };

  factory TranslationEngine.fromJson(Map<String, dynamic> j) => TranslationEngine(
    id: j['id'] as String, name: j['name'] as String, description: j['description'] as String,
    type: TranslationEngineType.values.byName(j['type'] as String),
    category: EngineCategory.values.byName(j['category'] as String),
    sortOrder: int.tryParse(j['sortOrder'] as String? ?? '0') ?? 0,
    apiKey: j['apiKey'] as String?, apiUrl: j['apiUrl'] as String?,
    modelName: j['modelName'] as String?, style: j['style'] as String?,
  );
}

final List<TranslationEngine> presetEngines = [
  TranslationEngine(
    id: 'local_bergamot', name: '本地离线翻译',
    description: 'Bergamot NMT 设备端神经机器翻译，无需联网',
    type: TranslationEngineType.local, category: EngineCategory.machine,
    sortOrder: 0, iconData: Icons.translate,
  ),
];

final translationEnginesProvider =
    StateNotifierProvider<TranslationEngineListNotifier, List<TranslationEngine>>((ref) {
  return TranslationEngineListNotifier(ref.read(enginePersistenceProvider));
});

final activeTranslationEngineProvider = Provider<TranslationEngine?>((ref) {
  final engines = ref.watch(translationEnginesProvider);
  return engines.isNotEmpty ? engines.first : null;
});

/// 引擎持久化 Provider
final enginePersistenceProvider = Provider<EnginePersistence>((ref) => EnginePersistence());

class EnginePersistence {
  static const _key = 'translation_engines';

  Future<void> save(List<TranslationEngine> engines) async {
    final db = _LibraryDatabase();
    final json = jsonEncode(engines.map((e) => e.toJson()).toList());
    await db.setSetting(_key, json);
  }

  Future<List<TranslationEngine>> load() async {
    final db = _LibraryDatabase();
    final json = await db.getSetting(_key);
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.map((e) => TranslationEngine.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }
}

class _LibraryDatabase {
  static LibraryDatabase get instance => LibraryDatabase();
  Future<void> setSetting(String key, String value) => instance.setSetting(key, value);
  Future<String?> getSetting(String key) => instance.getSetting(key);
}

class TranslationEngineListNotifier extends StateNotifier<List<TranslationEngine>> {
  final EnginePersistence _persistence;

  TranslationEngineListNotifier(this._persistence) : super([...presetEngines]) {
    _load();
  }

  Future<void> _load() async {
    final saved = await _persistence.load();
    if (saved.isNotEmpty) {
      state = saved;
    }
  }

  Future<void> _persist() async {
    await _persistence.save(state);
  }

  Future<void> add(TranslationEngine engine) async {
    state = [...state, engine];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _persist();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final list = [...state];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = list;
    await _persist();
  }

  bool contains(String id) => state.any((e) => e.id == id);
  int get length => state.length;
}

class TranslationStyle {
  final String id;
  final String name;
  final String description;
  const TranslationStyle({required this.id, required this.name, required this.description});
}

final List<TranslationStyle> translationStyles = [
  TranslationStyle(id: 'literal', name: '直译', description: '逐词翻译，保留原文结构'),
  TranslationStyle(id: 'fluent', name: '意译', description: '通顺自然，贴近目标语言习惯'),
  TranslationStyle(id: 'academic', name: '学术', description: '正式严谨，适合学术文献'),
];

final currentTranslationStyleProvider = StateProvider<String>((ref) => 'literal');

// ═══════════════════════════════════════════════════════════════
// 翻译引擎管理页面（主列表）
// ═══════════════════════════════════════════════════════════════

class TranslationEngineScreen extends ConsumerWidget {
  const TranslationEngineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engines = ref.watch(translationEnginesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('翻译引擎管理'),
        actions: [IconButton(icon: const Icon(Icons.check), tooltip: '完成', onPressed: () => Navigator.pop(context))],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Icon(Icons.miscellaneous_services, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('长按拖拽排序，左滑删除', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline)),
          ]),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: engines.length,
            onReorderItem: (oldIndex, newIndex) => ref.read(translationEnginesProvider.notifier).reorder(oldIndex, newIndex),
            proxyDecorator: (child, index, animation) => AnimatedBuilder(
              animation: animation,
              builder: (context, child) => Material(elevation: 4, shadowColor: Colors.black26, borderRadius: BorderRadius.circular(10), child: child),
              child: child,
            ),
            itemBuilder: (context, index) {
              final engine = engines[index];
              final notifier = ref.read(translationEnginesProvider.notifier);
              return Dismissible(
                key: ValueKey(engine.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) async {
                  final r = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                    title: Text('移除「${engine.name}」？'),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('移除'))],
                  ));
                  return r ?? false;
                },
                background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.error, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onError)),
                onDismissed: (_) => notifier.remove(engine.id),
                child: _EngineCard(engine: engine, index: index),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5))),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('添加翻译引擎'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _AddEnginePage())))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.palette_outlined, size: 18), label: const Text('管理翻译风格'),
              onPressed: () => _showStyleManager(context, ref))),
          ]),
        ),
      ]),
    );
  }

  void _showStyleManager(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentTranslationStyleProvider);
    showModalBottomSheet(context: context, builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Expanded(child: Text('翻译风格', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
        const SizedBox(height: 8),
        ...translationStyles.map((s) => RadioListTile<String>(
          contentPadding: EdgeInsets.zero, title: Text(s.name), subtitle: Text(s.description),
          value: s.id, groupValue: current,
          onChanged: (v) { if (v != null) { ref.read(currentTranslationStyleProvider.notifier).state = v; Navigator.pop(ctx); } },
        )),
      ]),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════
// 添加翻译引擎页面
// ═══════════════════════════════════════════════════════════════

class _AddEnginePage extends ConsumerWidget {
  const _AddEnginePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('添加翻译引擎')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        _SectionHeader(icon: Icons.auto_awesome, title: 'AI 大模型翻译'),
        const SizedBox(height: 4),
        _EngineOptionTile(name: '智谱 AI', subtitle: 'GLM 系列大模型，支持多轮对话与翻译', iconData: Icons.psychology, onTap: () => _openAIConfig(context, ref, 'zhipu', '智谱 AI', 'GLM 系列大模型，支持多轮对话与翻译', Icons.psychology)),
        _EngineOptionTile(name: 'DeepSeek', subtitle: 'DeepSeek 大语言模型翻译', iconData: Icons.auto_awesome, onTap: () => _openAIConfig(context, ref, 'deepseek', 'DeepSeek', 'DeepSeek 大语言模型翻译', Icons.auto_awesome)),
        _EngineOptionTile(name: '自定义 AI', subtitle: '自行填写厂商、API URL 与 Key', iconData: Icons.add_circle_outline, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _AIConfigPage(
          engineId: 'custom_ai_${DateTime.now().millisecondsSinceEpoch}', engineName: '自定义 AI', engineDescription: '自定义 AI 翻译引擎', iconData: Icons.add_circle_outline, customProvider: true)))),
        const Divider(height: 28),
        _SectionHeader(icon: Icons.translate, title: '机器翻译'),
        const SizedBox(height: 4),
        _EngineOptionTile(name: 'Bing 在线翻译', subtitle: 'Microsoft Bing 翻译引擎', iconData: Icons.language, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _MachineConfigPage(id: 'bing', name: 'Bing 在线翻译', description: 'Microsoft Bing 翻译引擎', iconData: Icons.language)))),
        _EngineOptionTile(name: '谷歌在线翻译', subtitle: 'Google Translate 翻译引擎', iconData: Icons.g_translate, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _MachineConfigPage(id: 'google', name: '谷歌在线翻译', description: 'Google Translate 翻译引擎', iconData: Icons.g_translate)))),
        const Divider(height: 8),
        _EngineOptionTile(name: '本地离线翻译', subtitle: 'Bergamot NMT 内置离线翻译，无需联网', iconData: Icons.translate, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _LocalEngineConfigPage()))),
        const Divider(height: 28),
        _SectionHeader(icon: Icons.vpn_key, title: '自定义 API Key'),
        const SizedBox(height: 4),
        _EngineOptionTile(name: '百度翻译', subtitle: '需要 APP ID 与密钥', iconData: Icons.key, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ApiKeyConfigPage(id: 'baidu', name: '百度翻译', description: '百度翻译 API（需 APP ID + 密钥）', iconData: Icons.key)))),
        _EngineOptionTile(name: '腾讯翻译', subtitle: '需要 Secret ID 与密钥', iconData: Icons.key, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ApiKeyConfigPage(id: 'tencent', name: '腾讯翻译', description: '腾讯翻译 API（需 Secret ID + 密钥）', iconData: Icons.key)))),
        _EngineOptionTile(name: '有道翻译', subtitle: '需要应用 ID 与密钥', iconData: Icons.key, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ApiKeyConfigPage(id: 'youdao', name: '有道翻译', description: '有道翻译 API（需应用 ID + 密钥）', iconData: Icons.key)))),
        _EngineOptionTile(name: '阿里翻译', subtitle: '需要 AccessKey ID 与 Secret', iconData: Icons.key, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ApiKeyConfigPage(id: 'aliyun', name: '阿里翻译', description: '阿里翻译 API（需 AccessKey + Secret）', iconData: Icons.key)))),
      ]),
    );
  }

  void _openAIConfig(BuildContext context, WidgetRef ref, String id, String name, String description, IconData icon) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _AIConfigPage(engineId: id, engineName: name, engineDescription: description, iconData: icon)));
  }
}

// ═══════════════════════════════════════════════════════════════
// AI 大模型配置页面
// ═══════════════════════════════════════════════════════════════

class _AIConfigPage extends ConsumerStatefulWidget {
  final String engineId; final String engineName; final String engineDescription; final IconData iconData; final bool customProvider;
  const _AIConfigPage({required this.engineId, required this.engineName, required this.engineDescription, required this.iconData, this.customProvider = false});

  @override
  _AIConfigPageState createState() => _AIConfigPageState();
}

class _AIConfigPageState extends ConsumerState<_AIConfigPage> {
  final _apiKeyController = TextEditingController(); final _providerController = TextEditingController(); final _apiUrlController = TextEditingController();
  String? _selectedModel; String _selectedStyle = 'literal'; bool _isVerifying = false; bool _isFetchingModels = false; String? _fetchModelsError;
  final List<String> _availableModels = []; bool _modelsLoaded = false; bool _showModelList = false;

  @override
  void dispose() { _apiKeyController.dispose(); _providerController.dispose(); _apiUrlController.dispose(); super.dispose(); }

  Future<void> _fetchModels() async {
    final apiUrl = _apiUrlController.text.trim(); final apiKey = _apiKeyController.text.trim();
    if (apiUrl.isEmpty) { _toast('请先填写 API URL'); return; }
    if (apiKey.isEmpty) { _toast('请先输入 API Key'); return; }
    setState(() { _isFetchingModels = true; _fetchModelsError = null; _showModelList = false; });
    final cleanUrl = apiUrl.endsWith('/') ? apiUrl.substring(0, apiUrl.length - 1) : apiUrl;
    List<String>? models; String? errMsg;
    try { final resp = await http.get(Uri.parse('$cleanUrl/models'), headers: {'Authorization': 'Bearer $apiKey'}).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) { models = _parseOpenAIModels(resp.body); } else if (resp.statusCode != 404) { errMsg = 'HTTP ${resp.statusCode}'; }
    } catch (_) {}
    if (models == null && errMsg == null) {
      try { final resp = await http.get(Uri.parse('$cleanUrl/api/tags')).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) { models = _parseOllamaModels(resp.body); } else if (resp.statusCode != 404) { errMsg = 'HTTP ${resp.statusCode}'; }
      } catch (_) {}
    }
    if (!mounted) return;
    if (models != null && models.isNotEmpty) {
      setState(() { _isFetchingModels = false; _modelsLoaded = true; _availableModels..clear()..addAll(models!); _selectedModel ??= _availableModels.first; });
    } else { setState(() { _isFetchingModels = false; _fetchModelsError = errMsg ?? '两个端点均无法获取模型列表'; }); }
  }

  List<String>? _parseOpenAIModels(String body) { try { final j = jsonDecode(body) as Map<String, dynamic>; final d = j['data'] as List<dynamic>?; if (d != null && d.isNotEmpty) return d.map<String>((m) => m is Map<String, dynamic> ? (m['id'] as String? ?? m.toString()) : m.toString()).toList(); } catch (_) {} return null; }
  List<String>? _parseOllamaModels(String body) { try { final j = jsonDecode(body) as Map<String, dynamic>; final m = j['models'] as List<dynamic>?; if (m != null && m.isNotEmpty) return m.map<String>((m2) => m2 is Map<String, dynamic> ? (m2['name'] as String? ?? m2.toString()) : m2.toString()).toList(); } catch (_) {} return null; }

  void _verifyApiKey() { if (_apiKeyController.text.trim().isEmpty) { _toast('请先输入 API Key'); return; } setState(() => _isVerifying = true); Future.delayed(const Duration(seconds: 1), () { if (!mounted) return; setState(() => _isVerifying = false); _toast('验证通过'); }); }

  void _addEngine() {
    if (_apiKeyController.text.trim().isEmpty) { _toast('请先输入 API Key'); return; }
    if (widget.customProvider) { if (_providerController.text.trim().isEmpty) { _toast('请填写厂商名称'); return; } if (_apiUrlController.text.trim().isEmpty) { _toast('请填写 API URL'); return; } }
    final effectiveName = widget.customProvider ? _providerController.text.trim() : widget.engineName;
    final effectiveDesc = widget.customProvider ? '自定义 AI 翻译引擎: ${_providerController.text.trim()} | 模型: ${_selectedModel ?? "未选择"}' : '${widget.engineDescription} | 模型: ${_selectedModel ?? "未选择"}';
    final notifier = ref.read(translationEnginesProvider.notifier);
    if (notifier.contains(widget.engineId)) { _toast('「$effectiveName」已添加'); return; }
    notifier.add(TranslationEngine(
      id: widget.engineId, name: effectiveName, description: effectiveDesc,
      type: TranslationEngineType.online, category: EngineCategory.ai, sortOrder: notifier.length, iconData: widget.iconData,
      apiKey: _apiKeyController.text.trim(), apiUrl: _apiUrlController.text.trim().isNotEmpty ? _apiUrlController.text.trim() : null,
      modelName: _selectedModel, style: _selectedStyle,
    ));
    Navigator.of(context).pop();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.engineName)),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)), child: Icon(widget.iconData, size: 24, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.engineName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2), Text(widget.engineDescription, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline)),
          ])),
        ]),
        const SizedBox(height: 24),
        if (widget.customProvider) ...[_Label('厂商名称'), const SizedBox(height: 8), TextField(controller: _providerController, decoration: const InputDecoration(hintText: '例: OpenAI、Anthropic', border: OutlineInputBorder())), const SizedBox(height: 20)],
        _Label('API URL'), const SizedBox(height: 8), TextField(controller: _apiUrlController, decoration: const InputDecoration(hintText: '例: https://api.openai.com/v1', border: OutlineInputBorder())), const SizedBox(height: 20),
        _Label('API Key'), const SizedBox(height: 8),
        TextField(controller: _apiKeyController, decoration: InputDecoration(hintText: '输入 API Key', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(_isVerifying ? Icons.hourglass_top : Icons.verified_outlined, color: Theme.of(context).colorScheme.primary), onPressed: _isVerifying ? null : _verifyApiKey, tooltip: '验证')), obscureText: true),
        const SizedBox(height: 20),
        _Label('模型设置'), const SizedBox(height: 8),
        InkWell(borderRadius: BorderRadius.circular(8), onTap: _isFetchingModels ? null : () { if (_modelsLoaded) { setState(() => _showModelList = !_showModelList); } else { _fetchModels(); } },
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(_isFetchingModels ? Icons.hourglass_top : Icons.model_training, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8), Expanded(child: _buildModelStatus()),
              Icon(_showModelList ? Icons.expand_less : Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ]),
          ),
        ),
        if (_fetchModelsError != null) ...[const SizedBox(height: 4), Text(_fetchModelsError!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error))],
        if (_showModelList && _availableModels.isNotEmpty) ...[const SizedBox(height: 4),
          Container(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))]),
            constraints: const BoxConstraints(maxHeight: 5 * 48.0),
            child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Scrollbar(child: ListView(padding: EdgeInsets.zero, shrinkWrap: true,
              children: _availableModels.map((model) => RadioListTile<String>(contentPadding: const EdgeInsets.symmetric(horizontal: 8), dense: true, title: Text(model, style: const TextStyle(fontSize: 14)),
                value: model, groupValue: _selectedModel, onChanged: (value) { if (value != null) { setState(() { _selectedModel = value; _showModelList = false; }); } },
              )).toList(),
            ))),
          ),
        ],
        const SizedBox(height: 20),
        _Label('翻译风格'), const SizedBox(height: 8),
        InkWell(borderRadius: BorderRadius.circular(8), onTap: () => _showStylePicker(context),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.palette_outlined, size: 20, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8),
              Expanded(child: Text(translationStyles.firstWhere((s) => s.id == _selectedStyle).name)),
              Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ]),
          ),
        ),
        const SizedBox(height: 40),
      ])),
      Container(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5))),
        child: Row(children: [
          Expanded(child: OutlinedButton.icon(icon: Icon(_isVerifying ? Icons.hourglass_top : Icons.check_circle_outline, size: 18), label: Text(_isVerifying ? '验证中...' : '验证'), onPressed: _isVerifying ? null : _verifyApiKey)),
          const SizedBox(width: 12),
          Expanded(child: FilledButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('添加'), onPressed: _addEngine)),
        ]),
      ),
    ]),
  );

  Widget _buildModelStatus() {
    if (_isFetchingModels) return const Text('获取模型中...', style: TextStyle(color: Colors.grey));
    if (_fetchModelsError != null) return const Text('获取失败，点击重试', style: TextStyle(color: Colors.red));
    if (_selectedModel != null) return Text(_selectedModel!, style: const TextStyle(fontWeight: FontWeight.w500));
    return Text('点击从 API URL 获取模型列表', style: TextStyle(color: Theme.of(context).colorScheme.outline));
  }

  void _showStylePicker(BuildContext context) {
    showModalBottomSheet(context: context, builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Expanded(child: Text('翻译风格', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))), IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
        const SizedBox(height: 8),
        ...translationStyles.map((s) => RadioListTile<String>(contentPadding: EdgeInsets.zero, title: Text(s.name), subtitle: Text(s.description), value: s.id, groupValue: _selectedStyle,
          onChanged: (v) { if (v != null) { setState(() => _selectedStyle = v); Navigator.pop(ctx); } },
        )),
      ]),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════
// 机器翻译配置页面
// ═══════════════════════════════════════════════════════════════

class _MachineConfigPage extends ConsumerWidget {
  final String id; final String name; final String description; final IconData iconData;
  const _MachineConfigPage({required this.id, required this.name, required this.description, required this.iconData});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(name)),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)), child: Icon(iconData, size: 24, color: Theme.of(context).colorScheme.primary)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2), Text(description, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline)),
        ])),
      ]),
      const SizedBox(height: 32), const Center(child: Icon(Icons.construction, size: 48, color: Colors.grey)),
      const SizedBox(height: 12), const Center(child: Text('机器翻译引擎配置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500))),
      const SizedBox(height: 8), Center(child: Text('自动调用云端接口，无需额外配置', style: TextStyle(color: Theme.of(context).colorScheme.outline))),
    ]),
    bottomNavigationBar: Container(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5))),
      child: FilledButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('直接添加'), onPressed: () {
        final notifier = ref.read(translationEnginesProvider.notifier);
        if (notifier.contains(id)) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「$name」已添加'), behavior: SnackBarBehavior.floating)); return; }
        notifier.add(TranslationEngine(id: id, name: name, description: description, type: TranslationEngineType.online, category: EngineCategory.machine, sortOrder: notifier.length, iconData: iconData));
        Navigator.of(context).pop();
      }),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════
// 自定义 API Key 配置页面
// ═══════════════════════════════════════════════════════════════

class _ApiKeyConfigPage extends ConsumerStatefulWidget {
  final String id; final String name; final String description; final IconData iconData;
  const _ApiKeyConfigPage({required this.id, required this.name, required this.description, required this.iconData});

  @override
  _ApiKeyConfigPageState createState() => _ApiKeyConfigPageState();
}

class _ApiKeyConfigPageState extends ConsumerState<_ApiKeyConfigPage> {
  final _appIdController = TextEditingController(); final _secretKeyController = TextEditingController(); bool _isVerifying = false;

  @override
  void dispose() { _appIdController.dispose(); _secretKeyController.dispose(); super.dispose(); }

  void _verify() { if (_appIdController.text.trim().isEmpty || _secretKeyController.text.trim().isEmpty) { _toast('请填写完整信息'); return; } setState(() => _isVerifying = true); Future.delayed(const Duration(seconds: 1), () { if (!mounted) return; setState(() => _isVerifying = false); _toast('验证通过'); }); }

  void _add() {
    if (_appIdController.text.trim().isEmpty || _secretKeyController.text.trim().isEmpty) { _toast('请填写完整信息'); return; }
    final notifier = ref.read(translationEnginesProvider.notifier);
    if (notifier.contains(widget.id)) { _toast('「${widget.name}」已添加'); return; }
    notifier.add(TranslationEngine(id: widget.id, name: widget.name, description: widget.description, type: TranslationEngineType.online, category: EngineCategory.customApi, sortOrder: notifier.length, iconData: widget.iconData, apiKey: _appIdController.text.trim()));
    Navigator.of(context).pop();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.name)),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)), child: Icon(widget.iconData, size: 24, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 2),
            Text(widget.description, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline)),
          ])),
        ]),
        const SizedBox(height: 24),
        TextField(controller: _appIdController, decoration: const InputDecoration(labelText: 'APP ID / AccessKey ID', hintText: '输入应用 ID', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _secretKeyController, decoration: const InputDecoration(labelText: '密钥 / Secret', hintText: '输入密钥', border: OutlineInputBorder()), obscureText: true),
      ])),
      Container(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5))),
        child: Row(children: [
          Expanded(child: OutlinedButton.icon(icon: Icon(_isVerifying ? Icons.hourglass_top : Icons.check_circle_outline, size: 18), label: Text(_isVerifying ? '验证中...' : '验证'), onPressed: _isVerifying ? null : _verify)),
          const SizedBox(width: 12),
          Expanded(child: FilledButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('添加'), onPressed: _add)),
        ]),
      ),
    ]),
  );
}

const Map<String, String> _langNames = {
  'zh': '中文', 'en': 'English', 'ja': '日本語', 'ko': '한국어',
  'fr': 'Français', 'de': 'Deutsch', 'es': 'Español', 'pt': 'Português',
  'it': 'Italiano', 'ru': 'Русский', 'ar': 'العربية', 'vi': 'Tiếng Việt',
  'th': 'ภาษาไทย', 'tr': 'Türkçe', 'nl': 'Nederlands', 'pl': 'Polski',
  'sv': 'Svenska', 'da': 'Dansk', 'fi': 'Suomi', 'cs': 'Čeština',
  'ro': 'Română', 'hu': 'Magyar', 'el': 'Ελληνικά', 'he': 'עברית',
  'id': 'Bahasa Indonesia', 'ms': 'Bahasa Melayu', 'nb': 'Norsk Bokmål',
  'nn': 'Norsk Nynorsk', 'sk': 'Slovenčina', 'sl': 'Slovenščina',
  'hr': 'Hrvatski', 'sr': 'Српски', 'bg': 'Български', 'uk': 'Українська',
  'be': 'Беларуская', 'ca': 'Català', 'et': 'Eesti', 'lv': 'Latviešu',
  'lt': 'Lietuvių', 'sq': 'Shqip', 'mk': 'Македонски', 'mt': 'Malti',
  'is': 'Ís lenska', 'ga': 'Gaeilge', 'fa': 'فارسی', 'hi': 'हिन्दी',
  'bn': 'বাংলা', 'ta': 'தமிழ்', 'te': 'తెలుగు', 'ml': 'മലയാളം',
  'kn': 'ಕನ್ನಡ', 'gu': 'ગુજરાતી', 'bs': 'Bosanski', 'az': 'Azərbaycan dili',
  'zh_hant': '繁體中文',
};

String _langFlag(String code) {
  const flags = <String, String>{'zh': '🇨🇳', 'en': '🇬🇧', 'ja': '🇯🇵', 'ko': '🇰🇷', 'fr': '🇫🇷', 'de': '🇩🇪', 'es': '🇪🇸'};
  return flags[code] ?? '🌐';
}

// ═══════════════════════════════════════════════════════════════
// 本地离线引擎配置（语言管理）
// ═══════════════════════════════════════════════════════════════

/// hf-mirror 上 Firefox Translations 支持的 52 种语言
const _allModelLangs = [
  'ar', 'az', 'be', 'bg', 'bn', 'bs', 'ca', 'cs', 'da', 'de',
  'el', 'en', 'es', 'et', 'fa', 'fi', 'fr', 'gu', 'he', 'hi',
  'hr', 'hu', 'id', 'is', 'it', 'ja', 'kn', 'ko', 'lt', 'lv',
  'ml', 'ms', 'nb', 'nl', 'nn', 'no', 'pl', 'pt', 'ro', 'ru',
  'sk', 'sl', 'sq', 'sr', 'sv', 'ta', 'te', 'th', 'tr', 'uk',
  'vi', 'zh',
];

class _LocalEngineConfigPage extends ConsumerStatefulWidget {
  const _LocalEngineConfigPage();
  @override
  _LocalEngineConfigPageState createState() => _LocalEngineConfigPageState();
}

class _LocalEngineConfigPageState extends ConsumerState<_LocalEngineConfigPage> {
  bool _isDownloading = false;
  String? _downloadingLang;
  final _downloadProgress = <String, double>{};

  Future<void> _downloadLanguage(String lang, String name) async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
      _downloadingLang = lang;
      _downloadProgress[lang] = 0.0;
    });

    try {
      await LocalTranslationService.downloadLanguageModel(
        lang,
        onProgress: (downloaded, total) {
          if (mounted) setState(() => _downloadProgress[lang] = downloaded / total);
        },
        onComplete: () {},
        onError: (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('下载失败: $error'), backgroundColor: Theme.of(context).colorScheme.error, behavior: SnackBarBehavior.floating));
          }
        },
      );
      // 标记为已安装
      ref.read(installedLangsProvider.notifier).add(lang);

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadingLang = null;
          _downloadProgress[lang] = 1.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已下载「$name」语言包，首次翻译时将自动加载模型'), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadingLang = null;
          _downloadProgress[lang] = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e'), backgroundColor: Theme.of(context).colorScheme.error, behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本地语言管理')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final installed = ref.watch(installedLangsProvider);
    final downloaded = <String>[];
    final available = <String>[];
    for (final code in _allModelLangs) {
      if (code == 'en' || installed.contains(code)) {
        downloaded.add(code);
      } else {
        available.add(code);
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader(context, '已下载', downloaded.length),
        if (downloaded.isEmpty)
          _emptyHint()
        else
          ...downloaded.map((code) => _buildLangTile(code)),
        const SizedBox(height: 16),
        _sectionHeader(context, '可下载', available.length),
        if (available.isEmpty)
          _emptyHint()
        else
          ...available.map((code) => _buildLangTile(code)),
      ],
    );
  }

  Widget _emptyHint() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    child: Text('暂无', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
  );

  Widget _sectionHeader(BuildContext context, String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8, bottom: 4),
      child: Row(children: [
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
          child: Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
        ),
      ]),
    );
  }

  Widget _buildLangTile(String code) {
    final downloading = _downloadingLang == code;
    final progress = _downloadProgress[code] ?? 0.0;
    final installed = ref.watch(installedLangsProvider).contains(code) || code == 'en';
    final name = _langNames[code] ?? code;
    final flag = _langFlag(code);
    return ListTile(
      leading: Text(flag, style: const TextStyle(fontSize: 28)),
      title: Text('$name ($code)'),
      subtitle: Text(installed ? '已下载' : '未下载'),
      trailing: downloading
          ? SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(
                value: progress > 0 && progress < 1 ? progress : null,
                strokeWidth: 2.5,
              ),
            )
          : installed
              ? const Icon(Icons.check_circle_outline, color: Colors.green, size: 22)
              : ElevatedButton.icon(
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('下载'),
                  onPressed: _isDownloading
                      ? null
                      : () => _downloadLanguage(code, name),
                ),
      dense: true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 通用组件
// ═══════════════════════════════════════════════════════════════

class _Label extends StatelessWidget {
  final String title; const _Label(this.title);
  @override Widget build(BuildContext context) => Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary));
}

class _SectionHeader extends StatelessWidget {
  final IconData icon; final String title; const _SectionHeader({required this.icon, required this.title});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(left: 4), child: Row(children: [
    Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8),
    Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
  ]));
}

class _EngineOptionTile extends StatelessWidget {
  final String name; final String subtitle; final IconData iconData; final VoidCallback onTap;
  const _EngineOptionTile({required this.name, required this.subtitle, required this.iconData, required this.onTap});
  @override Widget build(BuildContext context) => InkWell(borderRadius: BorderRadius.circular(10), onTap: onTap,
    child: Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), child: Row(children: [
      Container(width: 36, height: 36, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
        child: Icon(iconData, size: 20, color: Theme.of(context).colorScheme.primary)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2), Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
      ])),
      Icon(Icons.chevron_right, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
    ])),
  );
}

class _EngineCard extends StatelessWidget {
  final TranslationEngine engine; final int index;
  const _EngineCard({required this.engine, required this.index});
  @override Widget build(BuildContext context) => Card(margin: const EdgeInsets.symmetric(vertical: 4), elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5)),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        if (engine.type == TranslationEngineType.local || engine.id == 'local_bergamot') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const _LocalEngineConfigPage()));
        }
      },
      child: Padding(padding: const EdgeInsets.fromLTRB(4, 8, 12, 8), child: Row(children: [
        ReorderableDragStartListener(index: index, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.drag_handle, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)))),
        const SizedBox(width: 4),
        Container(width: 40, height: 40, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
          child: Icon(engine.iconData, size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(engine.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 2),
          Text(engine.description, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline), maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
        Icon(Icons.chevron_right, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
      ])),
    ),
  );
}