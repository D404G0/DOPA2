import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../models/task_model.dart';
import '../models/focus_session_model.dart';
import '../models/wellness_record_model.dart';
import '../models/reward_model.dart';
import 'api_service.dart';

/// Servicio de Persistencia Híbrida (Sincronización REST FastAPI `/api/v1` + Caché Local con SharedPreferences).
///
/// Inicia completamente vacío (cero tareas precargadas, cero rachas simuladas, sin nombre fijo)
/// y persiste tanto localmente como en PostgreSQL dentro de Docker en cuanto el usuario inicia sesión.
class DBService {
  static final DBService instance = DBService._init();
  DBService._init();

  static const String _prefUserNameKey = 'dopa_user_name';
  static const String _prefLocalTasksKey = 'dopa_local_tasks';
  static const String _prefLocalPointsKey = 'dopa_local_points';
  static const String _prefLocalSessionsKey = 'dopa_local_sessions';
  static const String _prefLocalEnergiaKey = 'dopa_local_energia';
  static const String _prefLocalWeeklyKey = 'dopa_local_weekly';
  static const String _prefUnsyncedTaskIdsKey = 'dopa_unsynced_task_ids';

  /// Notificador reactivo: se incrementa ante cualquier mutación o cambio de cuenta/servidor
  /// para que todas las pestañas (Inicio, Tareas, Dopamina) se sincronicen automáticamente.
  final ValueNotifier<int> dataVersion = ValueNotifier<int>(0);

  /// Indica si el usuario ya configuró su nombre o cuenta para mostrar la app principal.
  final ValueNotifier<bool> profileReadyNotifier = ValueNotifier<bool>(false);

  bool _isSyncedWithServer = false;
  String? _lastSyncError;

  bool get isSyncedWithServer => _isSyncedWithServer;
  String? get lastSyncError => _lastSyncError;

  Usuario _usuarioCache = Usuario(
    nombre: '',
    correo: '',
    dopaminaActual: 0,
    dopaminaMeta: 50,
    nivel: 1,
    rachaDias: 0,
    energiaNivel: 0.5,
  );

  List<TareaBloque> _tareasCache = [];
  List<SesionEnfoque> _sesionesCache = [];
  List<RegistroBienestar> _registrosCache = [];
  List<bool> _actividadSemanalCache = List<bool>.filled(7, false);
  int _sesionesCompletadasLocal = 0;
  final Set<int> _unsyncedLocalTaskIds = <int>{};

  bool get hasConfiguredProfile =>
      _usuarioCache.nombre.trim().isNotEmpty ||
      ApiService.instance.isAuthenticated;

  List<bool> get actividadSemanalCache =>
      List<bool>.from(_actividadSemanalCache);

  void notifyDataChanged() {
    dataVersion.value++;
  }

  /// Carga el estado local persistido desde `SharedPreferences` al arrancar la aplicación.
  Future<void> initLocalState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString(_prefUserNameKey)?.trim() ?? '';
      final savedPoints = prefs.getInt(_prefLocalPointsKey) ?? 0;
      final savedSessions = prefs.getInt(_prefLocalSessionsKey) ?? 0;
      final savedEnergia = prefs.getDouble(_prefLocalEnergiaKey) ?? 0.5;

      final weeklyRaw = prefs.getString(_prefLocalWeeklyKey);
      if (weeklyRaw != null && weeklyRaw.isNotEmpty) {
        final decoded = jsonDecode(weeklyRaw);
        if (decoded is List) {
          _actividadSemanalCache = List<bool>.generate(
            7,
            (i) => i < decoded.length && decoded[i] == true,
          );
        }
      }

      final unsyncedList = prefs.getStringList(_prefUnsyncedTaskIdsKey);
      _unsyncedLocalTaskIds
        ..clear()
        ..addAll(
          (unsyncedList ?? const [])
              .map((s) => int.tryParse(s))
              .whereType<int>(),
        );

      final tasksRaw = prefs.getString(_prefLocalTasksKey);
      if (tasksRaw != null && tasksRaw.isNotEmpty) {
        final decoded = jsonDecode(tasksRaw);
        if (decoded is List) {
          _tareasCache = decoded.whereType<Map<String, dynamic>>().map((item) {
            final rawPasos = item['micro_pasos'] as List<dynamic>? ?? const [];
            final pasos = rawPasos
                .whereType<Map<String, dynamic>>()
                .map(MicroPaso.fromMap)
                .toList();
            return TareaBloque.fromMap(item, pasos: pasos);
          }).toList();
        }
      } else {
        _tareasCache = [];
      }

      _sesionesCompletadasLocal = savedSessions;
      final activeDays = _actividadSemanalCache.where((a) => a).length;
      _usuarioCache = _usuarioCache.copyWith(
        nombre: savedName,
        dopaminaActual: savedPoints,
        rachaDias: activeDays,
        energiaNivel: savedEnergia,
      );
      profileReadyNotifier.value = hasConfiguredProfile;
    } catch (_) {
      // Mantiene el estado limpio si SharedPreferences aún no está disponible.
    }
  }

  Future<void> _persistLocalState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefUserNameKey, _usuarioCache.nombre);
      await prefs.setInt(_prefLocalPointsKey, _usuarioCache.dopaminaActual);
      await prefs.setInt(_prefLocalSessionsKey, _sesionesCompletadasLocal);
      await prefs.setDouble(_prefLocalEnergiaKey, _usuarioCache.energiaNivel);
      await prefs.setString(
        _prefLocalWeeklyKey,
        jsonEncode(_actividadSemanalCache),
      );
      await prefs.setStringList(
        _prefUnsyncedTaskIdsKey,
        _unsyncedLocalTaskIds.map((id) => id.toString()).toList(),
      );

      final serializedTasks = _tareasCache.map((t) {
        final map = t.toMap();
        map['micro_pasos'] = t.microPasos.map((m) => m.toMap()).toList();
        return map;
      }).toList();
      await prefs.setString(_prefLocalTasksKey, jsonEncode(serializedTasks));
    } catch (_) {
      // Silencioso en entornos sin canal de almacenamiento.
    }
  }

  /// Guarda o actualiza el nombre personalizado del usuario (local + PostgreSQL si está autenticado).
  Future<({bool synced, String? error})> setUserName(String nombre) async {
    final cleanName = nombre.trim();
    if (cleanName.isEmpty) {
      return (synced: false, error: 'Escribe tu nombre para continuar.');
    }

    _usuarioCache = _usuarioCache.copyWith(nombre: cleanName);
    profileReadyNotifier.value = hasConfiguredProfile;
    await _persistLocalState();
    notifyDataChanged();

    if (!ApiService.instance.isAuthenticated) {
      return (synced: false, error: null);
    }

    try {
      final updated = await _withAuthRetry(
        () => ApiService.instance.updateProfileName(cleanName),
      );
      final serverName = (updated['nombre'] as String?)?.trim() ?? cleanName;
      _usuarioCache = _usuarioCache.copyWith(
        id: updated['id'] as int? ?? _usuarioCache.id,
        nombre: serverName,
        correo: updated['correo'] as String? ?? _usuarioCache.correo,
      );
      _markOnline();
      await _persistLocalState();
      notifyDataChanged();
      return (synced: true, error: null);
    } catch (e) {
      _markOffline(e);
      return (
        synced: false,
        error: e is DopaApiException ? e.message : e.toString(),
      );
    }
  }

  /// Limpia la caché en memoria y local al cambiar de cuenta o cerrar sesión.
  void resetCacheForSessionChange({bool clearUserName = false}) {
    _tareasCache = [];
    _sesionesCache = [];
    _registrosCache = [];
    _actividadSemanalCache = List<bool>.filled(7, false);
    _sesionesCompletadasLocal = 0;
    _unsyncedLocalTaskIds.clear();
    _isSyncedWithServer = false;
    _lastSyncError = null;
    _usuarioCache = Usuario(
      nombre: clearUserName ? '' : _usuarioCache.nombre,
      correo: '',
      dopaminaActual: 0,
      dopaminaMeta: 50,
      nivel: 1,
      rachaDias: 0,
      energiaNivel: 0.5,
    );
    profileReadyNotifier.value = hasConfiguredProfile;
    _persistLocalState();
    notifyDataChanged();
  }

  /// Sube las tareas creadas localmente antes de iniciar sesión al servidor PostgreSQL y luego descarga la verdad del servidor.
  Future<({int tasksSynced, String? error})> syncLocalDataToServer() async {
    if (!ApiService.instance.isAuthenticated) {
      return (tasksSynced: 0, error: 'Inicia sesión primero.');
    }

    int syncedCount = 0;
    try {
      final pendingToPush = _tareasCache
          .where((t) => t.id != null && _unsyncedLocalTaskIds.contains(t.id))
          .toList();

      for (final localTask in pendingToPush) {
        final created = await ApiService.instance.createTask(
          titulo: localTask.titulo,
          descripcion: localTask.descripcion,
          prioridad: localTask.prioridad,
          fechaVencimiento: localTask.fechaVencimiento,
          subtareas: localTask.microPasos
              .map((m) => m.descripcion.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
        );
        final createdId = created['id'] as int?;
        if (localTask.estado == EstadoTarea.hecho && createdId != null) {
          await ApiService.instance.completeTask(createdId);
        }
        _unsyncedLocalTaskIds.remove(localTask.id);
        syncedCount++;
      }

      await getUsuario();
      await obtenerTareas();
      await obtenerResumenGamificacion();
      await _persistLocalState();
      _markOnline();
      notifyDataChanged();
      return (tasksSynced: syncedCount, error: null);
    } catch (e) {
      _markOffline(e);
      return (
        tasksSynced: syncedCount,
        error: e is DopaApiException ? e.message : e.toString(),
      );
    }
  }

  void _markOnline() {
    _isSyncedWithServer = true;
    _lastSyncError = null;
  }

  void _markOffline(Object error) {
    _isSyncedWithServer = false;
    _lastSyncError = error.toString();
    // Un 401/404/422 significa que el servidor SÍ responde, solo falta sesión o datos válidos.
    if (error is DopaApiException && error.statusCode < 500) {
      return;
    }
    ApiService.instance.connectionStatusNotifier.value = false;
  }

  void _recordLocalActivityToday({int addPoints = 0, bool addSession = false}) {
    final weekdayIdx = (DateTime.now().weekday - 1).clamp(0, 6);
    _actividadSemanalCache[weekdayIdx] = true;
    if (addSession) {
      _sesionesCompletadasLocal++;
    }
    final nextPoints = _usuarioCache.dopaminaActual + addPoints;
    final activeDays = _actividadSemanalCache.where((a) => a).length;
    final nextLevel = (nextPoints ~/ 50) + 1;
    _usuarioCache = _usuarioCache.copyWith(
      dopaminaActual: nextPoints,
      rachaDias: activeDays,
      nivel: nextLevel,
    );
  }

  /// Ejecuta una operación autenticada y, si el token expiró (401), intenta renovarlo una vez.
  Future<T> _withAuthRetry<T>(Future<T> Function() action) async {
    if (!ApiService.instance.isAuthenticated &&
        (ApiService.instance.refreshTokenValue == null ||
            ApiService.instance.refreshTokenValue!.isEmpty)) {
      throw DopaApiException(
        statusCode: 401,
        message: 'Inicia sesión o crea tu cuenta para guardar en PostgreSQL.',
      );
    }

    try {
      return await action();
    } on DopaApiException catch (e) {
      if (e.statusCode == 401) {
        if (ApiService.instance.refreshTokenValue != null &&
            ApiService.instance.refreshTokenValue!.isNotEmpty) {
          await ApiService.instance.refreshToken();
          return await action();
        }
        rethrow;
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
      final parsed = Usuario.fromBackendJson(dashboardJson);
      _usuarioCache = parsed.copyWith(
        rachaDias: _usuarioCache.rachaDias,
      );
      profileReadyNotifier.value = hasConfiguredProfile;
      _markOnline();
      await _persistLocalState();
      return _usuarioCache;
    } catch (e) {
      _markOffline(e);
      return _usuarioCache;
    }
  }

  /// Actualiza métricas o preferencias del usuario en `/api/v1/auth/preferences` y `/api/v1/dashboard/energy-checkin`.
  Future<int> updateUsuario(Usuario usuario) async {
    _usuarioCache = usuario;
    await _persistLocalState();
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
    _usuarioCache = _usuarioCache.copyWith(energiaNivel: energiaNivel);
    await _persistLocalState();
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
        sugerencia: 'Guardado localmente. Conéctate al servidor para respaldarlo en PostgreSQL.',
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

  /// Crea una tarea y sus micro-pasos en PostgreSQL (o localmente si aún no inicia sesión).
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
      await _persistLocalState();
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
        estresNivel:
            prioridad == 'Baja' ? 0.15 : (prioridad == 'Alta' ? 0.45 : 0.28),
        microPasos: localSteps,
        prioridad: prioridad,
      );
      _tareasCache.insert(0, nuevaLocal);
      _unsyncedLocalTaskIds.add(nextId);
      await _persistLocalState();
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
      _tareasCache = mapped;
      _markOnline();
      await _persistLocalState();
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
      await _persistLocalState();
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
      await _persistLocalState();
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
        await _persistLocalState();
        notifyDataChanged();
        return (tarea: updatedLocal, synced: false);
      }
      return (tarea: null, synced: false);
    }
  }

  /// Actualiza el estado o datos de una tarea en `/api/v1/tasks/{id}` o `/api/v1/tasks/{id}/complete`.
  Future<int> actualizarTarea(TareaBloque tarea) async {
    final index = _tareasCache.indexWhere((t) => t.id == tarea.id);
    final wasDone = index != -1 && _tareasCache[index].estado == EstadoTarea.hecho;
    if (index != -1) {
      _tareasCache[index] = tarea;
    }
    if (tarea.id == null) {
      await _persistLocalState();
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
          _usuarioCache = _usuarioCache.copyWith(
            dopaminaActual: puntosTotales,
            nivel: completed['nivel_actual'] as int? ?? _usuarioCache.nivel,
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
      await _persistLocalState();
      notifyDataChanged();
      return 1;
    } catch (e) {
      _markOffline(e);
      if (tarea.estado == EstadoTarea.hecho && !wasDone) {
        _recordLocalActivityToday(addPoints: tarea.puntosDopamina);
      }
      await _persistLocalState();
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
      await _persistLocalState();
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
      await _persistLocalState();
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
      await _persistLocalState();
      notifyDataChanged();
      return 1;
    } catch (e) {
      _markOffline(e);
      await _persistLocalState();
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
      await _persistLocalState();
      notifyDataChanged();
      return true;
    } catch (e) {
      _markOffline(e);
      await _persistLocalState();
      notifyDataChanged();
      return false;
    }
  }

  /// Elimina una tarea por ID en `/api/v1/tasks/{id}`.
  Future<int> eliminarTarea(int id) async {
    _tareasCache.removeWhere((t) => t.id == id);
    _unsyncedLocalTaskIds.remove(id);
    try {
      await _withAuthRetry(() => ApiService.instance.deleteTask(id));
      _markOnline();
      await _persistLocalState();
      notifyDataChanged();
      return 1;
    } catch (e) {
      _markOffline(e);
      await _persistLocalState();
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
          _usuarioCache = _usuarioCache.copyWith(
            dopaminaActual: nuevosPuntos,
            nivel: action['nivel_actual'] as int? ?? _usuarioCache.nivel,
          );
        }
      }
      _markOnline();
      await _persistLocalState();
      notifyDataChanged();
      return sessionId;
    } catch (e) {
      _markOffline(e);
      final localId = _sesionesCache.length + 201;
      _sesionesCache.add(
        SesionEnfoque(
          id: localId,
          tareaId: sesion.tareaId,
          duracionSegundos: sesion.duracionSegundos,
          completada: sesion.completada,
        ),
      );
      if (sesion.completada) {
        _recordLocalActivityToday(addPoints: 5, addSession: true);
      }
      await _persistLocalState();
      notifyDataChanged();
      return localId;
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
      _sesionesCache = items.whereType<Map<String, dynamic>>().map((json) {
        final min = json['duracionconcentracion'] as int? ?? 5;
        final completadas = json['sesionescompletadas'] as int? ?? 0;
        return SesionEnfoque(
          id: json['id'] as int?,
          tareaId: json['id_tarea'] as int?,
          duracionSegundos: min * 60,
          completada: completadas > 0,
        );
      }).toList();
      return List<SesionEnfoque>.from(_sesionesCache);
    } catch (e) {
      _markOffline(e);
      return List<SesionEnfoque>.from(_sesionesCache);
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
      final localId = _registrosCache.length + 301;
      _registrosCache.add(
        RegistroBienestar(
          id: localId,
          humor: registro.humor,
          nivelEnergia: registro.nivelEnergia,
          notas: registro.notas,
        ),
      );
      notifyDataChanged();
      return localId;
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
      _registrosCache = items.whereType<Map<String, dynamic>>().map((json) {
        final progreso =
            (json['progresoporcentaje'] as num?)?.toDouble() ?? 50.0;
        return RegistroBienestar(
          id: json['id'] as int?,
          humor: TipoHumor.conFoco,
          nivelEnergia: (progreso / 100.0).clamp(0.0, 1.0),
          notas: json['nombre'] as String?,
        );
      }).toList();
      return List<RegistroBienestar>.from(_registrosCache);
    } catch (e) {
      _markOffline(e);
      return List<RegistroBienestar>.from(_registrosCache);
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
      final rawWeekly = summary['actividad_semanal'];
      if (rawWeekly is List) {
        _actividadSemanalCache = List<bool>.generate(
          7,
          (i) => i < rawWeekly.length && rawWeekly[i] == true,
        );
      }
      _usuarioCache = _usuarioCache.copyWith(
        dopaminaActual: puntos ?? _usuarioCache.dopaminaActual,
        dopaminaMeta: meta ?? _usuarioCache.dopaminaMeta,
        nivel: nivel ?? _usuarioCache.nivel,
        rachaDias: dias ?? _usuarioCache.rachaDias,
      );
      _markOnline();
      await _persistLocalState();
      return {
        ...summary,
        'actividad_semanal': List<bool>.from(_actividadSemanalCache),
      };
    } catch (e) {
      _markOffline(e);
      return {
        'puntos_totales': _usuarioCache.dopaminaActual,
        'meta_diaria_puntos': _usuarioCache.dopaminaMeta,
        'nivel': _usuarioCache.nivel,
        'dias_activos_registrados': _usuarioCache.rachaDias,
        'actividad_semanal': List<bool>.from(_actividadSemanalCache),
        'tareas_completadas_total':
            _tareasCache.where((t) => t.estado == EstadoTarea.hecho).length,
        'sesiones_enfoque_completadas': _sesionesCompletadasLocal,
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
