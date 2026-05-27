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
import 'package:image_picker/image_picker.dart';
import 'services/image_food_service.dart';

/// Global notifier — screens listen to this to replay entrance animations
/// whenever their tab becomes active. Set by [_AppShellState._onTabTap].
final activeTabNotifier = ValueNotifier<int>(0);

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
        scrollBehavior: _AppScrollBehavior(),
        home: const SplashScreen(),
      ),
    );
  }
}

/// Gives every [ListView] / [ScrollView] iOS-style elastic overscroll
/// without touching individual screens.
class _AppScrollBehavior extends ScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();
}

// ─────────────────────────────────────────────────────────────────────────────
// Splash Screen
// ─────────────────────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Fade-in of entire splash content
  late final AnimationController _fadeInCtrl;
  late final Animation<double> _fadeIn;

  // Glow pulse on the emoji circle
  late final AnimationController _glowCtrl;
  late final Animation<double> _glow;

  // Fade-out before transitioning to AppShell
  late final AnimationController _fadeOutCtrl;
  late final Animation<double> _fadeOut;

  bool _showShell = false;

  @override
  void initState() {
    super.initState();

    // 1. Fade-in: 0 → 1 over 600ms
    _fadeInCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeIn =
        CurvedAnimation(parent: _fadeInCtrl, curve: Curves.easeOut);

    // 2. Glow pulse: repeats indefinitely, 400ms per half-cycle
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _glow = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut);

    // 3. Fade-out: 1 → 0 over 300ms just before switching
    _fadeOutCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fadeOut =
        CurvedAnimation(parent: _fadeOutCtrl, curve: Curves.easeIn);

    _runSequence();
  }

  Future<void> _runSequence() async {
    // Fade in the splash
    await _fadeInCtrl.forward();

    // Start glow pulse loop
    _glowCtrl.repeat(reverse: true);

    // Hold for ~1 second
    await Future.delayed(const Duration(milliseconds: 1000));

    // Fade out
    _glowCtrl.stop();
    await _fadeOutCtrl.forward();

    // Switch to shell
    if (mounted) setState(() => _showShell = true);
  }

  @override
  void dispose() {
    _fadeInCtrl.dispose();
    _glowCtrl.dispose();
    _fadeOutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showShell) return const AppShell();

    return AnimatedBuilder(
      animation: Listenable.merge([_fadeIn, _glow, _fadeOut]),
      builder: (context, _) {
        final opacity = _fadeIn.value * (1.0 - _fadeOut.value);
        // Glow blur: pulses between 8 and 28
        final glowBlur = 8.0 + (_glow.value * 20.0);
        // Glow spread: pulses between 0 and 6
        final glowSpread = _glow.value * 6.0;

        return Scaffold(
          backgroundColor: AppColors.surface,
          body: Opacity(
            opacity: opacity,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Emoji logo with glow ring ──
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryContainer,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.55),
                          blurRadius: glowBlur,
                          spreadRadius: glowSpread,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text('🏃', style: TextStyle(fontSize: 46)),
                  ),
                  const SizedBox(height: 24),

                  // ── App name ──
                  const Text(
                    'Health Tracker',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'DMSerifDisplay',
                      color: AppColors.onSurface,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // ── Tagline ──
                  Text(
                    'Your daily wellness companion',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.85),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // ── Subtle loading dots ──
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (i) {
                      final dotOpacity =
                          ((_glow.value + i / 3) % 1.0).clamp(0.2, 1.0);
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary
                              .withValues(alpha: dotOpacity),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// App Shell
// ─────────────────────────────────────────────────────────────────────────────

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

class _AppShellState extends State<AppShell> with TickerProviderStateMixin {
  int _currentIndex = 0;
  final PageController _pageCtrl = PageController();

  // One bounce controller per tab icon
  late final List<AnimationController> _bounceCtrl;
  late final List<Animation<double>> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = List.generate(
      _tabs.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 220),
      ),
    );
    _bounceAnim = _bounceCtrl.map((ctrl) {
      return TweenSequence<double>([
        TweenSequenceItem(
            tween: Tween(begin: 1.0, end: 1.28)
                .chain(CurveTween(curve: Curves.easeOut)),
            weight: 40),
        TweenSequenceItem(
            tween: Tween(begin: 1.28, end: 1.0)
                .chain(CurveTween(curve: Curves.elasticOut)),
            weight: 60),
      ]).animate(ctrl);
    }).toList();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    for (final c in _bounceCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTabTap(int i) {
    if (_currentIndex == i) return;

    // Bounce the icon
    _bounceCtrl[i].forward(from: 0);

    // Animate the page
    _pageCtrl.animateToPage(
      i,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );

    // Notify screens to replay their entrance animations
    activeTabNotifier.value = i;
  }

  void _showFABOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton(
              heroTag: 'fab_text',
              onPressed: () {
                Navigator.pop(ctx);
                _showQuickLogSheet();
              },
              backgroundColor: AppColors.surfaceContainerHigh,
              foregroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.edit_note_rounded),
            ),
            const SizedBox(width: 16),
            FloatingActionButton(
              heroTag: 'fab_cam',
              onPressed: () {
                Navigator.pop(ctx);
                _quickCamAction();
              },
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.photo_camera_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _quickCamAction() async {
    final XFile? file = await ImageFoodService.captureFromCamera();
    if (file == null) return;

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        bool loading = true;
        Map<String, dynamic>? estimate;
        String? errorMsg;

        // Fire parsing once
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final compressed = await ImageFoodService.compress(file);
          final result = await ImageFoodService.parseFoodFromImage(compressed, hint: null);
          if (ctx.mounted) {
            (ctx as Element).markNeedsBuild();
            loading = false;
            if (result != null) {
              estimate = result;
            } else {
              final reason = ImageFoodService.lastError ?? 'unknown';
              errorMsg = "❌ Image parse failed: $reason";
            }
          }
        });

        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Camera AI Log', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface, fontFamily: 'DMSerifDisplay')),
                const SizedBox(height: 12),
                if (loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  )
                else if (errorMsg != null)
                  Text(errorMsg!, style: const TextStyle(color: AppColors.error))
                else if (estimate != null) ...[
                  Text('${estimate!['item']} — ~${estimate!['calories']} kcal', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  Text('P:${estimate!['protein']}g · C:${estimate!['carbs']}g · F:${estimate!['fats']}g', style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 12),
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
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.outline)),
                        child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
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
          onPageChanged: (i) {
            setState(() => _currentIndex = i);
            activeTabNotifier.value = i;
          },
          physics: const ClampingScrollPhysics(),
          itemBuilder: (_, i) => _tabs[i].screen,
        ),
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: _showFABOptions,
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabTap,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (int i = 0; i < _tabs.length; i++)
            NavigationDestination(
              icon: ScaleTransition(
                scale: _bounceAnim[i],
                child: Icon(_tabs[i].icon),
              ),
              label: _tabs[i].label,
            ),
        ],
      ),
    );
  }
}
