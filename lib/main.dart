import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:io' show Platform;
import 'providers/app_state.dart';
import 'providers/planning_state.dart';
import 'screens/home_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/planning_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/warning_screen.dart';
import 'services/attendance_notification_service.dart';
import 'services/attendance_service.dart';
import 'services/battery_service.dart';
import 'services/planning_prefs_service.dart';
import 'services/update_check_service.dart';
import 'services/desktop_service.dart';
import 'services/desktop_single_instance_service.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final isPrimaryInstance =
        await DesktopSingleInstanceService.ensurePrimaryInstance();
    if (!isPrimaryInstance) {
      return;
    }

    await DesktopService.init();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  /// Global navigator key for showing SnackBars from notification callbacks.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..initialize()),
        ChangeNotifierProvider(
          create: (_) {
            final state = PlanningState();
            void initOthers() {
              AttendanceNotificationService.init().then((_) {
                BatteryService.ensureExempt();
                state.initialize();
              });
            }

            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
              initOthers();
            } else {
              AndroidAlarmManager.initialize().then((_) => initOthers());
            }
            return state;
          },
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: scaffoldMessengerKey,
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
  bool _updateCheckStarted = false;

  @override
  void initState() {
    super.initState();
    _checkForUpdatesInBackground();
  }

  Future<void> _checkForUpdatesInBackground() async {
    if (_updateCheckStarted) return;
    _updateCheckStarted = true;

    final result = await UpdateCheckService.checkForUpdate();
    if (!mounted || result == null || !result.hasUpdate) return;

    MyApp.scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('Nouvelle version disponible : ${result.latestVersion}'),
        action: SnackBarAction(
          label: 'Mettre à jour',
          onPressed: () {
            _openReleaseUrl(result.releaseUrl);
          },
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _openReleaseUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      MyApp.scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir le lien.')),
      );
    }
  }

  void _navigateToSettings() {
    setState(() {
      _currentIndex = 3;
    });
  }

  void _showSignResultSnackBar(AttendanceResult result) {
    final ctx = MyApp.navigatorKey.currentContext;
    if (ctx == null) return;
    final isSuccess =
        result == AttendanceResult.success ||
        result == AttendanceResult.alreadySignedIn;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
      ),
    );
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
        final result = await appState.signAttendance();
        // Show result SnackBar via global navigator key (not a widget context)
        _showSignResultSnackBar(result);
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
