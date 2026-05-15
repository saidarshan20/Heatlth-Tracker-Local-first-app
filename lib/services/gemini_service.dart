// ignore_for_file: avoid_print
//
// AI service — class name kept as `GeminiService` so existing call sites
// don't churn, but text now routes ONLY through Cerebras `gpt-oss-120b`.
// Gemini is still used for vision (image_food_service.dart) but is no
// longer a text fallback (its free tier was unreliable and the quota errors
// were noisy).
//
// .env keys:
//   CEREBRAS_API_KEY=csk-...
//   GEMINI_API_KEY=AIza...   (Google native key, used only for image parsing)
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiService {
  static String _cerebrasKey = '';

  static const _cerebrasUrl = 'https://api.cerebras.ai/v1/chat/completions';
  // Cerebras model. Llama 3.3 70B isn't available on this tier — `gpt-oss-120b`
  // is the closest in capability and is blazingly fast (~10ms total on this key).
  // Other ids available: 'qwen-3-235b-a22b-instruct-2507', 'zai-glm-4.7', 'llama3.1-8b'.
  static const _cerebrasModel = 'gpt-oss-120b';

  static void init() {
    _cerebrasKey = dotenv.env['CEREBRAS_API_KEY'] ?? '';
  }

  /// Routes a text prompt to Cerebras. Returns null on failure. Gemini is no
  /// longer used as a text fallback — its free tier is unreliable, and the
  /// noisy quota errors confused things. Image parsing still uses Gemini.
  static Future<String?> _generate(String prompt, {bool json = false, double temp = 0.7}) async {
    if (_cerebrasKey.isEmpty) {
      print('CEREBRAS_API_KEY missing — text AI is disabled');
      return null;
    }
    return await _callCerebras(prompt, json: json, temp: temp);
  }

  static Future<String?> _callCerebras(String prompt, {required bool json, required double temp}) async {
    try {
      final res = await http.post(
        Uri.parse(_cerebrasUrl),
        headers: {
          'Authorization': 'Bearer $_cerebrasKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _cerebrasModel,
          'temperature': temp,
          if (json) 'response_format': {'type': 'json_object'},
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['choices'][0]['message']['content'] as String?;
      }
      print('Cerebras API error: ${res.statusCode} ${res.body}');
      return null;
    } catch (e) {
      print('Cerebras exception: $e');
      return null;
    }
  }

  /// Parse food description → returns {item, calories, protein, carbs, fats}
  static Future<Map<String, dynamic>?> parseFood(String description) async {
    final prompt = '''You are a nutrition calculator for Indian food.
User ate: "$description"

Rules:
- Standard Indian serving sizes if quantity not given: Roti=80kcal/piece, Rice=150g cooked/katori, Dal=150ml/katori, Sabzi=150g/katori, Milk=200ml/glass, Egg=50g each
- Odia food refs: Pakhala 60kcal/100g, Dalma 120kcal/katori, Chakuli pitha 120kcal/piece, Chungdi malai 180kcal/katori
- Common: Roti 80kcal, Paratha 175kcal, Puri 130kcal, Chapati 70kcal
- Use COOKED weights. Assume 1 tsp oil/ghee per dish if not specified.
- IMPORTANT: If multiple items are mentioned (with +, comma, "and", or "with"), calculate ALL items and return their COMBINED total. Never ignore any item.
- Do NOT overestimate protein for vegetarian items.

Example: "3 idli + 1 katori dal" → {"item":"3 Idli + Dal","calories":360,"protein":12,"carbs":65,"fats":4}
Example: "2 roti and sabzi" → {"item":"2 Roti + Sabzi","calories":310,"protein":9,"carbs":52,"fats":8}

Return ONLY this single JSON object with the COMBINED total of ALL mentioned items (no markdown):
{"item":"<combined name>","calories":<int>,"protein":<int>,"carbs":<int>,"fats":<int>}''';

    final text = await _generate(prompt, json: true, temp: 0.1);
    if (text == null) return null;

    try {
      final cleanText = text.replaceAll('```json', '').replaceAll('```', '').trim();
      final decoded = jsonDecode(cleanText);
      if (decoded is List && decoded.isNotEmpty) {
        return decoded.first as Map<String, dynamic>;
      }
      return decoded as Map<String, dynamic>;
    } catch (e) {
      print('Food parse error: $e\nRaw text: $text');
      return null;
    }
  }

  /// Get meal suggestions
  static Future<String?> getMealSuggestions(String request) async {
    final prompt = '''Suggest 3 meal options for: "$request".
User lives in a village in Odisha, India.
Use simple, locally available ingredients only. No fancy/imported items.
Include estimated cal, protein, carbs, fats for each option.
Format as a numbered list with emojis. Keep it brief and practical.
Suggest things that can be made at home easily.''';

    return await _generate(prompt, temp: 0.7);
  }

  /// Get smart protein tip based on today's context
  static Future<String?> getProteinTip(List<String> todayFoods, int protRemaining, int calRemaining, String mealPeriod) async {
    final prompt = '''User has eaten: ${todayFoods.join(', ')}.
Remaining: ${protRemaining}g protein within $calRemaining kcal budget.
Time: $mealPeriod. They live in a village in Odisha, India.
Suggest 2-3 specific, simple, high-protein foods they can eat right now.
Include approx protein per serving. Keep it to 2-3 lines, friendly, with emojis.''';

    return await _generate(prompt, temp: 0.7);
  }

  /// Weekly insights
  static Future<String?> getWeeklyInsights(Map<String, dynamic> stats) async {
    final prompt = '''Weekly nutrition data (7 days):
- Avg Calories: ${stats['avgCal']}/1800 kcal
- Avg Protein: ${stats['avgProt']}/120g
- Avg Water: ${stats['avgWater']}/3000ml

Write a 4-5 line weekly review. Mention trends, best/worst days.
Give one specific actionable goal for next week. Be friendly with emojis.''';

    return await _generate(prompt, temp: 0.7);
  }
}
