import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/planning_state.dart';

/// Screen to manage ignore-keywords for attendance filtering.
class KeywordSettingsScreen extends StatefulWidget {
  const KeywordSettingsScreen({super.key});

  @override
  State<KeywordSettingsScreen> createState() => _KeywordSettingsScreenState();
}

class _KeywordSettingsScreenState extends State<KeywordSettingsScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlanningState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Mots-clés à ignorer')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Les cours dont le titre contient un de ces mots-clés ne nécessiteront pas d\'émargement (sauf override manuel).',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),

            // Input row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Ex: anglais, sport...',
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _add(state),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => _add(state),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Keywords list
            if (state.keywords.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'Aucun mot-clé configuré.\nTous les cours nécessiteront un émargement.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: state.keywords.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final kw = state.keywords[index];
                    return ListTile(
                      leading: const Icon(Icons.label_outline),
                      title: Text(kw),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () => state.removeKeyword(kw),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _add(PlanningState state) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    state.addKeyword(text);
    _controller.clear();
  }
}
