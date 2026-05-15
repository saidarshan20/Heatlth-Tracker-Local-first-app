// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';

/// Vision-based food parser. Mirrors [`GeminiService.parseFood`] but accepts
/// a photo of the food instead of a text description. Returns the same JSON
/// shape — `{item, calories, protein, carbs, fats}` — so the downstream
/// confirm/log UI stays identical.
///
/// Vision is Gemini-only (Cerebras llama-3.3 doesn't accept images). Text
/// parsing uses Cerebras with a Gemini fallback — see `gemini_service.dart`.
class ImageFoodService {
  static final ImagePicker _picker = ImagePicker();

  static String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  /// Last failure reason from `parseFoodFromImage` — read by the UI to show
  /// a specific snackbar instead of the generic "couldn't read the photo".
  /// Reset to null at the start of every call. Possible values:
  ///   "missing_key"    — GEMINI_API_KEY empty (.env not loaded? rotate key?)
  ///   "quota"          — Google free-tier limit reached
  ///   "network"        — request never reached Gemini
  ///   "parse"          — Gemini replied but the JSON was malformed
  ///   `unknown:<msg>` — anything else
  static String? lastError;

  // ── Capture / pick ──────────────────────────────────────────────────────

  /// Opens the device camera. Returns null if the user cancels.
  static Future<XFile?> captureFromCamera() async {
    return await _picker.pickImage(
      source: ImageSource.camera,
      // ImagePicker's own light compression — final compression happens below
      // so we stay readable even when the device returns a multi-MB file.
      imageQuality: 92,
    );
  }

  /// Opens the gallery. Returns null if the user cancels.
  static Future<XFile?> pickFromGallery() async {
    return await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
  }

  /// Reduce file size to keep upload fast without hurting recognition. Target
  /// ~200–400 KB with the longest edge capped at 1280 px; the food should
  /// still be clearly visible in the thumbnail preview.
  static Future<Uint8List> compress(XFile file) async {
    final bytes = await file.readAsBytes();
    final compressed = await FlutterImageCompress.compressWithList(
      bytes,
      quality: 85,
      minWidth: 1280,
      minHeight: 1280,
      format: CompressFormat.jpeg,
    );
    return compressed;
  }

  // ── Vision parse ────────────────────────────────────────────────────────

  static const _prompt = '''You are a nutrition calculator analyzing a photo of food.

Look at the image and identify ALL food items visible on the plate/bowl/container. The user lives in Odisha, India — expect Indian + Odia dishes (roti, rice, dal, sabzi, pakhala, dalma, chakuli pitha, chungdi malai, idli, paratha, puri, etc.) alongside common foods.

Rules:
- Estimate portion sizes from visual cues (plate size, utensils, hands).
- Standard servings if unsure: Roti=80kcal/piece, Rice=150g cooked/katori, Dal=150ml/katori, Sabzi=150g/katori, Milk=200ml/glass, Egg=50g each.
- Use COOKED weights. Assume 1 tsp oil/ghee per dish unless visibly dry.
- Sum ALL visible items into one combined total. Never ignore an item.
- Do NOT overestimate protein for vegetarian dishes.
- If a user hint is provided, trust it for quantities or items that are ambiguous in the photo.

Return ONLY this single JSON object with the COMBINED total (no markdown):
{"item":"<combined name>","calories":<int>,"protein":<int>,"carbs":<int>,"fats":<int>}''';

  /// Send a (compressed) image to Gemini vision and parse the JSON response.
  /// [hint] is an optional text note from the user ("3 rotis not 2") that
  /// gets appended to the prompt.
  static Future<Map<String, dynamic>?> parseFoodFromImage(
    Uint8List imageBytes, {
    String? hint,
  }) async {
    lastError = null;
    if (_apiKey.isEmpty) {
      lastError = 'missing_key';
      print('Image parse: GEMINI_API_KEY is empty — did .env load?');
      return null;
    }
    print('Image parse starting — gemini key=${_apiKey.length} chars, image=${imageBytes.length} bytes');
    final fullPrompt = (hint != null && hint.trim().isNotEmpty)
        ? '$_prompt\n\nUser hint: ${hint.trim()}'
        : _prompt;

    final raw = await _generateGemini(fullPrompt, imageBytes);
    if (raw == null) return null;

    try {
      final clean = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final decoded = jsonDecode(clean);
      if (decoded is List && decoded.isNotEmpty) {
        return decoded.first as Map<String, dynamic>;
      }
      return decoded as Map<String, dynamic>;
    } catch (e) {
      lastError = 'parse';
      print('Image food parse error: $e\nRaw text: $raw');
      return null;
    }
  }

  static Future<String?> _generateGemini(String prompt, Uint8List bytes) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: _apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.1,
          responseMimeType: 'application/json',
        ),
      );
      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', bytes),
        ]),
      ]);
      return response.text;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('quota') || msg.contains('exceeded') || msg.contains('limit')) {
        lastError = 'quota';
      } else if (msg.contains('SocketException') || msg.contains('Network') || msg.contains('Failed host lookup')) {
        lastError = 'network';
      } else {
        lastError = 'unknown:${msg.substring(0, msg.length > 120 ? 120 : msg.length)}';
      }
      print('Gemini vision exception ($lastError): $e');
      return null;
    }
  }
}
