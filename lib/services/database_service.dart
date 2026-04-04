// ignore_for_file: avoid_print, unnecessary_string_interpolations
import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' show join, dirname;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';


class DatabaseService {
  static Database? _db;

  static Future<void> initPlatform() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'health_tracker.db');

    var exists = await databaseExists(path);

    if (!exists) {
      print("Creating fresh database");
      try {
        await Directory(dirname(path)).create(recursive: true);
      } catch (_) {}
    } else {
      print("Opening existing database");
    }

    return await openDatabase(path, version: 3, onCreate: _create, onUpgrade: _upgrade);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS food_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        item TEXT NOT NULL,
        calories INTEGER NOT NULL,
        protein INTEGER NOT NULL,
        carbs INTEGER NOT NULL,
        fats INTEGER NOT NULL,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS water_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        ml INTEGER NOT NULL,
        type TEXT DEFAULT 'water',
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS medicines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        reminder_time TEXT NOT NULL,
        type TEXT DEFAULT 'tablet',
        active INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS medicine_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        medicine_id INTEGER NOT NULL,
        taken_at TEXT NOT NULL,
        FOREIGN KEY (medicine_id) REFERENCES medicines(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS weight_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        weight_kg REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS fasting_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_time TEXT NOT NULL,
        end_time TEXT,
        duration_min INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS common_meals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        calories INTEGER NOT NULL,
        protein INTEGER NOT NULL,
        carbs INTEGER NOT NULL,
        fats INTEGER NOT NULL,
        log_count INTEGER DEFAULT 1,
        last_logged TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS personal_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_type TEXT NOT NULL,
        value REAL NOT NULL,
        achieved_date TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        label TEXT NOT NULL,
        hour INTEGER NOT NULL,
        minute INTEGER NOT NULL,
        active INTEGER DEFAULT 1
      )
    ''');
  }

  static Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute("ALTER TABLE water_logs ADD COLUMN type TEXT DEFAULT 'water'");
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS reminders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            label TEXT NOT NULL,
            hour INTEGER NOT NULL,
            minute INTEGER NOT NULL,
            active INTEGER DEFAULT 1
          )
        ''');
      } catch (_) {}
    }
  }

  // ── Food ──
  static Future<int> addFood(String date, String item, int cal, int p, int c, int f) async {
    final db = await database;
    final id = await db.insert('food_logs', {
      'date': date, 'item': item, 'calories': cal,
      'protein': p, 'carbs': c, 'fats': f,
    });
    // Auto-save to common meals
    final existing = await db.query('common_meals', where: 'name = ?', whereArgs: [item]);
    if (existing.isNotEmpty) {
      await db.rawUpdate(
        'UPDATE common_meals SET log_count = log_count + 1, last_logged = ?, calories = ?, protein = ?, carbs = ?, fats = ? WHERE name = ?',
        [date, cal, p, c, f, item],
      );
    } else {
      await db.insert('common_meals', {
        'name': item, 'calories': cal, 'protein': p,
        'carbs': c, 'fats': f, 'log_count': 1, 'last_logged': date,
      });
    }
    return id;
  }

  static Future<List<Map<String, dynamic>>> getFoodForDate(String date) async {
    final db = await database;
    return await db.query('food_logs', where: 'date = ?', whereArgs: [date], orderBy: 'id DESC');
  }

  static Future<Map<String, int>> getFoodTotals(String date) async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT SUM(calories) as cal, SUM(protein) as p, SUM(carbs) as c, SUM(fats) as f FROM food_logs WHERE date = ?',
      [date],
    );
    if (r.isEmpty || r.first['cal'] == null) return {'cal': 0, 'p': 0, 'c': 0, 'f': 0};
    return {
      'cal': (r.first['cal'] as num).toInt(),
      'p': (r.first['p'] as num).toInt(),
      'c': (r.first['c'] as num).toInt(),
      'f': (r.first['f'] as num).toInt(),
    };
  }

  static Future<void> updateFood(int id, {String? item, int? cal, int? p, int? c, int? f}) async {
    final db = await database;
    final updates = <String, dynamic>{};
    if (item != null) updates['item'] = item;
    if (cal != null) updates['calories'] = cal;
    if (p != null) updates['protein'] = p;
    if (c != null) updates['carbs'] = c;
    if (f != null) updates['fats'] = f;
    await db.update('food_logs', updates, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteFood(int id) async {
    final db = await database;
    await db.delete('food_logs', where: 'id = ?', whereArgs: [id]);
  }

  /// Returns per-day aggregated calorie totals (last [days] days), newest first.
  /// Each item: { 'date', 'total_cal', 'total_prot', 'total_carbs', 'total_fats',
  ///              'entries': List, 'fasting_min': int, 'fast_count': int }
  /// Also includes 'peak' and 'lowest' day maps.
  static Future<Map<String, dynamic>> getDailyCalorieHistory({int days = 90}) async {
    final db = await database;

    final cutoff = DateTime.now().subtract(Duration(days: days));
    final cutoffStr = '${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}';

    final rows = await db.rawQuery('''
      SELECT date,
             SUM(calories) as total_cal,
             SUM(protein)  as total_prot,
             SUM(carbs)    as total_carbs,
             SUM(fats)     as total_fats
      FROM food_logs
      WHERE date >= ?
      GROUP BY date
      ORDER BY date DESC
    ''', [cutoffStr]);

    final allEntries = await db.query('food_logs',
        where: 'date >= ?', whereArgs: [cutoffStr], orderBy: 'date DESC, id DESC');

    final Map<String, List<Map<String, dynamic>>> entriesByDate = {};
    for (final e in allEntries) {
      final d = e['date'] as String;
      entriesByDate.putIfAbsent(d, () => []).add(e);
    }

    // ── Fetch fasting logs per date (date the fast started) ──
    final fastingRows = await db.rawQuery('''
      SELECT DATE(start_time) as fast_date,
             SUM(COALESCE(duration_min, 0)) as total_fast_min,
             COUNT(*) as fast_count
      FROM fasting_logs
      WHERE DATE(start_time) >= ?
      GROUP BY fast_date
    ''', [cutoffStr]);

    final Map<String, Map<String, dynamic>> fastingByDate = {};
    for (final f in fastingRows) {
      final d = f['fast_date'] as String;
      fastingByDate[d] = {
        'fasting_min': (f['total_fast_min'] as num?)?.toInt() ?? 0,
        'fast_count':  (f['fast_count']     as num?)?.toInt() ?? 0,
      };
    }

    final dailyList = rows.map((r) {
      final date   = r['date'] as String;
      final fsting = fastingByDate[date];
      return <String, dynamic>{
        'date':        date,
        'total_cal':   (r['total_cal']   as num).toInt(),
        'total_prot':  (r['total_prot']  as num?)?.toInt() ?? 0,
        'total_carbs': (r['total_carbs'] as num?)?.toInt() ?? 0,
        'total_fats':  (r['total_fats']  as num?)?.toInt() ?? 0,
        'entries':     entriesByDate[date] ?? <Map<String, dynamic>>[],
        'fasting_min': fsting?['fasting_min'] ?? 0,
        'fast_count':  fsting?['fast_count']  ?? 0,
      };
    }).toList();

    Map<String, dynamic>? peak;
    Map<String, dynamic>? lowest;
    for (final d in dailyList) {
      final cal = d['total_cal'] as int;
      if (peak == null || cal > (peak['total_cal'] as int)) peak = d;
      if (lowest == null || cal < (lowest['total_cal'] as int)) lowest = d;
    }

    return {'days': dailyList, 'peak': peak, 'lowest': lowest};
  }




  // ── Water ──
  static Future<int> addWater(String date, int ml, {String type = 'water'}) async {
    final db = await database;
    return await db.insert('water_logs', {'date': date, 'ml': ml, 'type': type});
  }

  static Future<int> getSoftDrinkWater(String date) async {
    final db = await database;
    final r = await db.rawQuery(
      "SELECT SUM(ml) as total FROM water_logs WHERE date = ? AND type = 'soft_drink'", [date],
    );
    return (r.first['total'] as num?)?.toInt() ?? 0;
  }

  static Future<int> getWaterTotal(String date) async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT SUM(ml) as total FROM water_logs WHERE date = ?', [date],
    );
    return (r.first['total'] as num?)?.toInt() ?? 0;
  }

  static Future<List<Map<String, dynamic>>> getWaterForDate(String date) async {
    final db = await database;
    return await db.query('water_logs', where: 'date = ?', whereArgs: [date], orderBy: 'id DESC');
  }

  static Future<void> deleteWater(int id) async {
    final db = await database;
    await db.delete('water_logs', where: 'id = ?', whereArgs: [id]);
  }

  /// Returns per-day aggregated water totals, newest first.
  /// Each map: { 'date': String, 'total_ml': int, 'entries': List<Map> }
  /// Also includes highest/lowest day info in result['peak'] / result['lowest'].
  static Future<Map<String, dynamic>> getDailyWaterHistory({int days = 90}) async {
    final db = await database;

    // All logs newest first within the window
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final cutoffStr = '${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}';

    final rows = await db.rawQuery('''
      SELECT date, SUM(ml) as total_ml
      FROM water_logs
      WHERE date >= ?
      GROUP BY date
      ORDER BY date DESC
    ''', [cutoffStr]);

    // Also pull detailed entries per day for the list
    final allEntries = await db.query('water_logs',
        where: 'date >= ?', whereArgs: [cutoffStr], orderBy: 'date DESC, id DESC');

    // Build entries map keyed by date
    final Map<String, List<Map<String, dynamic>>> entriesByDate = {};
    for (final e in allEntries) {
      final d = e['date'] as String;
      entriesByDate.putIfAbsent(d, () => []).add(e);
    }

    final dailyList = rows.map((r) => {
      'date': r['date'] as String,
      'total_ml': (r['total_ml'] as num).toInt(),
      'entries': entriesByDate[r['date'] as String] ?? [],
    }).toList();

    // Compute peak & lowest
    Map<String, dynamic>? peak;
    Map<String, dynamic>? lowest;
    for (final d in dailyList) {
      final ml = d['total_ml'] as int;
      if (peak == null || ml > (peak['total_ml'] as int)) peak = d;
      if (lowest == null || ml < (lowest['total_ml'] as int)) lowest = d;
    }

    return {
      'days': dailyList,
      'peak': peak,
      'lowest': lowest,
    };
  }


  // ── Medicines ──
  static Future<int> addMedicine(String name, String time, String type) async {
    final db = await database;
    return await db.insert('medicines', {'name': name, 'reminder_time': time, 'type': type});
  }

  static Future<List<Map<String, dynamic>>> getMedicines() async {
    final db = await database;
    return await db.query('medicines', where: 'active = 1', orderBy: 'reminder_time');
  }

  static Future<Map<String, dynamic>?> getMedicineById(int id) async {
    final db = await database;
    final r = await db.query('medicines', where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isNotEmpty ? r.first : null;
  }

  static Future<void> deleteMedicine(int id) async {
    final db = await database;
    await db.update('medicines', {'active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> takeMedicine(String date, int medId, String time) async {
    final db = await database;
    await db.insert('medicine_logs', {'date': date, 'medicine_id': medId, 'taken_at': time});
  }

  static Future<void> undoMedicine(String date, int medId) async {
    final db = await database;
    await db.delete('medicine_logs', where: 'date = ? AND medicine_id = ?', whereArgs: [date, medId]);
  }

  static Future<List<int>> getTakenMedicineIds(String date) async {
    final db = await database;
    final r = await db.query('medicine_logs', where: 'date = ?', whereArgs: [date]);
    return r.map((e) => e['medicine_id'] as int).toList();
  }

  static Future<List<Map<String, dynamic>>> getMedicineLogsForDate(String date) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT ml.id, ml.medicine_id, ml.taken_at, m.name, m.type
      FROM medicine_logs ml
      JOIN medicines m ON ml.medicine_id = m.id
      WHERE ml.date = ?
      ORDER BY ml.taken_at DESC
    ''', [date]);
  }

  static Future<int> getMedicineStreak() async {
    final db = await database;
    final meds = await getMedicines();
    if (meds.isEmpty) return 0;
    int streak = 0;
    for (int i = 0; i < 365; i++) {
      final date = DateTime.now().subtract(Duration(days: i));
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final taken = await getTakenMedicineIds(dateStr);
      if (taken.length >= meds.length) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  // ── Weight ──
  static Future<void> addWeight(String date, double kg) async {
    final db = await database;
    await db.insert('weight_logs', {'date': date, 'weight_kg': kg});
  }

  static Future<List<Map<String, dynamic>>> getWeightHistory({int limit = 7}) async {
    final db = await database;
    return await db.query('weight_logs', orderBy: 'date DESC', limit: limit);
  }

  static Future<List<Map<String, dynamic>>> getFullWeightHistory() async {
    final db = await database;
    return await db.query('weight_logs', orderBy: 'date DESC, id DESC');
  }

  static Future<void> updateWeight(int id, double kg) async {
    final db = await database;
    await db.update('weight_logs', {'weight_kg': kg}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteWeightById(int id) async {
    final db = await database;
    await db.delete('weight_logs', where: 'id = ?', whereArgs: [id]);
  }

  // type='weight_weekly', label=weekday int (1=Mon..7=Sun), hour/minute = time
  static Future<Map<String, dynamic>?> getWeightReminder() async {
    final db = await database;
    final r = await db.query('reminders', where: "type = 'weight_weekly'", limit: 1);
    return r.isNotEmpty ? r.first : null;
  }

  static Future<void> setWeightReminder(int weekday, int hour, int minute) async {
    final db = await database;
    await db.delete('reminders', where: "type = 'weight_weekly'");
    await db.insert('reminders', {
      'type': 'weight_weekly', 'label': '$weekday',
      'hour': hour, 'minute': minute, 'active': 1,
    });
  }

  static Future<void> clearWeightReminder() async {
    final db = await database;
    await db.delete('reminders', where: "type = 'weight_weekly'");
  }

  // ── Fasting ──
  static Future<Map<String, dynamic>?> getActiveFast() async {
    final db = await database;
    final r = await db.query('fasting_logs', where: 'end_time IS NULL', limit: 1);
    return r.isNotEmpty ? r.first : null;
  }

  static Future<int> startFast(String startTime) async {
    final db = await database;
    return await db.insert('fasting_logs', {'start_time': startTime});
  }

  static Future<void> endFast(int id, String endTime, int durationMin) async {
    final db = await database;
    await db.update('fasting_logs', {'end_time': endTime, 'duration_min': durationMin},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<Map<String, dynamic>?> getLastFast() async {
    final db = await database;
    final r = await db.query('fasting_logs', where: 'end_time IS NOT NULL', orderBy: 'id DESC', limit: 1);
    return r.isNotEmpty ? r.first : null;
  }

  static Future<List<Map<String, dynamic>>> getFastingHistory({int limit = 30}) async {
    final db = await database;
    return await db.query('fasting_logs',
        where: 'end_time IS NOT NULL',
        orderBy: 'id DESC',
        limit: limit);
  }

  // ── Common Meals ──
  static Future<List<Map<String, dynamic>>> getCommonMeals({int minCount = 3, int limit = 8}) async {
    final db = await database;
    return await db.query('common_meals',
        where: 'log_count >= ?', whereArgs: [minCount],
        orderBy: 'log_count DESC', limit: limit);
  }

  // ── Weekly Stats ──
  static Future<Map<String, dynamic>> getWeeklyStats() async {
    final now = DateTime.now();
    List<int> dailyCals = [], dailyProts = [], dailyWaters = [];

    for (int i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final ft = await getFoodTotals(dateStr);
      final wt = await getWaterTotal(dateStr);
      dailyCals.add(ft['cal']!);
      dailyProts.add(ft['p']!);
      dailyWaters.add(wt);
    }

    return {
      'dailyCals': dailyCals,
      'dailyProts': dailyProts,
      'dailyWaters': dailyWaters,
      'avgCal': dailyCals.reduce((a, b) => a + b) ~/ 7,
      'avgProt': dailyProts.reduce((a, b) => a + b) ~/ 7,
      'avgWater': dailyWaters.reduce((a, b) => a + b) ~/ 7,
    };
  }

  // ── Reminders ──
  static Future<List<Map<String, dynamic>>> getReminders({String? type}) async {
    final db = await database;
    if (type != null) {
      return await db.query('reminders', where: 'type = ?', whereArgs: [type], orderBy: 'hour, minute');
    }
    return await db.query('reminders', orderBy: 'hour, minute');
  }

  static Future<int> addReminder(String type, String label, int hour, int minute) async {
    final db = await database;
    return await db.insert('reminders', {
      'type': type, 'label': label, 'hour': hour, 'minute': minute, 'active': 1,
    });
  }

  static Future<void> deleteReminder(int id) async {
    final db = await database;
    await db.delete('reminders', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> toggleReminder(int id, bool active) async {
    final db = await database;
    await db.update('reminders', {'active': active ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> updateReminder(int id, String label, int hour, int minute) async {
    final db = await database;
    await db.update('reminders', {'label': label, 'hour': hour, 'minute': minute}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> seedDefaultReminders() async {
    final existing = await getReminders();
    if (existing.isNotEmpty) return; // Already seeded

    // Default water reminders
    final waterTimes = [
      ('Morning water', 7, 0),
      ('Mid-morning', 9, 0),
      ('Before lunch', 11, 0),
      ('After lunch', 13, 0),
      ('Afternoon', 14, 30),
      ('Evening', 16, 0),
      ('Pre-dinner', 18, 0),
      ('After dinner', 20, 0),
      ('Before bed', 21, 30),
    ];
    for (final (label, h, m) in waterTimes) {
      await addReminder('water', label, h, m);
    }

    // Default meal reminders
    await addReminder('meal', 'Log Breakfast 🍳', 8, 30);
    await addReminder('meal', 'Log Lunch 🍛', 13, 30);
    await addReminder('meal', 'Log Dinner 🍽️', 20, 30);
  }
  // ── Export / Import ──

  /// Returns a JSON string containing ALL data from every table.
  static Future<String> exportAllData() async {
    final db = await database;

    final foodLogs      = await db.query('food_logs',      orderBy: 'id ASC');
    final waterLogs     = await db.query('water_logs',     orderBy: 'id ASC');
    final medicines     = await db.query('medicines',      orderBy: 'id ASC');
    final medicineLogs  = await db.query('medicine_logs',  orderBy: 'id ASC');
    final weightLogs    = await db.query('weight_logs',    orderBy: 'id ASC');
    final fastingLogs   = await db.query('fasting_logs',   orderBy: 'id ASC');
    final commonMeals   = await db.query('common_meals',   orderBy: 'id ASC');
    final reminders     = await db.query('reminders',      orderBy: 'id ASC');

    final payload = {
      'exported_at': DateTime.now().toIso8601String(),
      'version': 1,
      'food_logs':     foodLogs,
      'water_logs':    waterLogs,
      'medicines':     medicines,
      'medicine_logs': medicineLogs,
      'weight_logs':   weightLogs,
      'fasting_logs':  fastingLogs,
      'common_meals':  commonMeals,
      'reminders':     reminders,
    };

    return jsonEncode(payload);
  }

  /// Clears all tables and restores data from a previously exported JSON string.
  /// Returns a summary string (e.g. "Imported 120 food logs, 80 water logs…").
  static Future<String> importAllData(String jsonString) async {
    final db = await database;
    final Map<String, dynamic> payload = jsonDecode(jsonString) as Map<String, dynamic>;

    await db.transaction((txn) async {
      // Wipe existing data (order matters for FK constraints)
      for (final table in [
        'medicine_logs', 'food_logs', 'water_logs',
        'weight_logs', 'fasting_logs', 'common_meals',
        'reminders', 'medicines',
      ]) {
        await txn.delete(table);
      }

      Future<void> insertRows(String table, dynamic rows) async {
        if (rows == null) return;
        for (final row in (rows as List)) {
          final map = Map<String, dynamic>.from(row as Map);
          map.remove('id'); // let the DB auto-assign new IDs
          await txn.insert(table, map);
        }
      }

      await insertRows('medicines',     payload['medicines']);
      await insertRows('food_logs',     payload['food_logs']);
      await insertRows('water_logs',    payload['water_logs']);
      await insertRows('medicine_logs', payload['medicine_logs']);
      await insertRows('weight_logs',   payload['weight_logs']);
      await insertRows('fasting_logs',  payload['fasting_logs']);
      await insertRows('common_meals',  payload['common_meals']);
      await insertRows('reminders',     payload['reminders']);
    });

    int _count(String key) => ((payload[key] as List?)?.length) ?? 0;

    return 'Imported:\n'
        '• ${_count('food_logs')} food logs\n'
        '• ${_count('water_logs')} water logs\n'
        '• ${_count('medicines')} medicines\n'
        '• ${_count('weight_logs')} weight logs\n'
        '• ${_count('reminders')} reminders';
  }
}
