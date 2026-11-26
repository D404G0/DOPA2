import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ai_chat_model.dart';
import '../models/task_model.dart';
import 'ai_context_service.dart';
import 'api_service.dart';
import 'db_service.dart';

/// Servicio de comunicación con el Asistente de IA de DOPA.
///
/// Arquitectura modular:
/// - **Modo principal (recomendado / seguro):** Flutter → Backend FastAPI (`/api/v1/ai/chat`)
///   → Python `from openai import OpenAI` (NVIDIA NIM / OpenAI) con contexto real de PostgreSQL.
/// - **Modo directo opcional:** si se inyecta `AI_API_KEY` vía `--dart-define` o `configure()`,
///   puede comunicarse directamente con la API OpenAI-compatible si el backend no está disponible.
class AIChatService {
  static final AIChatService instance = AIChatService._();
  AIChatService._();

  static const String _envBaseUrl = String.fromEnvironment(
    'AI_API_BASE_URL',
    defaultValue: 'https://integrate.api.nvidia.com/v1',
  );

  static const String _envApiKey = String.fromEnvironment(
    'AI_API_KEY',
    defaultValue: '',
  );

  static const String _envModel = String.fromEnvironment(
    'AI_MODEL',
    defaultValue: 'nvidia/nemotron-3.5-bolt-e4b',
  );

  String? _customBaseUrl;
  String? _customApiKey;
  String? _customModel;

  String get _baseUrl => _customBaseUrl ?? _envBaseUrl;
  String get _apiKey => _customApiKey ?? _envApiKey;
  String get _model => _customModel ?? _envModel;

  /// Configura dinámicamente un proveedor directo de IA en runtime (opcional).
  void configure({
    String? baseUrl,
    String? apiKey,
    String? model,
  }) {
    _customBaseUrl = baseUrl;
    _customApiKey = apiKey;
    _customModel = model;
  }

  /// Verdadero si hay API Key directa o el cliente está conectado al backend Docker.
  bool get isConfigured =>
      _apiKey.isNotEmpty || ApiService.instance.isServerReachable;

  Duration requestTimeout = const Duration(seconds: 60);

  final List<ChatMessage> _conversationHistory = [];

  List<ChatMessage> get conversationHistory =>
      List.unmodifiable(_conversationHistory);

  void clearConversation() {
    _conversationHistory.clear();
  }

  static const String _systemPromptBase = '''
Eres el asistente de productividad integrado en DOPA, una aplicación móvil diseñada para personas con TDAH que buscan gestionar sus tareas de forma empática y sin presión.
Responde en español, con tono cálido y conciso (máximo 3-4 párrafos cortos), usando siempre la información real del usuario.
''';

  /// Envía un mensaje del usuario al asistente de IA (vía Backend Docker `/api/v1/ai/chat`).
  Future<ChatMessage> sendMessage(String userMessage) async {
    final trimmed = userMessage.trim();
    // Capturar historial previo antes de agregar el mensaje actual
    final previousHistory = _getRecentMessages(maxMessages: 10);

    final userMsg = ChatMessage(
      role: ChatRole.user,
      content: trimmed,
    );
    _conversationHistory.add(userMsg);

    if (!ApiService.instance.isAuthenticated && _apiKey.isEmpty) {
      final msg = ApiService.instance.isServerReachable
          ? 'Tu servidor Docker está conectado, pero falta iniciar sesión o crear tu cuenta en el botón «• dopa» arriba a la derecha para usar el asistente de IA con tus datos.'
          : 'Conéctate a tu servidor Docker e inicia sesión desde el botón «• dopa» arriba a la derecha para activar el asistente de IA. 🌿';
      final errorMsg = ChatMessage.error(msg);
      _conversationHistory.add(errorMsg);
      return errorMsg;
    }

    // 1. Ruta principal: Backend Docker FastAPI (`/api/v1/ai/chat` usando `from openai import OpenAI`)
    try {
      final backendResult = await ApiService.instance.chatWithAI(
        message: trimmed,
        history: previousHistory,
        section: AIContextService.instance.currentSection,
      );

      final reply = (backendResult['reply'] as String?)?.trim() ??
          'No pude generar una respuesta.';
      final rawActions = backendResult['actions'] as List<dynamic>? ?? const [];
      final parsedActions = _parseBackendActions(rawActions);
      final actions =
          parsedActions.isNotEmpty ? parsedActions : _extractActions(reply);

      final assistantMsg = ChatMessage(
        role: ChatRole.assistant,
        content: reply,
        actions: actions,
      );
      _conversationHistory.add(assistantMsg);
      return assistantMsg;
    } on DopaApiException catch (e) {
      // Si el servidor respondió con un error explícito (ej. 503 sin AI_API_KEY o 401), mostrar detalle claro
      if (_apiKey.isEmpty) {
        final String text;
        if (e.statusCode == 503) {
          text = 'El servidor Docker aún no tiene configurada la variable AI_API_KEY en el archivo .env.';
        } else if (e.statusCode == 401) {
          text = 'Tu sesión venció. Inicia sesión de nuevo en el botón «• dopa» para usar el asistente de IA.';
        } else {
          text = 'El asistente devolvió un error (${e.statusCode}): ${e.message}';
        }
        final errorMsg = ChatMessage.error(text);
        _conversationHistory.add(errorMsg);
        return errorMsg;
      }
    } catch (e) {
      debugPrint('Backend AI chat error, checking direct fallback: $e');
      if (_apiKey.isEmpty) {
        final errorMsg = ChatMessage.error(
          'No pude conectarme con tu servidor Docker (${ApiService.instance.serverRootUrl}). '
          'Verifica la conexión en el botón "• dopa" arriba a la derecha. 🌿',
        );
        _conversationHistory.add(errorMsg);
        return errorMsg;
      }
    }

    // 2. Fallback directo opcional si se configuró una API Key local
    try {
      final contextPrompt = await AIContextService.instance.buildContextPrompt();
      final apiMessages = <Map<String, String>>[
        {
          'role': 'system',
          'content': '$_systemPromptBase\n\n$contextPrompt',
        },
        ...previousHistory,
        {'role': 'user', 'content': trimmed},
      ];

      final responseContent = await _callDirectAIAPI(apiMessages);
      final actions = _extractActions(responseContent);
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

  List<Map<String, String>> _getRecentMessages({int maxMessages = 10}) {
    final recent = _conversationHistory
        .where((m) =>
            !m.isLoading &&
            !m.isError &&
            (m.role == ChatRole.user || m.role == ChatRole.assistant))
        .toList();
    final start = recent.length > maxMessages ? recent.length - maxMessages : 0;
    return recent.sublist(start).map((m) => m.toApiMessage()).toList();
  }

  List<AIAction> _parseBackendActions(List<dynamic> rawActions) {
    final actions = <AIAction>[];
    for (final item in rawActions) {
      if (item is! Map<String, dynamic>) continue;
      final typeName = item['type'] as String? ?? '';
      final label = item['label'] as String? ?? '';
      final payload =
          (item['payload'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
      final type = AIActionType.values.where((e) => e.name == typeName).firstOrNull;
      if (type != null && label.isNotEmpty) {
        actions.add(AIAction(type: type, label: label, payload: payload));
      }
    }
    return actions;
  }

  /// Llamada directa compatible con OpenAI Chat Completions (solo si se configuró API key local).
  Future<String> _callDirectAIAPI(List<Map<String, String>> messages) async {
    final url = Uri.parse('$_baseUrl/chat/completions');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_apiKey',
    };
    final body = jsonEncode({
      'model': _model,
      'messages': messages,
      'temperature': 1,
      'top_p': 0.95,
      'max_tokens': 8192,
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

  List<AIAction> _extractActions(String response) {
    final actions = <AIAction>[];
    final lower = response.toLowerCase();

    if (lower.contains('podrías agregar') ||
        lower.contains('te sugiero crear') ||
        lower.contains('nueva tarea') ||
        lower.contains('podrías crear')) {
      actions.add(const AIAction(
        type: AIActionType.agregarTarea,
        label: '➕ Crear micro-tarea',
      ));
    }

    if (lower.contains('organizar') ||
        lower.contains('priorizar') ||
        lower.contains('reordenar') ||
        lower.contains('plan para')) {
      actions.add(const AIAction(
        type: AIActionType.organizarTareas,
        label: '📋 Ir a Mis Tareas',
      ));
    }

    if (lower.contains('break') ||
        lower.contains('descanso') ||
        lower.contains('pausa') ||
        lower.contains('descansar')) {
      actions.add(const AIAction(
        type: AIActionType.tomarBreak,
        label: '☁️ Tomar un break',
      ));
    }

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

  /// Ejecuta una acción sugerida por la IA.
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
            final actualizada = tarea.copyWith(
              subtitulo: '¡Hecho! · +${tarea.puntosDopamina} dopamina',
              estado: EstadoTarea.hecho,
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
        return null;
    }
  }

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
