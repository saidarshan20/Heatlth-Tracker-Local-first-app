// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'gemini_service.dart';

/// Vision-based food parser. Step 1: OpenRouter vision identifies food items.
/// Step 2: GeminiService.parseFood() (Cerebras) calculates macros. Returns
/// {item, calories, protein, carbs, fats} — same shape as the text path so
/// the confirm/log UI stays identical.
class ImageFoodService {
  static final ImagePicker _picker = ImagePicker();

  static String get _apiKey => dotenv.env['OPENROUTER_API_KEY'] ?? '';
  static String get _groqKey => dotenv.env['GROQ_API_KEY'] ?? '';

  static const _openRouterUrl = 'https://openrouter.ai/api/v1/chat/completions';
  static const _groqUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const _groqVisionModel = 'llama-3.2-90b-vision-preview';
  static const _visionModels = [
    // OpenRouter filters this router by required request features, including
    // image understanding. It is more stable than pinning one free endpoint.
    'openrouter/free',
    'google/gemma-4-31b-it:free',
    'meta-llama/llama-4-scout:free',
    'qwen/qwen-2.5-vl-7b-instruct:free',
  ];

  /// Last failure reason — read by the UI to show a specific snackbar.
  /// Reset to null at the start of every call. Possible values:
  ///   "missing_key"  — OPENROUTER_API_KEY empty (.env not loaded? rotate key?)
  ///   "quota"        — 429 after retry
  ///   "network"      — request timed out or no connection
  ///   "parse"        — vision replied but JSON was malformed / empty
  ///   "invalid_model"— OpenRouter rejected the configured model id
  ///   "unavailable"  — configured model/router has no active endpoint
  ///   `unknown:<msg>`— anything else
  static String? lastError;

  // ── Capture / pick ──────────────────────────────────────────────────────

  static Future<XFile?> captureFromCamera() async {
    return await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
    );
  }

  static Future<XFile?> pickFromGallery() async {
    return await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
  }

  /// Compress to ~200 KB with the longest edge capped at 1024 px.
  static Future<Uint8List> compress(XFile file) async {
    final bytes = await file.readAsBytes();
    final compressed = await FlutterImageCompress.compressWithList(
      bytes,
      quality: 75,
      minWidth: 1024,
      minHeight: 1024,
      format: CompressFormat.jpeg,
    );
    return compressed;
  }

  // ── Vision parse ────────────────────────────────────────────────────────

  static const _visionPrompt =
      'Identify all food items visible in the image. '
      'Return ONLY a JSON array of item names, nothing else. '
      'Example: ["roti","dal","rice"]. No explanation. No markdown.';

  /// Two-step parse: OpenRouter vision identifies items → Cerebras calculates macros.
  /// [hint] is an optional quantity/context note from the user ("3 rotis not 2")
  /// passed to Cerebras for accurate macro calculation.
  static Future<Map<String, dynamic>?> parseFoodFromImage(
    Uint8List imageBytes, {
    String? hint,
  }) async {
    lastError = null;

    if (_apiKey.isEmpty) {
      lastError = 'missing_key';
      print('Image parse: OPENROUTER_API_KEY is empty — did .env load?');
      return null;
    }

    print('Image parse starting — image=${imageBytes.length} bytes');

    // Step 1: identify food items via OpenRouter vision, fallback to Groq
    var items = await _callOpenRouter(imageBytes);
    if (items == null || items.isEmpty) {
      if (_groqKey.isNotEmpty) {
        print('OpenRouter failed, falling back to Groq Vision');
        items = await _callGroqVision(imageBytes);
      }
    }
    if (items == null || items.isEmpty) return null;

    print('Vision identified: $items');

    // Step 2: get macros from Cerebras (reuse existing service). User text is
    // treated as a correction/addition so tapping Analyze again recalculates
    // the full meal, not just the newly typed part.
    var description = 'Photo detected: ${items.join(', ')}.';
    if (hint != null && hint.trim().isNotEmpty) {
      description += ' User correction/additional items: ${hint.trim()}.';
    }

    final result = await GeminiService.parseFood(description);
    if (result == null) {
      // GeminiService sets no lastError, so set a generic one if not already set
      lastError ??= 'parse';
    }
    return result;
  }

  /// Call OpenRouter vision models and return a list of identified food items.
  /// Retries once per model on 429 / 5xx. Returns null and sets [lastError] on
  /// failure.
  static Future<List<String>?> _callOpenRouter(Uint8List bytes) async {
    final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';

    for (final model in _visionModels) {
      final body = jsonEncode({
        'model': model,
        'temperature': 0,
        'max_tokens': 100,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': _visionPrompt},
              {
                'type': 'image_url',
                'image_url': {'url': base64Image},
              },
            ],
          },
        ],
      });

      for (int attempt = 0; attempt < 2; attempt++) {
        if (attempt > 0) await Future.delayed(const Duration(seconds: 2));

        try {
          final res = await http
              .post(
                Uri.parse(_openRouterUrl),
                headers: {
                  'Authorization': 'Bearer $_apiKey',
                  'Content-Type': 'application/json',
                },
                body: body,
              )
              .timeout(const Duration(seconds: 15));

          if (res.statusCode == 429) {
            print('OpenRouter 429 for $model on attempt ${attempt + 1}');
            if (attempt == 1) lastError = 'quota';
            continue;
          }

          if (res.statusCode >= 500) {
            print(
              'OpenRouter ${res.statusCode} for $model on attempt ${attempt + 1}',
            );
            continue;
          }

          if (res.statusCode != 200) {
            if (res.statusCode == 400 &&
                res.body.contains('not a valid model ID')) {
              lastError = 'invalid_model';
              print('OpenRouter model id is invalid: $model');
              break;
            }

            if (res.statusCode == 404 &&
                res.body.contains('No endpoints found')) {
              lastError = 'unavailable';
              print('OpenRouter model has no endpoint: $model');
              break;
            }

            lastError =
                'unknown:${res.statusCode} ${res.body.substring(0, res.body.length > 120 ? 120 : res.body.length)}';
            print('OpenRouter error for $model: ${res.statusCode} ${res.body}');
            return null;
          }

          final data = jsonDecode(res.body);
          final content = _extractContent(data);
          if (content == null || content.trim().isEmpty) {
            lastError = 'parse';
            print('OpenRouter returned empty content for $model');
            break;
          }

          print('OpenRouter vision model used: $model');
          final items = _parseItemList(content);
          if (items != null && items.isNotEmpty) return items;
          print('OpenRouter returned unparseable content for $model: $content');
          break;
        } on TimeoutException {
          print('OpenRouter timeout for $model on attempt ${attempt + 1}');
          if (attempt == 1) lastError = 'network';
        } catch (e) {
          final msg = e.toString();
          if (msg.contains('SocketException') ||
              msg.contains('Failed host lookup') ||
              msg.contains('Network')) {
            lastError = 'network';
          } else {
            lastError =
                'unknown:${msg.substring(0, msg.length > 120 ? 120 : msg.length)}';
          }
          print('OpenRouter exception for $model ($lastError): $e');
          return null;
        }
      }
    }

    return null;
  }

  static Future<List<String>?> _callGroqVision(Uint8List bytes) async {
    final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    
    final body = jsonEncode({
      'model': _groqVisionModel,
      'temperature': 0,
      'max_tokens': 100,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': _visionPrompt},
            {
              'type': 'image_url',
              'image_url': {'url': base64Image},
            },
          ],
        },
      ],
    });

    try {
      final res = await http.post(
        Uri.parse(_groqUrl),
        headers: {
          'Authorization': 'Bearer $_groqKey',
          'Content-Type': 'application/json',
        },
        body: body,
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final content = _extractContent(data);
        if (content != null && content.trim().isNotEmpty) {
          return _parseItemList(content);
        }
      }
      
      print('Groq Vision error: ${res.statusCode} ${res.body}');
      return null;
    } catch (e) {
      print('Groq Vision exception: $e');
      return null;
    }
  }

  static String? _extractContent(dynamic data) {
    final content = data['choices']?[0]?['message']?['content'];
    if (content is String) return content;
    if (content is List) {
      final parts = content
          .whereType<Map>()
          .map((part) => part['text'])
          .whereType<String>()
          .where((text) => text.trim().isNotEmpty)
          .toList();
      if (parts.isNotEmpty) return parts.join('\n');
    }
    return null;
  }

  /// Parse the vision model's response into a clean list of item strings.
  /// Handles markdown fences and falls back gracefully on bad JSON.
  static List<String>? _parseItemList(String raw) {
    try {
      final clean = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final decoded = jsonDecode(clean);
      if (decoded is List && decoded.isNotEmpty) {
        final items = decoded
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toList();
        if (items.isNotEmpty) return items;
      }
      lastError = 'parse';
      print('Vision parse: unexpected shape — $raw');
      return null;
    } catch (e) {
      lastError = 'parse';
      print('Vision JSON parse error: $e\nRaw: $raw');
      return null;
    }
  }
}
