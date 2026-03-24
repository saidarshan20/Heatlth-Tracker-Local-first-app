import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    _notificationsEnabled = await NotificationService.checkPermission();
    _waterReminders = await DatabaseService.getReminders(type: 'water');
    _mealReminders = await DatabaseService.getReminders(type: 'meal');
    _medicines = await DatabaseService.getMedicines();
    if (mounted) setState(() {});
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
      await NotificationService.rescheduleAll();
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
      await NotificationService.rescheduleAll();
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
    await NotificationService.rescheduleAll();
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
          ],
        ),
      ),
    );
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
}
