import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CalorieRing extends StatelessWidget {
  final int consumed;
  final int goal;
  final double size;

  const CalorieRing({super.key, required this.consumed, required this.goal, this.size = 140});

  @override
  Widget build(BuildContext context) {
    final pct = (consumed / goal).clamp(0.0, 1.0);
    final over = consumed > goal;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(pct: pct, over: over),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$consumed',
                style: TextStyle(
                  fontSize: size * 0.16,
                  fontWeight: FontWeight.w700,
                  color: over ? AppColors.error : AppColors.onSurface,
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

  _RingPainter({required this.pct, required this.over});

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
    final sweepAngle = 2 * pi * pct;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2, sweepAngle,
      false,
      Paint()
        ..color = over ? AppColors.error : AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.pct != pct;
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
