import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// One-shot animated water bar. Same vibe as the calorie ring — fills from
/// 0 → target on mount with a smooth easeOutCubic / 600ms tween, then sits
/// still. No wiggles, no waves; just a clean bar with a subtle gradient.
class WaterWave extends StatelessWidget {
  final double value; // 0..1
  final double height;
  final Color color;
  final Color background;

  const WaterWave({
    super.key,
    required this.value,
    this.height = 10,
    this.color = AppColors.water,
    this.background = AppColors.surfaceContainerHigh,
  });

  @override
  Widget build(BuildContext context) {
    final target = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (_, c) => TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: target),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(color: background),
                Container(
                  width: c.maxWidth * v,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        color.withValues(alpha: 0.85),
                        color,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CalorieRing extends StatelessWidget {
  final int consumed;
  final int goal;
  final double size;

  const CalorieRing({super.key, required this.consumed, required this.goal, this.size = 140});

  @override
  Widget build(BuildContext context) {
    final rawPct = goal > 0 ? consumed / goal : 0.0;
    final pct = rawPct.clamp(0.0, 1.0);
    final over = rawPct > 1.0;
    final approaching = rawPct > 0.85 && !over;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Smoothly tween the arc when the value changes (e.g. after logging food).
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, value, _) => CustomPaint(
              size: Size(size, size),
              painter: _RingPainter(pct: value, over: over, approaching: approaching),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                child: Text(
                  '$consumed',
                  key: ValueKey(consumed),
                  style: TextStyle(
                    fontSize: size * 0.16,
                    fontWeight: FontWeight.w700,
                    color: over ? AppColors.error : AppColors.onSurface,
                  ),
                ),
              ),
              Text(
                'of $goal kcal',
                style: TextStyle(fontSize: size * 0.08, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double pct;
  final bool over;
  final bool approaching;

  _RingPainter({required this.pct, required this.over, required this.approaching});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    // Background ring
    canvas.drawCircle(
      center, radius,
      Paint()
        ..color = AppColors.surfaceContainerHigh
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10,
    );

    // Progress arc
    final arcColor = over ? AppColors.error : approaching ? const Color(0xFFFF9800) : AppColors.primary;
    final sweepAngle = 2 * pi * pct;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2, sweepAngle,
      false,
      Paint()
        ..color = arcColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.pct != pct || old.over != over || old.approaching != approaching;
}

class MacroBar extends StatelessWidget {
  final String label;
  final int current;
  final int goal;
  final Color color;

  const MacroBar({super.key, required this.label, required this.current, required this.goal, required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = (current / goal).clamp(0.0, 1.0);
    final over = current > goal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontFamily: 'DMSans', fontSize: 12),
                  children: [
                    TextSpan(
                      text: '${current}g ',
                      style: TextStyle(fontWeight: FontWeight.w600, color: over ? AppColors.error : AppColors.onSurface),
                    ),
                    TextSpan(text: '/ ${goal}g', style: const TextStyle(color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: AppColors.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation(over ? AppColors.error : color),
            ),
          ),
        ],
      ),
    );
  }
}

class MedicineRow extends StatelessWidget {
  final String time;
  final String name;
  final String emoji;
  final bool taken;
  final VoidCallback? onTap;

  const MedicineRow({super.key, required this.time, required this.name, required this.emoji, required this.taken, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: taken ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.outline.withValues(alpha: 0.5)))),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: taken ? AppColors.primaryContainer : AppColors.surfaceContainerHigh,
              ),
              alignment: Alignment.center,
              child: Text(taken ? '✓' : emoji, style: TextStyle(fontSize: taken ? 14 : 16)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
                  Text(time, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            Text(
              taken ? 'Done' : 'Pending',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: taken ? AppColors.primary : AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FoodEntryTile extends StatelessWidget {
  final String name;
  final int cal;
  final int p, c, f;
  final VoidCallback? onDelete;

  const FoodEntryTile({super.key, required this.name, required this.cal, required this.p, required this.c, required this.f, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.outline.withValues(alpha: 0.5)))),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: AppColors.primaryContainer),
            alignment: Alignment.center,
            child: const Text('🍽️', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                Text('P:${p}g · C:${c}g · F:${f}g', style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          Text('$cal kcal', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
        ],
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const AppCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: child,
    );
  }
}

/// One-shot fade + upward drift animation that fires on [initState].
///
/// Optionally delayed by [delay] — useful for staggering multiple items.
/// The widget fades from 0→1 opacity and slides from [Offset(0, 0.04)] →
/// [Offset.zero] over [duration] with [Curves.easeOutCubic].
class EntranceFade extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  const EntranceFade({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 320),
  });

  @override
  State<EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<EntranceFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);

    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(_anim),
        child: widget.child,
      ),
    );
  }
}

/// Wraps [child] in [EntranceFade] with a delay of [index] × [staggerMs].
///
/// Use this to cascade-animate a list of items:
/// ```dart
/// StaggerItem(index: 0, child: headerWidget),
/// StaggerItem(index: 1, child: cardOne),
/// StaggerItem(index: 2, child: cardTwo),
/// ```
class StaggerItem extends StatelessWidget {
  final int index;
  final Widget child;
  final int staggerMs;
  final Duration duration;

  const StaggerItem({
    super.key,
    required this.index,
    required this.child,
    this.staggerMs = 80,
    this.duration = const Duration(milliseconds: 320),
  });

  @override
  Widget build(BuildContext context) {
    return EntranceFade(
      delay: Duration(milliseconds: index * staggerMs),
      duration: duration,
      child: child,
    );
  }
}

