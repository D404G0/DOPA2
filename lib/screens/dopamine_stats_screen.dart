import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/dopa_card.dart';
import '../widgets/mood_selector.dart';
import '../widgets/streak_chart.dart';
import '../widgets/server_settings_sheet.dart';
import '../models/wellness_record_model.dart';
import '../services/db_service.dart';
import '../services/api_service.dart';

/// Pantalla 5: Mi Dopamina hoy (Gamificación libre de culpa y Diario de Bienestar).
class DopamineStatsScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const DopamineStatsScreen({super.key, this.onBack});

  @override
  State<DopamineStatsScreen> createState() => _DopamineStatsScreenState();
}

class _DopamineStatsScreenState extends State<DopamineStatsScreen> {
  int _selectedFilter = 0; // 0: Día, 1: Semana, 2: Mes
  TipoHumor _currentMood = TipoHumor.conFoco;
  int _dopaminaHoy = 0;
  int _metaHoy = 50;
  int _nivel = 1;
  int _streakDays = 0;
  int _tareasCompletadas = 0;
  int _sesionesEnfoque = 0;
  List<bool> _weeklyActivity = List<bool>.filled(7, false);
  DateTime _selectedDate = DateTime.now();

  static const _diasSemana = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  static const _meses = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  @override
  void initState() {
    super.initState();
    DBService.instance.dataVersion.addListener(_onDataChanged);
    _cargarDatosGamificacion();
  }

  @override
  void dispose() {
    DBService.instance.dataVersion.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) {
      _cargarDatosGamificacion();
    }
  }

  Future<void> _cargarDatosGamificacion() async {
    final summary = await DBService.instance.obtenerResumenGamificacion();
    if (!mounted) return;
    final rawWeekly = summary['actividad_semanal'];
    setState(() {
      _dopaminaHoy = (summary['puntos_totales'] as int?) ?? 0;
      _metaHoy = ((summary['meta_diaria_puntos'] as int?) ?? 50).clamp(10, 10000);
      _nivel = (summary['nivel'] as int?) ?? 1;
      _streakDays = (summary['dias_activos_registrados'] as int?) ?? 0;
      _tareasCompletadas = (summary['tareas_completadas_total'] as int?) ?? 0;
      _sesionesEnfoque = (summary['sesiones_enfoque_completadas'] as int?) ?? 0;
      if (rawWeekly is List) {
        _weeklyActivity = List<bool>.generate(
          7,
          (i) => i < rawWeekly.length && rawWeekly[i] == true,
        );
      }
    });
  }

  void _shiftDate(int direction) {
    setState(() {
      if (_selectedFilter == 0) {
        _selectedDate = _selectedDate.add(Duration(days: direction));
      } else if (_selectedFilter == 1) {
        _selectedDate = _selectedDate.add(Duration(days: direction * 7));
      } else {
        _selectedDate = DateTime(
          _selectedDate.year,
          _selectedDate.month + direction,
          _selectedDate.day.clamp(1, 28),
        );
      }
    });
  }

  String _formatDateLabel() {
    if (_selectedFilter == 2) {
      return '${_meses[_selectedDate.month - 1][0].toUpperCase()}${_meses[_selectedDate.month - 1].substring(1)} ${_selectedDate.year}';
    }
    final diaSem = _diasSemana[_selectedDate.weekday - 1];
    final mes = _meses[_selectedDate.month - 1];
    return '$diaSem, ${_selectedDate.day} de $mes';
  }

  @override
  Widget build(BuildContext context) {
    final double progreso = (_dopaminaHoy / _metaHoy).clamp(0.0, 1.0);
    final int porcentaje = (progreso * 100).toInt();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.borderDark,
          onRefresh: _cargarDatosGamificacion,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ENCABEZADO: Volver, Título y logo dopa conectado
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
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              'Mi Dopamina hoy',
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
                    ValueListenableBuilder<bool>(
                      valueListenable: ApiService.instance.connectionStatusNotifier,
                      builder: (context, isOnline, _) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: ApiService.instance.authStatusNotifier,
                          builder: (context, isAuthed, _) {
                            final dotColor = isOnline
                                ? (isAuthed
                                    ? const Color(0xFF3FB97F)
                                    : const Color(0xFFE5A93B))
                                : const Color(0xFFE08A4E);
                            return GestureDetector(
                              onTap: () => ServerSettingsSheet.show(context),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.asset(
                                      'assets/icon/dopa_logo.png',
                                      width: 22,
                                      height: 22,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: dotColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'dopa',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // SELECTOR DE PERIODO: [ Día | Semana | Mes ]
                Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5EDE8),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      _buildFilterItem('Día', 0),
                      _buildFilterItem('Semana', 1),
                      _buildFilterItem('Mes', 2),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // SELECTOR DE FECHA CON NAVEGACIÓN REAL
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildNavArrow(Icons.chevron_left_rounded, () => _shiftDate(-1)),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.pastelYellow,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.borderDark,
                            width: AppTheme.borderWidth,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 16,
                              color: AppTheme.borderDark,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _formatDateLabel(),
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildNavArrow(Icons.chevron_right_rounded, () => _shiftDate(1)),
                  ],
                ),
                const SizedBox(height: 20),

                // TARJETA PRINCIPAL: DOPAMINA REUNIDA
                DopaCard(
                  backgroundColor: AppTheme.pastelMint,
                  padding: const EdgeInsets.all(20.0),
                  borderRadius: AppTheme.radiusLarge,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Dopamina reunida',
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textPrimary,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$_dopaminaHoy pts',
                                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.5,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Nivel $_nivel · $_tareasCompletadas tareas · $_sesionesEnfoque focos',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: AppTheme.textSecondary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppTheme.pastelYellow,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.borderDark,
                                width: AppTheme.borderWidth,
                              ),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$porcentaje%',
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                        ),
                                  ),
                                  Text(
                                    'de tu meta',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          height: 1.1,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceWhite,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.borderDark,
                            width: 1.4,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8.5),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progreso,
                            child: Container(
                              color: AppTheme.pastelPink,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // DIARIO DE BIENESTAR ("Mi humor")
                Text(
                  'Mi humor',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 14),
                MoodSelector(
                  selectedMood: _currentMood,
                  onMoodChanged: (nuevoHumor) {
                    setState(() {
                      _currentMood = nuevoHumor;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Estado de ánimo guardado ✨'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // MOTOR DE GAMIFICACIÓN ("Rachas")
                StreakChart(
                  streakDays: _streakDays,
                  weeklyActivity: _weeklyActivity,
                ),
                const SizedBox(height: 76),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterItem(String title, int index) {
    final bool isSelected = _selectedFilter == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilter = index),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.surfaceWhite : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavArrow(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppTheme.borderDark,
            width: AppTheme.borderWidth,
          ),
        ),
        child: Icon(icon, color: AppTheme.borderDark, size: 22),
      ),
    );
  }
}
