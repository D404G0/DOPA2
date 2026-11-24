import 'package:flutter/material.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/ai_floating_button.dart';
import '../services/ai_context_service.dart';
import 'home_dashboard_screen.dart';
import 'tasks_screen.dart';
import 'dopamine_stats_screen.dart';
import 'gentle_break_screen.dart';

/// Pantalla contenedora de la barra de navegación inferior.
/// Controla el flujo entre las 4 secciones principales de App Dopa.
class MainNavigationScreen extends StatefulWidget {
  /// Notificador global ligero para permitir saltos de pestaña desde sub-rutas
  /// (por ejemplo, desde SessionSuccessScreen hacia 'Dopamina' o 'Inicio').
  static final ValueNotifier<int> tabNotifier = ValueNotifier<int>(0);

  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  @override
  void initState() {
    super.initState();
    MainNavigationScreen.tabNotifier.addListener(_handleExternalTabChange);
  }

  @override
  void dispose() {
    MainNavigationScreen.tabNotifier.removeListener(_handleExternalTabChange);
    super.dispose();
  }

  void _handleExternalTabChange() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Nombres de las secciones para el contexto de la IA.
  static const _sectionNames = ['Inicio', 'Tareas', 'Dopamina', 'Pausa'];

  void _onTabTapped(int index) {
    MainNavigationScreen.tabNotifier.value = index;
    // Actualizar la sección actual para el contexto de la IA
    if (index >= 0 && index < _sectionNames.length) {
      AIContextService.instance.setCurrentSection(_sectionNames[index]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = MainNavigationScreen.tabNotifier.value;

    final screens = [
      // Tab 0: Inicio / Dashboard
      HomeDashboardScreen(
        onNavigateToTasks: () => _onTabTapped(1),
        onNavigateToBreak: () => _onTabTapped(3),
      ),
      // Tab 1: Tareas
      TasksScreen(
        onBack: () => _onTabTapped(0),
      ),
      // Tab 2: Dopamina
      DopamineStatsScreen(
        onBack: () => _onTabTapped(0),
      ),
      // Tab 3: Pausa / Break
      GentleBreakScreen(
        onBack: () => _onTabTapped(0),
        onGoHome: () => _onTabTapped(0),
      ),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: currentIndex,
            children: screens,
          ),
          // Botón flotante del asistente de IA
          const AIFloatingButton(),
        ],
      ),
      bottomNavigationBar: DopaBottomNavBar(
        currentIndex: currentIndex,
        onTap: _onTabTapped,
      ),
    );
  }
}
