import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/ai_chat_model.dart';
import 'dopa_card.dart';

/// Burbuja de mensaje individual en la conversación con el asistente de IA.
///
/// Estilo "Soft Neo-Brutalism" coherente con el diseño de DOPA:
/// - Mensajes del usuario: fondo pastelLime, alineados a la derecha.
/// - Mensajes del asistente: fondo surfaceWhite, alineados a la izquierda.
/// - Estados de carga: indicador animado de puntos.
/// - Errores: fondo pastelPeach con icono de advertencia.
class AIChatBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onActionTap;

  const AIChatBubble({
    super.key,
    required this.message,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isLoading) {
      return _buildLoadingBubble(context);
    }

    final bool isUser = message.role == ChatRole.user;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            // Avatar del asistente
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.pastelYellow,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.borderDark,
                  width: 1.4,
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: AppTheme.borderDark,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Burbuja del mensaje
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                DopaCard(
                  backgroundColor: message.isError
                      ? AppTheme.pastelPeach
                      : (isUser ? AppTheme.pastelLime : AppTheme.surfaceWhite),
                  borderRadius: AppTheme.radiusSmall,
                  borderWidth: 1.4,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14.0,
                    vertical: 10.0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.isError) ...[
                        const Padding(
                          padding: EdgeInsets.only(right: 8, top: 2),
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                      Flexible(
                        child: Text(
                          message.content,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                    fontSize: 13,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Hora del mensaje
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                  child: Text(
                    _formatTime(message.timestamp),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.textMuted,
                          fontSize: 10,
                        ),
                  ),
                ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildLoadingBubble(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.pastelYellow,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.borderDark,
                width: 1.4,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.auto_awesome,
                size: 16,
                color: AppTheme.borderDark,
              ),
            ),
          ),
          const SizedBox(width: 8),
          DopaCard(
            backgroundColor: AppTheme.surfaceWhite,
            borderRadius: AppTheme.radiusSmall,
            borderWidth: 1.4,
            padding: const EdgeInsets.symmetric(
              horizontal: 18.0,
              vertical: 12.0,
            ),
            child: const _TypingIndicator(),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// Indicador animado de "escribiendo..." con tres puntos.
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final value = (_controller.value - delay).clamp(0.0, 1.0);
            final opacity = (0.3 + 0.7 * (1 - (2 * value - 1).abs())).clamp(0.3, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
