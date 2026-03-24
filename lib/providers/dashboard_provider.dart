import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';

class DashboardProvider extends ChangeNotifier {
  // Goals
  static const int calGoal = 1800;
  static const int protGoal = 120;
  static const int carbGoal = 200;
  static const int fatGoal = 60;
  static const int waterGoal = 3000;

  int totalCal = 0, totalProt = 0, totalCarb = 0, totalFat = 0;
  int totalWater = 0;
  int softDrinkWater = 0;
  List<Map<String, dynamic>> foodEntries = [];
  List<Map<String, dynamic>> medicines = [];
  List<int> takenMedIds = [];
  List<Map<String, dynamic>> commonMeals = [];
  List<Map<String, dynamic>> waterEntries = [];
  List<Map<String, dynamic>> medicineLogsToday = [];
  int medStreak = 0;

  String get today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  String get greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get dateLabel => DateFormat('EEEE, d MMMM').format(DateTime.now());

  Future<void> refresh() async {
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
    waterEntries = await DatabaseService.getWaterForDate(today);
    medicineLogsToday = await DatabaseService.getMedicineLogsForDate(today);
    medStreak = await DatabaseService.getMedicineStreak();

    notifyListeners();
  }

  Future<void> addWater(int ml) async {
    await DatabaseService.addWater(today, ml);
    await refresh();
  }

  Future<void> deleteWater(int id) async {
    await DatabaseService.deleteWater(id);
    await refresh();
  }

  Future<void> addThumbsUp() async {
    // Log 250ml soft drink water
    await DatabaseService.addWater(today, 250, type: 'soft_drink');
    // Log food entry: Thumbs Up 250ml = 100kcal, 0P, 25C, 0F
    await DatabaseService.addFood(today, 'Thumbs Up 250ml', 100, 0, 25, 0);
    await refresh();
  }

  Future<void> addFood(String item, int cal, int p, int c, int f) async {
    await DatabaseService.addFood(today, item, cal, p, c, f);
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
    await refresh();
  }

  Future<void> undoMedicine(int medId) async {
    await DatabaseService.undoMedicine(today, medId);
    // Remove the auto-logged 250ml water (delete most recent 250ml entry for today)
    if (waterEntries.isNotEmpty) {
      // Find the most recent 250ml water log
      final waterEntry = waterEntries.firstWhere(
        (w) => (w['ml'] as int) == 250 && (w['type'] ?? 'water') == 'water',
        orElse: () => <String, dynamic>{},
      );
      if (waterEntry.isNotEmpty) {
        await DatabaseService.deleteWater(waterEntry['id'] as int);
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
