import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../models/task_model.dart';
import '../models/focus_session_model.dart';
import '../models/wellness_record_model.dart';
import '../models/reward_model.dart';
import 'api_service.dart';

/// Servicio de Persistencia Híbrida (Sincronización REST FastAPI `/api/v1` + Caché Local Offline-First).
///
/// Agente Responsable: Agent_Frontend & Agent_Backend
/// Conecta todas las pantallas de Flutter con los endpoints del Backend FastAPI y
/// mantiene un respaldo en memoria para garantizar respuesta instantánea y
/// tolerancia a desconexiones móviles.
class DBService {
  static final DBService instance = DBService._init();
  DBService._init();

  /// Notificador reactivo: se incrementa ante cualquier mutación o cambio de cuenta/servidor
  /// para que todas las pestañas (Inicio, Tareas, Dopamina) se sincronicen automáticamente.
  final ValueNotifier<int> dataVersion = ValueNotifier<int>(0);

  bool _isSyncedWithServer = false;
  String? _lastSyncError;

  bool get isSyncedWithServer => _isSyncedWithServer;
  String? get lastSyncError => _lastSyncError;

  void notifyDataChanged() {
    dataVersion.value++;
  }

  /// Limpia la caché en memoria al cambiar de cuenta o de servidor Docker.
  void resetCacheForSessionChange() {
    _tareasCache = [];
    _isSyncedWithServer = false;
    _lastSyncError = null;
    notifyDataChanged();
  }

  Usuario _usuarioCache = Usuario(
    id: 1,
    nombre: 'Fred',
    dopaminaActual: 32,
    dopaminaMeta: 50,
    rachaDias: 4,
    energiaNivel: 0.45,
  );

  List<TareaBloque> _tareasCache = [
    TareaBloque(
      id: 1,
      titulo: 'Hacer la cama',
      subtitulo: 'Fácil · 1/2 pasos · 5 min',
      descripcion: 'Un solo paso pequeño basta para empezar el día con calma.',
      duracionMinutos: 5,
      estado: EstadoTarea.ahora,
      puntosDopamina: 10,
      estresNivel: 0.15,
      prioridad: 'Media',
      microPasos: [
        MicroPaso(
          id: 1,
          tareaId: 1,
          descripcion: '1. Estirar las sábanas',
          completado: true,
        ),
        MicroPaso(
          id: 2,
          tareaId: 1,
          descripcion: '2. Colocar almohadas',
          completado: false,
        ),
      ],
    ),
    TareaBloque(
      id: 2,
      titulo: 'Responder a Ana',
      subtitulo: 'Sin prisa · 1/2 pasos · 8 min',
      descripcion: 'Enviar confirmación breve sobre la reunión de mañana.',
      duracionMinutos: 8,
      estado: EstadoTarea.despues,
      puntosDopamina: 10,
      estresNivel: 0.35,
      prioridad: 'Alta',
      microPasos: [
        MicroPaso(
          id: 3,
          tareaId: 2,
          descripcion: '1. Abrir el chat de Ana',
          completado: true,
        ),
        MicroPaso(
          id: 4,
          tareaId: 2,
          descripcion: '2. Escribir respuesta de 2 líneas y enviar',
          completado: false,
        ),
      ],
    ),
    TareaBloque(
      id: 3,
      titulo: 'Guardar la ropa',
      subtitulo: 'Suave · 0/2 pasos · 5 min',
      descripcion: 'Doblar solo las prendas que están sobre la silla.',
      duracionMinutos: 5,
      estado: EstadoTarea.despues,
      puntosDopamina: 10,
      estresNivel: 0.25,
      prioridad: 'Media',
      microPasos: [
        MicroPaso(
          id: 5,
          tareaId: 3,
          descripcion: '1. Separar camisetas de pantalones',
          completado: false,
        ),
        MicroPaso(
          id: 6,
          tareaId: 3,
          descripcion: '2. Guardar en el primer cajón',
          completado: false,
        ),
      ],
    ),
    TareaBloque(
      id: 4,
      titulo: 'Preparar la botella',
      subtitulo: '¡Hecho! · +10 dopamina',
      descripcion: 'Llenar la botella de agua para el escritorio.',
      duracionMinutos: 3,
      estado: EstadoTarea.hecho,
      puntosDopamina: 10,
      estresNivel: 0.1,
      prioridad: 'Baja',
    ),
  ];

  void _markOnline() {
    _isSyncedWithServer = true;
    _lastSyncError = null;
  }

  void _markOffline(Object error) {
    _isSyncedWithServer = false;
    _lastSyncError = error.toString();
    ApiService.instance.connectionStatusNotifier.value = false;
  }

  /// Ejecuta una operación autenticada y, si el token expiró (401), intenta renovarlo una vez.
  Future<T> _withAuthRetry<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DopaApiException catch (e) {
      if (e.statusCode == 401) {
        try {
          if (ApiService.instance.refreshTokenValue != null &&
              ApiService.instance.refreshTokenValue!.isNotEmpty) {
            await ApiService.instance.refreshToken();
          } else {
            ApiService.instance.clearSession();
            await ApiService.instance.ensureAuthenticated();
          }
          return await action();
        } catch (_) {
          rethrow;
        }
      }
      rethrow;
    }
  }

  // ===========================================================================
  // 1. CRUD: USUARIO & DASHBOARD (`/api/v1/dashboard` y `/api/v1/auth/me`)
  // ===========================================================================

  Usuario get usuarioActualCache => _usuarioCache;

  /// Obtiene los datos del perfil del usuario desde `/api/v1/dashboard` con respaldo local.
  Future<Usuario> getUsuario() async {
    try {
      final dashboardJson = await _withAuthRetry(
        () => ApiService.instance.getDashboard(),
      );
      _usuarioCache = Usuario.fromBackendJson(dashboardJson);
      _markOnline();
      return _usuarioCache;
    } catch (e) {
      _markOffline(e);
      return _usuarioCache;
    }
  }

  /// Actualiza métricas o preferencias del usuario en `/api/v1/auth/preferences` y `/api/v1/dashboard/energy-checkin`.
  Future<int> updateUsuario(Usuario usuario) async {
    _usuarioCache = usuario;
    try {
      await _withAuthRetry(
        () => ApiService.instance.updatePreferences({
          'meta_diaria_dopamina': usuario.dopaminaMeta,
        }),
      );
      final nivelEnergia = _mapEnergiaLabel(usuario.energiaNivel);
      await _withAuthRetry(
        () => ApiService.instance.energyCheckin(nivelEnergia: nivelEnergia),
      );
      _markOnline();
      notifyDataChanged();
      return 1;
    } catch (e) {
      _markOffline(e);
      notifyDataChanged();
      return 1;
    }
  }

  /// Registra el chequeo de energía en `/api/v1/dashboard/energy-checkin`.
  Future<({bool synced, String sugerencia})> registrarCheckinEnergia({
    required double energiaNivel,
    String? humor,
  }) async {
    final nivelStr = _mapEnergiaLabel(energiaNivel);
    _usuarioCache = Usuario(
      id: _usuarioCache.id,
      nombre: _usuarioCache.nombre,
      correo: _usuarioCache.correo,
      dopaminaActual: _usuarioCache.dopaminaActual,
      dopaminaMeta: _usuarioCache.dopaminaMeta,
      nivel: _usuarioCache.nivel,
      rachaDias: _usuarioCache.rachaDias,
      energiaNivel: energiaNivel,
    );
    try {
      final res = await _withAuthRetry(
        () => ApiService.instance.energyCheckin(
          nivelEnergia: nivelStr,
          humor: humor,
        ),
      );
      _markOnline();
      notifyDataChanged();
      return (
        synced: true,
        sugerencia: res['sugerencia_baja_friccion'] as String? ??
            '¡Gracias por escuchar cómo te sientes hoy!',
      );
    } catch (e) {
      _markOffline(e);
      notifyDataChanged();
      return (
        synced: false,
        sugerencia: 'Guardado localmente. Conéctate a Docker para sincronizar.',
      );
    }
  }

  String _mapEnergiaLabel(double energiaNivel) {
    if (energiaNivel < 0.35) return 'poquita';
    if (energiaNivel > 0.7) return 'a tope';
    return 'media';
  }

  // ===========================================================================
  // 2. CRUD: TAREA_BLOQUE & MICRO_PASOS (`/api/v1/tasks`)
  // ===========================================================================

  /// Inserta una nueva micro-tarea en `/api/v1/tasks`.
  Future<int> insertarTarea(TareaBloque tarea) async {
    final result = await crearTarea(
      titulo: tarea.titulo,
      descripcion: tarea.descripcion,
      prioridad: tarea.prioridad,
      fechaVencimiento: tarea.fechaVencimiento,
      subtareas: tarea.microPasos.map((m) => m.descripcion).toList(),
    );
    return result.tarea.id ?? 101;
  }

  /// Crea una tarea y sus micro-pasos en el backend PostgreSQL devolviendo estado de sincronización.
  Future<({TareaBloque tarea, bool synced})> crearTarea({
    required String titulo,
    String? descripcion,
    String prioridad = 'Media',
    String? fechaVencimiento,
    List<String> subtareas = const [],
  }) async {
    final cleanSteps =
        subtareas.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    try {
      final created = await _withAuthRetry(
        () => ApiService.instance.createTask(
          titulo: titulo.trim(),
          descripcion: (descripcion != null && descripcion.trim().isNotEmpty)
              ? descripcion.trim()
              : null,
          prioridad: prioridad,
          fechaVencimiento: fechaVencimiento,
          subtareas: cleanSteps,
        ),
      );
      final nuevaTarea = TareaBloque.fromBackendJson(
        created,
        isFirstPending: _tareasCache.every((t) => t.estado == EstadoTarea.hecho),
      );
      _tareasCache.insert(0, nuevaTarea);
      _markOnline();
      notifyDataChanged();
      return (tarea: nuevaTarea, synced: true);
    } catch (e) {
      _markOffline(e);
      final maxId = _tareasCache.fold<int>(
        100,
        (prev, el) => (el.id ?? 0) > prev ? (el.id ?? 0) : prev,
      );
      final nextId = maxId + 1;
      final duracion = prioridad == 'Baja' ? 3 : (prioridad == 'Alta' ? 8 : 5);
      final etiqueta = prioridad == 'Baja'
          ? 'Fácil'
          : (prioridad == 'Alta' ? 'Sin prisa' : 'Suave');
      final localSteps = <MicroPaso>[];
      for (int i = 0; i < cleanSteps.length; i++) {
        localSteps.add(
          MicroPaso(
            id: nextId * 100 + i + 1,
            tareaId: nextId,
            descripcion: cleanSteps[i],
            completado: false,
          ),
        );
      }
      final nuevaLocal = TareaBloque(
        id: nextId,
        titulo: titulo.trim(),
        descripcion: descripcion?.trim(),
        fechaVencimiento: fechaVencimiento,
        subtitulo: localSteps.isNotEmpty
            ? '$etiqueta · 0/${localSteps.length} pasos · $duracion min'
            : '$etiqueta · $duracion min',
        duracionMinutos: duracion,
        estado: EstadoTarea.ahora,
        puntosDopamina: 10,
        estresNivel: prioridad == 'Baja' ? 0.15 : (prioridad == 'Alta' ? 0.45 : 0.28),
        microPasos: localSteps,
        prioridad: prioridad,
      );
      _tareasCache.insert(0, nuevaLocal);
      notifyDataChanged();
      return (tarea: nuevaLocal, synced: false);
    }
  }

  /// Obtiene la lista de tareas del usuario desde `/api/v1/tasks`.
  Future<List<TareaBloque>> obtenerTareas() async {
    try {
      final response = await _withAuthRetry(
        () => ApiService.instance.listTasks(limit: 100, offset: 0),
      );
      final rawItems = response['items'] as List<dynamic>? ?? const [];
      bool firstPendingAssigned = false;
      final mapped = <TareaBloque>[];
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          final bool isPending = item['completada'] != true;
          final bool markAsNow = isPending && !firstPendingAssigned;
          if (markAsNow) firstPendingAssigned = true;
          mapped.add(
            TareaBloque.fromBackendJson(item, isFirstPending: markAsNow),
          );
        }
      }
      // Actualiza siempre la caché con la verdad de PostgreSQL (incluso si está vacía).
      _tareasCache = mapped;
      _markOnline();
      return List<TareaBloque>.from(_tareasCache);
    } catch (e) {
      _markOffline(e);
      return List<TareaBloque>.from(_tareasCache);
    }
  }

  /// Obtiene el detalle actualizado de una tarea y sus micro-pasos (`GET /api/v1/tasks/{id}`).
  Future<TareaBloque?> obtenerTareaDetalle(int id) async {
    try {
      final json = await _withAuthRetry(() => ApiService.instance.getTask(id));
      final detalle = TareaBloque.fromBackendJson(json);
      final idx = _tareasCache.indexWhere((t) => t.id == id);
      if (idx != -1) {
        _tareasCache[idx] = detalle;
      }
      _markOnline();
      return detalle;
    } catch (e) {
      _markOffline(e);
      for (final t in _tareasCache) {
        if (t.id == id) return t;
      }
      return null;
    }
  }

  /// Edita una tarea existente en PostgreSQL (`PUT /api/v1/tasks/{id}`).
  Future<({TareaBloque? tarea, bool synced})> editarTarea({
    required int id,
    required String titulo,
    String? descripcion,
    String? prioridad,
    String? fechaVencimiento,
    bool? completada,
  }) async {
    final fields = <String, dynamic>{
      'titulo': titulo.trim(),
    };
    if (descripcion != null) {
      fields['descripcion'] = descripcion.trim();
    }
    if (prioridad != null) {
      fields['prioridad'] = prioridad;
    }
    if (fechaVencimiento != null) {
      fields['fechavencimiento'] = fechaVencimiento;
    }
    if (completada != null) {
      fields['completada'] = completada;
    }

    try {
      final updatedJson = await _withAuthRetry(
        () => ApiService.instance.updateTask(id, fields),
      );
      final updated = TareaBloque.fromBackendJson(updatedJson);
      final index = _tareasCache.indexWhere((t) => t.id == id);
      if (index != -1) {
        _tareasCache[index] = updated;
      }
      _markOnline();
      notifyDataChanged();
      return (tarea: updated, synced: true);
    } catch (e) {
      _markOffline(e);
      final index = _tareasCache.indexWhere((t) => t.id == id);
      if (index != -1) {
        final prev = _tareasCache[index];
        final nextPrio = prioridad ?? prev.prioridad;
        final nextDur = nextPrio == 'Baja' ? 3 : (nextPrio == 'Alta' ? 8 : 5);
        final updatedLocal = prev.copyWith(
          titulo: titulo.trim(),
          descripcion: descripcion?.trim() ?? prev.descripcion,
          prioridad: nextPrio,
          fechaVencimiento: fechaVencimiento ?? prev.fechaVencimiento,
          duracionMinutos: nextDur,
          estado: completada == null
              ? prev.estado
              : (completada ? EstadoTarea.hecho : EstadoTarea.despues),
        );
        _tareasCache[index] = updatedLocal;
        notifyDataChanged();
        return (tarea: updatedLocal, synced: false);
      }
      return (tarea: null, synced: false);
    }
  }

  /// Actualiza el estado o datos de una tarea en `/api/v1/tasks/{id}` o `/api/v1/tasks/{id}/complete`.
  Future<int> actualizarTarea(TareaBloque tarea) async {
    final index = _tareasCache.indexWhere((t) => t.id == tarea.id);
    if (index != -1) {
      _tareasCache[index] = tarea;
    }
    if (tarea.id == null) {
      notifyDataChanged();
      return 1;
    }

    try {
      if (tarea.estado == EstadoTarea.hecho) {
        final completed = await _withAuthRetry(
          () => ApiService.instance.completeTask(tarea.id!),
        );
        final puntosTotales = completed['puntos_totales'] as int?;
        if (puntosTotales != null) {
          _usuarioCache = Usuario(
            id: _usuarioCache.id,
            nombre: _usuarioCache.nombre,
            correo: _usuarioCache.correo,
            dopaminaActual: puntosTotales,
            dopaminaMeta: _usuarioCache.dopaminaMeta,
            nivel: completed['nivel_actual'] as int? ?? _usuarioCache.nivel,
            rachaDias: _usuarioCache.rachaDias,
            energiaNivel: _usuarioCache.energiaNivel,
          );
        }
        final tareaJson = completed['tarea'];
        if (tareaJson is Map<String, dynamic> && index != -1) {
          _tareasCache[index] = TareaBloque.fromBackendJson(tareaJson);
        }
      } else {
        final fields = <String, dynamic>{
          'titulo': tarea.titulo,
          'prioridad': tarea.prioridad,
          'completada': false,
        };
        if (tarea.descripcion != null) {
          fields['descripcion'] = tarea.descripcion;
        }
        final updatedJson = await _withAuthRetry(
          () => ApiService.instance.updateTask(tarea.id!, fields),
        );
        if (index != -1) {
          _tareasCache[index] = TareaBloque.fromBackendJson(updatedJson);
        }
      }
      _markOnline();
      notifyDataChanged();
      return 1;
    } catch (e) {
      _markOffline(e);
      notifyDataChanged();
      return 1;
    }
  }

  /// Agrega un nuevo micro-paso a una tarea existente (`POST /api/v1/tasks/{task_id}/subtasks`).
  Future<({MicroPaso paso, bool synced})> crearMicroPaso({
    required int tareaId,
    required String descripcion,
  }) async {
    final cleanDesc = descripcion.trim();
    try {
      final json = await _withAuthRetry(
        () => ApiService.instance.createSubtask(tareaId, cleanDesc),
      );
      final nuevoPaso = MicroPaso.fromBackendJson(json);
      final idx = _tareasCache.indexWhere((t) => t.id == tareaId);
      if (idx != -1) {
        final pasosActualizados = List<MicroPaso>.from(_tareasCache[idx].microPasos)
          ..add(nuevoPaso);
        _tareasCache[idx] = _tareasCache[idx].copyWith(microPasos: pasosActualizados);
      }
      _markOnline();
      notifyDataChanged();
      return (paso: nuevoPaso, synced: true);
    } catch (e) {
      _markOffline(e);
      final localPaso = MicroPaso(
        id: DateTime.now().millisecondsSinceEpoch % 1000000,
        tareaId: tareaId,
        descripcion: cleanDesc,
        completado: false,
      );
      final idx = _tareasCache.indexWhere((t) => t.id == tareaId);
      if (idx != -1) {
        final pasosActualizados = List<MicroPaso>.from(_tareasCache[idx].microPasos)
          ..add(localPaso);
        _tareasCache[idx] = _tareasCache[idx].copyWith(microPasos: pasosActualizados);
      }
      notifyDataChanged();
      return (paso: localPaso, synced: false);
    }
  }

  /// Actualiza el estado de un micro-paso individual en `/api/v1/tasks/{task_id}/subtasks/{subtask_id}`.
  Future<int> actualizarMicroPaso({
    required int tareaId,
    required int microPasoId,
    required bool completado,
  }) async {
    final idx = _tareasCache.indexWhere((t) => t.id == tareaId);
    if (idx != -1) {
      for (final paso in _tareasCache[idx].microPasos) {
        if (paso.id == microPasoId) {
          paso.completado = completado;
          break;
        }
      }
    }
    try {
      await _withAuthRetry(
        () => ApiService.instance.updateSubtask(
          tareaId,
          microPasoId,
          completada: completado,
        ),
      );
      _markOnline();
      notifyDataChanged();
      return 1;
    } catch (e) {
      _markOffline(e);
      notifyDataChanged();
      return 1;
    }
  }

  /// Elimina un micro-paso de una tarea (`DELETE /api/v1/tasks/{task_id}/subtasks/{subtask_id}`).
  Future<bool> eliminarMicroPaso({
    required int tareaId,
    required int microPasoId,
  }) async {
    final idx = _tareasCache.indexWhere((t) => t.id == tareaId);
    if (idx != -1) {
      final pasosActualizados = _tareasCache[idx]
          .microPasos
          .where((p) => p.id != microPasoId)
          .toList();
      _tareasCache[idx] = _tareasCache[idx].copyWith(microPasos: pasosActualizados);
    }
    try {
      await _withAuthRetry(
        () => ApiService.instance.deleteSubtask(tareaId, microPasoId),
      );
      _markOnline();
      notifyDataChanged();
      return true;
    } catch (e) {
      _markOffline(e);
      notifyDataChanged();
      return false;
    }
  }

  /// Elimina una tarea por ID en `/api/v1/tasks/{id}`.
  Future<int> eliminarTarea(int id) async {
    _tareasCache.removeWhere((t) => t.id == id);
    try {
      await _withAuthRetry(() => ApiService.instance.deleteTask(id));
      _markOnline();
      notifyDataChanged();
      return 1;
    } catch (e) {
      _markOffline(e);
      notifyDataChanged();
      return 1;
    }
  }

  // ===========================================================================
  // 3. CRUD: SESION_ENFOQUE (`/api/v1/pomodoro/sessions`)
  // ===========================================================================

  /// Registra una sesión de enfoque suave en `/api/v1/pomodoro/sessions` y la completa si aplica.
  Future<int> registrarSesion(SesionEnfoque sesion) async {
    try {
      final duracionMin = (sesion.duracionSegundos ~/ 60).clamp(1, 180);
      final created = await _withAuthRetry(
        () => ApiService.instance.createPomodoroSession(
          idTarea: sesion.tareaId,
          duracionConcentracion: duracionMin,
          duracionDescanso: 5,
        ),
      );
      final sessionId = created['id'] as int? ?? 201;
      if (sesion.completada) {
        final action = await _withAuthRetry(
          () => ApiService.instance.completePomodoroSession(sessionId),
        );
        final nuevosPuntos = action['puntos_totales'] as int?;
        if (nuevosPuntos != null) {
          _usuarioCache = Usuario(
            id: _usuarioCache.id,
            nombre: _usuarioCache.nombre,
            correo: _usuarioCache.correo,
            dopaminaActual: nuevosPuntos,
            dopaminaMeta: _usuarioCache.dopaminaMeta,
            nivel: action['nivel_actual'] as int? ?? _usuarioCache.nivel,
            rachaDias: _usuarioCache.rachaDias,
            energiaNivel: _usuarioCache.energiaNivel,
          );
        }
      }
      _markOnline();
      notifyDataChanged();
      return sessionId;
    } catch (e) {
      _markOffline(e);
      return 201;
    }
  }

  /// Obtiene el historial de sesiones de enfoque desde `/api/v1/pomodoro/sessions`.
  Future<List<SesionEnfoque>> obtenerSesiones() async {
    try {
      final response = await _withAuthRetry(
        () => ApiService.instance.listPomodoroSessions(),
      );
      final items = response['items'] as List<dynamic>? ?? const [];
      _markOnline();
      return items.whereType<Map<String, dynamic>>().map((json) {
        final min = json['duracionconcentracion'] as int? ?? 5;
        final completadas = json['sesionescompletadas'] as int? ?? 0;
        return SesionEnfoque(
          id: json['id'] as int?,
          tareaId: json['id_tarea'] as int?,
          duracionSegundos: min * 60,
          completada: completadas > 0,
        );
      }).toList();
    } catch (e) {
      _markOffline(e);
      return [
        SesionEnfoque(
          id: 1,
          tareaId: 1,
          duracionSegundos: 300,
          completada: true,
        ),
      ];
    }
  }

  // ===========================================================================
  // 4. CRUD: REGISTRO_BIENESTAR (`/api/v1/personal-records`)
  // ===========================================================================

  /// Guarda el estado de ánimo y nivel de energía del usuario en `/api/v1/personal-records`.
  Future<int> guardarRegistroBienestar(RegistroBienestar registro) async {
    try {
      final created = await _withAuthRetry(
        () => ApiService.instance.createPersonalRecord(
          nombre: 'Estado emocional: ${registro.humor.name}',
          valorObjetivo: 5.0,
          valorActual: (registro.nivelEnergia * 5.0).clamp(1.0, 5.0),
        ),
      );
      _markOnline();
      notifyDataChanged();
      return created['id'] as int? ?? 301;
    } catch (e) {
      _markOffline(e);
      return 301;
    }
  }

  /// Obtiene los registros de bienestar desde `/api/v1/personal-records`.
  Future<List<RegistroBienestar>> obtenerRegistrosBienestar(
    DateTime fecha,
  ) async {
    try {
      final response = await _withAuthRetry(
        () => ApiService.instance.listPersonalRecords(),
      );
      final items = response['items'] as List<dynamic>? ?? const [];
      _markOnline();
      return items.whereType<Map<String, dynamic>>().map((json) {
        final progreso =
            (json['progresoporcentaje'] as num?)?.toDouble() ?? 64.0;
        return RegistroBienestar(
          id: json['id'] as int?,
          humor: TipoHumor.conFoco,
          nivelEnergia: (progreso / 100.0).clamp(0.0, 1.0),
          notas: json['nombre'] as String?,
        );
      }).toList();
    } catch (e) {
      _markOffline(e);
      return [
        RegistroBienestar(
          id: 1,
          humor: TipoHumor.conFoco,
          nivelEnergia: 0.64,
          notas: 'Enfoque tranquilo tras hacer la cama.',
        ),
      ];
    }
  }

  // ===========================================================================
  // 5. CRUD: RECOMPENSA & GAMIFICACIÓN (`/api/v1/gamification`)
  // ===========================================================================

  /// Agrega una recompensa ganada en `/api/v1/gamification/rewards`.
  Future<int> agregarRecompensa(Recompensa recompensa) async {
    try {
      final created = await _withAuthRetry(
        () => ApiService.instance.createReward(
          nombre: recompensa.titulo,
          costoPuntos: recompensa.puntosDopamina,
        ),
      );
      _markOnline();
      notifyDataChanged();
      return created['id'] as int? ?? 401;
    } catch (e) {
      _markOffline(e);
      return 401;
    }
  }

  /// Obtiene el resumen completo de gamificación desde `/api/v1/gamification/summary`.
  Future<Map<String, dynamic>> obtenerResumenGamificacion() async {
    try {
      final summary = await _withAuthRetry(
        () => ApiService.instance.getGamificationSummary(),
      );
      final puntos = summary['puntos_totales'] as int?;
      final meta = summary['meta_diaria_puntos'] as int?;
      final nivel = summary['nivel'] as int?;
      final dias = summary['dias_activos_registrados'] as int?;
      _usuarioCache = Usuario(
        id: _usuarioCache.id,
        nombre: _usuarioCache.nombre,
        correo: _usuarioCache.correo,
        dopaminaActual: puntos ?? _usuarioCache.dopaminaActual,
        dopaminaMeta: meta ?? _usuarioCache.dopaminaMeta,
        nivel: nivel ?? _usuarioCache.nivel,
        rachaDias: dias ?? _usuarioCache.rachaDias,
        energiaNivel: _usuarioCache.energiaNivel,
      );
      _markOnline();
      return summary;
    } catch (e) {
      _markOffline(e);
      return {
        'puntos_totales': _usuarioCache.dopaminaActual,
        'meta_diaria_puntos': _usuarioCache.dopaminaMeta,
        'nivel': _usuarioCache.nivel,
        'dias_activos_registrados': _usuarioCache.rachaDias,
        'tareas_completadas_total':
            _tareasCache.where((t) => t.estado == EstadoTarea.hecho).length,
        'sesiones_enfoque_completadas': 1,
        'recompensas_recientes': const <dynamic>[],
      };
    }
  }

  /// Obtiene la dopamina total reunida hoy desde `/api/v1/gamification/summary`.
  Future<int> obtenerTotalDopaminaHoy() async {
    final summary = await obtenerResumenGamificacion();
    return (summary['puntos_totales'] as int?) ?? _usuarioCache.dopaminaActual;
  }
}
