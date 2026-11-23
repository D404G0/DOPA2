import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/task_model.dart';
import '../widgets/ai_recommendation_card.dart';
import '../widgets/task_item_tile.dart';
import '../widgets/dopa_card.dart';
import '../widgets/task_editor_sheet.dart';
import '../widgets/server_settings_sheet.dart';
import '../services/db_service.dart';
import '../services/api_service.dart';
import 'soft_focus_screen.dart';

/// Pantalla 2: Mis tareas ("Poquito a poquito").
///
/// Principio UX: Priorización suave y no intrusiva.
/// Conectada con `/api/v1/tasks` (GET, POST, PUT, DELETE, POST complete) y micro-pasos.
class TasksScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const TasksScreen({super.key, this.onBack});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<TareaBloque> _tareas = [];
  int? _selectedTaskId;
  bool _isLoading = false;
  int _filterIndex = 0; // 0: Todas, 1: Pendientes, 2: Hechas

  @override
  void initState() {
    super.initState();
    DBService.instance.dataVersion.addListener(_onDataChanged);
    _cargarTareas();
  }

  @override
  void dispose() {
    DBService.instance.dataVersion.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) {
      _cargarTareas();
    }
  }

  Future<void> _cargarTareas() async {
    final tareasDB = await DBService.instance.obtenerTareas();
    if (!mounted) return;
    setState(() {
      _tareas = tareasDB;
      _isLoading = false;
      // Asegura que la tarea seleccionada siga existiendo; si no, selecciona la primera pendiente.
      final exists = _selectedTaskId != null &&
          _tareas.any((t) => t.id == _selectedTaskId);
      if (!exists) {
        final firstPending = _tareas
            .where((t) => t.estado != EstadoTarea.hecho)
            .firstOrNull;
        _selectedTaskId = firstPending?.id ?? (_tareas.isNotEmpty ? _tareas.first.id : null);
      }
    });
  }

  List<TareaBloque> get _tareasFiltradas {
    switch (_filterIndex) {
      case 1:
        return _tareas.where((t) => t.estado != EstadoTarea.hecho).toList();
      case 2:
        return _tareas.where((t) => t.estado == EstadoTarea.hecho).toList();
      case 0:
      default:
        return _tareas;
    }
  }

  TareaBloque? get _tareaSeleccionada {
    if (_tareas.isEmpty) return null;
    if (_selectedTaskId != null) {
      final found = _tareas.where((t) => t.id == _selectedTaskId).firstOrNull;
      if (found != null) return found;
    }
    return _tareas.where((t) => t.estado != EstadoTarea.hecho).firstOrNull ??
        _tareas.first;
  }

  Future<void> _crearNuevaTarea() async {
    final creada = await TaskEditorSheet.show(context);
    if (creada != null && mounted) {
      setState(() {
        _selectedTaskId = creada.id;
      });
      await _cargarTareas();
    }
  }

  Future<void> _editarTarea(TareaBloque tarea) async {
    final detalle = tarea.id != null
        ? (await DBService.instance.obtenerTareaDetalle(tarea.id!)) ?? tarea
        : tarea;
    if (!mounted) return;
    final editada = await TaskEditorSheet.show(context, existingTask: detalle);
    if (editada != null && mounted) {
      setState(() {
        _selectedTaskId = editada.id;
      });
      await _cargarTareas();
    }
  }

  Future<void> _confirmarEliminarTarea(TareaBloque tarea) async {
    if (tarea.id == null) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.borderDark, width: 1.8),
        ),
        title: const Text(
          'Eliminar tarea',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          '¿Quieres eliminar «${tarea.titulo}» y sus micro-pasos?',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(
                color: Color(0xFFC94A4A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await DBService.instance.eliminarTarea(tarea.id!);
      if (!mounted) return;
      await _cargarTareas();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('«${tarea.titulo}» eliminada'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _iniciarTareaActual() async {
    final tareaActual = _tareaSeleccionada;
    if (tareaActual == null) {
      await _crearNuevaTarea();
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SoftFocusScreen(
          taskId: tareaActual.id,
          taskTitle: tareaActual.titulo,
          microSteps: tareaActual.microPasos,
          durationMinutes: tareaActual.duracionMinutos,
          pointsReward: tareaActual.puntosDopamina,
        ),
      ),
    );
    if (mounted) {
      await _cargarTareas();
    }
  }

  Future<void> _toggleTarea(TareaBloque tarea, bool? nuevoValor) async {
    final isNowDone = nuevoValor == true;
    final tareaActualizada = tarea.copyWith(
      subtitulo: isNowDone
          ? '¡Hecho! · +${tarea.puntosDopamina} dopamina'
          : '${tarea.prioridad == 'Baja' ? 'Fácil' : (tarea.prioridad == 'Alta' ? 'Sin prisa' : 'Suave')} · ${tarea.duracionMinutos} min',
      estado: isNowDone ? EstadoTarea.hecho : EstadoTarea.despues,
    );
    setState(() {
      final idx = _tareas.indexWhere((t) => t.id == tarea.id);
      if (idx != -1) _tareas[idx] = tareaActualizada;
    });
    await DBService.instance.actualizarTarea(tareaActualizada);
    if (!mounted) return;
    if (isNowDone) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('¡Conseguido! +${tarea.puntosDopamina} dopamina ✨'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final int completadas =
        _tareas.where((t) => t.estado == EstadoTarea.hecho).length;
    final String contadorTexto = '$completadas/${_tareas.length}';

    final tareaActiva = _tareaSeleccionada;
    final visibleTasks = _tareasFiltradas;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.borderDark,
          onRefresh: _cargarTareas,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // -------------------------------------------------------------
                // ENCABEZADO: Botón atrás, Título y botón "+ Nueva"
                // -------------------------------------------------------------
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: widget.onBack ?? () => Navigator.maybePop(context),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.borderDark,
                                  width: AppTheme.borderWidth,
                                ),
                              ),
                              child: const Icon(
                                Icons.chevron_left_rounded,
                                color: AppTheme.borderDark,
                                size: 26,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'Mis tareas',
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      key: const Key('add_task_button'),
                      onTap: _crearNuevaTarea,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppTheme.pastelLime,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppTheme.borderDark,
                            width: AppTheme.borderWidth,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded, size: 18, color: AppTheme.borderDark),
                            SizedBox(width: 4),
                            Text(
                              'Nueva',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Banner discreto si el teléfono aún no se conecta a Docker
                ValueListenableBuilder<bool>(
                  valueListenable: ApiService.instance.connectionStatusNotifier,
                  builder: (context, isOnline, _) {
                    if (isOnline) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DopaCard(
                        backgroundColor: AppTheme.pastelPeach,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        borderRadius: 14,
                        onTap: () => ServerSettingsSheet.show(context),
                        child: const Row(
                          children: [
                            Icon(Icons.cloud_off_rounded, size: 18, color: AppTheme.borderDark),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Modo local · Toca aquí para conectar con tu servidor Docker',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.borderDark),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // -------------------------------------------------------------
                // TÍTULO PRINCIPAL Y CONTADOR CIRCULAR (completadas/total)
                // -------------------------------------------------------------
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Poquito a poquito',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Elige solo una para empezar',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppTheme.pastelMint,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.borderDark,
                          width: AppTheme.borderWidth,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          contadorTexto,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Filtros simples: Todas | Pendientes | Hechas
                Container(
                  height: 38,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5EDE8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      _buildFilterTab('Todas (${_tareas.length})', 0),
                      _buildFilterTab(
                        'Pendientes (${_tareas.length - completadas})',
                        1,
                      ),
                      _buildFilterTab('Hechas ($completadas)', 2),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // -------------------------------------------------------------
                // CONTENEDOR DEL AGENTE DE IA (Sugerencia Adaptativa)
                // -------------------------------------------------------------
                const AIRecommendationCard(
                  customMessage:
                      'Empieza por la tarea que te dé más alivio, no por la más grande.',
                ),
                const SizedBox(height: 16),

                // -------------------------------------------------------------
                // LISTA DE TAREAS (o Estado Vacío)
                // -------------------------------------------------------------
                if (_isLoading && _tareas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: CircularProgressIndicator(color: AppTheme.borderDark),
                    ),
                  )
                else if (visibleTasks.isEmpty)
                  DopaCard(
                    backgroundColor: AppTheme.surfaceWhite,
                    padding: const EdgeInsets.all(22),
                    onTap: _crearNuevaTarea,
                    child: Column(
                      children: [
                        const Text('🌱', style: TextStyle(fontSize: 32)),
                        const SizedBox(height: 10),
                        Text(
                          _tareas.isEmpty
                              ? 'Aún no tienes micro-tareas'
                              : 'No hay tareas en este filtro',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Toca aquí o en «+ Nueva» para crear tu primera micro-tarea y guardarla en tu base de datos.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: visibleTasks.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final tarea = visibleTasks[index];
                      final isSelected = tarea.id == _selectedTaskId;

                      return TaskItemTile(
                        tarea: tarea,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            _selectedTaskId = tarea.id;
                          });
                        },
                        onToggle: (nuevoValor) => _toggleTarea(tarea, nuevoValor),
                        onEdit: () => _editarTarea(tarea),
                        onDelete: () => _confirmarEliminarTarea(tarea),
                      );
                    },
                  ),
                const SizedBox(height: 14),

                // -------------------------------------------------------------
                // LEYENDA DE ESTADOS
                // -------------------------------------------------------------
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _StatusLegend(color: AppTheme.pastelPink, label: 'ahora'),
                    SizedBox(width: 16),
                    _StatusLegend(color: Color(0xFF90D0EE), label: 'después'),
                    SizedBox(width: 16),
                    _StatusLegend(color: Color(0xFF6DC89E), label: 'hecho'),
                  ],
                ),
                const SizedBox(height: 20),

                // -------------------------------------------------------------
                // BOTÓN DE ACCIÓN PRIMARIO: Empezar Tarea o Crear Nueva
                // -------------------------------------------------------------
                DopaCard(
                  backgroundColor: AppTheme.pastelLime,
                  padding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 16.0),
                  onTap: _iniciarTareaActual,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        tareaActiva == null
                            ? Icons.add_rounded
                            : Icons.play_arrow_outlined,
                        color: AppTheme.borderDark,
                        size: 26,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          tareaActiva == null
                              ? 'Crear mi primera micro-tarea'
                              : 'Empezar «${tareaActiva.titulo}»',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                                fontSize: 16,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 76),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterTab(String label, int index) {
    final isSelected = _filterIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filterIndex = index),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.surfaceWhite : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Center(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _StatusLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
