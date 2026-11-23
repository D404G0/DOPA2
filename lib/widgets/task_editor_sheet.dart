import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/task_model.dart';
import '../services/db_service.dart';
import 'dopa_card.dart';

/// Bottom sheet modal de baja fricción para crear o editar una tarea y sus micro-pasos.
/// Persiste directamente contra `/api/v1/tasks` y `/api/v1/tasks/{id}/subtasks`.
class TaskEditorSheet extends StatefulWidget {
  final TareaBloque? existingTask;

  const TaskEditorSheet({super.key, this.existingTask});

  static Future<TareaBloque?> show(
    BuildContext context, {
    TareaBloque? existingTask,
  }) {
    return showModalBottomSheet<TareaBloque>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TaskEditorSheet(existingTask: existingTask),
    );
  }

  @override
  State<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<TaskEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  final TextEditingController _stepInputController = TextEditingController();

  late String _prioridad; // 'Baja', 'Media', 'Alta'
  String? _fechaVencimiento; // YYYY-MM-DD o null

  /// Pasos en edición: si es tarea existente, guardamos referencia de pasos existentes y nuevos.
  final List<MicroPaso> _existingSteps = [];
  final List<int> _deletedStepIds = [];
  final List<String> _newSteps = [];

  bool _isSaving = false;
  String? _validationError;

  bool get _isEditing => widget.existingTask != null && widget.existingTask!.id != null;

  @override
  void initState() {
    super.initState();
    final task = widget.existingTask;
    _titleController = TextEditingController(text: task?.titulo ?? '');
    _descController = TextEditingController(text: task?.descripcion ?? '');
    _prioridad = task?.prioridad ?? 'Media';
    _fechaVencimiento = task?.fechaVencimiento ?? _formatIsoDate(DateTime.now());
    if (task != null) {
      _existingSteps.addAll(task.microPasos);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _stepInputController.dispose();
    super.dispose();
  }

  String _formatIsoDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  void _addStep() {
    final text = _stepInputController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _newSteps.add(text);
      _stepInputController.clear();
    });
  }

  Future<void> _save() async {
    // Si el usuario escribió un micro-paso y olvidó presionar "+", lo incluimos automáticamente
    if (_stepInputController.text.trim().isNotEmpty) {
      _newSteps.add(_stepInputController.text.trim());
      _stepInputController.clear();
    }

    final titulo = _titleController.text.trim();
    if (titulo.isEmpty) {
      setState(() {
        _validationError = 'Escribe un nombre corto para tu micro-tarea.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _validationError = null;
    });

    final descripcion = _descController.text.trim();

    if (_isEditing) {
      final taskId = widget.existingTask!.id!;
      final res = await DBService.instance.editarTarea(
        id: taskId,
        titulo: titulo,
        descripcion: descripcion.isEmpty ? null : descripcion,
        prioridad: _prioridad,
        fechaVencimiento: _fechaVencimiento,
      );

      for (final deletedId in _deletedStepIds) {
        await DBService.instance.eliminarMicroPaso(
          tareaId: taskId,
          microPasoId: deletedId,
        );
      }
      for (final newStepDesc in _newSteps) {
        await DBService.instance.crearMicroPaso(
          tareaId: taskId,
          descripcion: newStepDesc,
        );
      }

      final refreshed =
          await DBService.instance.obtenerTareaDetalle(taskId) ?? res.tarea;
      if (!mounted) return;
      Navigator.pop(context, refreshed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.synced
                ? 'Tarea actualizada y guardada en PostgreSQL ✨'
                : 'Tarea actualizada localmente (sin conexión a Docker)',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      final res = await DBService.instance.crearTarea(
        titulo: titulo,
        descripcion: descripcion.isEmpty ? null : descripcion,
        prioridad: _prioridad,
        fechaVencimiento: _fechaVencimiento,
        subtareas: _newSteps,
      );
      if (!mounted) return;
      Navigator.pop(context, res.tarea);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.synced
                ? 'Tarea «${res.tarea.titulo}» guardada en la base de datos ✨'
                : 'Tarea creada localmente (conéctate a Docker para guardarla en BD)',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final todayIso = _formatIsoDate(DateTime.now());
    final tomorrowIso = _formatIsoDate(DateTime.now().add(const Duration(days: 1)));

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: AppTheme.borderDark, width: 2),
          left: BorderSide(color: AppTheme.borderDark, width: 2),
          right: BorderSide(color: AppTheme.borderDark, width: 2),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle superior
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppTheme.borderDark.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Encabezado
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _isEditing ? 'Editar micro-tarea' : 'Nueva micro-tarea',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: AppTheme.borderDark),
                  ),
                ],
              ),
              Text(
                'Empieza con algo concreto y pequeño. Siempre puedes editarlo después.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
              ),
              const SizedBox(height: 14),

              if (_validationError != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.pastelPink,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.borderDark, width: 1.4),
                  ),
                  child: Text(
                    _validationError!,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],

              // Título
              Text(
                '¿Qué quieres lograr?',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                autofocus: !_isEditing,
                decoration: _fieldDecoration('Ej. Ordenar el escritorio o estudiar 10 min'),
              ),
              const SizedBox(height: 14),

              // Descripción opcional
              Text(
                'Nota opcional',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _descController,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                decoration: _fieldDecoration('Un recordatorio amable sin presión...'),
              ),
              const SizedBox(height: 16),

              // Nivel de esfuerzo / Prioridad
              Text(
                'Nivel de esfuerzo',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildEffortChip(
                    label: 'Fácil',
                    subtitle: '3 min',
                    value: 'Baja',
                    color: AppTheme.pastelMint,
                  ),
                  const SizedBox(width: 8),
                  _buildEffortChip(
                    label: 'Suave',
                    subtitle: '5 min',
                    value: 'Media',
                    color: AppTheme.pastelYellow,
                  ),
                  const SizedBox(width: 8),
                  _buildEffortChip(
                    label: 'Sin prisa',
                    subtitle: '8 min',
                    value: 'Alta',
                    color: AppTheme.pastelPink,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Fecha rápida
              Text(
                '¿Para cuándo?',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildDateChip('Hoy', todayIso),
                  const SizedBox(width: 8),
                  _buildDateChip('Mañana', tomorrowIso),
                  const SizedBox(width: 8),
                  _buildDateChip('Sin fecha', null),
                ],
              ),
              const SizedBox(height: 18),

              // Micro-pasos
              Text(
                'Micro-pasos (opcional)',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Divide la tarea en pasitos muy fáciles para vencer el bloqueo.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _stepInputController,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _addStep(),
                      decoration: _fieldDecoration('Ej. Abrir el cuaderno y leer 1 página'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _addStep,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.pastelYellow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.borderDark, width: 1.8),
                      ),
                      child: const Icon(Icons.add_rounded, color: AppTheme.borderDark, size: 26),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Lista de pasos existentes (en edición)
              ..._existingSteps.asMap().entries.map((entry) {
                final idx = entry.key;
                final step = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DopaCard(
                    backgroundColor: AppTheme.surfaceWhite,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    borderRadius: 14,
                    child: Row(
                      children: [
                        Icon(
                          step.completado
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 18,
                          color: step.completado
                              ? const Color(0xFF4CAF7D)
                              : AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            step.descripcion,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              if (step.id != null) {
                                _deletedStepIds.add(step.id!);
                              }
                              _existingSteps.removeAt(idx);
                            });
                          },
                          child: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              // Lista de pasos nuevos por guardar
              ..._newSteps.asMap().entries.map((entry) {
                final idx = entry.key;
                final desc = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DopaCard(
                    backgroundColor: AppTheme.pastelYellow.withValues(alpha: 0.45),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    borderRadius: 14,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.subdirectory_arrow_right_rounded,
                          size: 18,
                          color: AppTheme.borderDark,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            desc,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _newSteps.removeAt(idx)),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 16),

              // Botón Guardar
              DopaCard(
                backgroundColor: AppTheme.pastelLime,
                padding: const EdgeInsets.symmetric(vertical: 16),
                borderRadius: AppTheme.radiusLarge,
                onTap: _isSaving ? null : _save,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isSaving)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: AppTheme.borderDark,
                        ),
                      )
                    else
                      const Icon(Icons.check_rounded, color: AppTheme.borderDark, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      _isSaving
                          ? 'Guardando...'
                          : (_isEditing ? 'Guardar cambios' : 'Crear micro-tarea'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEffortChip({
    required String label,
    required String subtitle,
    required String value,
    required Color color,
  }) {
    final selected = _prioridad == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _prioridad = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? color : AppTheme.surfaceWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.borderDark,
              width: selected ? 2.4 : 1.3,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateChip(String label, String? value) {
    final selected = _fechaVencimiento == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _fechaVencimiento = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppTheme.pastelBlue : AppTheme.surfaceWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.borderDark,
              width: selected ? 2.2 : 1.2,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: AppTheme.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppTheme.surfaceWhite,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppTheme.borderDark, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppTheme.borderDark, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppTheme.borderDark, width: 2.2),
      ),
    );
  }
}
