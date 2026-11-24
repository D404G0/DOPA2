import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'ai_assistant_panel.dart';

/// Botón flotante (FAB) para abrir el asistente de IA de DOPA.
///
/// Se muestra como una burbuja animada en la esquina inferior derecha,
/// justo arriba de la barra de navegación, disponible en todas las secciones.
///
/// Estilo: Soft Neo-Brutalism con color pastelYellow (el color de la IA en DOPA).
class AIFloatingButton extends StatefulWidget {
  const AIFloatingButton({super.key});

  @override
  State<AIFloatingButton> createState() => _AIFloatingButtonState();
}

class _AIFloatingButtonState extends State<AIFloatingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 12,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value,
            child: child,
          );
        },
        child: GestureDetector(
          onTap: () => AIAssistantPanel.show(context),
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppTheme.pastelYellow,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.borderDark,
                width: 2.0,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x251E3830),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.auto_awesome,
                color: AppTheme.borderDark,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
