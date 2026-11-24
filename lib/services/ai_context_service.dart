import '../models/task_model.dart';
import '../models/user_model.dart';
import 'db_service.dart';

/// Servicio que recopila el contexto actual de la aplicación DOPA
/// para enriquecer las solicitudes al modelo de IA.
///
/// Reúne información de tareas, usuario, energía, dopamina y la
/// sección activa para que las recomendaciones del asistente sean
/// relevantes y personalizadas.
class AIContextService {
  static final AIContextService instance = AIContextService._();
  AIContextService._();

  /// Nombre de la sección/pestaña actual donde se encuentra el usuario.
  String _currentSection = 'Inicio';

  /// Actualiza la sección actual del usuario (llamado desde MainNavigationScreen).
  void setCurrentSection(String section) {
    _currentSection = section;
  }

  String get currentSection => _currentSection;

  /// Genera un resumen textual completo del contexto actual de la app
  /// para incluir como mensaje `system` en la conversación con la IA.
  Future<String> buildContextPrompt() async {
    final buffer = StringBuffer();

    // 1. Información del usuario
    final Usuario usuario = await DBService.instance.getUsuario();
    buffer.writeln('=== CONTEXTO ACTUAL DE LA APP DOPA ===');
    buffer.writeln('Fecha y hora actual: ${DateTime.now().toIso8601String()}');
    buffer.writeln('');
    buffer.writeln('## Usuario');
    buffer.writeln('- Nombre: ${usuario.nombre}');
    buffer.writeln('- Nivel de energía: ${_describeEnergy(usuario.energiaNivel)}');
    buffer.writeln('- Dopamina acumulada hoy: ${usuario.dopaminaActual} pts');
    buffer.writeln('- Meta diaria de dopamina: ${usuario.dopaminaMeta} pts');
    buffer.writeln('- Racha de días activos: ${usuario.rachaDias} días');
    buffer.writeln('- Nivel del usuario: ${usuario.nivel}');
    buffer.writeln('');

    // 2. Sección actual
    buffer.writeln('## Sección activa');
    buffer.writeln('- El usuario está en: $_currentSection');
    buffer.writeln('');

    // 3. Tareas
    final List<TareaBloque> tareas = await DBService.instance.obtenerTareas();
    final pendientes = tareas.where((t) => t.estado != EstadoTarea.hecho).toList();
    final completadas = tareas.where((t) => t.estado == EstadoTarea.hecho).toList();
    final ahora = tareas.where((t) => t.estado == EstadoTarea.ahora).toList();

    buffer.writeln('## Resumen de Tareas');
    buffer.writeln('- Total de tareas: ${tareas.length}');
    buffer.writeln('- Pendientes: ${pendientes.length}');
    buffer.writeln('- Completadas hoy: ${completadas.length}');
    buffer.writeln('- Marcadas como "ahora": ${ahora.length}');
    buffer.writeln('');

    if (pendientes.isNotEmpty) {
      buffer.writeln('## Tareas Pendientes (detalle)');
      for (int i = 0; i < pendientes.length; i++) {
        final t = pendientes[i];
        buffer.writeln('${i + 1}. "${t.titulo}"');
        buffer.writeln('   - Prioridad: ${t.prioridad}');
        buffer.writeln('   - Duración estimada: ${t.duracionMinutos} min');
        buffer.writeln('   - Nivel de estrés: ${_describeStress(t.estresNivel)}');
        buffer.writeln('   - Puntos de dopamina: +${t.puntosDopamina}');
        buffer.writeln('   - Estado: ${t.estado == EstadoTarea.ahora ? "Marcada como AHORA" : "Para después"}');
        if (t.microPasos.isNotEmpty) {
          final completados = t.microPasos.where((m) => m.completado).length;
          buffer.writeln('   - Micro-pasos: $completados/${t.microPasos.length} completados');
          for (final paso in t.microPasos) {
            buffer.writeln('     ${paso.completado ? "✓" : "○"} ${paso.descripcion}');
          }
        }
      }
      buffer.writeln('');
    }

    if (completadas.isNotEmpty) {
      buffer.writeln('## Tareas Completadas Hoy');
      for (final t in completadas) {
        buffer.writeln('- ✓ "${t.titulo}" (+${t.puntosDopamina} dopamina)');
      }
      buffer.writeln('');
    }

    // 4. Progreso del día
    final double progresoDia = tareas.isEmpty
        ? 0.0
        : completadas.length / tareas.length;
    buffer.writeln('## Progreso del día');
    buffer.writeln('- Tareas completadas: ${(progresoDia * 100).toInt()}%');
    buffer.writeln('- Dopamina: ${usuario.dopaminaActual}/${usuario.dopaminaMeta} pts (${((usuario.dopaminaActual / usuario.dopaminaMeta) * 100).toInt()}%)');

    return buffer.toString();
  }

  String _describeEnergy(double nivel) {
    if (nivel < 0.25) return 'Muy baja ($nivel)';
    if (nivel < 0.4) return 'Baja ($nivel)';
    if (nivel < 0.6) return 'Media ($nivel)';
    if (nivel < 0.8) return 'Alta ($nivel)';
    return 'Muy alta ($nivel)';
  }

  String _describeStress(double nivel) {
    if (nivel < 0.15) return 'Muy bajo';
    if (nivel < 0.3) return 'Bajo';
    if (nivel < 0.5) return 'Medio';
    return 'Alto';
  }
}
