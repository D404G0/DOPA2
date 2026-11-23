import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'dopa_card.dart';

/// Componente visual interactivo del medidor de energía y nivel de dopamina.
/// Permite registrar "¿Cómo está tu energía?" con un toque ('Poquita', 'Media', 'A tope').
class EnergyDopamineCard extends StatelessWidget {
  final double energyLevel; // 0.0 (poquita) a 1.0 (a tope)
  final String emoji;
  final ValueChanged<double>? onEnergyChanged;

  const EnergyDopamineCard({
    super.key,
    this.energyLevel = 0.45,
    this.emoji = '😌',
    this.onEnergyChanged,
  });

  String get _computedEmoji {
    if (energyLevel < 0.35) return '😴';
    if (energyLevel > 0.7) return '⚡';
    return emoji;
  }

  String get _levelLabel {
    if (energyLevel < 0.35) return 'Poquita';
    if (energyLevel > 0.7) return 'A tope';
    return 'Media';
  }

  @override
  Widget build(BuildContext context) {
    final clamped = energyLevel.clamp(0.08, 0.92);

    return DopaCard(
      backgroundColor: AppTheme.pastelPink,
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título y emoji de estado
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '¿Cómo está tu energía?',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _computedEmoji,
                style: const TextStyle(fontSize: 26),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dopamina',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              Text(
                'Nivel: $_levelLabel',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.textPrimary.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Barra multicolor segmentada con indicador de posición
          LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              final markerLeft = (barWidth * clamped - 9).clamp(0.0, barWidth - 18);
              return GestureDetector(
                onTapDown: onEnergyChanged == null
                    ? null
                    : (details) {
                        final ratio = (details.localPosition.dx / barWidth).clamp(0.1, 0.95);
                        if (ratio < 0.35) {
                          onEnergyChanged!(0.2);
                        } else if (ratio > 0.68) {
                          onEnergyChanged!(0.85);
                        } else {
                          onEnergyChanged!(0.5);
                        }
                      },
                child: SizedBox(
                  height: 22,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 16,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.borderDark,
                            width: 1.5,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8.5),
                          child: Row(
                            children: [
                              Expanded(flex: 2, child: Container(color: const Color(0xFFE57388))),
                              Expanded(flex: 2, child: Container(color: const Color(0xFFF6C8A4))),
                              Expanded(flex: 3, child: Container(color: const Color(0xFFFDF08E))),
                              Expanded(flex: 3, child: Container(color: const Color(0xFF75CEA6))),
                              Expanded(flex: 3, child: Container(color: const Color(0xFFA5D8F2))),
                              Expanded(flex: 2, child: Container(color: const Color(0xFFD3B6ED))),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: markerLeft,
                        child: Container(
                          width: 18,
                          height: 22,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceWhite,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.borderDark,
                              width: 2.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),

          // Etiquetas interactivas para cambiar energía en 1 toque
          if (onEnergyChanged != null)
            Row(
              children: [
                _buildQuickEnergyPill('poquita', 0.2, energyLevel < 0.35),
                const SizedBox(width: 8),
                _buildQuickEnergyPill(
                  'media',
                  0.5,
                  energyLevel >= 0.35 && energyLevel <= 0.7,
                ),
                const SizedBox(width: 8),
                _buildQuickEnergyPill('a tope', 0.85, energyLevel > 0.7),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'poquita',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.textPrimary.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  'a tope',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.textPrimary.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildQuickEnergyPill(String label, double value, bool isSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () => onEnergyChanged?.call(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.surfaceWhite
                : AppTheme.surfaceWhite.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.borderDark,
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
