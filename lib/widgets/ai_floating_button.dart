import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'ai_assistant_panel.dart';

/// Botón flotante (FAB) para abrir el asistente de IA de DOPA.
///
/// Se muestra como una burbuja tranquila en la esquina inferior derecha,
/// justo arriba de la barra de navegación, disponible en todas las secciones.
///
/// Estilo: Soft Neo-Brutalism con color pastelYellow (el color de la IA en DOPA).
class AIFloatingButton extends StatefulWidget {
  const AIFloatingButton({super.key});

  @override
  State<AIFloatingButton> createState() => _AIFloatingButtonState();
}

class _AIFloatingButtonState extends State<AIFloatingButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 12,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          AIAssistantPanel.show(context);
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 120),
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
