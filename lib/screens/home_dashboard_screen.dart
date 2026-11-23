import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/dopa_card.dart';
import '../widgets/energy_bar.dart';
import '../widgets/server_settings_sheet.dart';
import '../widgets/task_editor_sheet.dart';
import '../services/db_service.dart';
import '../services/api_service.dart';
import '../models/task_model.dart';
import 'soft_focus_screen.dart';

/// Pantalla 1: Inicio (Dashboard de Cero Fricción Cognitiva).
///
/// Principio UX: "Single Source of Truth".
/// Conectada con `/api/v1/dashboard`, `/api/v1/dashboard/energy-checkin` y `/api/v1/dashboard/quick-task`.
class HomeDashboardScreen extends StatefulWidget {
  final VoidCallback onNavigateToTasks;
  final VoidCallback onNavigateToBreak;

  const HomeDashboardScreen({
    super.key,
    required this.onNavigateToTasks,
    required this.onNavigateToBreak,
  });

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  String _saludo = '¡Hola, Fred!';
  String _subtitulo = 'Vamos un paso a la vez';
  double _energyLevel = 0.45;
  int _pendientesCount = 2;
  TareaBloque? _quickTask;
  String _quickTaskTitle = 'Poner un vaso de agua cerca';
  int? _quickTaskId = 2;
  int _quickTaskDuration = 5;
  double _quickTaskStress = 0.35;
  List<MicroPaso> _quickTaskSteps = const [];
  bool _hasNoPendingTasks = false;

  @override
  void initState() {
    super.initState();
    DBService.instance.dataVersion.addListener(_onDataChanged);
    _sincronizarDashboard();
  }

  @override
  void dispose() {
    DBService.instance.dataVersion.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) {
      _sincronizarDashboard();
    }
  }

  Future<void> _sincronizarDashboard() async {
    try {
      final dashboard = await ApiService.instance.getDashboard();
      if (!mounted) return;
      final estadoEnergia =
          (dashboard['estado_energia_hoy'] as String? ?? 'media').toLowerCase();
      double parsedEnergy = 0.5;
      if (estadoEnergia == 'poquita' || estadoEnergia == 'baja') {
        parsedEnergy = 0.2;
      } else if (estadoEnergia == 'a tope' || estadoEnergia == 'alta') {
        parsedEnergy = 0.85;
      }

      setState(() {
        if (dashboard['saludo'] is String) {
          _saludo = dashboard['saludo'] as String;
        }
        if (dashboard['subtitulo_amigable'] is String) {
          _subtitulo = dashboard['subtitulo_amigable'] as String;
        }
        _energyLevel = parsedEnergy;

        final resumen = dashboard['resumen_tareas'] as Map<String, dynamic>?;
        if (resumen != null && resumen['pendientes'] is int) {
          _pendientesCount = resumen['pendientes'] as int;
        }

        final microTareas = dashboard['micro_tareas_hoy'] as List<dynamic>?;
        if (microTareas != null && microTareas.isNotEmpty) {
          final first = microTareas.first;
          if (first is Map<String, dynamic>) {
            final mapped =
                TareaBloque.fromBackendJson(first, isFirstPending: true);
            _quickTask = mapped;
            _quickTaskTitle = mapped.titulo;
            _quickTaskId = mapped.id;
            _quickTaskDuration = mapped.duracionMinutos;
            _quickTaskStress = mapped.estresNivel;
            _quickTaskSteps = mapped.microPasos;
            _hasNoPendingTasks = false;
          }
        } else {
          _quickTask = null;
          _quickTaskId = null;
          _quickTaskSteps = const [];
          _hasNoPendingTasks = true;
        }
      });
    } catch (_) {
      final usuario = await DBService.instance.getUsuario();
      if (!mounted) return;
      setState(() {
        _energyLevel = usuario.energiaNivel;
        if (usuario.nombre.isNotEmpty) {
          _saludo = '¡Hola, ${usuario.nombre.split(' ').first}!';
        }
      });
    }
  }

  Future<void> _onEnergyChanged(double newLevel) async {
    setState(() {
      _energyLevel = newLevel;
    });
    final res = await DBService.instance.registrarCheckinEnergia(
      energiaNivel: newLevel,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.sugerencia),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _stressLabel(double stress) {
    if (stress <= 0.2) return 'Estrés: bajito';
    if (stress <= 0.35) return 'Estrés: suave';
    return 'Estrés: moderado';
  }

  Future<void> _abrirNuevaTareaRapida() async {
    final creada = await TaskEditorSheet.show(context);
    if (creada != null && mounted) {
      await _sincronizarDashboard();
    }
  }

  Future<void> _abrirQuickTask() async {
    if (_hasNoPendingTasks) {
      await _abrirNuevaTareaRapida();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SoftFocusScreen(
          taskId: _quickTaskId,
          taskTitle: _quickTaskTitle,
          microSteps: _quickTaskSteps,
          durationMinutes: _quickTask?.duracionMinutos ?? _quickTaskDuration,
          pointsReward: _quickTask?.puntosDopamina ?? 10,
        ),
      ),
    );
    if (mounted) {
      _sincronizarDashboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.borderDark,
          onRefresh: _sincronizarDashboard,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // -------------------------------------------------------------
                // ENCABEZADO: Saludo empático y botón de conexión Docker/Cuenta
                // -------------------------------------------------------------
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              _saludo,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('✨', style: TextStyle(fontSize: 22)),
                        ],
                      ),
                    ),
                    // Pill interactivo "• dopa" con estado de conexión a Docker
                    ValueListenableBuilder<bool>(
                      valueListenable: ApiService.instance.connectionStatusNotifier,
                      builder: (context, isOnline, _) {
                        return GestureDetector(
                          key: const Key('server_settings_button'),
                          onTap: () => ServerSettingsSheet.show(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceWhite,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: AppTheme.borderDark,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: isOnline
                                        ? const Color(0xFF3FB97F)
                                        : const Color(0xFFE08A4E),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'dopa',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.textPrimary,
                                        fontSize: 14,
                                      ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.tune_rounded,
                                  size: 16,
                                  color: AppTheme.borderDark,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitulo,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                ),
                const SizedBox(height: 20),

                // -------------------------------------------------------------
                // 1. MEDIDOR DE ENERGÍA Y DOPAMINA (Interactivo -> PostgreSQL)
                // -------------------------------------------------------------
                EnergyDopamineCard(
                  energyLevel: _energyLevel,
                  emoji: '😌',
                  onEnergyChanged: _onEnergyChanged,
                ),
                const SizedBox(height: 18),

                // -------------------------------------------------------------
                // 2. ACCIONES RÁPIDAS BINARIAS (Baja Fricción Cognitiva)
                // -------------------------------------------------------------
                Row(
                  children: [
                    // Botón Rosa: "¡Hacer algo fácil!"
                    Expanded(
                      child: DopaCard(
                        backgroundColor: AppTheme.pastelPink,
                        padding: const EdgeInsets.symmetric(vertical: 22.0, horizontal: 12.0),
                        onTap: widget.onNavigateToTasks,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.auto_awesome, color: AppTheme.borderDark, size: 28),
                            const SizedBox(height: 12),
                            Text(
                              '¡Hacer algo fácil!',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textPrimary,
                                    fontSize: 15,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Botón Celeste: "¡Tomar un break!"
                    Expanded(
                      child: DopaCard(
                        backgroundColor: AppTheme.pastelBlue,
                        padding: const EdgeInsets.symmetric(vertical: 22.0, horizontal: 12.0),
                        onTap: widget.onNavigateToBreak,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.nightlight_round_outlined, color: AppTheme.borderDark, size: 28),
                            const SizedBox(height: 12),
                            Text(
                              '¡Tomar un break!',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textPrimary,
                                    fontSize: 15,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // -------------------------------------------------------------
                // 3. SECCIÓN: MIS MICRO-TAREAS (Siguiente paso sin abrumar)
                // -------------------------------------------------------------
                DopaCard(
                  backgroundColor: AppTheme.surfaceWhite,
                  padding: const EdgeInsets.all(18.0),
                  onTap: _abrirQuickTask,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Título de la sección y contador de pendientes
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Mis micro-tareas',
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textPrimary,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '$_pendientesCount pendientes',
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      if (_hasNoPendingTasks) ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.celebration_outlined,
                              color: AppTheme.borderDark,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '¡Sin pendientes! Toca aquí para crear una nueva micro-tarea.',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        // Micro-tarea inmediata real
                        Row(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: AppTheme.pastelYellow,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.borderDark,
                                  width: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _quickTaskTitle,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                              ),
                            ),
                            Text(
                              '$_quickTaskDuration min',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Indicador de nivel de estrés dinámico
                        Row(
                          children: [
                            Text(
                              _stressLabel(_quickTaskStress),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE5EDE8),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: _quickTaskStress.clamp(0.15, 0.9),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF67C297),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Botón rápido para agregar una tarea propia desde Inicio
                DopaCard(
                  backgroundColor: AppTheme.pastelLime,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  borderRadius: AppTheme.radiusMedium,
                  onTap: _abrirNuevaTareaRapida,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_circle_outline_rounded, color: AppTheme.borderDark, size: 22),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Crear nueva micro-tarea',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
