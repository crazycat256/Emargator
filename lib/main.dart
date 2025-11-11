import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/logs_screen.dart';
import 'services/storage_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..initialize(),
      child: MaterialApp(
        title: 'Émargator',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const _StartupScreen(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/home': (context) => const HomeScreen(),
          '/logs': (context) => const LogsScreen(),
        },
      ),
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: StorageService().hasCredentials(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final hasCredentials = snapshot.data ?? false;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.of(
            context,
          ).pushReplacementNamed(hasCredentials ? '/home' : '/login');
        });

        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
