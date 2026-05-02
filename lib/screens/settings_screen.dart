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
  List<Map<String, dynamic>> _waterReminders = [];
  List<Map<String, dynamic>> _mealReminders = [];
  List<Map<String, dynamic>> _medicines = [];
  bool _waterExpanded = false;
  bool _medExpanded = false;
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
  bool _goalsExpanded = false;
  bool _summaryEnabled = false;
  TimeOfDay _summaryTime = const TimeOfDay(hour: 9, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadData();
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
    _waterReminders = await DatabaseService.getReminders(type: 'water');
    _mealReminders = await DatabaseService.getReminders(type: 'meal');
    _medicines = await DatabaseService.getMedicines();

    // Load goals
    _calCtrl.text = '${await DatabaseService.getSettingInt('cal_goal', 1800)}';
    _protCtrl.text = '${await DatabaseService.getSettingInt('prot_goal', 120)}';
    _carbCtrl.text = '${await DatabaseService.getSettingInt('carb_goal', 200)}';
    _fatCtrl.text = '${await DatabaseService.getSettingInt('fat_goal', 60)}';
    _waterCtrl.text = '${await DatabaseService.getSettingInt('water_goal', 3000)}';

    // Load height
    final h = await DatabaseService.getSettingDouble('height_cm', 0);
    _heightCtrl.text = h > 0 ? h.toStringAsFixed(0) : '';

    // Load summary notification config
    _summaryEnabled = await DatabaseService.getSettingBool('summary_enabled', false);
    final sHour = await DatabaseService.getSettingInt('summary_hour', 9);
    final sMin = await DatabaseService.getSettingInt('summary_minute', 0);
    _summaryTime = TimeOfDay(hour: sHour, minute: sMin);

    if (mounted) setState(() {});
  }

  Future<void> _saveGoals() async {
    await DatabaseService.setSetting('cal_goal', _calCtrl.text.trim());
    await DatabaseService.setSetting('prot_goal', _protCtrl.text.trim());
    await DatabaseService.setSetting('carb_goal', _carbCtrl.text.trim());
    await DatabaseService.setSetting('fat_goal', _fatCtrl.text.trim());
    await DatabaseService.setSetting('water_goal', _waterCtrl.text.trim());
    // Reload goals into the provider
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
      // Send a test notification immediately so user sees it works
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
      await DatabaseService.updateReminder(
        reminder['id'] as int,
        result['label'],
        result['hour'],
        result['minute'],
      );
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
                      Text(
                        selectedTime.format(ctx),
                        style: const TextStyle(color: AppColors.onSurface, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
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
                Navigator.pop(ctx, {
                  'label': label,
                  'hour': selectedTime.hour,
                  'minute': selectedTime.minute,
                });
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
                const Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'DMSerifDisplay', color: AppColors.onSurface)),
              ],
            ),
            const SizedBox(height: 16),

            // ── Daily Goals (Collapsible) ──
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => setState(() => _goalsExpanded = !_goalsExpanded),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('🎯 Daily Goals', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                            const SizedBox(height: 2),
                            Text(
                              _goalsExpanded ? 'Tap to collapse' : '${_calCtrl.text} kcal · P:${_protCtrl.text}g · ${_waterCtrl.text}ml',
                              style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                        Icon(
                          _goalsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 20, color: AppColors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                  if (_goalsExpanded) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _goalField('Calories', _calCtrl, 'kcal')),
                        const SizedBox(width: 8),
                        Expanded(child: _goalField('Protein', _protCtrl, 'g')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _goalField('Carbs', _carbCtrl, 'g')),
                        const SizedBox(width: 8),
                        Expanded(child: _goalField('Fat', _fatCtrl, 'g')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _goalField('Water', _waterCtrl, 'ml')),
                        const SizedBox(width: 8),
                        Expanded(child: _goalField('Height', _heightCtrl, 'cm')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          await _saveGoals();
                          await _saveHeight();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.surface,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Save Goals', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Notifications Permission ──
            AppCard(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('🔔 Notifications', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                            const SizedBox(height: 4),
                            Text(
                              _notificationsEnabled ? 'Enabled — reminders are active' : 'Disabled — tap to enable',
                              style: TextStyle(fontSize: 11, color: _notificationsEnabled ? AppColors.primary : AppColors.error),
                            ),
                          ],
                        ),
                      ),
                      if (!_notificationsEnabled)
                        ElevatedButton(
                          onPressed: _requestPermission,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.surface,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Enable', style: TextStyle(fontSize: 12)),
                        )
                      else
                        const Icon(Icons.check_circle, color: AppColors.primary, size: 24),
                    ],
                  ),
                  if (_notificationsEnabled) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await NotificationService.sendTestNotification();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('🔔 Test notification sent! Check your notification bar.')),
                            );
                          }
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
                    // ── Daily Summary Toggle ──
                    Row(
                      children: [
                        const Text('📋', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Daily Summary', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                              Text(
                                _summaryEnabled
                                    ? 'Receive at ${_summaryTime.format(context)}'
                                    : 'Disabled',
                                style: TextStyle(fontSize: 10, color: _summaryEnabled ? AppColors.primary : AppColors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        if (_summaryEnabled)
                          TextButton(
                            onPressed: () async {
                              final t = await showTimePicker(context: context, initialTime: _summaryTime);
                              if (t != null) {
                                setState(() => _summaryTime = t);
                                await DatabaseService.setSetting('summary_hour', '${t.hour}');
                                await DatabaseService.setSetting('summary_minute', '${t.minute}');
                                await NotificationService.rescheduleAll(force: true);
                              }
                            },
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            child: Text(_summaryTime.format(context), style: const TextStyle(fontSize: 11, color: AppColors.primary)),
                          ),
                        Switch(
                          value: _summaryEnabled,
                          activeColor: AppColors.primary,
                          onChanged: (v) async {
                            setState(() => _summaryEnabled = v);
                            await DatabaseService.setSettingBool('summary_enabled', v);
                            await NotificationService.rescheduleAll(force: true);
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Medicine Reminders ──
            _buildCollapsibleSection(
              emoji: '💊',
              title: 'Medicine Reminders',
              subtitle: 'Auto-synced from your medicines',
              items: _medicines,
              expanded: _medExpanded,
              collapseAfter: 3,
              onToggle: () => setState(() => _medExpanded = !_medExpanded),
              itemBuilder: (med) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(_getMedEmoji(med['type'] as String? ?? 'tablet'), style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(med['name'] as String, style: const TextStyle(fontSize: 12, color: AppColors.onSurface))),
                    Text(med['reminder_time'] as String, style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Water Reminders ──
            _buildCollapsibleSection(
              emoji: '💧',
              title: 'Water Reminders',
              subtitle: '${_waterReminders.length} reminders set',
              items: _waterReminders,
              expanded: _waterExpanded,
              collapseAfter: 4,
              onToggle: () => setState(() => _waterExpanded = !_waterExpanded),
              onAdd: () => _addReminder('water'),
              itemBuilder: (r) => Dismissible(
                key: ValueKey('wr_${r['id']}'),
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
                        const Text('💧', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(r['label'] as String, style: const TextStyle(fontSize: 12, color: AppColors.onSurface))),
                        Text(
                          '${(r['hour'] as int).toString().padLeft(2, '0')}:${(r['minute'] as int).toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 11, color: AppColors.water, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit_outlined, size: 14, color: AppColors.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Meal Reminders ──
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🍽️ Meal Reminders', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                          Text('${_mealReminders.length} reminders set', style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: AppColors.primary, size: 20),
                        onPressed: () => _addReminder('meal'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (_mealReminders.isEmpty)
                    const Text('No meal reminders. Tap + to add.', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant))
                  else
                    ..._mealReminders.map((r) => Dismissible(
                      key: ValueKey('mr_${r['id']}'),
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
                              const Text('🍽️', style: TextStyle(fontSize: 14)),
                              const SizedBox(width: 8),
                              Expanded(child: Text(r['label'] as String, style: const TextStyle(fontSize: 12, color: AppColors.onSurface))),
                              Text(
                                '${(r['hour'] as int).toString().padLeft(2, '0')}:${(r['minute'] as int).toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 11, color: AppColors.secondary, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.edit_outlined, size: 14, color: AppColors.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    )),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Data Management ──
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💾 Data Management', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                  const SizedBox(height: 4),
                  const Text(
                    'Export or restore your health data.',
                    style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),

                  // ── Export Buttons Row ──
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isExporting ? null : _exportData,
                          icon: _isExporting
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                              : const Icon(Icons.upload_rounded, size: 16),
                          label: const Text('JSON Backup'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.surface,
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
                            backgroundColor: const Color(0xFF217346),
                            foregroundColor: AppColors.surface,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'DMSans'),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // ── Import Button ──
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
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.error),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Text(
                          'Import will overwrite ALL existing data.',
                          style: TextStyle(fontSize: 10, color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportData() async {
    setState(() => _isExporting = true);
    try {
      final jsonStr = await DatabaseService.exportAllData();
      final now = DateTime.now();
      final fileName =
          'health_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.json';

      // Write to a temp file then share it
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
    // Step 1: confirm they really want to overwrite
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

    // Step 2: pick the file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;

    setState(() => _isImporting = true);
    try {
      final file = File(result.files.single.path!);
      final jsonStr = await file.readAsString();
      // Basic sanity check
      jsonDecode(jsonStr); // throws if invalid JSON

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

  Widget _buildCollapsibleSection({
    required String emoji,
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> items,
    required bool expanded,
    required int collapseAfter,
    required VoidCallback onToggle,
    required Widget Function(Map<String, dynamic>) itemBuilder,
    VoidCallback? onAdd,
  }) {
    final showToggle = items.length > collapseAfter;
    final visibleItems = expanded ? items : items.take(collapseAfter).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$emoji $title', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                ],
              ),
              if (onAdd != null)
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: AppColors.primary, size: 20),
                  onPressed: onAdd,
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            Text('No $title set.', style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant))
          else ...[
            ...visibleItems.map(itemBuilder),
            if (showToggle) ...[
              if (!expanded)
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.transparent],
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: const SizedBox(height: 8),
                ),
              Center(
                child: TextButton(
                  onPressed: onToggle,
                  child: Text(
                    expanded ? 'Show less' : 'Show all (${items.length})',
                    style: const TextStyle(fontSize: 12, color: AppColors.primary),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
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
        filled: true,
        fillColor: AppColors.surfaceContainerHigh,
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

      // ── Food Log sheet ──
      final foodSheet = excel['Food Log'];
      foodSheet.appendRow([
        xl.TextCellValue('Date'), xl.TextCellValue('Item'),
        xl.TextCellValue('Calories'), xl.TextCellValue('Protein (g)'),
        xl.TextCellValue('Carbs (g)'), xl.TextCellValue('Fats (g)'),
      ]);
      final foods = await db.query('food_logs', orderBy: 'date DESC, id DESC');
      for (final f in foods) {
        foodSheet.appendRow([
          xl.TextCellValue(f['date'] as String),
          xl.TextCellValue(f['item'] as String),
          xl.IntCellValue(f['calories'] as int),
          xl.IntCellValue(f['protein'] as int),
          xl.IntCellValue(f['carbs'] as int),
          xl.IntCellValue(f['fats'] as int),
        ]);
      }

      // ── Water Log sheet ──
      final waterSheet = excel['Water Log'];
      waterSheet.appendRow([
        xl.TextCellValue('Date'), xl.TextCellValue('Amount (ml)'),
        xl.TextCellValue('Type'), xl.TextCellValue('Logged At'),
      ]);
      final waters = await db.query('water_logs', orderBy: 'date DESC, id DESC');
      for (final w in waters) {
        waterSheet.appendRow([
          xl.TextCellValue(w['date'] as String),
          xl.IntCellValue(w['ml'] as int),
          xl.TextCellValue((w['type'] as String?) ?? 'water'),
          xl.TextCellValue((w['created_at'] as String?) ?? ''),
        ]);
      }

      // ── Weight Log sheet ──
      final weightSheet = excel['Weight Log'];
      weightSheet.appendRow([xl.TextCellValue('Date'), xl.TextCellValue('Weight (kg)')]);
      final weights = await db.query('weight_logs', orderBy: 'date DESC');
      for (final w in weights) {
        weightSheet.appendRow([
          xl.TextCellValue(w['date'] as String),
          xl.DoubleCellValue(w['weight_kg'] as double),
        ]);
      }

      // ── Fasting Log sheet ──
      final fastSheet = excel['Fasting Log'];
      fastSheet.appendRow([
        xl.TextCellValue('Start'), xl.TextCellValue('End'),
        xl.TextCellValue('Duration (min)'),
      ]);
      final fasts = await db.query('fasting_logs', orderBy: 'id DESC');
      for (final f in fasts) {
        fastSheet.appendRow([
          xl.TextCellValue(f['start_time'] as String),
          xl.TextCellValue((f['end_time'] as String?) ?? 'Active'),
          xl.IntCellValue((f['duration_min'] as int?) ?? 0),
        ]);
      }

      // ── Sleep Log sheet ──
      final sleepSheet = excel['Sleep Log'];
      sleepSheet.appendRow([
        xl.TextCellValue('Start'), xl.TextCellValue('End'),
        xl.TextCellValue('Duration (min)'),
      ]);
      final sleeps = await db.query('sleep_logs', orderBy: 'id DESC');
      for (final s in sleeps) {
        sleepSheet.appendRow([
          xl.TextCellValue(s['start_time'] as String),
          xl.TextCellValue((s['end_time'] as String?) ?? 'Active'),
          xl.IntCellValue((s['duration_min'] as int?) ?? 0),
        ]);
      }

      // Remove default Sheet1
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

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
