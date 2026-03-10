import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io' show Platform;
import 'providers/app_state.dart';
import 'providers/planning_state.dart';
import 'screens/home_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/planning_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/warning_screen.dart';
import 'services/attendance_notification_service.dart';
import 'services/planning_prefs_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(450, 715),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..initialize()),
        ChangeNotifierProvider(
          create: (_) {
            final state = PlanningState();
            AttendanceNotificationService.init().then((_) async {
              await AttendanceNotificationService.requestPermission();
              state.initialize();
            });
            return state;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Émargator',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const MainTabScreen(),
      ),
    );
  }
}

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _currentIndex = 0;
  bool _listeningToAppState = false;
  bool _notifCallbacksWired = false;

  void _navigateToSettings() {
    setState(() {
      _currentIndex = 3;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final planningState = context.read<PlanningState>();

    // Reschedule notifications whenever AppState changes (sign-in, Moodle fetch)
    if (!_listeningToAppState) {
      _listeningToAppState = true;
      appState.addListener(() {
        planningState.rescheduleNotifications();
      });
    }

    // Wire notification action callbacks once both providers are available
    if (!_notifCallbacksWired) {
      _notifCallbacksWired = true;
      AttendanceNotificationService.onSignAttendance = () async {
        await appState.signAttendance();
      };
      AttendanceNotificationService.onIgnoreSlot = (slotKey) async {
        await PlanningPrefsService.setOverride(
          slotKey,
          LessonOverride.forceSkip,
        );
        await planningState.rescheduleNotifications();
      };
    }

    if (!appState.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!appState.hasAcceptedWarning) {
      return WarningScreen(
        onAccept: () async {
          await appState.acceptWarning();
        },
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(onNavigateToSettings: _navigateToSettings),
          const PlanningScreen(),
          const LogsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Planning',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Historique',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Paramètres',
          ),
        ],
      ),
    );
  }
}
