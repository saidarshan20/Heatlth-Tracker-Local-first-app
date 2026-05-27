import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/dashboard_provider.dart';
import '../services/database_service.dart';
import '../services/gemini_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../main.dart' show activeTabNotifier;
import 'health_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Incremented each time this tab becomes active — changing the key forces
  // StaggerItem / EntranceFade widgets to rebuild and replay their animations.
  int _animationEpoch = 0;
  bool _isActivityExpanded = false;

  @override
  void initState() {
    super.initState();
    activeTabNotifier.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    activeTabNotifier.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (activeTabNotifier.value == 0 && mounted) {
      setState(() => _animationEpoch++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, dash, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            // ── Header ──
            StaggerItem(
              key: ValueKey('home_header_$_animationEpoch'),
              index: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dash.dateLabel, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                      Text('${dash.greeting}, Sai 👋',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'DMSerifDisplay', color: AppColors.onSurface)),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                    child: Container(
                      width: 40, height: 40,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primaryContainer),
                      alignment: Alignment.center,
                      child: const Text('🧑', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Calorie + Macros ──
            StaggerItem(
              key: ValueKey('home_cal_$_animationEpoch'),
              index: 1,
              child: AppCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        CalorieRing(consumed: dash.totalCal, goal: DashboardProvider.calGoal),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Remaining', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                              Text(
                                '${dash.calRemaining > 0 ? dash.calRemaining : 0}',
                                style: TextStyle(
                                  fontSize: 26, fontWeight: FontWeight.w800,
                                  color: dash.calRemaining > 0 ? AppColors.primary : AppColors.error,
                                ),
                              ),
                              const Text('kcal left', style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    MacroBar(label: 'Protein', current: dash.totalProt, goal: DashboardProvider.protGoal, color: AppColors.primary),
                    MacroBar(label: 'Carbs', current: dash.totalCarb, goal: DashboardProvider.carbGoal, color: AppColors.secondary),
                    MacroBar(label: 'Fat', current: dash.totalFat, goal: DashboardProvider.fatGoal, color: const Color(0xFFA8D8CB)),
                  ],
                ),
              ),
            ),

            // ── Water ──
            StaggerItem(
              key: ValueKey('home_water_$_animationEpoch'),
              index: 2,
              child: AppCard(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('💧 Water Intake', style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                            const SizedBox(height: 4),
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(fontFamily: 'DMSans'),
                                children: [
                                  TextSpan(text: '${dash.totalWater} ',
                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                                  TextSpan(text: '/ ${DashboardProvider.waterGoal} ml',
                                      style: const TextStyle(fontSize: 14, color: AppColors.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () async {
                                final data = await DatabaseService.getDailyWaterHistory();
                                if (context.mounted) {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (_) => WaterHistorySheet(data: data),
                                  );
                                }
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('History', style: TextStyle(fontSize: 11, color: AppColors.water)),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: List.generate(12, (i) {
                                final totalBars = (dash.totalWater / (DashboardProvider.waterGoal / 12)).round();
                                final softDrinkBars = (dash.softDrinkWater / (DashboardProvider.waterGoal / 12)).round();
                                final waterBars = totalBars - softDrinkBars;
                                Color barColor;
                                if (i < waterBars) {
                                  barColor = AppColors.water;
                                } else if (i < totalBars) {
                                  barColor = const Color(0xFF9C27B0);
                                } else {
                                  barColor = AppColors.surfaceContainerHigh;
                                }
                                return Container(
                                  width: 8, height: 28, margin: const EdgeInsets.only(left: 3),
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: barColor),
                                );
                              }),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    WaterWave(
                      value: dash.totalWater / DashboardProvider.waterGoal,
                      height: 10,
                    ),
                  ],
                ),
              ),
            ),

            // ── Medicines ──
            StaggerItem(
              key: ValueKey('home_meds_$_animationEpoch'),
              index: 3,
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💊 Today\'s Medicines', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                    if (dash.medicines.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No medicines. Go to Health → Add.',
                            style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                      ),
                    ...dash.medicines.map((m) {
                      final taken = dash.isMedTaken(m['id'] as int);
                      return MedicineRow(
                        time: m['reminder_time'] as String,
                        name: m['name'] as String,
                        emoji: dash.getMedEmoji(m['type'] as String? ?? 'tablet'),
                        taken: taken,
                        onTap: () async {
                          if (taken) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${m['name']} already taken.'),
                                action: SnackBarAction(
                                  label: 'Undo', textColor: AppColors.primary,
                                  onPressed: () async {
                                    await dash.undoMedicine(m['id'] as int);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('↩️ ${m['name']} undone. 💧 250ml water removed.')),
                                      );
                                    }
                                  },
                                ),
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          } else {
                            await dash.takeMedicine(m['id'] as int);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('✅ ${m['name']} taken! 💧 +250ml water logged.')),
                              );
                            }
                          }
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),

            // ── Quick Water Buttons + Custom ──
            StaggerItem(
              key: ValueKey('home_quickwater_$_animationEpoch'),
              index: 4,
              child: Column(
                children: [
                  Row(
                    children: [
                      // +250ml water
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: OutlinedButton(
                            onPressed: () async {
                              await dash.addWater(250);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('💧 +250ml water logged!')),
                                );
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              side: const BorderSide(color: AppColors.outline),
                              backgroundColor: AppColors.surfaceContainer,
                            ),
                            child: const Text('+250ml', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12)),
                          ),
                        ),
                      ),
                      // +500ml water
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: OutlinedButton(
                            onPressed: () async {
                              await dash.addWater(500);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('💧 +500ml water logged!')),
                                );
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              side: const BorderSide(color: AppColors.outline),
                              backgroundColor: AppColors.surfaceContainer,
                            ),
                            child: const Text('+500ml', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12)),
                          ),
                        ),
                      ),
                      // Pinned drink button (or Thumbs Up default)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _PinnedDrinkButton(dash: dash),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton(
                      onPressed: () => _showWaterCustomSheet(context, dash),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('+ Custom amount', style: TextStyle(color: AppColors.water, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),

            // ── Today's Activity (water + medicine logs) ──
            StaggerItem(
              key: ValueKey('home_activity_$_animationEpoch'),
              index: 5,
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _isActivityExpanded = !_isActivityExpanded),
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('📋 Today\'s Activity',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                          Icon(
                            _isActivityExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                            color: AppColors.onSurfaceVariant,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                    
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _isActivityExpanded ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
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
                                child: Row(children: [
                                  Text(dash.getMedEmoji(ml['type'] as String? ?? 'tablet'),
                                      style: const TextStyle(fontSize: 14)),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(ml['name'] as String,
                                      style: const TextStyle(fontSize: 12, color: AppColors.onSurface))),
                                  Text(ml['taken_at'] as String,
                                      style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                                ]),
                              ),
                            )),
                            const Divider(height: 16, color: AppColors.outline),
                          ],

                          if (dash.waterEntries.isNotEmpty) ...[
                            const Text('Water intake:', style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                            const SizedBox(height: 4),
                            ...dash.waterEntries.map((w) {
                              final isSoftDrink = (w['type'] ?? 'water') == 'soft_drink';
                              final drinkName = w['drink_name'] as String?;
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
                                  child: Row(children: [
                                    Text(isSoftDrink
                                        ? DashboardProvider.drinkEmoji(drinkName ?? '')
                                        : '💧', style: const TextStyle(fontSize: 14)),
                                    const SizedBox(width: 8),
                                    Text('+${w['ml']}ml',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                            color: isSoftDrink ? const Color(0xFF9C27B0) : AppColors.water)),
                                    if (isSoftDrink && drinkName != null) ...[
                                      const SizedBox(width: 6),
                                      Text(DashboardProvider.drinkDisplayName(drinkName),
                                          style: const TextStyle(fontSize: 10, color: Color(0xFF9C27B0))),
                                    ],
                                    const Spacer(),
                                    Builder(builder: (ctx) {
                                      String timeStr = '';
                                      if (w['created_at'] != null) {
                                        try {
                                          final raw = '${w['created_at'].toString().replaceAll(' ', 'T')}Z';
                                          final dt = DateTime.parse(raw).toLocal();
                                          final h = dt.hour.toString().padLeft(2, '0');
                                          final m = dt.minute.toString().padLeft(2, '0');
                                          timeStr = '$h:$m';
                                        } catch (_) {}
                                      }
                                      return Text(timeStr, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant));
                                    }),
                                  ]),
                                ),
                              );
                            }),
                          ],

                          if (dash.medicineLogsToday.isEmpty && dash.waterEntries.isEmpty)
                            const Text('Nothing logged yet today.',
                                style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                        ],
                      ) : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),

          ],
        );
      },
    );
  }

  void _showWaterCustomSheet(BuildContext context, DashboardProvider dash) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WaterCustomSheet(dash: dash),
    );
  }
}

// ── Pinned drink quick-button ──
class _PinnedDrinkButton extends StatelessWidget {
  final DashboardProvider dash;
  const _PinnedDrinkButton({required this.dash});

  @override
  Widget build(BuildContext context) {
    final hasPinned = dash.pinnedDrink.isNotEmpty;
    final label = hasPinned
        ? '+${dash.pinnedDrinkMl}ml ${DashboardProvider.drinkEmoji(dash.pinnedDrink)}'
        : '+250ml 🥤';

    return OutlinedButton(
      onPressed: () async {
        if (hasPinned) {
          final messenger = ScaffoldMessenger.of(context);
          final name = DashboardProvider.drinkDisplayName(dash.pinnedDrink, otherName: dash.pinnedDrinkName);
          await dash.addDrinkEntry(dash.pinnedDrinkMl, dash.pinnedDrink, otherName: dash.pinnedDrinkName);
          messenger.showSnackBar(SnackBar(content: Text('${DashboardProvider.drinkEmoji(dash.pinnedDrink)} +${dash.pinnedDrinkMl}ml $name logged!')));
        } else {
          await dash.addThumbsUp();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('🥤 Thumbs Up logged! +250ml +110kcal')),
            );
          }
        }
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: Color(0xFF9C27B0)),
        backgroundColor: AppColors.surfaceContainer,
      ),
      child: Text(label,
          style: const TextStyle(color: Color(0xFF9C27B0), fontWeight: FontWeight.w600, fontSize: 12),
          overflow: TextOverflow.ellipsis),
    );
  }
}

// ── Water Custom Amount Bottom Sheet ──
class _WaterCustomSheet extends StatefulWidget {
  final DashboardProvider dash;
  const _WaterCustomSheet({required this.dash});

  @override
  State<_WaterCustomSheet> createState() => _WaterCustomSheetState();
}

class _WaterCustomSheetState extends State<_WaterCustomSheet> {
  final _mlCtrl = TextEditingController(text: '250');
  final _nameCtrl = TextEditingController();
  String _selectedDrink = 'water'; // default
  bool _loading = false;

  static const _drinks = [
    ('water',     '💧', 'Water'),
    ('thumbs_up', '🥤', 'Thumbs Up'),
    ('coke',      '🥤', 'Coke'),
    ('coke_zero', '🫙', 'Coke Zero'),
    ('diet_coke', '🥤', 'Diet Coke'),
    ('other',     '🧃', 'Other'),
  ];

  @override
  void initState() {
    super.initState();
    // Pre-select pinned drink in the selector (but don't hide it if pinned)
    final pinned = widget.dash.pinnedDrink;
    if (pinned.isNotEmpty) _selectedDrink = pinned;
  }

  @override
  void dispose() {
    _mlCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _isPinned => widget.dash.pinnedDrink == _selectedDrink && _selectedDrink != 'water';

  Future<void> _confirm() async {
    final ml = int.tryParse(_mlCtrl.text.trim()) ?? 0;
    if (ml <= 0) return;

    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    try {
      if (_selectedDrink == 'water') {
        await widget.dash.addWater(ml);
        messenger.showSnackBar(SnackBar(content: Text('💧 +${ml}ml water logged!')));
      } else if (_selectedDrink == 'other') {
        final drinkName = _nameCtrl.text.trim();
        if (drinkName.isEmpty) {
          messenger.showSnackBar(const SnackBar(content: Text('Please enter a drink name.')));
          setState(() => _loading = false);
          return;
        }
        // Use the AI parser to fetch nutrition
        final result = await GeminiService.parseFood('${ml}ml $drinkName drink');
        if (!mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Confirm: $drinkName ${ml}ml',
                style: const TextStyle(color: AppColors.onSurface, fontSize: 15, fontWeight: FontWeight.w700)),
            content: result == null
                ? const Text('Could not fetch nutrition. Will log as 0 kcal.',
                    style: TextStyle(color: AppColors.onSurfaceVariant))
                : Text(
                    '~${result['calories']} kcal · P:${result['protein']}g · C:${result['carbs']}g · F:${result['fats']}g',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant))),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.surface),
                  child: const Text('Add')),
            ],
          ),
        );
        if (confirm != true) { setState(() => _loading = false); return; }
        await widget.dash.addDrinkEntry(ml, 'other',
          otherName: drinkName,
          overrideKcal:    result != null ? (result['calories'] as num).toInt() : 0,
          overrideCarbs:   result != null ? (result['carbs']    as num).toInt() : 0,
          overrideProtein: result != null ? (result['protein']  as num).toInt() : 0,
          overrideFat:     result != null ? (result['fats']     as num).toInt() : 0,
        );
        messenger.showSnackBar(SnackBar(content: Text('🧃 +${ml}ml $drinkName logged!')));
      } else {
        await widget.dash.addDrinkEntry(ml, _selectedDrink);
        final name = DashboardProvider.drinkDisplayName(_selectedDrink);
        final emoji = DashboardProvider.drinkEmoji(_selectedDrink);
        messenger.showSnackBar(SnackBar(content: Text('$emoji +${ml}ml $name logged!')));
      }
      nav.pop();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePin() async {
    if (_selectedDrink == 'water') return;
    final ml = int.tryParse(_mlCtrl.text.trim()) ?? 250;
    final name = _selectedDrink == 'other' ? _nameCtrl.text.trim() : null;
    if (_isPinned) {
      await widget.dash.clearPinnedDrink();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📌 Unpinned drink')),
        );
      }
    } else {
      await widget.dash.setPinnedDrink(_selectedDrink, ml, otherName: name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('📌 ${DashboardProvider.drinkDisplayName(_selectedDrink, otherName: name)} pinned!')),
        );
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(99))),
            ),
            const SizedBox(height: 16),
            const Text('Custom Drink Amount',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
            const SizedBox(height: 16),

            // ml input
            TextField(
              controller: _mlCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.onSurface, fontSize: 15),
              decoration: InputDecoration(
                labelText: 'Amount',
                suffixText: 'ml',
                suffixStyle: const TextStyle(color: AppColors.onSurfaceVariant),
                filled: true, fillColor: AppColors.surfaceContainerHigh,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),

            // Drink selector
            const Text('Drink type', style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _drinks.map((d) {
                final key = d.$1; final emoji = d.$2; final label = d.$3;
                final isPinnedDrink = widget.dash.pinnedDrink == key;
                final selected = _selectedDrink == key;
                return FilterChip(
                  label: Text('$emoji $label${isPinnedDrink ? ' 📌' : ''}',
                      style: TextStyle(fontSize: 12,
                          color: selected ? AppColors.primary : AppColors.onSurfaceVariant)),
                  selected: selected,
                  selectedColor: AppColors.primaryContainer,
                  backgroundColor: AppColors.surfaceContainerHigh,
                  checkmarkColor: AppColors.primary,
                  side: BorderSide(color: selected ? AppColors.primary : AppColors.outline),
                  showCheckmark: false,
                  onSelected: (_) => setState(() {
                    _selectedDrink = selected ? 'water' : key; // toggle off resets to water
                  }),
                );
              }).toList(),
            ),

            // Other drink name field
            if (_selectedDrink == 'other') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: AppColors.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Drink name (e.g. Maaza, Frooti)',
                  filled: true, fillColor: AppColors.surfaceContainerHigh,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Pin toggle (not for water)
            if (_selectedDrink != 'water')
              Row(
                children: [
                  Icon(
                    _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 16, color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: _togglePin,
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero, minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: Text(
                      _isPinned ? 'Unpin this drink' : 'Pin this drink to quick button',
                      style: const TextStyle(fontSize: 12, color: AppColors.primary),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.water, foregroundColor: AppColors.surface,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                    : const Text('Add', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
