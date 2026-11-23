import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/task_model.dart';
import '../models/focus_session_model.dart';
import '../widgets/dopa_card.dart';
import '../services/db_service.dart';
import 'session_success_screen.dart';

/// Pantalla 3: Enfoque suave (Temporizador Pomodoro y Micro-pasos reales).
///
/// Principio UX: Reducción drástica del estrés ejecutivo.
/// Conectada con `/api/v1/tasks/{id}`, `/api/v1/tasks/{id}/subtasks`,
/// `/api/v1/tasks/{id}/complete` y `/api/v1/pomodoro/sessions`.
class SoftFocusScreen extends StatefulWidget {
  final int? taskId;
  final String taskTitle;
  final List<MicroPaso> microSteps;
  final int durationMinutes;
  final int pointsReward;

  const SoftFocusScreen({
    super.key,
    this.taskId,
    this.taskTitle = 'Hacer la cama',
    this.microSteps = const [],
    this.durationMinutes = 5,
    this.pointsReward = 10,
  });

  @override
  State<SoftFocusScreen> createState() => _SoftFocusScreenState();
}

class _SoftFocusScreenState extends State<SoftFocusScreen> {
  late int _selectedMinutes;
  late int _remainingSeconds;
  bool _isRunning = false;
  bool _isCompleting = false;
  Timer? _timer;

  late List<MicroPaso> _steps;
  final TextEditingController _newStepController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedMinutes = widget.durationMinutes.clamp(1, 60);
    _remainingSeconds = _selectedMinutes * 60;
    _steps = widget.microSteps
        .map(
          (m) => MicroPaso(
            id: m.id,
            tareaId: m.tareaId,
            descripcion: m.descripcion,
            completado: m.completado,
          ),
        )
        .toList();
    _cargarDetalleTarea();
  }

  Future<void> _cargarDetalleTarea() async {
    if (widget.taskId == null) return;
    final detalle = await DBService.instance.obtenerTareaDetalle(widget.taskId!);
    if (!mounted || detalle == null) return;
    setState(() {
      _steps = detalle.microPasos
          .map(
            (m) => MicroPaso(
              id: m.id,
              tareaId: m.tareaId,
              descripcion: m.descripcion,
              completado: m.completado,
            ),
          )
          .toList();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _newStepController.dispose();
    super.dispose();
  }

  void _selectDuration(int minutes) {
    if (_isRunning) return;
    setState(() {
      _selectedMinutes = minutes;
      _remainingSeconds = minutes * 60;
    });
  }

  void _toggleTimer() {
    if (_isRunning) {
      _timer?.cancel();
      setState(() => _isRunning = false);
    } else {
      setState(() => _isRunning = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_remainingSeconds > 0) {
          setState(() => _remainingSeconds--);
        } else {
          _timer?.cancel();
          setState(() => _isRunning = false);
          _completarSesion();
        }
      });
    }
  }

  Future<void> _toggleMicroStep(int stepIndex) async {
    final step = _steps[stepIndex];
    final nextValue = !step.completado;
    setState(() {
      _steps[stepIndex].completado = nextValue;
    });

    if (widget.taskId != null && step.id != null) {
      await DBService.instance.actualizarMicroPaso(
        tareaId: widget.taskId!,
        microPasoId: step.id!,
        completado: nextValue,
      );
    }
  }

  Future<void> _agregarMicroPaso() async {
    final desc = _newStepController.text.trim();
    if (desc.isEmpty) return;
    _newStepController.clear();

    if (widget.taskId != null) {
      final res = await DBService.instance.crearMicroPaso(
        tareaId: widget.taskId!,
        descripcion: desc,
      );
      if (!mounted) return;
      setState(() {
        _steps.add(res.paso);
      });
    } else {
      setState(() {
        _steps.add(MicroPaso(descripcion: desc, completado: false));
      });
    }
  }

  Future<void> _eliminarMicroPaso(int index) async {
    final step = _steps[index];
    setState(() {
      _steps.removeAt(index);
    });
    if (widget.taskId != null && step.id != null) {
      await DBService.instance.eliminarMicroPaso(
        tareaId: widget.taskId!,
        microPasoId: step.id!,
      );
    }
  }

  Future<void> _completarSesion() async {
    if (_isCompleting) return;
    setState(() => _isCompleting = true);
    _timer?.cancel();

    final tareaId = widget.taskId;

    // 1. Marcar tarea como completada en el backend (`/api/v1/tasks/{id}/complete`)
    if (tareaId != null) {
      await DBService.instance.actualizarTarea(
        TareaBloque(
          id: tareaId,
          titulo: widget.taskTitle,
          subtitulo: '¡Hecho! · +${widget.pointsReward} dopamina',
          duracionMinutos: _selectedMinutes,
          estado: EstadoTarea.hecho,
          puntosDopamina: widget.pointsReward,
          microPasos: _steps,
        ),
      );
    }

    // 2. Guardar la sesión de enfoque completada (`/api/v1/pomodoro/sessions`)
    await DBService.instance.registrarSesion(
      SesionEnfoque(
        tareaId: tareaId,
        duracionSegundos: _selectedMinutes * 60,
        completada: true,
      ),
    );

    final totalHoy = await DBService.instance.obtenerTotalDopaminaHoy();
    final userName = DBService.instance.usuarioActualCache.nombre.split(' ').first;

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => SessionSuccessScreen(
          userName: userName.isEmpty ? 'Fred' : userName,
          taskTitle: widget.taskTitle,
          stepsCount: _steps.length,
          dopamineGained: widget.pointsReward,
          totalDopamineToday: totalHoy,
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final int firstPendingIndex = _steps.indexWhere((s) => !s.completado);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // -------------------------------------------------------------
              // ENCABEZADO: Volver, Título y Salir
              // -------------------------------------------------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.maybePop(context),
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
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            'Enfoque suave',
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
                    onTap: () => Navigator.maybePop(context),
                    child: Text(
                      'Salir',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // -------------------------------------------------------------
              // TARJETA DE TAREA ACTUAL (Verde Lima Pastel)
              // -------------------------------------------------------------
              DopaCard(
                backgroundColor: AppTheme.pastelLime,
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.album_outlined,
                          size: 16,
                          color: AppTheme.borderDark,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'TAREA ACTUAL',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: AppTheme.borderDark,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.taskTitle,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Solo mira el siguiente paso. Lo demás puede esperar.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.textPrimary.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // -------------------------------------------------------------
              // SECCIÓN: MICRO-PASOS DINÁMICOS DE LA TAREA REAL
              // -------------------------------------------------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Micro-pasos',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if (_steps.isNotEmpty)
                    Text(
                      '${_steps.where((s) => s.completado).length}/${_steps.length} listos',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              if (_steps.isEmpty)
                DopaCard(
                  backgroundColor: AppTheme.surfaceWhite,
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'Esta tarea aún no tiene micro-pasos. Puedes enfocarte directo o dividirla abajo en pasos pequeños.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                )
              else
                ..._steps.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final step = entry.value;
                  final bool isCurrentNext = idx == firstPendingIndex;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DopaCard(
                      backgroundColor: isCurrentNext
                          ? AppTheme.pastelYellow
                          : AppTheme.surfaceWhite,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      onTap: () => _toggleMicroStep(idx),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: step.completado
                                  ? const Color(0xFF6DC89E)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.borderDark,
                                width: 1.5,
                              ),
                            ),
                            child: step.completado
                                ? const Icon(Icons.check, size: 18, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              step.descripcion,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight:
                                        isCurrentNext ? FontWeight.w800 : FontWeight.w700,
                                    decoration: step.completado
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                            ),
                          ),
                          if (step.completado)
                            Text(
                              'listo',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: const Color(0xFF5BAA86),
                                    fontWeight: FontWeight.w700,
                                  ),
                            )
                          else if (isCurrentNext)
                            const Icon(
                              Icons.auto_awesome,
                              size: 18,
                              color: AppTheme.borderDark,
                            ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _eliminarMicroPaso(idx),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 8),
              // Input rápido para añadir un nuevo micro-paso en caliente
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newStepController,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _agregarMicroPaso(),
                      decoration: InputDecoration(
                        hintText: 'Agregar un micro-paso...',
                        filled: true,
                        fillColor: AppTheme.surfaceWhite,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppTheme.borderDark,
                            width: 1.4,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppTheme.borderDark,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _agregarMicroPaso,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.pastelYellow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.borderDark,
                          width: 1.6,
                        ),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: AppTheme.borderDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // -------------------------------------------------------------
              // TEMPORIZADOR POMODORO AMIGABLE
              // -------------------------------------------------------------
              DopaCard(
                backgroundColor: AppTheme.surfaceWhite,
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppTheme.coralRed,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.borderDark,
                              width: AppTheme.borderWidth,
                            ),
                          ),
                          child: const Center(
                            child: Text('🌱', style: TextStyle(fontSize: 28)),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Enfoque',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textSecondary,
                                    ),
                              ),
                              Text(
                                _formatTime(_remainingSeconds),
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.0,
                                      color: AppTheme.textPrimary,
                                    ),
                              ),
                              Text(
                                'minutos · sin notificaciones',
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: AppTheme.textMuted,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Presets rápidos de tiempo (cuando no está corriendo)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [3, 5, 10, 15, 25].map((mins) {
                        final selected = _selectedMinutes == mins;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GestureDetector(
                            onTap: _isRunning ? null : () => _selectDuration(mins),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppTheme.pastelBlue
                                    : AppTheme.background,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.borderDark,
                                  width: selected ? 1.8 : 1.0,
                                ),
                              ),
                              child: Text(
                                '${mins}m',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Botón Rosa: Iniciar / Pausar
                    DopaCard(
                      backgroundColor: AppTheme.pastelPink,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      borderRadius: AppTheme.radiusLarge,
                      onTap: _toggleTimer,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isRunning
                                ? Icons.pause_rounded
                                : Icons.play_arrow_outlined,
                            color: AppTheme.borderDark,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _isRunning
                                  ? 'Pausar temporizador'
                                  : 'Iniciar temporizador',
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textPrimary,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // -------------------------------------------------------------
              // BANNER INFERIOR DE RECOMPENSA DIRECTA
              // -------------------------------------------------------------
              DopaCard(
                backgroundColor: AppTheme.pastelMint,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                borderRadius: AppTheme.radiusLarge,
                onTap: _isCompleting ? null : _completarSesion,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _isCompleting ? 'Guardando logro...' : '¡Conseguido!',
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('✨', style: TextStyle(fontSize: 18)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '(+${widget.pointsReward} dopamina)',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
