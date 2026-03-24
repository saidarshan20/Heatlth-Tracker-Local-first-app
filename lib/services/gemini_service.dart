// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiService {
  static GenerativeModel? _jsonModel;
  static GenerativeModel? _chatModel;
  static String _apiKey = '';

  static bool get _isOpenRouter => _apiKey.startsWith('sk-or-');

  static void init() {
    _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (_apiKey.isEmpty) return;

    if (!_isOpenRouter) {
      _jsonModel = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: _apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.1,
          responseMimeType: 'application/json',
        ),
      );

      _chatModel = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: _apiKey,
        generationConfig: GenerationConfig(temperature: 0.7),
      );
    }
  }

  static Future<String?> _generate(String prompt, {bool json = false, double temp = 0.7}) async {
    if (_apiKey.isEmpty) return null;

    if (_isOpenRouter) {
      try {
        final res = await http.post(
          Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'google/gemini-2.0-flash-001',
            'temperature': temp,
            if (json) 'response_format': {"type": "json_object"},
            'messages': [
              {'role': 'user', 'content': prompt}
            ]
          }),
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          return data['choices'][0]['message']['content'] as String?;
        }
        print('OpenRouter API error: ${res.statusCode} ${res.body}');
        return null;
      } catch (e) {
        print('OpenRouter Exception: $e');
        return null;
      }
    } else {
      try {
        final model = json ? _jsonModel : _chatModel;
        if (model == null) return null;
        final response = await model.generateContent([Content.text(prompt)]);
        return response.text;
      } catch (e) {
        print('Gemini SDK Exception: $e');
        return null;
      }
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
- For mixed meals, sum each component separately.
- Do NOT overestimate protein for vegetarian items.

Return ONLY this JSON (no markdown, no extra text):
{"item": "<name>", "calories": <int>, "protein": <int>, "carbs": <int>, "fats": <int>}''';

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
      print('Gemini food parse error: $e\\nRaw text: $text');
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
