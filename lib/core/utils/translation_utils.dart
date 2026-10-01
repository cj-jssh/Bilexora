import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../features/settings/translation_engine_screen.dart';

/// 估算文本的 token 数量
int estimateTokens(String text) {
  int ascii = 0, cjk = 0;
  for (final c in text.runes) {
    if (c >= 0x4E00 && c <= 0x9FFF) {
      cjk++;
    } else if (c < 128) {
      ascii++;
    }
  }
  return (ascii ~/ 4) + cjk + (text.length - ascii - cjk);
}

/// 将翻译异常转为人可读的错误消息
String translateErrorMessage(Object error) {
  if (error is TimeoutException) return '请求超时，服务器未在 60 秒内响应';
  if (error is SocketException) {
    return '网络连接失败，请检查网络设置 (${error.message})';
  }
  if (error is http.ClientException) return 'HTTP 请求失败: ${error.message}';
  final msg = error.toString();
  if (msg.contains('401') || msg.contains('Unauthorized')) {
    return 'API Key 无效或未授权';
  }
  if (msg.contains('402')) return 'API 额度不足 (402 Payment Required)';
  if (msg.contains('429')) return '请求过于频繁，请稍后重试 (429 Too Many Requests)';
  if (msg.contains('500')) return 'AI 服务器内部错误 (500)，请稍后重试';
  if (msg.contains('502') || msg.contains('503')) {
    return 'AI 服务暂时不可用，请稍后重试';
  }
  if (msg.contains('API key')) return 'API Key 配置有误，请在翻译引擎设置中检查';
  if (msg.contains('Incorrect API key')) return 'API Key 不正确，请检查后重试';
  if (msg.contains('model') && msg.contains('found')) {
    return '模型 "${msg.split('"').where((s) => s.contains('-')).firstOrNull ?? ''}" 不存在，请重新选择';
  }
  return msg.length > 120 ? '${msg.substring(0, 120)}...' : msg;
}

/// 使用 AI 引擎翻译（支持批处理与重试）
Future<List<({int globalIndex, String text})>> translateWithAI({
  required TranslationEngine engine,
  required List<({int globalIndex, String text})> sentences,
  required String sourceLanguage,
  required String targetLanguage,
  void Function(int processed, int total)? onProgress,
}) async {
  final baseUrl = engine.apiUrl!.endsWith('/')
      ? engine.apiUrl!.substring(0, engine.apiUrl!.length - 1)
      : engine.apiUrl!;
  final chatUrl = baseUrl.contains('/chat/completions')
      ? baseUrl
      : '$baseUrl/chat/completions';
  final modelName = engine.modelName ?? 'gpt-3.5-turbo';
  final results = <({int globalIndex, String text})>[];

  const maxBatchTokens = 5000;
  int processedCount = 0;
  final totalCount = sentences.length;

  int i = 0;
  while (i < sentences.length) {
    int batchTokens = 0;
    int j = i;
    while (j < sentences.length) {
      batchTokens += estimateTokens(sentences[j].text) + 1;
      j++;
      if (batchTokens > maxBatchTokens) break;
    }
    final batch = sentences.sublist(i, j);
    final texts = batch.map((s) => s.text).join('\n<<<>>>\n');

    // Retry loop: up to 3 attempts with exponential backoff
    List<String>? lines;
    int attempt = 0;
    const maxAttempts = 3;
    String? lastError;
    while (attempt < maxAttempts) {
      attempt++;
      try {
        final resp = await http.post(
          Uri.parse(chatUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${engine.apiKey}'
          },
          body: jsonEncode({
            'model': modelName,
            'messages': [
              {
                'role': 'system',
                'content':
                    'Translate each segment in order from $sourceLanguage to $targetLanguage. Segments are separated by "<<<>>>". Only output translations, one per line.'
              },
              {'role': 'user', 'content': texts},
            ],
            'temperature': 0.1
          }),
        ).timeout(const Duration(seconds: 60));

        if (resp.statusCode != 200) {
          lastError = 'HTTP ${resp.statusCode}: ${resp.body}';
          if (resp.statusCode == 401 ||
              resp.statusCode == 402 ||
              resp.statusCode == 403) {
            break; // Don't retry auth/forbidden errors
          }
          continue;
        }

        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final translated =
            body['choices']?[0]?['message']?['content'] as String? ?? '';
        if (translated.isEmpty) {
          lastError = 'AI 返回空结果';
          continue;
        }
        lines = translated
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        break; // Success
      } catch (e) {
        lastError = e.toString();
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
        }
      }
    }

    if (lines == null) {
      throw Exception(translateErrorMessage(lastError ?? '未知错误'));
    }

    for (int k = 0; k < batch.length && k < lines.length; k++) {
      results.add((globalIndex: batch[k].globalIndex, text: lines[k]));
    }
    processedCount += batch.length;
    onProgress?.call(processedCount, totalCount);
    i = j;
  }
  return results;
}