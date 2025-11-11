import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DeveloperScreen extends StatelessWidget {
  const DeveloperScreen({super.key});

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copié dans le presse-papiers'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Développeur')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 16),
          const Center(child: Icon(Icons.person, size: 80, color: Colors.blue)),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'crazycat256',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Coordonnées',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.chat_bubble_outline,
                color: Colors.blueAccent,
              ),
              title: const Text('Discord'),
              subtitle: const Text('crazycat256'),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () =>
                    _copyToClipboard(context, 'crazycat256', 'Discord'),
                tooltip: 'Copier',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.email_outlined, color: Colors.red),
              title: const Text('Email'),
              subtitle: const Text('contact@crazycat256.fr'),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () => _copyToClipboard(
                  context,
                  'contact@crazycat256.fr',
                  'Email',
                ),
                tooltip: 'Copier',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
