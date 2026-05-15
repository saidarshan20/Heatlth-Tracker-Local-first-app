// ignore_for_file: avoid_print
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'database_service.dart';

/// Writes a JSON snapshot of all app data to external storage on every app
/// launch. Keeps the last [_keepCount] snapshots and deletes older ones.
///
/// Location on Android: `/storage/emulated/0/Android/data/com.sai.health_tracker/files/auto_backups/`
/// (visible via Files app, included in Google Auto Backup via `backup_rules.xml`).
///
/// Failures are logged and swallowed — backup must never block app startup.
class AutoBackupService {
  static const _folderName = 'auto_backups';
  static const _keepCount = 7;

  /// Best-effort backup. Returns the written file path, or null on failure.
  static Future<String?> runOnStartup() async {
    try {
      final dir = await _backupDir();
      if (dir == null) return null;

      final jsonStr = await DatabaseService.exportAllData();
      final now = DateTime.now();
      final stamp =
          '${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
      final file = File('${dir.path}/health_tracker_$stamp.json');
      await file.writeAsString(jsonStr, flush: true);

      await _rotate(dir);
      print('Auto-backup written: ${file.path}');
      return file.path;
    } catch (e, st) {
      print('Auto-backup failed: $e\n$st');
      return null;
    }
  }

  static Future<Directory?> _backupDir() async {
    // Prefer app-specific external storage on Android (visible via Files app,
    // included in Auto Backup). Falls back to internal documents elsewhere.
    Directory? base;
    if (Platform.isAndroid) {
      base = await getExternalStorageDirectory();
    }
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_folderName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<void> _rotate(Directory dir) async {
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    if (files.length <= _keepCount) return;
    files.sort((a, b) => a.path.compareTo(b.path)); // timestamped names → lexical = chronological
    final toDelete = files.length - _keepCount;
    for (var i = 0; i < toDelete; i++) {
      try {
        await files[i].delete();
      } catch (_) {/* ignore */}
    }
  }

  static String _pad(int v) => v.toString().padLeft(2, '0');
}
