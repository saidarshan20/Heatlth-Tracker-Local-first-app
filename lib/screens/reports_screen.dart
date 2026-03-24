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
              const Text('📊 Daily Calories', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
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
