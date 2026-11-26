import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'dopa_card.dart';

/// Componente visual del "Motor de Gamificación" (Rachas amables sin culpa).
/// Representa el gráfico semanal de rachas (L, M, X, J, V, S, D).
class StreakChart extends StatelessWidget {
  final int streakDays;
  final List<bool> weeklyActivity;

  const StreakChart({
    super.key,
    this.streakDays = 0,
    this.weeklyActivity = const [false, false, false, false, false, false, false],
  });

  @override
  Widget build(BuildContext context) {
    const labels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    final List<Map<String, dynamic>> days = List.generate(7, (i) {
      final isActive = i < weeklyActivity.length && weeklyActivity[i];
      return {
        'day': labels[i],
        'height': isActive ? 54.0 : 22.0,
        'active': isActive,
      };
    });

    return DopaCard(
      backgroundColor: AppTheme.surfaceWhite,
      padding: const EdgeInsets.all(18.0),
      borderRadius: AppTheme.radiusLarge,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Rachas',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.pastelLilac,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.borderDark.withValues(alpha: 0.3),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⭐', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    Text(
                      '$streakDays días',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Barras semanales
          SizedBox(
            height: 92,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: days.map((item) {
                final bool isActive = item['active'] as bool;
                final double barHeight = item['height'] as double;
                final String label = item['day'] as String;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: 22,
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: isActive ? AppTheme.pastelPink : const Color(0xFFE4ECE8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.borderDark,
                          width: AppTheme.borderWidth,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
