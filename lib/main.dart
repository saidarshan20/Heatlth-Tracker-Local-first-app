import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  final _screens = const [
    HomeScreen(),
    LogScreen(),
    HealthScreen(),
    ReportsScreen(),
  ];

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
      body: SafeArea(child: _screens[_currentIndex]),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: _showQuickLogSheet,
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.edit_rounded), label: 'Log'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite_rounded), label: 'Health'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'Reports'),
        ],
      ),
    );
  }
}
