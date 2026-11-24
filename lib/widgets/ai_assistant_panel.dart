import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/ai_chat_model.dart';
import '../services/ai_chat_service.dart';
import '../services/ai_context_service.dart';
import '../widgets/ai_chat_bubble.dart';
import '../widgets/dopa_card.dart';
import '../screens/main_navigation_screen.dart';

/// Panel del asistente de IA que se muestra como bottom sheet.
///
/// Diseñado como un panel deslizable desde abajo que mantiene el contexto
/// de la conversación mientras el usuario navega entre secciones.
///
/// Integración:
/// - Recopila contexto real de la app via AIContextService.
/// - Se comunica con el modelo de IA via AIChatService.
/// - Permite ejecutar acciones sugeridas por la IA.
/// - Muestra chips de sugerencias para facilitar el inicio.
class AIAssistantPanel extends StatefulWidget {
  const AIAssistantPanel({super.key});

  /// Muestra el panel del asistente como un bottom sheet modal.
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AIAssistantPanel(),
    );
  }

  @override
  State<AIAssistantPanel> createState() => _AIAssistantPanelState();
}

class _AIAssistantPanelState extends State<AIAssistantPanel> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<ChatMessage> _messages = [];
  List<String> _suggestedPrompts = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _messages = AIChatService.instance.conversationHistory.toList();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    final prompts = await AIChatService.instance.getSuggestedPrompts();
    if (mounted) {
      setState(() => _suggestedPrompts = prompts);
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    _textController.clear();

    setState(() {
      _isLoading = true;
      _messages = AIChatService.instance.conversationHistory.toList();
      // Agregar indicador de carga
      _messages.add(ChatMessage.loading());
    });

    _scrollToBottom();

    final response = await AIChatService.instance.sendMessage(text.trim());

    if (mounted) {
      setState(() {
        _isLoading = false;
        _messages = AIChatService.instance.conversationHistory.toList();
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleAction(AIAction action) {
    switch (action.type) {
      case AIActionType.organizarTareas:
        Navigator.pop(context);
        MainNavigationScreen.tabNotifier.value = 1; // Tab Tareas
        break;
      case AIActionType.tomarBreak:
        Navigator.pop(context);
        MainNavigationScreen.tabNotifier.value = 3; // Tab Pausa
        break;
      case AIActionType.iniciarFoco:
        Navigator.pop(context);
        MainNavigationScreen.tabNotifier.value = 1; // Tab Tareas
        break;
      case AIActionType.agregarTarea:
      case AIActionType.completarTarea:
      case AIActionType.marcarPrioridad:
        _executeAction(action);
        break;
    }
  }

  Future<void> _executeAction(AIAction action) async {
    final result = await AIChatService.instance.executeAction(action);
    if (result != null && mounted) {
      // Enviar resultado como mensaje del sistema
      setState(() {
        _messages.add(ChatMessage(
          role: ChatRole.assistant,
          content: result,
        ));
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.85,
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: AppTheme.borderDark, width: 2),
          left: BorderSide(color: AppTheme.borderDark, width: 2),
          right: BorderSide(color: AppTheme.borderDark, width: 2),
        ),
      ),
      child: Column(
        children: [
          // Handle del panel
          _buildHandle(),

          // Header del asistente
          _buildHeader(context),

          const Divider(height: 1, color: Color(0xFFE2EBE5), thickness: 1.5),

          // Área de mensajes
          Expanded(
            child: _messages.isEmpty
                ? _buildWelcomeView(context)
                : _buildMessageList(context),
          ),

          // Chips de sugerencias (solo si no hay mensajes o pocos)
          if (_messages.length < 3 && _suggestedPrompts.isNotEmpty)
            _buildSuggestionChips(context),

          // Input de texto
          _buildInput(context, bottomInset),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppTheme.textMuted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.pastelYellow,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.borderDark,
                width: AppTheme.borderWidth,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.auto_awesome,
                size: 18,
                color: AppTheme.borderDark,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Asistente DOPA',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                ),
                Text(
                  'En: ${AIContextService.instance.currentSection}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          // Botón de nueva conversación
          if (_messages.isNotEmpty)
            GestureDetector(
              onTap: () {
                AIChatService.instance.clearConversation();
                setState(() {
                  _messages = [];
                });
                _loadSuggestions();
              },
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.borderDark,
                    width: 1.4,
                  ),
                ),
                child: const Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: AppTheme.borderDark,
                ),
              ),
            ),
          const SizedBox(width: 8),
          // Botón cerrar
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.borderDark,
                  width: 1.4,
                ),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 18,
                color: AppTheme.borderDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeView(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.pastelYellow,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.borderDark,
                width: AppTheme.borderWidth,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.auto_awesome,
                size: 30,
                color: AppTheme.borderDark,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '¡Hola! Soy tu asistente 🌿',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Puedo ayudarte a organizar tus tareas, sugerir qué hacer primero y planificar tu día. '
            'Pregúntame lo que necesites.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 24),
          // Tarjetas de ejemplo
          _buildExampleCard(
            context,
            icon: Icons.lightbulb_outline_rounded,
            title: 'Priorizar',
            description: '¿Qué debería hacer primero?',
            color: AppTheme.pastelYellow,
            onTap: () => _sendMessage('¿Qué debería hacer primero hoy?'),
          ),
          const SizedBox(height: 10),
          _buildExampleCard(
            context,
            icon: Icons.calendar_today_outlined,
            title: 'Planificar',
            description: 'Organiza mis tareas para hoy',
            color: AppTheme.pastelMint,
            onTap: () => _sendMessage('Organiza mis tareas para hoy'),
          ),
          const SizedBox(height: 10),
          _buildExampleCard(
            context,
            icon: Icons.battery_charging_full_outlined,
            title: 'Energía baja',
            description: 'Tengo poca energía, ¿qué hago?',
            color: AppTheme.pastelBlue,
            onTap: () =>
                _sendMessage('Tengo poco tiempo y poca energía, ¿qué debería priorizar?'),
          ),
        ],
      ),
    );
  }

  Widget _buildExampleCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return DopaCard(
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: AppTheme.borderDark, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppTheme.borderDark,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AIChatBubble(message: message),
            // Botones de acción si el mensaje los tiene
            if (message.actions.isNotEmpty && !message.isLoading)
              Padding(
                padding: const EdgeInsets.only(left: 40, top: 4, bottom: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: message.actions.map((action) {
                    return GestureDetector(
                      onTap: () => _handleAction(action),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.pastelLime,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.borderDark,
                            width: 1.4,
                          ),
                        ),
                        child: Text(
                          action.label,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                                fontSize: 12,
                              ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSuggestionChips(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _suggestedPrompts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () => _sendMessage(_suggestedPrompts[index]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceWhite,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.borderDark,
                  width: 1.2,
                ),
              ),
              child: Text(
                _suggestedPrompts[index],
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInput(BuildContext context, double bottomInset) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 12,
        top: 10,
        bottom: 10 + bottomInset,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceWhite,
        border: Border(
          top: BorderSide(color: Color(0xFFE2EBE5), width: 1.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: AppTheme.borderDark,
                  width: 1.4,
                ),
              ),
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                enabled: !_isLoading,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                minLines: 1,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                decoration: InputDecoration(
                  hintText: _isLoading
                      ? 'Pensando...'
                      : '¿En qué te puedo ayudar?',
                  hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  isDense: true,
                ),
                onSubmitted: (text) {
                  if (!_isLoading) _sendMessage(text);
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Botón enviar
          GestureDetector(
            onTap: _isLoading
                ? null
                : () => _sendMessage(_textController.text),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _isLoading
                    ? AppTheme.textMuted.withValues(alpha: 0.3)
                    : AppTheme.pastelYellow,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.borderDark,
                  width: AppTheme.borderWidth,
                ),
              ),
              child: Icon(
                _isLoading ? Icons.hourglass_top_rounded : Icons.send_rounded,
                color: AppTheme.borderDark,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
