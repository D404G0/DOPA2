/// Modelos para el módulo de Asistente de IA conversacional de DOPA.
///
/// Define los tipos de mensaje, acciones sugeridas y el estado
/// de la conversación del asistente inteligente.

/// Rol del mensaje en la conversación.
enum ChatRole { user, assistant, system }

/// Tipos de acción que la IA puede sugerir al usuario.
enum AIActionType {
  agregarTarea,
  marcarPrioridad,
  completarTarea,
  organizarTareas,
  iniciarFoco,
  tomarBreak,
}

/// Acción sugerida por la IA que el usuario puede ejecutar con un tap.
class AIAction {
  final AIActionType type;
  final String label;
  final Map<String, dynamic> payload;

  const AIAction({
    required this.type,
    required this.label,
    this.payload = const {},
  });
}

/// Mensaje individual en la conversación con el asistente.
class ChatMessage {
  final String id;
  final ChatRole role;
  final String content;
  final DateTime timestamp;
  final List<AIAction> actions;
  final bool isLoading;
  final bool isError;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.actions = const [],
    this.isLoading = false,
    this.isError = false,
  })  : id = id ?? '${DateTime.now().millisecondsSinceEpoch}_${role.name}',
        timestamp = timestamp ?? DateTime.now();

  /// Crea un mensaje de carga (typing indicator) del asistente.
  factory ChatMessage.loading() => ChatMessage(
        id: 'loading_${DateTime.now().millisecondsSinceEpoch}',
        role: ChatRole.assistant,
        content: '',
        isLoading: true,
      );

  /// Crea un mensaje de error del asistente.
  factory ChatMessage.error(String message) => ChatMessage(
        role: ChatRole.assistant,
        content: message,
        isError: true,
      );

  /// Convierte este mensaje al formato esperado por la API OpenAI-compatible.
  Map<String, String> toApiMessage() => {
        'role': role.name,
        'content': content,
      };
}
