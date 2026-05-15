import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/auto_backup_service.dart';
import 'services/database_service.dart';
import 'services/gemini_service.dart';
import 'services/notification_service.dart';
import 'providers/dashboard_provider.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/log_screen.dart';
import 'screens/health_screen.dart';
import 'screens/reports_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await DatabaseService.initPlatform();
  await DatabaseService.database; // init DB
  await DatabaseService.seedDefaultReminders();
  // Best-effort: write a JSON snapshot of all data to external storage on
  // every launch. Failures are swallowed so a flaky disk never blocks startup.
  await AutoBackupService.runOnStartup();
  GeminiService.init();
  await NotificationService.init();
  await NotificationService.rescheduleAll();
  runApp(const HealthTrackerApp());
}

class HealthTrackerApp extends StatelessWidget {
  const HealthTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DashboardProvider()..refresh(),
      child: MaterialApp(
        title: 'Health Tracker',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

/// One entry per top-level tab. Add a new tab by appending one row.
class _TabConfig {
  final IconData icon;
  final String label;
  final Widget screen;
  const _TabConfig({required this.icon, required this.label, required this.screen});
}

const _tabs = <_TabConfig>[
  _TabConfig(icon: Icons.home_rounded,      label: 'Home',    screen: HomeScreen()),
  _TabConfig(icon: Icons.edit_rounded,      label: 'Log',     screen: LogScreen()),
  _TabConfig(icon: Icons.favorite_rounded,  label: 'Health',  screen: HealthScreen()),
  _TabConfig(icon: Icons.bar_chart_rounded, label: 'Reports', screen: ReportsScreen()),
];

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  final PageController _pageCtrl = PageController();

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onTabTap(int i) {
    if (_currentIndex == i) return;
    _pageCtrl.animateToPage(
      i,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _showQuickLogSheet() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        bool loading = false;
        Map<String, dynamic>? estimate;
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Quick Log', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface, fontFamily: 'DMSerifDisplay')),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 14, color: AppColors.onSurface),
                  decoration: InputDecoration(
                    hintText: 'What did you eat?',
                    hintStyle: const TextStyle(color: AppColors.onSurfaceVariant),
                    filled: true, fillColor: AppColors.surfaceContainerHigh,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.outline)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.outline)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary)),
                  ),
                ),
                const SizedBox(height: 12),
                if (estimate != null) ...[
                  Text('${estimate!['item']} — ~${estimate!['calories']} kcal', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  Text('P:${estimate!['protein']}g · C:${estimate!['carbs']}g · F:${estimate!['fats']}g', style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final dash = context.read<DashboardProvider>();
                            await dash.addFood(
                              estimate!['item'] as String,
                              (estimate!['calories'] as num).toInt(),
                              (estimate!['protein'] as num).toInt(),
                              (estimate!['carbs'] as num).toInt(),
                              (estimate!['fats'] as num).toInt(),
                              rawInput: ctrl.text.trim(),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('✅ ${estimate!['item']} +${estimate!['calories']} kcal')),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.surface),
                          child: const Text('✅ Confirm'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => setSheetState(() => estimate = null),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.outline)),
                        child: const Text('↩️ Retry', style: TextStyle(color: AppColors.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ] else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: loading ? null : () async {
                        if (ctrl.text.trim().isEmpty) return;
                        setSheetState(() => loading = true);
                        final result = await GeminiService.parseFood(ctrl.text.trim());
                        setSheetState(() { loading = false; estimate = result; });
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      child: loading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                          : const Text('✨ Analyze', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageView.builder(
          controller: _pageCtrl,
          itemCount: _tabs.length,
          onPageChanged: (i) => setState(() => _currentIndex = i),
          physics: const ClampingScrollPhysics(),
          itemBuilder: (_, i) => _tabs[i].screen,
        ),
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: _showQuickLogSheet,
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.add_a_photo_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabTap,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final t in _tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}
