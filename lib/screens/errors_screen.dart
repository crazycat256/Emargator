import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class ErrorsScreen extends StatelessWidget {
  const ErrorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapports d\'erreurs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              context.read<AppState>().clearErrors();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Historique des erreurs effacé')),
              );
            },
          )
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          if (appState.errors.isEmpty) {
            return const Center(child: Text('Aucune erreur enregistrée.'));
          }
          return ListView.builder(
            itemCount: appState.errors.length,
            itemBuilder: (context, index) {
              final error = appState.errors[index];
              return ListTile(
                title: Text(error.contextName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(error.timestamp.toString().substring(0, 19)),
                    Text(error.error, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
                isThreeLine: true,
                onTap: () {
                    Clipboard.setData(ClipboardData(text: error.toString()));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Rapport copié dans le presse-papier'))
                    );
                },
              );
            },
          );
        },
      ),
    );
  }
}

