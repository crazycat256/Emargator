import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Confirmer'),
                  content: const Text('Effacer tout l\'historique ?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Annuler'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Effacer'),
                    ),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                await context.read<AppState>().clearLogs();
              }
            },
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, state, _) {
          if (state.logs.isEmpty) {
            return const Center(child: Text('Aucun historique'));
          }

          return ListView.builder(
            itemCount: state.logs.length,
            itemBuilder: (context, index) {
              final log = state.logs[index];
              final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');

              final color =
                  log.result == 'success' || log.result == 'alreadySignedIn'
                  ? Colors.green
                  : Colors.red;

              return ListTile(
                leading: Icon(
                  log.result == 'success'
                      ? Icons.check_circle
                      : log.result == 'alreadySignedIn'
                      ? Icons.info
                      : Icons.error,
                  color: color,
                ),
                title: Text(log.message),
                subtitle: Text(dateFormat.format(log.timestamp)),
              );
            },
          );
        },
      ),
    );
  }
}
