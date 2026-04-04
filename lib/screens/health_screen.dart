import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/dashboard_provider.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  Map<String, dynamic>? _activeFast;
  List<Map<String, dynamic>> _weights = [];
  Timer? _fastTimer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _fastTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    _activeFast = await DatabaseService.getActiveFast();
    _weights = await DatabaseService.getWeightHistory();
    if (_activeFast != null) {
      _startTimer();
      // Resume the live notification if a fast was already running
      final start = DateTime.parse(_activeFast!['start_time']);
      await NotificationService.showFastingNotification(start);
    }
    if (mounted) setState(() {});
  }

  int _notifTickCount = 0;

  void _startTimer() {
    _fastTimer?.cancel();
    _notifTickCount = 0;
    _fastTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeFast == null) return;
      final start = DateTime.parse(_activeFast!['start_time']);
      setState(() { _elapsed = DateTime.now().difference(start); });
      // Refresh the live notification every 60 seconds
      _notifTickCount++;
      if (_notifTickCount % 60 == 0) {
        NotificationService.showFastingNotification(start);
      }
    });
    // Tick immediately so elapsed is correct before the first second
    if (_activeFast != null) {
      final start = DateTime.parse(_activeFast!['start_time']);
      setState(() { _elapsed = DateTime.now().difference(start); });
    }
  }

  Future<void> _startFast() async {
    await DatabaseService.startFast(DateTime.now().toIso8601String());
    await _loadData();
    // Show the live notification immediately
    if (_activeFast != null) {
      final start = DateTime.parse(_activeFast!['start_time']);
      await NotificationService.showFastingNotification(start);
    }
  }

  Future<void> _endFast() async {
    if (_activeFast == null) return;
    final start = DateTime.parse(_activeFast!['start_time']);
    final dur = DateTime.now().difference(start).inMinutes;
    await DatabaseService.endFast(_activeFast!['id'] as int, DateTime.now().toIso8601String(), dur);
    _fastTimer?.cancel();
    await NotificationService.cancelFastingNotification();
    setState(() { _activeFast = null; _elapsed = Duration.zero; });
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚡ Fast ended! Duration: ${dur ~/ 60}h ${dur % 60}m')),
      );
      // Automatically open history so user sees their result
      _showFastingHistory();
    }
  }

  Future<void> _showFastingHistory() async {
    final history = await DatabaseService.getFastingHistory();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FastingHistorySheet(history: history),
    );
  }

  void _showAddMedicineDialog() {
    final nameCtrl = TextEditingController();
    TimeOfDay selectedTime = const TimeOfDay(hour: 9, minute: 0);
    String selectedType = 'tablet';

    final types = [
      ('tablet', '💊 Tablet'),
      ('capsule', '💊 Capsule'),
      ('cream', '🧴 Cream'),
      ('drops', '💧 Drops'),
      ('syrup', '🥤 Syrup'),
      ('injection', '💉 Injection'),
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add Medicine', style: TextStyle(color: AppColors.onSurface, fontFamily: 'DMSans')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: AppColors.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Medicine name',
                  hintStyle: const TextStyle(color: AppColors.onSurfaceVariant),
                  filled: true, fillColor: AppColors.surfaceContainerHigh,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              // Type selector
              Wrap(
                spacing: 6, runSpacing: 6,
                children: types.map((t) => ChoiceChip(
                  label: Text(t.$2, style: TextStyle(fontSize: 11, color: selectedType == t.$1 ? AppColors.primary : AppColors.onSurfaceVariant)),
                  selected: selectedType == t.$1,
                  selectedColor: AppColors.primaryContainer,
                  backgroundColor: AppColors.surfaceContainerHigh,
                  side: BorderSide(color: selectedType == t.$1 ? AppColors.primary : AppColors.outline),
                  onSelected: (_) => setDialogState(() => selectedType = t.$1),
                )).toList(),
              ),
              const SizedBox(height: 12),
              // Time picker
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.access_time, color: AppColors.primary),
                title: Text(selectedTime.format(ctx), style: const TextStyle(color: AppColors.onSurface)),
                onTap: () async {
                  final t = await showTimePicker(context: ctx, initialTime: selectedTime);
                  if (t != null) setDialogState(() => selectedTime = t);
                },
              ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant))),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final timeStr = '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
                await context.read<DashboardProvider>().addMedicine(nameCtrl.text.trim(), timeStr, selectedType);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.surface),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddWeightDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log Weight', style: TextStyle(color: AppColors.onSurface, fontFamily: 'DMSans')),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: AppColors.onSurface),
          decoration: InputDecoration(
            hintText: 'e.g. 71.5',
            suffixText: 'kg',
            suffixStyle: const TextStyle(color: AppColors.onSurfaceVariant),
            hintStyle: const TextStyle(color: AppColors.onSurfaceVariant),
            filled: true, fillColor: AppColors.surfaceContainerHigh,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant))),
          ElevatedButton(
            onPressed: () async {
              final w = double.tryParse(ctrl.text);
              if (w == null) return;
              final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
              await DatabaseService.addWeight(today, w);
              await _loadData();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚖️ ${w}kg logged!')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.surface),
            child: const Text('Log'),
          ),
        ],
      ),
    );
  }

  Future<void> _showWeightHistorySheet() async {
    final history = await DatabaseService.getFullWeightHistory();
    final reminder = await DatabaseService.getWeightReminder();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _WeightHistorySheet(initialHistory: history, initialReminder: reminder),
    );
    // Refresh main screen chart after any edits/deletes
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, dash, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            const Text('Health', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'DMSerifDisplay', color: AppColors.onSurface)),
            const Text('Medicines · Fasting · Weight', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 16),

            // ── Medicines ──
            AppCard(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('💊 Medicines', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                      TextButton(
                        onPressed: _showAddMedicineDialog,
                        child: const Text('+ Add', style: TextStyle(fontSize: 11, color: AppColors.primary)),
                      ),
                    ],
                  ),
                  if (dash.medicines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No medicines added yet.', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                    ),
                  ...dash.medicines.map((m) => Dismissible(
                    key: ValueKey('med_${m['id']}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete_outline, color: AppColors.error),
                    ),
                    onDismissed: (_) => dash.deleteMedicine(m['id'] as int),
                    child: MedicineRow(
                      time: m['reminder_time'] as String,
                      name: m['name'] as String,
                      emoji: dash.getMedEmoji(m['type'] as String? ?? 'tablet'),
                      taken: dash.isMedTaken(m['id'] as int),
                      onTap: () async {
                        await dash.takeMedicine(m['id'] as int);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('✅ ${m['name']} taken! 💧 +250ml water logged.')),
                          );
                        }
                      },
                    ),
                  )),
                ],
              ),
            ),

            // ── Fasting ──
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('⚡ Fasting Tracker', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                      TextButton(
                        onPressed: _showFastingHistory,
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        child: const Text('History', style: TextStyle(fontSize: 11, color: AppColors.primary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_activeFast != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _fastStat('${_elapsed.inHours}:${(_elapsed.inMinutes % 60).toString().padLeft(2, '0')}', 'elapsed'),
                        _fastStat('${(16 * 60 - _elapsed.inMinutes).clamp(0, 960) ~/ 60}:${((16 * 60 - _elapsed.inMinutes).clamp(0, 960) % 60).toString().padLeft(2, '0')}', 'remaining'),
                        _fastStat('16h', 'goal'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (_elapsed.inMinutes / (16 * 60)).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: AppColors.surfaceContainerHigh,
                        valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _endFast,
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.error), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: const Text('Break Fast', style: TextStyle(color: AppColors.error)),
                      ),
                    ),
                  ] else ...[
                    const Text('No active fast.', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _startFast,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: const Text('Start Fast'),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Weight ──
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('⚖️ Weight History', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: _showWeightHistorySheet,
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            child: const Text('History', style: TextStyle(fontSize: 11, color: AppColors.primary)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: AppColors.primary, size: 20),
                            onPressed: _showAddWeightDialog,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_weights.isEmpty)
                    const Text('No weight logged yet.', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant))
                  else ...[
                    const SizedBox(height: 8),
                    Row(
                      children: _weights.reversed.map((w) {
                        final kg = (w['weight_kg'] as num).toDouble();
                        final allWeights = _weights.map((e) => (e['weight_kg'] as num).toDouble()).toList();
                        final minW = allWeights.reduce((a, b) => a < b ? a : b);
                        final maxW = allWeights.reduce((a, b) => a > b ? a : b);
                        final range = (maxW - minW).clamp(0.5, double.infinity);
                        final pct = ((kg - minW) / range * 80 + 20).clamp(4.0, 100.0);
                        final isLast = w == _weights.first;
                        return Expanded(
                          child: Column(
                            children: [
                              SizedBox(
                                height: 40,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor: pct / 100,
                                    child: Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.symmetric(horizontal: 3),
                                      decoration: BoxDecoration(
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                        color: isLast ? AppColors.primary : AppColors.surfaceContainerHigh,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text('${kg.toStringAsFixed(1)}', style: TextStyle(fontSize: 8, color: isLast ? AppColors.primary : AppColors.onSurfaceVariant)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    if (_weights.length >= 2) _buildWeightTrend(),
                  ],
                ],
              ),
            ),

            // ── Today's Activity ──
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📋 Today\'s Activity', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                  const SizedBox(height: 8),

                  // Medicine logs
                  if (dash.medicineLogsToday.isNotEmpty) ...[
                    const Text('Medicines taken:', style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    ...dash.medicineLogsToday.map((ml) => Dismissible(
                      key: ValueKey('ml_${ml['id']}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Text('Undo', style: TextStyle(color: AppColors.error, fontSize: 12)),
                      ),
                      onDismissed: (_) async {
                        await dash.undoMedicine(ml['medicine_id'] as int);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('↩️ ${ml['name']} undone')),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Text(dash.getMedEmoji(ml['type'] as String? ?? 'tablet'), style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(ml['name'] as String, style: const TextStyle(fontSize: 12, color: AppColors.onSurface))),
                            Text(ml['taken_at'] as String, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    )),
                    const Divider(height: 16, color: AppColors.outline),
                  ],

                  // Water logs
                  if (dash.waterEntries.isNotEmpty) ...[
                    const Text('Water intake:', style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    ...dash.waterEntries.map((w) {
                      final isSoftDrink = (w['type'] ?? 'water') == 'soft_drink';
                      return Dismissible(
                        key: ValueKey('water_${w['id']}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          child: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
                        ),
                        onDismissed: (_) async {
                          await dash.deleteWater(w['id'] as int);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('🗑️ ${w['ml']}ml deleted')),
                            );
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Text(isSoftDrink ? '🥤' : '💧', style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 8),
                              Text(
                                '+${w['ml']}ml',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSoftDrink ? const Color(0xFF9C27B0) : AppColors.water,
                                ),
                              ),
                              if (isSoftDrink) ...[
                                const SizedBox(width: 6),
                                const Text('Soft drink', style: TextStyle(fontSize: 10, color: Color(0xFF9C27B0))),
                              ],
                              const Spacer(),
                              Builder(
                                builder: (ctx) {
                                  String timeStr = '';
                                  if (w['created_at'] != null) {
                                    try {
                                      final raw = w['created_at'].toString().replaceAll(' ', 'T') + 'Z';
                                      final dt = DateTime.parse(raw).toLocal();
                                      timeStr = DateFormat('hh:mm a').format(dt);
                                    } catch (_) {}
                                  }
                                  return Text(timeStr, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant));
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],

                  if (dash.medicineLogsToday.isEmpty && dash.waterEntries.isEmpty)
                    const Text('No activity logged yet today.', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWeightTrend() {
    final current = (_weights.first['weight_kg'] as num).toDouble();
    final oldest = (_weights.last['weight_kg'] as num).toDouble();
    final diff = current - oldest;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        RichText(text: TextSpan(style: const TextStyle(fontFamily: 'DMSans', fontSize: 11, color: AppColors.onSurfaceVariant), children: [
          const TextSpan(text: 'Current: '),
          TextSpan(text: '${current.toStringAsFixed(1)} kg', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
        ])),
        Text(
          '${diff > 0 ? "↑" : "↓"} ${diff.abs().toStringAsFixed(1)} kg',
          style: TextStyle(fontSize: 11, color: diff > 0 ? AppColors.error : AppColors.primary),
        ),
      ],
    );
  }

  Widget _fastStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.primary)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Fasting History Bottom Sheet
// ─────────────────────────────────────────────
class _FastingHistorySheet extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _FastingHistorySheet({required this.history});

  static const int _goalMinutes = 16 * 60;

  String _fmt(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  String _fmtDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.day} ${months[dt.month - 1]}';
    } catch (_) { return ''; }
  }

  String _fmtTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      return '$h:$m $ampm';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    // Summary stats
    int totalFasts = history.length;
    int bestMin = 0, sumMin = 0;
    for (final f in history) {
      final d = (f['duration_min'] as int?) ?? 0;
      if (d > bestMin) bestMin = d;
      sumMin += d;
    }
    final avgMin = totalFasts > 0 ? sumMin ~/ totalFasts : 0;
    final goalsHit = history.where((f) => ((f['duration_min'] as int?) ?? 0) >= _goalMinutes).length;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(99))),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text('⚡ Fasting History',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                          fontFamily: 'DMSerifDisplay', color: AppColors.onSurface)),
                  const Spacer(),
                  Text('$totalFasts sessions',
                      style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Summary strip ──
            if (totalFasts > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _statChip('🏆 Best', _fmt(bestMin)),
                    const SizedBox(width: 8),
                    _statChip('📊 Avg', _fmt(avgMin)),
                    const SizedBox(width: 8),
                    _statChip('🎯 Goals hit', '$goalsHit / $totalFasts'),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.outline),

            // ── List ──
            Expanded(
              child: history.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('⚡', style: TextStyle(fontSize: 36)),
                          SizedBox(height: 8),
                          Text('No completed fasts yet.',
                              style: TextStyle(fontSize: 14, color: AppColors.onSurfaceVariant)),
                          SizedBox(height: 4),
                          Text('Start your first fast from the Health screen.',
                              style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final f = history[i];
                        final durMin = (f['duration_min'] as int?) ?? 0;
                        final goalMet = durMin >= _goalMinutes;
                        final progress = (durMin / _goalMinutes).clamp(0.0, 1.0);
                        final dateLabel = _fmtDate(f['start_time'] as String);
                        final startLabel = _fmtTime(f['start_time'] as String);
                        final endLabel = _fmtTime(f['end_time'] as String);

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(16),
                            border: goalMet
                                ? Border.all(color: AppColors.primary.withOpacity(0.4), width: 1)
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top row: date + goal pill
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(dateLabel,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                          color: AppColors.onSurface)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: goalMet
                                          ? AppColors.primary.withOpacity(0.15)
                                          : AppColors.surfaceContainer,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      goalMet ? '🎯 Goal met' : '⏱ ${_fmt(durMin)}',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: goalMet ? AppColors.primary : AppColors.onSurfaceVariant),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              // Duration + times
                              Row(
                                children: [
                                  Text(
                                    _fmt(durMin),
                                    style: TextStyle(
                                        fontSize: 22, fontWeight: FontWeight.w800,
                                        color: goalMet ? AppColors.primary : AppColors.onSurface),
                                  ),
                                  const SizedBox(width: 10),
                                  Text('$startLabel → $endLabel',
                                      style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Progress bar
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 5,
                                  backgroundColor: AppColors.surfaceContainer,
                                  valueColor: AlwaysStoppedAnimation(
                                      goalMet ? AppColors.primary : AppColors.onSurfaceVariant),
                                ),
                              ),
                              if (goalMet) ...[
                                const SizedBox(height: 4),
                                Text('+${_fmt(durMin - _goalMinutes)} over goal',
                                    style: const TextStyle(fontSize: 9, color: AppColors.primary)),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 9, color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Weight History Bottom Sheet
// ─────────────────────────────────────────────
class _WeightHistorySheet extends StatefulWidget {
  final List<Map<String, dynamic>> initialHistory;
  final Map<String, dynamic>? initialReminder;
  const _WeightHistorySheet({required this.initialHistory, this.initialReminder});

  @override
  State<_WeightHistorySheet> createState() => _WeightHistorySheetState();
}

class _WeightHistorySheetState extends State<_WeightHistorySheet> {
  late List<Map<String, dynamic>> _history;
  Map<String, dynamic>? _reminder;

  int _selectedWeekday = DateTime.monday;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 8, minute: 0);
  bool _editingReminder = false;

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _history = List.from(widget.initialHistory);
    _reminder = widget.initialReminder;
    if (_reminder != null) {
      _selectedWeekday = int.tryParse(_reminder!['label'].toString()) ?? DateTime.monday;
      _selectedTime = TimeOfDay(hour: _reminder!['hour'] as int, minute: _reminder!['minute'] as int);
    }
  }

  String _fmtDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
    } catch (_) { return dateStr; }
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  Future<void> _editWeight(Map<String, dynamic> entry) async {
    final ctrl = TextEditingController(text: (entry['weight_kg'] as num).toStringAsFixed(1));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Weight', style: TextStyle(color: AppColors.onSurface, fontFamily: 'DMSans')),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          style: const TextStyle(color: AppColors.onSurface),
          decoration: InputDecoration(
            suffixText: 'kg',
            suffixStyle: const TextStyle(color: AppColors.onSurfaceVariant),
            filled: true, fillColor: AppColors.surfaceContainerHigh,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.surface),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final newKg = double.tryParse(ctrl.text);
    if (newKg == null || newKg <= 0) return;
    await DatabaseService.updateWeight(entry['id'] as int, newKg);
    setState(() {
      final idx = _history.indexWhere((e) => e['id'] == entry['id']);
      if (idx != -1) _history[idx] = Map.from(_history[idx])..['weight_kg'] = newKg;
    });
  }

  Future<void> _deleteWeight(Map<String, dynamic> entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Entry?', style: TextStyle(color: AppColors.onSurface)),
        content: Text(
          'Remove ${(entry['weight_kg'] as num).toStringAsFixed(1)} kg on ${_fmtDate(entry['date'] as String)}?',
          style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DatabaseService.deleteWeightById(entry['id'] as int);
    setState(() => _history.removeWhere((e) => e['id'] == entry['id']));
  }

  Future<void> _saveReminder() async {
    await DatabaseService.setWeightReminder(_selectedWeekday, _selectedTime.hour, _selectedTime.minute);
    await NotificationService.scheduleWeeklyWeightReminder(
      weekday: _selectedWeekday, hour: _selectedTime.hour, minute: _selectedTime.minute,
    );
    setState(() {
      _reminder = {'label': '$_selectedWeekday', 'hour': _selectedTime.hour, 'minute': _selectedTime.minute};
      _editingReminder = false;
    });
  }

  Future<void> _clearReminder() async {
    await DatabaseService.clearWeightReminder();
    await NotificationService.cancelWeightReminder();
    setState(() { _reminder = null; _editingReminder = false; });
  }

  @override
  Widget build(BuildContext context) {
    final weights = _history.map((e) => (e['weight_kg'] as num).toDouble()).toList();
    final current = weights.isNotEmpty ? weights.first : null;
    final highest = weights.isNotEmpty ? weights.reduce((a, b) => a > b ? a : b) : null;
    final lowest  = weights.isNotEmpty ? weights.reduce((a, b) => a < b ? a : b) : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.70,
      minChildSize: 0.4,
      maxChildSize: 0.93,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(99))),
            ),
            // Title row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text('\u2696\ufe0f Weight History',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                          fontFamily: 'DMSerifDisplay', color: AppColors.onSurface)),
                  const Spacer(),
                  Text('${_history.length} entries',
                      style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Summary chips
            if (current != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  _statChip('\ud83d\udccd Current', '${current.toStringAsFixed(1)} kg'),
                  const SizedBox(width: 8),
                  _statChip('\ud83d\udcc8 Highest', '${highest!.toStringAsFixed(1)} kg'),
                  const SizedBox(width: 8),
                  _statChip('\ud83d\udcc9 Lowest', '${lowest!.toStringAsFixed(1)} kg'),
                ]),
              ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.outline),
            // Scrollable list (entries + reminder section as last item)
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: _history.isEmpty ? 1 : _history.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  // Last item → reminder section
                  if (_history.isEmpty || i == _history.length) return _buildReminderSection();

                  final entry = _history[i];
                  final kg = (entry['weight_kg'] as num).toDouble();
                  final isLatest = i == 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(14),
                      border: isLatest
                          ? Border.all(color: AppColors.primary.withOpacity(0.4), width: 1)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_fmtDate(entry['date'] as String),
                                  style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                              const SizedBox(height: 2),
                              Text('${kg.toStringAsFixed(1)} kg',
                                  style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700,
                                    color: isLatest ? AppColors.primary : AppColors.onSurface,
                                  )),
                            ],
                          ),
                        ),
                        if (isLatest)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Text('Latest', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.primary)),
                          ),
                        // Edit button
                        InkWell(
                          onTap: () => _editWeight(entry),
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.all(7),
                            child: Icon(Icons.edit_outlined, size: 17, color: AppColors.primary),
                          ),
                        ),
                        // Delete button
                        InkWell(
                          onTap: () => _deleteWeight(entry),
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.all(7),
                            child: Icon(Icons.delete_outline, size: 17, color: AppColors.error),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderSection() {
    final activeWd = _reminder != null
        ? int.tryParse(_reminder!['label'].toString()) ?? DateTime.monday
        : _selectedWeekday;
    final activeTime = _reminder != null
        ? TimeOfDay(hour: _reminder!['hour'] as int, minute: _reminder!['minute'] as int)
        : _selectedTime;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 28, color: AppColors.outline),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('\ud83d\udd14 Weekly Reminder',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
            if (_reminder != null && !_editingReminder)
              TextButton(
                onPressed: () => setState(() => _editingReminder = true),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
                child: const Text('Edit', style: TextStyle(fontSize: 11, color: AppColors.primary)),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Active reminder display ──
        if (_reminder != null && !_editingReminder) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.alarm, color: AppColors.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Every ${_dayLabels[activeWd - 1]} at ${_fmtTime(activeTime)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary),
                  ),
                ),
                TextButton(
                  onPressed: _clearReminder,
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
                  child: const Text('Remove', style: TextStyle(fontSize: 11, color: AppColors.error)),
                ),
              ],
            ),
          ),
        ] else ...[
          // ── Reminder setup UI ──
          const Text('Pick a day to weigh in every week:',
              style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 10),
          // Day chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(7, (i) {
                final wd = i + 1;
                final isSelected = _selectedWeekday == wd;
                return Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedWeekday = wd),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: isSelected ? AppColors.primary : AppColors.outline),
                      ),
                      child: Text(
                        _dayLabels[i],
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: isSelected ? AppColors.surface : AppColors.onSurface,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 12),
          // Time picker
          GestureDetector(
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: _selectedTime);
              if (t != null) setState(() => _selectedTime = t);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.outline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.access_time, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(_fmtTime(_selectedTime),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.onSurfaceVariant),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveReminder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary, foregroundColor: AppColors.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Set Reminder'),
                ),
              ),
              if (_editingReminder) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _editingReminder = false),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _statChip(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 9, color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────
// Water History Bottom Sheet
// ─────────────────────────────────────────────
class WaterHistorySheet extends StatefulWidget {
  final Map<String, dynamic> data;
  const WaterHistorySheet({super.key, required this.data});

  @override
  State<WaterHistorySheet> createState() => WaterHistorySheetState();
}

class WaterHistorySheetState extends State<WaterHistorySheet> {
  final Set<int> _expandedIndices = {};

  static const int _goalMl = 2500;

  String _fmtDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
      return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]}';
    } catch (_) { return dateStr; }
  }

  String _fmtTime(String? createdAt) {
    if (createdAt == null) return '';
    try {
      final raw = createdAt.replaceAll(' ', 'T') + 'Z';
      final dt = DateTime.parse(raw).toLocal();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ap = dt.hour < 12 ? 'AM' : 'PM';
      return '$h:$m $ap';
    } catch (_) { return ''; }
  }

  Color _barColor(int ml) {
    if (ml >= _goalMl) return AppColors.water;
    if (ml >= _goalMl * 0.7) return AppColors.water.withOpacity(0.6);
    return AppColors.error.withOpacity(0.5);
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.data['days'] as List<dynamic>;
    final peak = widget.data['peak'] as Map<String, dynamic>?;
    final lowest = widget.data['lowest'] as Map<String, dynamic>?;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Drag handle ──
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(99)),
              ),
            ),

            // ── Title ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text('💧 Water History',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                          fontFamily: 'DMSerifDisplay', color: AppColors.onSurface)),
                  const Spacer(),
                  Text('${days.length} days',
                      style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Peak / Lowest stat chips ──
            if (peak != null && lowest != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // Highest
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.water.withOpacity(0.18), AppColors.water.withOpacity(0.06)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.water.withOpacity(0.35)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Text('🏆', style: TextStyle(fontSize: 13)),
                                SizedBox(width: 4),
                                Text('Best Day', style: TextStyle(fontSize: 10, color: AppColors.water, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${(peak['total_ml'] as int)} ml',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.water),
                            ),
                            Text(
                              _fmtDate(peak['date'] as String),
                              style: const TextStyle(fontSize: 9, color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Lowest
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.error.withOpacity(0.13), AppColors.error.withOpacity(0.04)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.error.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('📉', style: TextStyle(fontSize: 13)),
                                const SizedBox(width: 4),
                                Text('Lowest Day',
                                    style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${(lowest['total_ml'] as int)} ml',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.error),
                            ),
                            Text(
                              _fmtDate(lowest['date'] as String),
                              style: const TextStyle(fontSize: 9, color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.outline),

            // ── Daily list ──
            Expanded(
              child: days.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('💧', style: TextStyle(fontSize: 40)),
                          SizedBox(height: 8),
                          Text('No water logged yet.',
                              style: TextStyle(fontSize: 14, color: AppColors.onSurfaceVariant)),
                          SizedBox(height: 4),
                          Text('Start logging from the Home screen.',
                              style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                      itemCount: days.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final day = days[i] as Map<String, dynamic>;
                        final totalMl = day['total_ml'] as int;
                        final entries = day['entries'] as List<dynamic>;
                        final pct = (totalMl / _goalMl).clamp(0.0, 1.0);
                        final goalMet = totalMl >= _goalMl;
                        final isExpanded = _expandedIndices.contains(i);
                        final isPeak = peak != null && day['date'] == peak['date'];
                        final isLowest = lowest != null && day['date'] == lowest['date'];

                        return GestureDetector(
                          onTap: () => setState(() {
                            if (isExpanded) _expandedIndices.remove(i);
                            else _expandedIndices.add(i);
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(16),
                              border: isPeak
                                  ? Border.all(color: AppColors.water.withOpacity(0.45), width: 1.5)
                                  : isLowest
                                      ? Border.all(color: AppColors.error.withOpacity(0.35), width: 1.5)
                                      : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Row: date + badge + ml ──
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(_fmtDate(day['date'] as String),
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                                              if (isPeak) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.water.withOpacity(0.18),
                                                    borderRadius: BorderRadius.circular(99),
                                                  ),
                                                  child: const Text('🏆 Best', style: TextStyle(fontSize: 9, color: AppColors.water, fontWeight: FontWeight.w700)),
                                                ),
                                              ] else if (isLowest) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.error.withOpacity(0.13),
                                                    borderRadius: BorderRadius.circular(99),
                                                  ),
                                                  child: Text('📉 Low', style: TextStyle(fontSize: 9, color: AppColors.error, fontWeight: FontWeight.w700)),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text('${entries.length} log${entries.length == 1 ? '' : 's'}',
                                              style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
                                        ],
                                      ),
                                    ),
                                    // ml + goal badge
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '$totalMl ml',
                                          style: TextStyle(
                                            fontSize: 18, fontWeight: FontWeight.w800,
                                            color: goalMet ? AppColors.water : AppColors.onSurface,
                                          ),
                                        ),
                                        if (goalMet)
                                          const Text('✅ Goal met',
                                              style: TextStyle(fontSize: 9, color: AppColors.water, fontWeight: FontWeight.w600))
                                        else
                                          Text('${_goalMl - totalMl} ml short',
                                              style: TextStyle(fontSize: 9, color: AppColors.error.withOpacity(0.8))),
                                      ],
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                      size: 18, color: AppColors.onSurfaceVariant,
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 8),

                                // ── Progress bar ──
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    value: pct,
                                    minHeight: 5,
                                    backgroundColor: AppColors.surfaceContainer,
                                    valueColor: AlwaysStoppedAnimation(_barColor(totalMl)),
                                  ),
                                ),

                                // ── Expanded: individual entries ──
                                if (isExpanded && entries.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  const Divider(height: 1, color: AppColors.outline),
                                  const SizedBox(height: 8),
                                  ...entries.map((e) {
                                    final entry = e as Map<String, dynamic>;
                                    final isSoft = (entry['type'] ?? 'water') == 'soft_drink';
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        children: [
                                          Text(isSoft ? '🥤' : '💧', style: const TextStyle(fontSize: 12)),
                                          const SizedBox(width: 8),
                                          Text(
                                            '+${entry['ml']} ml',
                                            style: TextStyle(
                                              fontSize: 12, fontWeight: FontWeight.w600,
                                              color: isSoft ? const Color(0xFF9C27B0) : AppColors.water,
                                            ),
                                          ),
                                          if (isSoft) ...[
                                            const SizedBox(width: 5),
                                            const Text('Soft drink', style: TextStyle(fontSize: 9, color: Color(0xFF9C27B0))),
                                          ],
                                          const Spacer(),
                                          Text(_fmtTime(entry['created_at'] as String?),
                                              style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
