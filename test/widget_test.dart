import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dopa_app/main.dart';
import 'package:dopa_app/screens/main_navigation_screen.dart';
import 'package:dopa_app/services/api_service.dart';
import 'package:dopa_app/services/db_service.dart';
import 'package:dopa_app/models/task_model.dart';
import 'package:dopa_app/models/focus_session_model.dart';
import 'package:dopa_app/models/wellness_record_model.dart';
import 'package:dopa_app/models/reward_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _jsonBytesResponse(Object data, {int statusCode = 200}) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(data)),
    statusCode,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    MainNavigationScreen.tabNotifier.value = 0;
    ApiService.instance.clearSession();
    ApiService.instance.httpClient = null;
    DBService.instance.resetCacheForSessionChange(clearUserName: true);
    await DBService.instance.initLocalState();
  });

  group('1. Pruebas de UI, Onboarding, Estado Limpio y Navegación Móvil', () {
    testWidgets(
        'Muestra bienvenida para personalizar nombre e inicia completamente en blanco (0 tareas, 0 pts, 0 días)',
        (WidgetTester tester) async {
      await tester.pumpWidget(const DopaApp());
      await tester.pumpAndSettle();

      // 1. Pantalla de Onboarding pide el nombre del usuario sin datos demo
      expect(find.text('Bienvenido a DOPA'), findsOneWidget);
      expect(find.text('¿Cómo te llamas?'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('onboarding_name_field')),
        'Sofía',
      );
      await tester.ensureVisible(
        find.byKey(const Key('onboarding_submit_button')),
      );
      await tester.tap(find.byKey(const Key('onboarding_submit_button')));
      await tester.pumpAndSettle();

      // 2. Dashboard Principal con el nombre del usuario y cero tareas/rachas previas
      expect(find.text('¡Hola, Sofía!'), findsOneWidget);
      expect(find.text('Vamos un paso a la vez'), findsOneWidget);
      expect(find.text('¡Hacer algo fácil!'), findsOneWidget);
      expect(find.text('¡Tomar un break!'), findsOneWidget);
      expect(find.text('Mis micro-tareas'), findsOneWidget);
      expect(find.text('0 pendientes'), findsOneWidget);
      expect(
        find.text('¡Sin pendientes! Toca aquí para crear una nueva micro-tarea.'),
        findsOneWidget,
      );
      expect(find.text('¡Hola, Fred!'), findsNothing);
      expect(find.text('Hacer la cama'), findsNothing);

      // 3. Navegar a Tareas
      await tester.tap(find.text('¡Hacer algo fácil!'));
      await tester.pumpAndSettle();
      expect(find.text('Poquito a poquito'), findsOneWidget);
      expect(find.text('Elige solo una para empezar'), findsOneWidget);

      // 4. Navegar a Dopamina y verificar 0 pts / 0 días
      await tester.tap(find.text('Dopamina'));
      await tester.pumpAndSettle();
      expect(find.text('Mi Dopamina hoy'), findsOneWidget);
      expect(find.text('Dopamina reunida'), findsOneWidget);
      expect(find.text('0 pts'), findsOneWidget);
      expect(find.text('0 días'), findsOneWidget);
      expect(find.text('Rachas'), findsOneWidget);

      // 5. Navegar a Pausa / Break
      await tester.tap(find.text('Pausa'));
      await tester.pumpAndSettle();
      expect(find.text('Un break suave'), findsOneWidget);
      expect(find.text('Bajemos el volumen'), findsOneWidget);
      expect(find.text('Actividades de bajo estímulo'), findsOneWidget);
    });

    testWidgets(
        'Permite crear una micro-tarea con micro-pasos y abrir Enfoque Suave',
        (WidgetTester tester) async {
      await DBService.instance.setUserName('Camila');
      await tester.pumpWidget(const DopaApp());
      await tester.pumpAndSettle();

      expect(find.text('¡Hola, Camila!'), findsOneWidget);

      // Ir a la pestaña de Tareas
      await tester.tap(find.text('¡Hacer algo fácil!'));
      await tester.pumpAndSettle();

      // Abrir el formulario "+ Nueva"
      await tester.tap(find.byKey(const Key('add_task_button')));
      await tester.pumpAndSettle();

      expect(find.text('Nueva micro-tarea'), findsOneWidget);

      // Llenar título y un micro-paso personalizado
      await tester.enterText(
        find.widgetWithText(
            TextField, 'Ej. Ordenar el escritorio o estudiar 10 min'),
        'Estudiar arquitectura',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Ej. Abrir el cuaderno y leer 1 página'),
        'Leer resumen del capítulo 1',
      );

      // Desplazar hasta el botón Guardar y tocarlo
      await tester.ensureVisible(find.text('Crear micro-tarea'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear micro-tarea'));
      await tester.pumpAndSettle();

      // La tarea nueva aparece en la lista y queda seleccionada
      expect(find.text('Estudiar arquitectura'), findsOneWidget);
      expect(find.text('Empezar «Estudiar arquitectura»'), findsOneWidget);

      // Iniciar Enfoque Suave con la tarea recién creada
      await tester.ensureVisible(find.text('Empezar «Estudiar arquitectura»'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empezar «Estudiar arquitectura»'));
      await tester.pumpAndSettle();

      // Verificar que Enfoque Suave muestra el título y el micro-paso real del usuario
      expect(find.text('Enfoque suave'), findsOneWidget);
      expect(find.text('Estudiar arquitectura'), findsOneWidget);
      expect(find.text('Leer resumen del capítulo 1'), findsOneWidget);
      expect(find.text('05:00'), findsOneWidget);
      expect(find.text('1. Estirar las sábanas'), findsNothing);
    });

    testWidgets(
        'Abre la configuración de perfil, conexión Docker y Cuenta desde Inicio',
        (WidgetTester tester) async {
      await DBService.instance.setUserName('Sofía');
      await tester.pumpWidget(const DopaApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('server_settings_button')));
      await tester.pumpAndSettle();

      expect(find.text('Perfil, Docker y Cuenta'), findsOneWidget);
      expect(find.text('1. Tu nombre en DOPA'), findsOneWidget);
      expect(find.text('Probar y guardar servidor'), findsOneWidget);
      expect(find.text('3. Cuenta PostgreSQL'), findsOneWidget);
      expect(find.text('Crear cuenta'), findsOneWidget);
    });
  });

  group('2. Pruebas de Integración de Endpoints FastAPI (/api/v1/*)', () {
    test(
        'Autenticación JWT, Perfil, Dashboard, Tareas, Pomodoro, Gamificación e IA',
        () async {
      String? capturedIdempotencyKey;
      String? capturedAuthHeader;

      final mockClient = MockClient((http.Request request) async {
        final path = request.url.path;
        final method = request.method;
        capturedAuthHeader = request.headers['Authorization'];

        if (path.endsWith('/health') && method == 'GET') {
          return _jsonBytesResponse({
            'status': 'ok',
            'database': 'ok',
            'version': '1.0.0',
          });
        }

        if (path.endsWith('/api/v1/auth/login') && method == 'POST') {
          return _jsonBytesResponse({
            'access_token': 'jwt-access-camila-2026',
            'refresh_token': 'jwt-refresh-camila-2026',
            'token_type': 'bearer',
            'expires_in': 1800,
            'usuario': {
              'id': 1,
              'nombre': 'Camila',
              'correo': 'camila@dopa.app',
              'puntos': 0,
              'nivel': 1,
              'preferencias': {
                'duracion_concentracion_min': 5,
                'duracion_descanso_min': 5,
                'meta_diaria_dopamina': 50,
              },
            },
          });
        }

        if (path.endsWith('/api/v1/auth/profile') && method == 'PUT') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return _jsonBytesResponse({
            'id': 1,
            'nombre': body['nombre'],
            'correo': 'camila@dopa.app',
            'puntos': 0,
            'nivel': 1,
          });
        }

        if (path.endsWith('/api/v1/dashboard') && method == 'GET') {
          return _jsonBytesResponse({
            'panel_id': 1,
            'fecha_actual': '2026-11-26',
            'saludo': '¡Hola, Camila!',
            'subtitulo_amigable': 'Vamos un paso a la vez',
            'puntos_dopamina': 10,
            'meta_diaria_puntos': 50,
            'nivel': 1,
            'estado_energia_hoy': 'a tope',
            'resumen_tareas': {
              'pendientes': 1,
              'completadas_hoy': 0,
              'total_hoy': 1,
            },
            'micro_tareas_hoy': [
              {
                'id': 1,
                'id_usuario': 1,
                'titulo': 'Organizar apuntes',
                'prioridad': 'Baja',
                'etiqueta_esfuerzo': 'Fácil',
                'completada': false,
                'puntos_recompensa': 10,
                'subtareas': [
                  {
                    'id': 1,
                    'id_tarea': 1,
                    'descripcion': 'Abrir carpeta de notas',
                    'completada': false,
                  },
                ],
              },
            ],
            'rutinas_hoy': [],
            'recordatorios_proximos': [],
          });
        }

        if (path.endsWith('/api/v1/dashboard/energy-checkin') &&
            method == 'POST') {
          return _jsonBytesResponse({
            'mensaje': '¡Gracias por escuchar cómo te sientes hoy!',
            'nivel_energia': 'media',
            'humor': 'Con foco',
            'puntos_dopamina': 10,
            'sugerencia_baja_friccion':
                'Buen ritmo para avanzar Poquito a poquito.',
            'registro_id': 10,
          }, statusCode: 201);
        }

        if (path.endsWith('/api/v1/tasks') && method == 'GET') {
          return _jsonBytesResponse({
            'encabezado': 'Poquito a poquito',
            'total': 1,
            'pendientes': 1,
            'completadas': 0,
            'resumen_progreso': '0 de 1 listas',
            'limit': 50,
            'offset': 0,
            'items': [
              {
                'id': 1,
                'id_usuario': 1,
                'titulo': 'Organizar apuntes',
                'prioridad': 'Baja',
                'etiqueta_esfuerzo': 'Fácil',
                'completada': false,
                'puntos_recompensa': 10,
                'subtareas': [
                  {
                    'id': 1,
                    'id_tarea': 1,
                    'descripcion': 'Abrir carpeta de notas',
                    'completada': false,
                  },
                ],
              },
            ],
          });
        }

        if (path.endsWith('/api/v1/tasks/1/complete') && method == 'POST') {
          capturedIdempotencyKey = request.headers['Idempotency-Key'];
          return _jsonBytesResponse({
            'mensaje_celebracion': '¡Lo hiciste, Camila!',
            'puntos_ganados': 10,
            'puntos_totales': 10,
            'nivel_actual': 1,
            'idempotente': false,
            'tarea': {
              'id': 1,
              'id_usuario': 1,
              'titulo': 'Organizar apuntes',
              'prioridad': 'Baja',
              'etiqueta_esfuerzo': 'Fácil',
              'completada': true,
              'puntos_recompensa': 10,
              'subtareas': [],
            },
            'recompensas_desbloqueadas': [],
          });
        }

        if (path.endsWith('/api/v1/pomodoro/sessions') && method == 'POST') {
          return _jsonBytesResponse({
            'id': 77,
            'id_usuario': 1,
            'id_tarea': 1,
            'duracionconcentracion': 5,
            'duraciondescanso': 5,
            'sesionescompletadas': 0,
          }, statusCode: 201);
        }

        if (path.endsWith('/api/v1/pomodoro/sessions/77/complete') &&
            method == 'POST') {
          return _jsonBytesResponse({
            'mensaje': 'Ciclo completado',
            'estado': 'completada',
            'puntos_ganados': 5,
            'puntos_totales': 15,
            'nivel_actual': 1,
            'idempotente': false,
            'sugerencia_descanso': 'Toma un break suave',
            'sesion': {
              'id': 77,
              'id_usuario': 1,
              'id_tarea': 1,
              'duracionconcentracion': 5,
              'duraciondescanso': 5,
              'sesionescompletadas': 1,
            },
          });
        }

        if (path.endsWith('/api/v1/gamification/summary') && method == 'GET') {
          return _jsonBytesResponse({
            'encabezado': 'Mi Dopamina hoy',
            'puntos_totales': 15,
            'nivel': 1,
            'meta_diaria_puntos': 50,
            'porcentaje_meta_diaria': 30.0,
            'dias_activos_registrados': 1,
            'actividad_semanal': [false, false, false, true, false, false, false],
            'tareas_completadas_total': 1,
            'sesiones_enfoque_completadas': 1,
            'recompensas_recientes': [],
          });
        }

        if (path.endsWith('/api/v1/gamification/rewards') && method == 'POST') {
          return _jsonBytesResponse({
            'id': 9,
            'nombre': 'Pausa completada',
            'costopuntos': 5,
            'desbloqueada': true,
          }, statusCode: 201);
        }

        if (path.endsWith('/api/v1/personal-records') && method == 'POST') {
          return _jsonBytesResponse({
            'id': 15,
            'id_usuario': 1,
            'nombre': 'Estado emocional: conFoco',
            'valorobjetivo': 5.0,
            'valoractual': 4.0,
            'progresoporcentaje': 80.0,
          }, statusCode: 201);
        }

        if (path.endsWith('/api/v1/financial-goals') && method == 'GET') {
          return _jsonBytesResponse({
            'total': 1,
            'limit': 20,
            'offset': 0,
            'items': [
              {
                'id': 1,
                'id_usuario': 1,
                'nombre': 'Fondo de tranquilidad',
                'valorobjetivo': 500.0,
                'valoractual': 200.0,
                'progresoporcentaje': 40.0,
                'meta_alcanzada': false,
              },
            ],
          });
        }

        if (path.endsWith('/api/v1/ai/chat') && method == 'POST') {
          return _jsonBytesResponse({
            'reply':
                'Empieza por "Organizar apuntes", es cortita y te dará impulso ✨',
            'model': 'nvidia/nemotron-3.5-bolt-e4b',
            'actions': [
              {'type': 'iniciarFoco', 'label': '🎯 Iniciar enfoque', 'payload': {}},
            ],
          });
        }

        return _jsonBytesResponse({'detail': 'Not Found'}, statusCode: 404);
      });

      ApiService.instance.httpClient = mockClient;

      // 1. Verificar Health Check
      final health = await ApiService.instance.checkHealth();
      expect(health['status'], equals('ok'));

      // 2. Verificar Login explícito (cero auto-login silencioso) y actualización de nombre
      final loggedUser = await ApiService.instance.login(
        correo: 'camila@dopa.app',
        contrasena: 'Password123!',
      );
      expect(ApiService.instance.isAuthenticated, isTrue);
      expect(
        (loggedUser['usuario'] as Map<String, dynamic>?)?['nombre'],
        equals('Camila'),
      );

      final updatedProfile =
          await ApiService.instance.updateProfileName('Camila M.');
      expect(updatedProfile['nombre'], equals('Camila M.'));

      // 3. Dashboard via DBService
      final usuario = await DBService.instance.getUsuario();
      expect(capturedAuthHeader, equals('Bearer jwt-access-camila-2026'));
      expect(usuario.nombre, equals('Camila'));
      expect(usuario.dopaminaActual, equals(10));
      expect(usuario.energiaNivel, greaterThan(0.7));

      // 4. Listado y mapeo de tareas con micro-pasos
      final tareas = await DBService.instance.obtenerTareas();
      expect(tareas, isNotEmpty);
      expect(tareas.first.titulo, equals('Organizar apuntes'));
      expect(tareas.first.microPasos.length, equals(1));

      // 5. Completado idempotente de tarea
      await DBService.instance.actualizarTarea(
        TareaBloque(
          id: 1,
          titulo: 'Organizar apuntes',
          subtitulo: '¡Hecho!',
          duracionMinutos: 5,
          estado: EstadoTarea.hecho,
        ),
      );
      expect(capturedIdempotencyKey, isNotNull);
      expect(capturedIdempotencyKey, startsWith('task-complete-1-'));

      // 6. Sesión Pomodoro completada
      final sessionId = await DBService.instance.registrarSesion(
        SesionEnfoque(tareaId: 1, duracionSegundos: 300, completada: true),
      );
      expect(sessionId, equals(77));

      // 7. Resumen de gamificación (incluyendo actividad_semanal) y recompensas
      final totalDopamina = await DBService.instance.obtenerTotalDopaminaHoy();
      expect(totalDopamina, equals(15));
      expect(DBService.instance.actividadSemanalCache[3], isTrue);

      final rewardId = await DBService.instance.agregarRecompensa(
        Recompensa(titulo: 'Pausa completada', puntosDopamina: 5),
      );
      expect(rewardId, equals(9));

      // 8. Registro personal y recomendación IA
      final recordId = await DBService.instance.guardarRegistroBienestar(
        RegistroBienestar(humor: TipoHumor.conFoco, nivelEnergia: 0.8),
      );
      expect(recordId, equals(15));

      final aiRec = await ApiService.instance.fetchAIRecommendation(
        nivelEnergia: 0.5,
        humor: TipoHumor.conFoco,
      );
      expect(aiRec.recommendation, contains('Poquito a poquito'));

      // 9. Metas financieras
      final goals = await ApiService.instance.listFinancialGoals();
      expect(goals['total'], equals(1));

      // 10. Asistente de IA vía Backend (/api/v1/ai/chat)
      final aiChatResp = await ApiService.instance.chatWithAI(
        message: '¿Qué debería hacer primero hoy?',
      );
      expect(aiChatResp['reply'], contains('Organizar apuntes'));
      expect(aiChatResp['model'], equals('nvidia/nemotron-3.5-bolt-e4b'));
    });
  });
}
