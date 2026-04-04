import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/dashboard_provider.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'health_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, dash, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            // ── Header ──
            Row(
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
            const SizedBox(height: 20),

            // ── Calorie + Macros ──
            AppCard(
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

            // ── Water ──
            AppCard(
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
                                TextSpan(text: '${dash.totalWater} ', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                                TextSpan(text: '/ ${DashboardProvider.waterGoal} ml', style: const TextStyle(fontSize: 14, color: AppColors.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // History button
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
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('History', style: TextStyle(fontSize: 11, color: AppColors.water)),
                          ),
                          const SizedBox(height: 4),
                          // Visual bars — blue for water, purple for soft drink
                          Row(
                            children: List.generate(12, (i) {
                              final totalBars = (dash.totalWater / (DashboardProvider.waterGoal / 12)).round();
                              final softDrinkBars = (dash.softDrinkWater / (DashboardProvider.waterGoal / 12)).round();
                              final waterBars = totalBars - softDrinkBars;
                              
                              Color barColor;
                              if (i < waterBars) {
                                barColor = AppColors.water;
                              } else if (i < totalBars) {
                                barColor = const Color(0xFF9C27B0); // Purple for soft drinks
                              } else {
                                barColor = AppColors.surfaceContainerHigh;
                              }
                              
                              return Container(
                                width: 8, height: 28, margin: const EdgeInsets.only(left: 3),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: barColor,
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: (dash.totalWater / DashboardProvider.waterGoal).clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: AppColors.surfaceContainerHigh,
                      valueColor: const AlwaysStoppedAnimation(AppColors.water),
                    ),
                  ),
                ],
              ),
            ),

            // ── Medicines ──
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💊 Today\'s Medicines', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  if (dash.medicines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No medicines. Go to Health → Add.', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
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
                          // Already taken — offer undo
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${m['name']} already taken.'),
                              action: SnackBarAction(
                                label: 'Undo',
                                textColor: AppColors.primary,
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

            // ── Quick Water Buttons ──
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
                // +250ml Thumbs Up 🥤
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: OutlinedButton(
                      onPressed: () async {
                        await dash.addThumbsUp();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('🥤 Thumbs Up logged! +250ml water +100kcal')),
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: Color(0xFF9C27B0)),
                        backgroundColor: AppColors.surfaceContainer,
                      ),
                      child: const Text('+250ml 🥤', style: TextStyle(color: Color(0xFF9C27B0), fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
