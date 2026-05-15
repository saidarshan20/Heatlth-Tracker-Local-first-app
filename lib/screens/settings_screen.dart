import 'dart:convert';

import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../providers/dashboard_provider.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = false;
  bool _exactAlarmsAllowed = true;
  List<Map<String, dynamic>> _waterReminders = [];
  List<Map<String, dynamic>> _mealReminders = [];
  List<Map<String, dynamic>> _medicines = [];

  // Collapsible states
  bool _goalsExpanded = false;
  bool _notifExpanded = false;
  bool _medRemindersExpanded = false;
  bool _waterRemindersExpanded = false;
  bool _mealRemindersExpanded = false;

  bool _isExporting = false;
  bool _isImporting = false;

  // Goals
  final _calCtrl = TextEditingController();
  final _protCtrl = TextEditingController();
  final _carbCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _waterCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  // Summary notification
  bool _summaryEnabled = false;
  TimeOfDay _summaryTime = const TimeOfDay(hour: 9, minute: 0);

  // Sleep reminder notification
  bool _sleepReminderEnabled = false;
  TimeOfDay _sleepReminderTime = const TimeOfDay(hour: 23, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _fmtTime(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _calCtrl.dispose();
    _protCtrl.dispose();
    _carbCtrl.dispose();
    _fatCtrl.dispose();
    _waterCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    _notificationsEnabled = await NotificationService.checkPermission();
    _exactAlarmsAllowed = await NotificationService.canScheduleExactAlarms();
    _waterReminders = await DatabaseService.getReminders(type: 'water');
    _mealReminders = await DatabaseService.getReminders(type: 'meal');
    _medicines = await DatabaseService.getMedicines();

    _calCtrl.text = '${await DatabaseService.getSettingInt('cal_goal', 1800)}';
    _protCtrl.text = '${await DatabaseService.getSettingInt('prot_goal', 120)}';
    _carbCtrl.text = '${await DatabaseService.getSettingInt('carb_goal', 200)}';
    _fatCtrl.text = '${await DatabaseService.getSettingInt('fat_goal', 60)}';
    _waterCtrl.text = '${await DatabaseService.getSettingInt('water_goal', 3000)}';

    final h = await DatabaseService.getSettingDouble('height_cm', 0);
    _heightCtrl.text = h > 0 ? h.toStringAsFixed(0) : '';

    _summaryEnabled = await DatabaseService.getSettingBool('summary_enabled', false);
    final sHour = await DatabaseService.getSettingInt('summary_hour', 9);
    final sMin = await DatabaseService.getSettingInt('summary_minute', 0);
    _summaryTime = TimeOfDay(hour: sHour, minute: sMin);

    _sleepReminderEnabled = await DatabaseService.getSettingBool('sleep_reminder_enabled', false);
    final srHour = await DatabaseService.getSettingInt('sleep_reminder_hour', 23);
    final srMin = await DatabaseService.getSettingInt('sleep_reminder_minute', 0);
    _sleepReminderTime = TimeOfDay(hour: srHour, minute: srMin);

    if (mounted) setState(() {});
  }

  Future<void> _saveGoals() async {
    await DatabaseService.setSetting('cal_goal', _calCtrl.text.trim());
    await DatabaseService.setSetting('prot_goal', _protCtrl.text.trim());
    await DatabaseService.setSetting('carb_goal', _carbCtrl.text.trim());
    await DatabaseService.setSetting('fat_goal', _fatCtrl.text.trim());
    await DatabaseService.setSetting('water_goal', _waterCtrl.text.trim());
    await DashboardProvider.loadGoals();
    if (mounted) {
      context.read<DashboardProvider>().refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🎯 Goals updated!')),
      );
    }
  }

  Future<void> _saveHeight() async {
    final h = _heightCtrl.text.trim();
    if (h.isNotEmpty) {
      await DatabaseService.setSetting('height_cm', h);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📏 Height saved!')),
        );
      }
    }
  }

  Future<void> _requestPermission() async {
    final granted = await NotificationService.requestPermission();
    setState(() => _notificationsEnabled = granted);
    if (granted) {
      await NotificationService.sendTestNotification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🔔 Notifications enabled! Check your notification bar.')),
        );
      }
    }
  }

  Future<void> _addReminder(String type) async {
    final result = await _showReminderDialog(type: type);
    if (result != null) {
      await DatabaseService.addReminder(type, result['label'], result['hour'], result['minute']);
      await NotificationService.rescheduleAll(force: true);
      await _loadData();
    }
  }

  Future<void> _editReminder(Map<String, dynamic> reminder) async {
    final type = reminder['type'] as String;
    final result = await _showReminderDialog(
      type: type,
      initialLabel: reminder['label'] as String,
      initialHour: reminder['hour'] as int,
      initialMinute: reminder['minute'] as int,
    );
    if (result != null) {
      await DatabaseService.updateReminder(reminder['id'] as int, result['label'], result['hour'], result['minute']);
      await NotificationService.rescheduleAll(force: true);
      await _loadData();
    }
  }

  Future<Map<String, dynamic>?> _showReminderDialog({
    required String type,
    String? initialLabel,
    int? initialHour,
    int? initialMinute,
  }) async {
    final isEdit = initialLabel != null;
    final labelCtrl = TextEditingController(text: initialLabel ?? '');
    TimeOfDay selectedTime = TimeOfDay(hour: initialHour ?? 12, minute: initialMinute ?? 0);

    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            '${isEdit ? 'Edit' : 'Add'} ${type == 'water' ? '💧 Water' : '🍽️ Meal'} Reminder',
            style: const TextStyle(color: AppColors.onSurface, fontFamily: 'DMSans', fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                style: const TextStyle(color: AppColors.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  hintText: type == 'water' ? 'e.g. After gym' : 'e.g. Log Snack',
                  hintStyle: const TextStyle(color: AppColors.onSurfaceVariant),
                  filled: true, fillColor: AppColors.surfaceContainerHigh,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final t = await showTimePicker(context: ctx, initialTime: selectedTime);
                  if (t != null) setDialogState(() => selectedTime = t);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, color: AppColors.primary, size: 20),
                      const SizedBox(width: 12),
                      Text(_fmtTime(selectedTime),
                          style: const TextStyle(color: AppColors.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      const Text('Tap to change', style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
            ),
            ElevatedButton(
              onPressed: () {
                final label = labelCtrl.text.trim().isEmpty
                    ? (type == 'water' ? 'Water reminder' : 'Meal reminder')
                    : labelCtrl.text.trim();
                Navigator.pop(ctx, {'label': label, 'hour': selectedTime.hour, 'minute': selectedTime.minute});
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.surface),
              child: Text(isEdit ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteReminder(int id) async {
    await DatabaseService.deleteReminder(id);
    await NotificationService.rescheduleAll(force: true);
    await _loadData();
  }

  // ── Shared collapsible card helper ──
  Widget _collapsibleCard({
    required String emoji,
    required String title,
    required String subtitle,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget body,
    Widget? trailing,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$emoji $title',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (trailing != null && expanded) trailing,
                Icon(
                  expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 20, color: AppColors.onSurfaceVariant,
                ),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 12),
            body,
          ],
        ],
      ),
    );
  }

  Widget _reminderRow({
    required Map<String, dynamic> r,
    required String emoji,
    required Color timeColor,
  }) {
    return Dismissible(
      key: ValueKey('rem_${r['id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
      ),
      onDismissed: (_) => _deleteReminder(r['id'] as int),
      child: InkWell(
        onTap: () => _editReminder(r),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(child: Text(r['label'] as String, style: const TextStyle(fontSize: 12, color: AppColors.onSurface))),
              Text(
                '${(r['hour'] as int).toString().padLeft(2, '0')}:${(r['minute'] as int).toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 11, color: timeColor, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.edit_outlined, size: 14, color: AppColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // ── Header ──
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 4),
                const Text('Settings',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'DMSerifDisplay', color: AppColors.onSurface)),
              ],
            ),
            const SizedBox(height: 16),

            // ── 1. Daily Goals ──
            _collapsibleCard(
              emoji: '🎯',
              title: 'Daily Goals',
              subtitle: _goalsExpanded
                  ? 'Tap to collapse'
                  : '${_calCtrl.text} kcal · P:${_protCtrl.text}g · ${_waterCtrl.text}ml',
              expanded: _goalsExpanded,
              onToggle: () => setState(() => _goalsExpanded = !_goalsExpanded),
              body: Column(
                children: [
                  Row(children: [
                    Expanded(child: _goalField('Calories', _calCtrl, 'kcal')),
                    const SizedBox(width: 8),
                    Expanded(child: _goalField('Protein', _protCtrl, 'g')),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _goalField('Carbs', _carbCtrl, 'g')),
                    const SizedBox(width: 8),
                    Expanded(child: _goalField('Fat', _fatCtrl, 'g')),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _goalField('Water', _waterCtrl, 'ml')),
                    const SizedBox(width: 8),
                    Expanded(child: _goalField('Height', _heightCtrl, 'cm')),
                  ]),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async { await _saveGoals(); await _saveHeight(); },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary, foregroundColor: AppColors.surface,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Save Goals', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── 2. Notifications ──
            _collapsibleCard(
              emoji: '🔔',
              title: 'Notifications',
              subtitle: _notificationsEnabled
                  ? (_summaryEnabled ? 'Enabled · Summary at ${_fmtTime(_summaryTime)}' : 'Enabled')
                  : 'Disabled — tap to expand',
              expanded: _notifExpanded,
              onToggle: () => setState(() => _notifExpanded = !_notifExpanded),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Enable / status row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _notificationsEnabled ? 'Enabled — reminders are active' : 'Disabled — tap to enable',
                          style: TextStyle(fontSize: 11,
                              color: _notificationsEnabled ? AppColors.primary : AppColors.error),
                        ),
                      ),
                      if (!_notificationsEnabled)
                        ElevatedButton(
                          onPressed: _requestPermission,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary, foregroundColor: AppColors.surface,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Enable', style: TextStyle(fontSize: 12)),
                        )
                      else
                        const Icon(Icons.check_circle, color: AppColors.primary, size: 24),
                    ],
                  ),
                  // Exact-alarm permission banner — on Android 12+ this is a
                  // separate permission, and without it ColorOS can fire
                  // notifications several minutes early.
                  if (!_exactAlarmsAllowed) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Reminders may fire early. Tap to allow exact alarms.',
                              style: TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await NotificationService.requestExactAlarmPermission();
                              // User returns from system page — re-check.
                              await Future.delayed(const Duration(milliseconds: 400));
                              if (mounted) await _loadData();
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Fix', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_notificationsEnabled) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await NotificationService.sendTestNotification();
                          messenger.showSnackBar(
                            const SnackBar(content: Text('🔔 Test notification sent!')),
                          );
                        },
                        icon: const Icon(Icons.notifications_active, size: 16),
                        label: const Text('Send Test Notification', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.outline),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1, color: AppColors.outline),
                    const SizedBox(height: 8),

                    // Daily Summary toggle
                    _notifToggleRow(
                      emoji: '📋',
                      title: 'Daily Summary',
                      subtitle: _summaryEnabled ? 'Yesterday\'s stats at ${_fmtTime(_summaryTime)}' : 'Disabled',
                      enabled: _summaryEnabled,
                      time: _summaryEnabled ? _summaryTime : null,
                      onTimeChanged: (t) async {
                        setState(() => _summaryTime = t);
                        await DatabaseService.setSetting('summary_hour', '${t.hour}');
                        await DatabaseService.setSetting('summary_minute', '${t.minute}');
                        await NotificationService.rescheduleAll(force: true);
                      },
                      onToggled: (v) async {
                        setState(() => _summaryEnabled = v);
                        await DatabaseService.setSettingBool('summary_enabled', v);
                        await NotificationService.rescheduleAll(force: true);
                      },
                    ),

                    const SizedBox(height: 4),
                    const Divider(height: 1, color: AppColors.outline),
                    const SizedBox(height: 8),

                    // Sleep Reminder toggle
                    _notifToggleRow(
                      emoji: '🌙',
                      title: 'Sleep Reminder',
                      subtitle: _sleepReminderEnabled ? 'Bedtime reminder at ${_fmtTime(_sleepReminderTime)}' : 'Disabled',
                      enabled: _sleepReminderEnabled,
                      time: _sleepReminderEnabled ? _sleepReminderTime : null,
                      onTimeChanged: (t) async {
                        setState(() => _sleepReminderTime = t);
                        await DatabaseService.setSetting('sleep_reminder_hour', '${t.hour}');
                        await DatabaseService.setSetting('sleep_reminder_minute', '${t.minute}');
                        await NotificationService.rescheduleAll(force: true);
                      },
                      onToggled: (v) async {
                        setState(() => _sleepReminderEnabled = v);
                        await DatabaseService.setSettingBool('sleep_reminder_enabled', v);
                        await NotificationService.rescheduleAll(force: true);
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── 3. Medicine Reminders ──
            _collapsibleCard(
              emoji: '💊',
              title: 'Medicine Reminders',
              subtitle: '${_medicines.length} ${_medicines.length == 1 ? 'medicine' : 'medicines'} — auto-synced',
              expanded: _medRemindersExpanded,
              onToggle: () => setState(() => _medRemindersExpanded = !_medRemindersExpanded),
              body: _medicines.isEmpty
                  ? const Text('No medicines added. Go to Health → + Add.',
                      style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant))
                  : Column(
                      children: _medicines.map((med) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Text(_getMedEmoji(med['type'] as String? ?? 'tablet'),
                              style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(med['name'] as String,
                              style: const TextStyle(fontSize: 12, color: AppColors.onSurface))),
                          Text(med['reminder_time'] as String,
                              style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                        ]),
                      )).toList(),
                    ),
            ),
            const SizedBox(height: 8),

            // ── 4. Water Reminders ──
            _collapsibleCard(
              emoji: '💧',
              title: 'Water Reminders',
              subtitle: '${_waterReminders.length} reminder${_waterReminders.length == 1 ? '' : 's'} set',
              expanded: _waterRemindersExpanded,
              onToggle: () => setState(() => _waterRemindersExpanded = !_waterRemindersExpanded),
              trailing: IconButton(
                icon: const Icon(Icons.add_circle_outline, color: AppColors.primary, size: 20),
                onPressed: () => _addReminder('water'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              body: _waterReminders.isEmpty
                  ? const Text('No water reminders. Tap + to add.',
                      style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant))
                  : Column(
                      children: _waterReminders.map((r) => _reminderRow(
                        r: r, emoji: '💧', timeColor: AppColors.water,
                      )).toList(),
                    ),
            ),
            const SizedBox(height: 8),

            // ── 5. Meal Reminders ──
            _collapsibleCard(
              emoji: '🍽️',
              title: 'Meal Reminders',
              subtitle: '${_mealReminders.length} reminder${_mealReminders.length == 1 ? '' : 's'} set',
              expanded: _mealRemindersExpanded,
              onToggle: () => setState(() => _mealRemindersExpanded = !_mealRemindersExpanded),
              trailing: IconButton(
                icon: const Icon(Icons.add_circle_outline, color: AppColors.primary, size: 20),
                onPressed: () => _addReminder('meal'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              body: _mealReminders.isEmpty
                  ? const Text('No meal reminders. Tap + to add.',
                      style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant))
                  : Column(
                      children: _mealReminders.map((r) => _reminderRow(
                        r: r, emoji: '🍽️', timeColor: AppColors.secondary,
                      )).toList(),
                    ),
            ),
            const SizedBox(height: 8),

            // ── Data Management ──
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💾 Data Management',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                  const SizedBox(height: 4),
                  const Text('Export or restore your health data.',
                      style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isExporting ? null : _exportData,
                        icon: _isExporting
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                            : const Icon(Icons.upload_rounded, size: 16),
                        label: const Text('JSON Backup'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary, foregroundColor: AppColors.surface,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'DMSans'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isExporting ? null : _exportExcel,
                        icon: const Icon(Icons.table_chart_rounded, size: 16),
                        label: const Text('Excel Report'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF217346), foregroundColor: AppColors.surface,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'DMSans'),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isImporting ? null : _importData,
                      icon: _isImporting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                          : const Icon(Icons.download_rounded, size: 18),
                      label: Text(_isImporting ? 'Importing…' : 'Import Data (Restore)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.outline),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'DMSans'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isImporting ? null : _importFromExcel,
                      icon: const Icon(Icons.table_view_rounded, size: 18),
                      label: const Text('Recover from Excel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF217346),
                        side: const BorderSide(color: Color(0xFF217346)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'DMSans'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.error),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text('JSON import overwrites everything. Excel recovery appends only food/water/weight/fasting/sleep.',
                          style: TextStyle(fontSize: 10, color: AppColors.error)),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Notification toggle row (Daily Summary / Sleep Reminder) ──
  Widget _notifToggleRow({
    required String emoji,
    required String title,
    required String subtitle,
    required bool enabled,
    required TimeOfDay? time,
    required ValueChanged<TimeOfDay> onTimeChanged,
    required ValueChanged<bool> onToggled,
  }) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
              Text(subtitle,
                  style: TextStyle(fontSize: 10,
                      color: enabled ? AppColors.primary : AppColors.onSurfaceVariant)),
            ],
          ),
        ),
        if (enabled && time != null)
          TextButton(
            onPressed: () async {
              final t = await showTimePicker(context: context, initialTime: time);
              if (t != null) onTimeChanged(t);
            },
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Text(_fmtTime(time), style: const TextStyle(fontSize: 11, color: AppColors.primary)),
          ),
        Switch(
          value: enabled,
          activeThumbColor: AppColors.primary,
          activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
          onChanged: onToggled,
        ),
      ],
    );
  }

  Future<void> _exportData() async {
    setState(() => _isExporting = true);
    try {
      final jsonStr = await DatabaseService.exportAllData();
      final now = DateTime.now();
      final fileName =
          'health_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.json';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(jsonStr, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'Health Tracker Backup – $fileName',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Export failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('⚠️ Overwrite Data?',
            style: TextStyle(color: AppColors.onSurface, fontFamily: 'DMSans', fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
          'Importing will permanently replace ALL your current health data with the backup. This cannot be undone.\n\nAre you sure?',
          style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: AppColors.surface),
            child: const Text('Yes, Overwrite'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['json'], allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;

    setState(() => _isImporting = true);
    try {
      final file = File(result.files.single.path!);
      final jsonStr = await file.readAsString();
      jsonDecode(jsonStr);
      final summary = await DatabaseService.importAllData(jsonStr);
      await NotificationService.rescheduleAll(force: true);
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('✅ Import Successful',
                style: TextStyle(color: AppColors.onSurface, fontFamily: 'DMSans', fontSize: 16, fontWeight: FontWeight.w700)),
            content: Text(summary, style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13, height: 1.6)),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.surface),
                child: const Text('Done'),
              ),
            ],
          ),
        );
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Import failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _importFromExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['xlsx'], allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;

    setState(() => _isImporting = true);
    try {
      final file = File(result.files.single.path!);
      final summary = await DatabaseService.importFromExcel(file);
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('✅ Recovery Complete',
                style: TextStyle(color: AppColors.onSurface, fontFamily: 'DMSans', fontSize: 16, fontWeight: FontWeight.w700)),
            content: Text(summary, style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13, height: 1.6)),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.surface),
                child: const Text('Done'),
              ),
            ],
          ),
        );
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Excel recovery failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  String _getMedEmoji(String type) {
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

  Widget _goalField(String label, TextEditingController ctrl, String suffix) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 13, color: AppColors.onSurface),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
        suffixText: suffix,
        suffixStyle: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
        filled: true, fillColor: AppColors.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        isDense: true,
      ),
    );
  }

  Future<void> _exportExcel() async {
    setState(() => _isExporting = true);
    try {
      final db = await DatabaseService.database;
      final excel = xl.Excel.createExcel();

      final foodSheet = excel['Food Log'];
      foodSheet.appendRow([
        xl.TextCellValue('Date'), xl.TextCellValue('Item'),
        xl.TextCellValue('Calories'), xl.TextCellValue('Protein (g)'),
        xl.TextCellValue('Carbs (g)'), xl.TextCellValue('Fats (g)'),
      ]);
      final foods = await db.query('food_logs', orderBy: 'date DESC, id DESC');
      for (final f in foods) {
        foodSheet.appendRow([
          xl.TextCellValue(f['date'] as String), xl.TextCellValue(f['item'] as String),
          xl.IntCellValue(f['calories'] as int), xl.IntCellValue(f['protein'] as int),
          xl.IntCellValue(f['carbs'] as int), xl.IntCellValue(f['fats'] as int),
        ]);
      }

      final waterSheet = excel['Water Log'];
      waterSheet.appendRow([
        xl.TextCellValue('Date'), xl.TextCellValue('Amount (ml)'),
        xl.TextCellValue('Type'), xl.TextCellValue('Drink'), xl.TextCellValue('Logged At'),
      ]);
      final waters = await db.query('water_logs', orderBy: 'date DESC, id DESC');
      for (final w in waters) {
        waterSheet.appendRow([
          xl.TextCellValue(w['date'] as String), xl.IntCellValue(w['ml'] as int),
          xl.TextCellValue((w['type'] as String?) ?? 'water'),
          xl.TextCellValue((w['drink_name'] as String?) ?? ''),
          xl.TextCellValue((w['created_at'] as String?) ?? ''),
        ]);
      }

      final weightSheet = excel['Weight Log'];
      weightSheet.appendRow([xl.TextCellValue('Date'), xl.TextCellValue('Weight (kg)')]);
      final weights = await db.query('weight_logs', orderBy: 'date DESC');
      for (final w in weights) {
        weightSheet.appendRow([
          xl.TextCellValue(w['date'] as String),
          xl.DoubleCellValue(w['weight_kg'] as double),
        ]);
      }

      final fastSheet = excel['Fasting Log'];
      fastSheet.appendRow([
        xl.TextCellValue('Start'), xl.TextCellValue('End'), xl.TextCellValue('Duration (min)'),
      ]);
      final fasts = await db.query('fasting_logs', orderBy: 'id DESC');
      for (final f in fasts) {
        fastSheet.appendRow([
          xl.TextCellValue(f['start_time'] as String),
          xl.TextCellValue((f['end_time'] as String?) ?? 'Active'),
          xl.IntCellValue((f['duration_min'] as int?) ?? 0),
        ]);
      }

      final sleepSheet = excel['Sleep Log'];
      sleepSheet.appendRow([
        xl.TextCellValue('Start'), xl.TextCellValue('End'), xl.TextCellValue('Duration (min)'),
      ]);
      final sleeps = await db.query('sleep_logs', orderBy: 'id DESC');
      for (final s in sleeps) {
        sleepSheet.appendRow([
          xl.TextCellValue(s['start_time'] as String),
          xl.TextCellValue((s['end_time'] as String?) ?? 'Active'),
          xl.IntCellValue((s['duration_min'] as int?) ?? 0),
        ]);
      }

      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

      final bytes = excel.save();
      if (bytes == null) throw 'Failed to generate Excel';

      final now = DateTime.now();
      final fileName =
          'health_report_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.xlsx';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        subject: 'Health Tracker Report — $fileName',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Excel export failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }
}
