import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

class DashboardProvider extends ChangeNotifier {
  // Goals — loaded from DB, these are the defaults
  static int calGoal = 1800;
  static int protGoal = 120;
  static int carbGoal = 200;
  static int fatGoal = 60;
  static int waterGoal = 3000;

  static bool _goalsLoaded = false;

  /// Loads goals from the database. Call once at startup.
  static Future<void> loadGoals() async {
    calGoal = await DatabaseService.getSettingInt('cal_goal', 1800);
    protGoal = await DatabaseService.getSettingInt('prot_goal', 120);
    carbGoal = await DatabaseService.getSettingInt('carb_goal', 200);
    fatGoal = await DatabaseService.getSettingInt('fat_goal', 60);
    waterGoal = await DatabaseService.getSettingInt('water_goal', 3000);
    _goalsLoaded = true;
  }

  int totalCal = 0, totalProt = 0, totalCarb = 0, totalFat = 0;
  int totalWater = 0;
  int softDrinkWater = 0;
  List<Map<String, dynamic>> foodEntries = [];
  List<Map<String, dynamic>> medicines = [];
  List<int> takenMedIds = [];
  List<Map<String, dynamic>> commonMeals = [];
  List<Map<String, dynamic>> pinnedMeals = [];
  List<Map<String, dynamic>> waterEntries = [];
  List<Map<String, dynamic>> medicineLogsToday = [];
  int medStreak = 0;

  // Pinned drink
  String pinnedDrink = '';    // e.g. 'coke_zero', 'coke', 'thumbs_up', 'diet_coke', 'other', or '' (none)
  int pinnedDrinkMl = 250;
  String? pinnedDrinkName;    // only used when pinnedDrink == 'other'

  String get today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  String get greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get dateLabel => DateFormat('EEEE, d MMMM').format(DateTime.now());

  Future<void> refresh() async {
    if (!_goalsLoaded) await loadGoals();

    final totals = await DatabaseService.getFoodTotals(today);
    totalCal = totals['cal']!;
    totalProt = totals['p']!;
    totalCarb = totals['c']!;
    totalFat = totals['f']!;

    totalWater = await DatabaseService.getWaterTotal(today);
    softDrinkWater = await DatabaseService.getSoftDrinkWater(today);
    foodEntries = await DatabaseService.getFoodForDate(today);
    medicines = await DatabaseService.getMedicines();
    takenMedIds = await DatabaseService.getTakenMedicineIds(today);
    commonMeals = await DatabaseService.getCommonMeals();
    pinnedMeals = await DatabaseService.getPinnedMeals();
    waterEntries = await DatabaseService.getWaterForDate(today);
    medicineLogsToday = await DatabaseService.getMedicineLogsForDate(today);
    medStreak = await DatabaseService.getMedicineStreak();

    pinnedDrink = await DatabaseService.getSetting('pinned_drink') ?? '';
    pinnedDrinkMl = await DatabaseService.getSettingInt('pinned_drink_ml', 250);
    pinnedDrinkName = await DatabaseService.getSetting('pinned_drink_name');

    notifyListeners();
  }

  Future<void> addWater(int ml) async {
    await DatabaseService.addWater(today, ml);
    await NotificationService.evaluateWaterPace();
    await refresh();
  }

  Future<void> deleteWater(int id) async {
    await DatabaseService.deleteWater(id);
    await refresh();
  }

  Future<void> addThumbsUp() async {
    await DatabaseService.addWater(today, 250, type: 'soft_drink', drinkName: 'thumbs_up');
    await DatabaseService.addFood(today, 'Thumbs Up 250ml', 110, 0, 28, 0);
    await refresh();
  }

  // Hardcoded nutrition per 100ml for known drinks
  static const _drinkNutrition = {
    'thumbs_up': {'kcal': 44.0, 'carbs': 11.0, 'protein': 0.0, 'fat': 0.0},
    'coke':      {'kcal': 42.0, 'carbs': 10.6, 'protein': 0.0, 'fat': 0.0},
    'coke_zero': {'kcal': 0.3,  'carbs': 0.0,  'protein': 0.0, 'fat': 0.0},
    'diet_coke': {'kcal': 0.3,  'carbs': 0.1,  'protein': 0.1, 'fat': 0.0},
  };

  static String drinkDisplayName(String key, {String? otherName}) {
    switch (key) {
      case 'thumbs_up': return 'Thumbs Up';
      case 'coke':      return 'Coke';
      case 'coke_zero': return 'Coke Zero';
      case 'diet_coke': return 'Diet Coke';
      case 'other':     return otherName ?? 'Other';
      default:          return 'Water';
    }
  }

  static String drinkEmoji(String key) {
    switch (key) {
      case 'thumbs_up': return '🥤';
      case 'coke':      return '🥤';
      case 'coke_zero': return '🫙';
      case 'diet_coke': return '🥤';
      case 'other':     return '🧃';
      default:          return '💧';
    }
  }

  /// Logs a drink entry. For known drinks, calculates nutrition from hardcoded table.
  /// For 'other', caller must supply [overrideKcal] and [overrideCarbs].
  Future<void> addDrinkEntry(int ml, String drinkKey, {
    String? otherName,
    int? overrideKcal,
    int? overrideCarbs,
    int? overrideProtein,
    int? overrideFat,
  }) async {
    await DatabaseService.addWater(today, ml, type: 'soft_drink',
        drinkName: drinkKey == 'other' ? (otherName ?? 'other') : drinkKey);

    int kcal, carbs, protein, fat;
    if (drinkKey == 'other') {
      kcal    = overrideKcal    ?? 0;
      carbs   = overrideCarbs   ?? 0;
      protein = overrideProtein ?? 0;
      fat     = overrideFat     ?? 0;
    } else {
      final n = _drinkNutrition[drinkKey] ?? {};
      kcal    = ((n['kcal']    ?? 0.0) * ml / 100).round();
      carbs   = ((n['carbs']   ?? 0.0) * ml / 100).round();
      protein = ((n['protein'] ?? 0.0) * ml / 100).round();
      fat     = ((n['fat']     ?? 0.0) * ml / 100).round();
    }

    final name = drinkDisplayName(drinkKey, otherName: otherName);
    if (kcal > 0 || carbs > 0 || protein > 0 || fat > 0) {
      await DatabaseService.addFood(today, '$name ${ml}ml', kcal, protein, carbs, fat);
    }
    await NotificationService.evaluateWaterPace();
    await refresh();
  }

  Future<void> setPinnedDrink(String drinkKey, int ml, {String? otherName}) async {
    await DatabaseService.setSetting('pinned_drink', drinkKey);
    await DatabaseService.setSetting('pinned_drink_ml', '$ml');
    if (drinkKey == 'other' && otherName != null) {
      await DatabaseService.setSetting('pinned_drink_name', otherName);
    } else {
      await DatabaseService.setSetting('pinned_drink_name', '');
    }
    pinnedDrink = drinkKey;
    pinnedDrinkMl = ml;
    pinnedDrinkName = drinkKey == 'other' ? otherName : null;
    notifyListeners();
  }

  Future<void> clearPinnedDrink() async {
    await DatabaseService.setSetting('pinned_drink', '');
    pinnedDrink = '';
    pinnedDrinkMl = 250;
    pinnedDrinkName = null;
    notifyListeners();
  }

  Future<void> addFood(String item, int cal, int p, int c, int f, {String? rawInput}) async {
    await DatabaseService.addFood(today, item, cal, p, c, f);
    await NotificationService.suppressMealReminderIfRelevant(item, rawInput: rawInput);
    await refresh();
  }

  Future<void> updateFood(int id, String item, int cal, int p, int c, int f) async {
    await DatabaseService.updateFood(id, item: item, cal: cal, p: p, c: c, f: f);
    await refresh();
  }

  Future<void> deleteFood(int id) async {
    await DatabaseService.deleteFood(id);
    await refresh();
  }

  Future<void> takeMedicine(int medId) async {
    final now = DateFormat('HH:mm').format(DateTime.now());
    await DatabaseService.takeMedicine(today, medId, now);
    // Auto-log 250ml water
    await DatabaseService.addWater(today, 250);
    await NotificationService.evaluateWaterPace();

    // Cancel today's upcoming alarm so it doesn't fire after already taken
    final notifId = 1000 + medId;
    await NotificationService.cancelNotification(notifId);
    // Reschedule for tomorrow at the same time (so the daily reminder continues)
    final med = await DatabaseService.getMedicineById(medId);
    if (med != null) {
      final parts = (med['reminder_time'] as String).split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]) ?? 9;
        final minute = int.tryParse(parts[1]) ?? 0;
        // Schedule from tomorrow onwards
        await NotificationService.scheduleDailyNotificationFromTomorrow(
          id: notifId,
          title: '💊 Medicine Reminder',
          body: 'Time to take ${med['name']}',
          hour: hour,
          minute: minute,
        );
      }
    }
    // Persist suppression so rescheduleAll() on next app restart keeps this
    // alarm on tomorrow (not re-added for today)
    await DatabaseService.suppressNotifForToday(notifId);

    // Bump all-time best streak if today's completion exceeded the record.
    await DatabaseService.refreshMedicineStreaks();

    await refresh();
  }

  Future<void> undoMedicine(int medId) async {
    await DatabaseService.undoMedicine(today, medId);
    // Remove the auto-logged 250ml water (delete most recent 250ml entry for today)
    if (waterEntries.isNotEmpty) {
      final waterEntry = waterEntries.firstWhere(
        (w) => (w['ml'] as int) == 250 && (w['type'] ?? 'water') == 'water',
        orElse: () => <String, dynamic>{},
      );
      if (waterEntry.isNotEmpty) {
        await DatabaseService.deleteWater(waterEntry['id'] as int);
      }
    }

    // Reinstate the notification — scheduleDailyNotification fires today if time
    // hasn't passed yet, or tomorrow if it has, so this is always safe to call.
    final notifId = 1000 + medId;
    final med = await DatabaseService.getMedicineById(medId);
    if (med != null) {
      final parts = (med['reminder_time'] as String).split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]) ?? 9;
        final minute = int.tryParse(parts[1]) ?? 0;
        await NotificationService.scheduleDailyNotification(
          id: notifId,
          title: '💊 Medicine Reminder',
          body: 'Time to take ${med['name']}',
          hour: hour,
          minute: minute,
        );
      }
    }

    await refresh();
  }

  Future<void> addMedicine(String name, String time, String type) async {
    await DatabaseService.addMedicine(name, time, type);
    await refresh();
  }

  Future<void> deleteMedicine(int id) async {
    await DatabaseService.deleteMedicine(id);
    await refresh();
  }

  bool isMedTaken(int medId) => takenMedIds.contains(medId);

  int get calRemaining => calGoal - totalCal;
  int get protRemaining => protGoal - totalProt;
  int get waterRemaining => waterGoal - totalWater;

  String getMedEmoji(String type) {
    switch (type) {
      case 'tablet': return '💊';
      case 'capsule': return '💊';
      case 'cream': return '🧴';
      case 'drops': return '💧';
      case 'syrup': return '🥤';
      case 'injection': return '💉';
      default: return '💊';
    }
  }
}
