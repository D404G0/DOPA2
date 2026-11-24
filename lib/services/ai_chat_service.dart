import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ai_chat_model.dart';
import '../models/task_model.dart';
import 'ai_context_service.dart';
import 'db_service.dart';

/// Servicio de comunicación con el modelo de IA (compatible con API OpenAI).
///
/// Arquitectura modular: Interfaz → AIChatService → AIContextService → Modelo de IA
///
/// La API Key y el endpoint se inyectan mediante `--dart-define` en compilación
/// o se configuran dinámicamente. Nunca se hardcodean en el código fuente.
///
/// Para cambiar de proveedor/modelo de IA, solo hay que modificar este servicio.
class AIChatService {
  static final AIChatService instance = AIChatService._();
  AIChatService._();

  // ---------------------------------------------------------------------------
  // Configuración del proveedor de IA (inyectada por --dart-define)
  // ---------------------------------------------------------------------------

  /// URL base de la API de IA. Inyectada en compilación:
  /// `--dart-define=AI_API_BASE_URL=https://integrate.api.nvidia.com/v1`
  static const String _envBaseUrl = String.fromEnvironment(
    'AI_API_BASE_URL',
    defaultValue: 'https://integrate.api.nvidia.com/v1',
  );

  /// API Key del proveedor de IA. Inyectada en compilación:
  /// `--dart-define=AI_API_KEY=nvapi-...`
  static const String _envApiKey = String.fromEnvironment(
    'AI_API_KEY',
    defaultValue: '',
  );

  /// Modelo de IA a utilizar. Inyectado en compilación:
  /// `--dart-define=AI_MODEL=meta/muse-glimmer-30b`
  static const String _envModel = String.fromEnvironment(
    'AI_MODEL',
    defaultValue: 'meta/muse-glimmer-30b',
  );

  /// Permite configurar dinámicamente en runtime (ej: desde settings).
  String? _customBaseUrl;
  String? _customApiKey;
  String? _customModel;

  String get _baseUrl => _customBaseUrl ?? _envBaseUrl;
  String get _apiKey => _customApiKey ?? _envApiKey;
  String get _model => _customModel ?? _envModel;

  /// Configura dinámicamente el proveedor de IA en runtime.
  void configure({
    String? baseUrl,
    String? apiKey,
    String? model,
  }) {
    _customBaseUrl = baseUrl;
    _customApiKey = apiKey;
    _customModel = model;
  }

  /// Verifica si el servicio de IA está configurado con API Key.
  bool get isConfigured => _apiKey.isNotEmpty;

  /// Timeout para solicitudes al modelo de IA.
  Duration requestTimeout = const Duration(seconds: 30);

  // ---------------------------------------------------------------------------
  // Historial de conversación en memoria
  // ---------------------------------------------------------------------------
  final List<ChatMessage> _conversationHistory = [];

  List<ChatMessage> get conversationHistory =>
      List.unmodifiable(_conversationHistory);

  void clearConversation() {
    _conversationHistory.clear();
  }

  // ---------------------------------------------------------------------------
  // Prompt del sistema (personalidad del asistente DOPA)
  // ---------------------------------------------------------------------------

  static const String _systemPromptBase = '''
Eres el asistente de productividad integrado en DOPA, una aplicación móvil diseñada para personas que buscan gestionar sus tareas de forma empática y sin presión.

Tu personalidad:
- Eres amigable, empático y motivador, nunca juzgas ni presionas.
- Usas un tono cálido y conversacional, como un amigo que te ayuda a organizarte.
- Prefieres sugerencias suaves y de baja fricción: "poquito a poquito".
- Cuando recomiendas tareas, explicas brevemente por qué (ej: "es rápida y te dará un impulso de dopamina").
- Nunca usas lenguaje técnico ni abrumador.
- Respondes en español.
- Mantén tus respuestas concisas y útiles (máximo 3-4 párrafos cortos).

Tu rol:
- Ayudar al usuario a decidir qué tarea hacer primero.
- Organizar y priorizar tareas según urgencia, dificultad y energía del usuario.
- Sugerir un plan para el día.
- Recomendar cuándo tomar un break.
- Analizar las tareas pendientes y completadas para dar feedback.
- Proponer nuevas micro-tareas cuando tenga sentido.
- Usar SIEMPRE la información real del usuario (tareas, energía, dopamina) en tus respuestas.
- Nunca inventar tareas que el usuario no tiene; puedes sugerir nuevas pero aclarando que son sugerencias.

Formato de respuesta:
- Usa emojis con moderación para hacer la conversación más amigable.
- Cuando recomiendes tareas específicas del usuario, menciónalas entre comillas.
- Si sugieres acciones, indícalas claramente para que el usuario pueda ejecutarlas.
- Para listas, usa viñetas simples.
''';

  // ---------------------------------------------------------------------------
  // Enviar mensaje y obtener respuesta de la IA
  // ---------------------------------------------------------------------------

  /// Envía un mensaje del usuario al modelo de IA y retorna la respuesta.
  ///
  /// Recopila automáticamente el contexto actual de la aplicación
  /// para enriquecer la consulta.
  Future<ChatMessage> sendMessage(String userMessage) async {
    // 1. Agregar mensaje del usuario al historial
    final userMsg = ChatMessage(
      role: ChatRole.user,
      content: userMessage,
    );
    _conversationHistory.add(userMsg);

    // 2. Verificar que tenemos API Key
    if (!isConfigured) {
      final errorMsg = ChatMessage.error(
        'El asistente de IA no está configurado. '
        'Configura la API Key para activar esta funcionalidad.',
      );
      _conversationHistory.add(errorMsg);
      return errorMsg;
    }

    try {
      // 3. Obtener contexto actual de la app
      final contextPrompt = await AIContextService.instance.buildContextPrompt();

      // 4. Construir mensajes para la API
      final apiMessages = <Map<String, String>>[
        {
          'role': 'system',
          'content': '$_systemPromptBase\n\n$contextPrompt',
        },
        // Incluir últimos mensajes del historial (máx 10 para no exceder tokens)
        ..._getRecentMessages(maxMessages: 10),
      ];

      // 5. Llamar a la API del modelo de IA
      final responseContent = await _callAIAPI(apiMessages);

      // 6. Analizar si la respuesta sugiere acciones
      final actions = _extractActions(responseContent);

      // 7. Crear y guardar mensaje de respuesta
      final assistantMsg = ChatMessage(
        role: ChatRole.assistant,
        content: responseContent,
        actions: actions,
      );
      _conversationHistory.add(assistantMsg);

      return assistantMsg;
    } catch (e) {
      final errorMsg = ChatMessage.error(
        'No pude conectarme con el asistente en este momento. '
        'Intenta de nuevo en unos segundos. 🌿',
      );
      _conversationHistory.add(errorMsg);
      return errorMsg;
    }
  }

  /// Obtiene los mensajes recientes para incluir en la API (sin system).
  List<Map<String, String>> _getRecentMessages({int maxMessages = 10}) {
    final recent = _conversationHistory
        .where((m) => !m.isLoading && !m.isError)
        .toList();
    final start = recent.length > maxMessages ? recent.length - maxMessages : 0;
    return recent.sublist(start).map((m) => m.toApiMessage()).toList();
  }

  /// Llama a la API compatible con OpenAI Chat Completions.
  Future<String> _callAIAPI(List<Map<String, String>> messages) async {
    final url = Uri.parse('$_baseUrl/chat/completions');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_apiKey',
    };
    final body = jsonEncode({
      'model': _model,
      'messages': messages,
      'temperature': 0.7,
      'top_p': 0.9,
      'max_tokens': 1024,
      'stream': false,
    });

    final response = await http.Client()
        .post(url, headers: headers, body: body)
        .timeout(requestTimeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final choices = data['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        final message = choices[0]['message'] as Map<String, dynamic>?;
        if (message != null) {
          return message['content'] as String? ?? 'No pude generar una respuesta.';
        }
      }
      return 'No pude generar una respuesta.';
    } else {
      debugPrint('AI API Error: ${response.statusCode} - ${response.body}');
      throw Exception('Error HTTP ${response.statusCode} del servicio de IA');
    }
  }

  // ---------------------------------------------------------------------------
  // Extracción de acciones sugeridas desde la respuesta
  // ---------------------------------------------------------------------------

  /// Analiza la respuesta de la IA para detectar acciones que el usuario
  /// podría ejecutar directamente desde el chat.
  List<AIAction> _extractActions(String response) {
    final actions = <AIAction>[];
    final lower = response.toLowerCase();

    // Detectar si la IA sugiere crear/agregar una nueva tarea
    if (lower.contains('podrías agregar') ||
        lower.contains('te sugiero crear') ||
        lower.contains('nueva tarea') ||
        lower.contains('podrías crear')) {
      actions.add(const AIAction(
        type: AIActionType.agregarTarea,
        label: '➕ Agregar nueva tarea',
      ));
    }

    // Detectar si sugiere organizar/priorizar tareas
    if (lower.contains('organizar') ||
        lower.contains('priorizar') ||
        lower.contains('reordenar') ||
        lower.contains('plan para')) {
      actions.add(const AIAction(
        type: AIActionType.organizarTareas,
        label: '📋 Ir a Mis Tareas',
      ));
    }

    // Detectar si sugiere tomar un break
    if (lower.contains('break') ||
        lower.contains('descanso') ||
        lower.contains('pausa') ||
        lower.contains('descansar')) {
      actions.add(const AIAction(
        type: AIActionType.tomarBreak,
        label: '☁️ Tomar un break',
      ));
    }

    // Detectar si sugiere iniciar foco/concentración
    if (lower.contains('empezar') ||
        lower.contains('iniciar') ||
        lower.contains('enfocarte') ||
        lower.contains('concentrar')) {
      actions.add(const AIAction(
        type: AIActionType.iniciarFoco,
        label: '🎯 Iniciar tarea',
      ));
    }

    return actions;
  }

  // ---------------------------------------------------------------------------
  // Ejecución de acciones sugeridas por la IA
  // ---------------------------------------------------------------------------

  /// Ejecuta una acción sugerida por la IA.
  /// Retorna un mensaje describiendo el resultado.
  Future<String?> executeAction(AIAction action) async {
    switch (action.type) {
      case AIActionType.agregarTarea:
        final titulo = action.payload['titulo'] as String? ?? 'Nueva micro-tarea';
        await DBService.instance.insertarTarea(TareaBloque(
          titulo: titulo,
          subtitulo: 'Suave · 5 min',
          duracionMinutos: 5,
          prioridad: 'Media',
        ));
        return 'Tarea "$titulo" agregada ✨';

      case AIActionType.completarTarea:
        final taskId = action.payload['taskId'] as int?;
        if (taskId != null) {
          final tareas = await DBService.instance.obtenerTareas();
          final tarea = tareas.where((t) => t.id == taskId).firstOrNull;
          if (tarea != null) {
            final actualizada = TareaBloque(
              id: tarea.id,
              titulo: tarea.titulo,
              subtitulo: '¡Hecho! · +${tarea.puntosDopamina} dopamina',
              duracionMinutos: tarea.duracionMinutos,
              estado: EstadoTarea.hecho,
              puntosDopamina: tarea.puntosDopamina,
              microPasos: tarea.microPasos,
              prioridad: tarea.prioridad,
            );
            await DBService.instance.actualizarTarea(actualizada);
            return 'Tarea "${tarea.titulo}" completada 🎉';
          }
        }
        return null;

      case AIActionType.marcarPrioridad:
      case AIActionType.organizarTareas:
      case AIActionType.iniciarFoco:
      case AIActionType.tomarBreak:
        // Estas acciones se manejan como navegación desde el widget de UI
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Mensajes rápidos sugeridos (chips de ejemplo)
  // ---------------------------------------------------------------------------

  /// Sugerencias contextuales para ayudar al usuario a empezar la conversación.
  Future<List<String>> getSuggestedPrompts() async {
    final tareas = await DBService.instance.obtenerTareas();
    final pendientes = tareas.where((t) => t.estado != EstadoTarea.hecho).length;
    final completadas = tareas.where((t) => t.estado == EstadoTarea.hecho).length;

    final prompts = <String>[
      '¿Qué debería hacer primero hoy?',
      'Organiza mis tareas para hoy',
    ];

    if (pendientes > 0) {
      prompts.add('Tengo poco tiempo, ¿qué priorizo?');
    }
    if (completadas > 0) {
      prompts.add('¿Qué podría hacer después?');
    }
    if (pendientes == 0 && completadas > 0) {
      prompts.add('Sugiere nuevas tareas para hoy');
    }
    prompts.add('Ayúdame a planificar mi día');

    return prompts;
  }
}
