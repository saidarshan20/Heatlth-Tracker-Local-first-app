import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/dashboard_provider.dart';
import '../services/database_service.dart';
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
    if (_activeFast != null) _startTimer();
    if (mounted) setState(() {});
  }

  void _startTimer() {
    _fastTimer?.cancel();
    _fastTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeFast == null) return;
      final start = DateTime.parse(_activeFast!['start_time']);
      setState(() { _elapsed = DateTime.now().difference(start); });
    });
  }

  Future<void> _startFast() async {
    await DatabaseService.startFast(DateTime.now().toIso8601String());
    await _loadData();
  }

  Future<void> _endFast() async {
    if (_activeFast == null) return;
    final start = DateTime.parse(_activeFast!['start_time']);
    final dur = DateTime.now().difference(start).inMinutes;
    await DatabaseService.endFast(_activeFast!['id'] as int, DateTime.now().toIso8601String(), dur);
    _fastTimer?.cancel();
    setState(() { _activeFast = null; _elapsed = Duration.zero; });
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚡ Fast ended! Duration: ${dur ~/ 60}h ${dur % 60}m')),
      );
    }
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
                  const Text('⚡ Fasting Tracker', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
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
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: AppColors.primary, size: 20),
                        onPressed: _showAddWeightDialog,
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
