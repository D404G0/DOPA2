import 'package:flutter/material.dart';
import '../models/task_model.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import 'dopa_card.dart';

/// Widget Contenedor del Agente de Inteligencia Artificial (FastAPI Backend).
///
/// Este componente muestra las recomendaciones adaptativas del agente inteligente
/// para reducir la sobrecarga cognitiva y evitar la parálisis por análisis.
class AIRecommendationCard extends StatefulWidget {
  final String? customMessage;

  const AIRecommendationCard({
    super.key,
    this.customMessage,
  });

  @override
  State<AIRecommendationCard> createState() => _AIRecommendationCardState();
}

class _AIRecommendationCardState extends State<AIRecommendationCard> {
  late Future<AIRecommendationResponse> _recommendationFuture;

  @override
  void initState() {
    super.initState();
    _recommendationFuture = _loadRecommendation();
  }

  Future<AIRecommendationResponse> _loadRecommendation() async {
    if (ApiService.instance.isAuthenticated) {
      return ApiService.instance.fetchAIRecommendation();
    }
    final tareas = await DBService.instance.obtenerTareas();
    final pendientes =
        tareas.where((t) => t.estado != EstadoTarea.hecho).toList();
    if (pendientes.isEmpty) {
      return AIRecommendationResponse(
        recommendation:
            'Tu tablero está en blanco. Crea un micro-paso de 3 minutos para empezar sin presión.',
        tone: 'gentle',
      );
    }
    return AIRecommendationResponse(
      recommendation:
          'Empieza por «${pendientes.first.titulo}» un solo bloque a la vez.',
      tone: 'gentle',
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AIRecommendationResponse>(
      future: _recommendationFuture,
      builder: (context, snapshot) {
        final message = widget.customMessage ??
            snapshot.data?.recommendation ??
            'Empieza por la tarea que te dé más alivio, no por la más grande.';

        return DopaCard(
          backgroundColor: AppTheme.pastelYellow,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icono de bombillo / idea de bajo estímulo
              Container(
                margin: const EdgeInsets.only(top: 2, right: 12),
                child: const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: AppTheme.textPrimary,
                  size: 24,
                ),
              ),

              // Contenedor del mensaje del Agente de IA
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
