import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/database_service.dart';
import '../services/gemini_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Map<String, dynamic>? _stats;
  int _medStreak = 0;
  String? _aiInsights;
  String? _mealPlan;
  bool _loadingPlan = false;
  final _planCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _planCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final stats = await DatabaseService.getWeeklyStats();
    final streak = await DatabaseService.getMedicineStreak();
    setState(() { _stats = stats; _medStreak = streak; });
  }

  Future<void> _getAIInsights() async {
    if (_stats == null) return;
    final insights = await GeminiService.getWeeklyInsights(_stats!);
    if (mounted) setState(() { _aiInsights = insights; });
  }

  Future<void> _getMealPlan() async {
    if (_planCtrl.text.trim().isEmpty) return;
    setState(() { _loadingPlan = true; });
    final plan = await GeminiService.getMealSuggestions(_planCtrl.text.trim());
    if (mounted) setState(() { _mealPlan = plan; _loadingPlan = false; });
  }

  String _streakBadge(int s) {
    if (s >= 100) return '💎';
    if (s >= 30) return '🏆';
    if (s >= 7) return '🔥';
    return '⭐';
  }

  @override
  Widget build(BuildContext context) {
    final dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    // Re-order labels to end on today's weekday
    final reordered = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return dayLabels[d.weekday - 1];
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        const Text('Weekly Report', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'DMSerifDisplay', color: AppColors.onSurface)),
        Text(
          '${_formatDate(now.subtract(const Duration(days: 6)))} – ${_formatDate(now)}',
          style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 16),

        // ── Calorie chart ──
        if (_stats != null) AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('📊 Daily Calories', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  TextButton(
                    onPressed: () async {
                      final data = await DatabaseService.getDailyCalorieHistory();
                      if (context.mounted) {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => CalorieHistorySheet(data: data),
                        );
                      }
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('History', style: TextStyle(fontSize: 11, color: AppColors.primary)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 120,
                child: BarChart(
                  BarChartData(
                    barGroups: List.generate(7, (i) {
                      final val = (_stats!['dailyCals'] as List<int>)[i].toDouble();
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: val,
                            width: 20,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            color: i == 6 ? AppColors.primary : AppColors.surfaceContainerHigh,
                          ),
                        ],
                      );
                    }),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, _) => Text(
                            reordered[v.toInt()],
                            style: TextStyle(
                              fontSize: 10, fontFamily: 'DMSans',
                              color: v.toInt() == 6 ? AppColors.primary : AppColors.onSurfaceVariant,
                              fontWeight: v.toInt() == 6 ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    barTouchData: BarTouchData(enabled: false),
                    extraLinesData: ExtraLinesData(
                      horizontalLines: [
                        HorizontalLine(y: 1800, color: AppColors.outline, strokeWidth: 1, dashArray: [5, 5]),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary)),
                  const SizedBox(width: 4),
                  Text('Avg: ${_stats!['avgCal']} kcal/day · Goal: 1800 kcal', style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),

        // ── Stat cards ──
        if (_stats != null) Row(
          children: [
            Expanded(child: AppCard(child: _statCard('Avg Protein', '${_stats!['avgProt']}g', 'goal: 120g', AppColors.primary))),
            const SizedBox(width: 8),
            Expanded(child: AppCard(child: _statCard('Avg Water', '${(_stats!['avgWater'] / 1000).toStringAsFixed(1)}L', 'goal: 3L', AppColors.water))),
            const SizedBox(width: 8),
            Expanded(child: AppCard(child: _statCard('Med Streak', '$_medStreak${_streakBadge(_medStreak)}', 'days', AppColors.warning))),
          ],
        ),

        // ── AI Insights ──
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('📝 AI Insights', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  TextButton(
                    onPressed: _getAIInsights,
                    child: const Text('Generate', style: TextStyle(fontSize: 11, color: AppColors.primary)),
                  ),
                ],
              ),
              if (_aiInsights != null)
                Text(_aiInsights!.replaceAll('**', ''), style: const TextStyle(fontSize: 13, color: AppColors.onSurface, height: 1.5)),
            ],
          ),
        ),

        // ── Meal Planner ──
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🥗 Meal Planner', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 10),
              TextField(
                controller: _planCtrl,
                style: const TextStyle(fontSize: 13, color: AppColors.onSurface),
                decoration: InputDecoration(
                  hintText: 'e.g. "evening snacks 300kcal"',
                  hintStyle: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
                  filled: true, fillColor: AppColors.surfaceContainerHigh,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.outline)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.outline)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loadingPlan ? null : _getMealPlan,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: _loadingPlan
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                      : const Text('Get Suggestions'),
                ),
              ),
              if (_mealPlan != null) ...[
                const SizedBox(height: 12),
                Text(_mealPlan!.replaceAll('**', ''), style: const TextStyle(fontSize: 13, color: AppColors.onSurface, height: 1.5)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, String sub, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        Text(sub, style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
      ],
    );
  }

  String _formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
}


// ─────────────────────────────────────────────
// Calorie History Bottom Sheet
// ─────────────────────────────────────────────
class CalorieHistorySheet extends StatefulWidget {
  final Map<String, dynamic> data;
  const CalorieHistorySheet({super.key, required this.data});

  @override
  State<CalorieHistorySheet> createState() => _CalorieHistorySheetState();
}

class _CalorieHistorySheetState extends State<CalorieHistorySheet> {
  static const int _goalKcal = 1800;
  final Set<int> _expandedIndices = {};

  String _fmtDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
      return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]}';
    } catch (_) { return dateStr; }
  }

  // Returns true if this is TODAY
  bool _isToday(String dateStr) {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    return dateStr == todayStr;
  }

  Color _calColor(int cal) {
    if (cal == 0) return AppColors.onSurfaceVariant;
    if (cal <= _goalKcal) return AppColors.primary;
    if (cal <= _goalKcal * 1.15) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final days  = widget.data['days']   as List<dynamic>;
    final peak  = widget.data['peak']   as Map<String, dynamic>?;
    final lowest = widget.data['lowest'] as Map<String, dynamic>?;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
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
            // Drag handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(99)),
              ),
            ),

            // Title row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text('📊 Calorie History',
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
                    // Highest calorie day
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.error.withValues(alpha: 0.15), AppColors.error.withValues(alpha: 0.04)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Text('🔥', style: TextStyle(fontSize: 13)),
                                SizedBox(width: 4),
                                Text('Highest Day',
                                    style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${peak['total_cal']} kcal',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.error),
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
                    // Lowest calorie day
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primary.withValues(alpha: 0.15), AppColors.primary.withValues(alpha: 0.04)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Text('🧘', style: TextStyle(fontSize: 13)),
                                SizedBox(width: 4),
                                Text('Lightest Day',
                                    style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${lowest['total_cal']} kcal',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primary),
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
                          Text('🍽️', style: TextStyle(fontSize: 40)),
                          SizedBox(height: 8),
                          Text('No food logged yet.',
                              style: TextStyle(fontSize: 14, color: AppColors.onSurfaceVariant)),
                          SizedBox(height: 4),
                          Text('Start logging from the Log screen.',
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
                        final day     = days[i] as Map<String, dynamic>;
                        final cal     = day['total_cal']   as int;
                        final prot    = day['total_prot']  as int;
                        final carbs   = day['total_carbs'] as int;
                        final fats    = day['total_fats']  as int;
                        final entries = day['entries']     as List<dynamic>;
                        final fastMin = day['fasting_min'] as int? ?? 0;
                        final isExpanded = _expandedIndices.contains(i);
                        final isPeak   = peak  != null && day['date'] == peak['date'];
                        final isLow    = lowest != null && day['date'] == lowest['date'];
                        final isToday  = _isToday(day['date'] as String);
                        final overGoal = cal > _goalKcal;
                        final hasFast  = fastMin > 0;
                        final pct      = (cal / _goalKcal).clamp(0.0, 1.5);

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
                                  ? Border.all(color: AppColors.error.withValues(alpha: 0.4), width: 1.5)
                                  : isToday
                                      ? Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 1.5)
                                      : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Top row: date + badges + kcal ──
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                isToday ? 'Today' : _fmtDate(day['date'] as String),
                                                style: TextStyle(
                                                  fontSize: 12, fontWeight: FontWeight.w700,
                                                  color: isToday ? AppColors.primary : AppColors.onSurface,
                                                ),
                                              ),
                                              if (isToday) ...[
                                                const SizedBox(width: 5),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(99),
                                                  ),
                                                  child: const Text('Today', style: TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w700)),
                                                ),
                                              ] else if (isPeak) ...[
                                                const SizedBox(width: 5),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.error.withValues(alpha: 0.13),
                                                    borderRadius: BorderRadius.circular(99),
                                                  ),
                                                  child: const Text('🔥 Highest', style: TextStyle(fontSize: 9, color: AppColors.error, fontWeight: FontWeight.w700)),
                                                ),
                                              ] else if (isLow) ...[
                                                const SizedBox(width: 5),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary.withValues(alpha: 0.13),
                                                    borderRadius: BorderRadius.circular(99),
                                                  ),
                                                  child: const Text('🧘 Lightest', style: TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w700)),
                                                ),
                                              ],
                                              if (hasFast) ...[
                                                const SizedBox(width: 5),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.warning.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(99),
                                                  ),
                                                  child: Text('⏱️ ${fastMin ~/ 60}h Fast', style: const TextStyle(fontSize: 9, color: AppColors.warning, fontWeight: FontWeight.w700)),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${hasFast ? '⏱️ Fasted · ' : ''}P:${prot}g  C:${carbs}g  F:${fats}g  ·  ${entries.length} item${entries.length == 1 ? '' : 's'}',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: hasFast ? AppColors.warning.withValues(alpha: 0.85) : AppColors.onSurfaceVariant,
                                            ),
                                          ),

                                        ],
                                      ),
                                    ),
                                    // kcal display
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '$cal kcal',
                                          style: TextStyle(
                                            fontSize: 18, fontWeight: FontWeight.w800,
                                            color: _calColor(cal),
                                          ),
                                        ),
                                        Text(
                                          overGoal
                                              ? '+${cal - _goalKcal} over'
                                              : '${_goalKcal - cal} under',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: overGoal ? AppColors.error.withValues(alpha: 0.8) : AppColors.primary.withValues(alpha: 0.8),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      isExpanded
                                          ? Icons.keyboard_arrow_up_rounded
                                          : Icons.keyboard_arrow_down_rounded,
                                      size: 18, color: AppColors.onSurfaceVariant,
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 8),

                                // ── Calorie progress bar ──
                                Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(99),
                                      child: LinearProgressIndicator(
                                        value: pct.clamp(0.0, 1.0),
                                        minHeight: 5,
                                        backgroundColor: AppColors.surfaceContainer,
                                        valueColor: AlwaysStoppedAnimation(_calColor(cal)),
                                      ),
                                    ),
                                    // Over-goal red overflow indicator
                                    if (overGoal)
                                      Positioned.fill(
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: Container(
                                            width: 5, height: 5,
                                            decoration: const BoxDecoration(
                                              color: AppColors.error,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),

                                // ── Macro mini-bars ──
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    _macroChip('P', prot, AppColors.primary),
                                    const SizedBox(width: 4),
                                    _macroChip('C', carbs, AppColors.secondary),
                                    const SizedBox(width: 4),
                                    _macroChip('F', fats, const Color(0xFFA8D8CB)),
                                  ],
                                ),

                                // ── Expanded food items ──
                                if (isExpanded && entries.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  const Divider(height: 1, color: AppColors.outline),
                                  const SizedBox(height: 8),
                                  ...entries.map((e) {
                                    final entry = e as Map<String, dynamic>;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 7),
                                      child: Row(
                                        children: [
                                          const Text('🍽️', style: TextStyle(fontSize: 12)),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              entry['item'] as String,
                                              style: const TextStyle(fontSize: 11, color: AppColors.onSurface),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${entry['calories']} kcal',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'P:${entry['protein']}  C:${entry['carbs']}  F:${entry['fats']}',
                                            style: const TextStyle(fontSize: 9, color: AppColors.onSurfaceVariant),
                                          ),
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

  Widget _macroChip(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: ${value}g',
        style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
