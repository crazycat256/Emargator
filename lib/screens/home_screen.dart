import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/attendance_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Émargator')),
      body: Consumer<AppState>(
        builder: (context, state, _) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SSOStatusCard(status: state.ssoStatus),
                const SizedBox(height: 24),
                if (state.ssoStatus == SSOStatus.disconnected &&
                    !state.hasCredentials) ...[
                  const _NoCredentialsCard(),
                  const SizedBox(height: 24),
                ],
                Expanded(
                  child: Center(
                    child: ElevatedButton(
                      onPressed:
                          state.isSigningAttendance ||
                              state.ssoStatus != SSOStatus.connected
                          ? null
                          : () => _signAttendance(context, state),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(48),
                        shape: const CircleBorder(),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(200, 200),
                      ),
                      child: state.isSigningAttendance
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, size: 64),
                                SizedBox(height: 8),
                                Text('Émarger', style: TextStyle(fontSize: 24)),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _signAttendance(BuildContext context, AppState state) async {
    final result = await state.signAttendance();

    if (!context.mounted) return;

    final message = result.message;
    final color =
        result == AttendanceResult.success ||
            result == AttendanceResult.alreadySignedIn
        ? Colors.green
        : Colors.red;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }
}

class _NoCredentialsCard extends StatelessWidget {
  const _NoCredentialsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.info_outline, color: Colors.orange, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Identifiants non configurés',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Veuillez configurer vos identifiants SSO dans l\'onglet Paramètres pour pouvoir émarger.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SSOStatusCard extends StatelessWidget {
  final SSOStatus status;

  const _SSOStatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(status.icon, color: status.color, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Statut SSO',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(status.label, style: TextStyle(color: status.color)),
                ],
              ),
            ),
            if (status == SSOStatus.error || status == SSOStatus.disconnected)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => context.read<AppState>().connectSSO(),
              ),
          ],
        ),
      ),
    );
  }
}
