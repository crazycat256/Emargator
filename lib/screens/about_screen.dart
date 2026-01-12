import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'warning_details_screen.dart';
import 'errors_screen.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _version = packageInfo.version;
      });
    } catch (e) {
      setState(() {
        _version = '1.0.0';
      });
    }
  }

  Future<void> _openGitHub() async {
    final uri = Uri.parse('https://github.com/crazycat256/Emargator');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d\'ouvrir le lien'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('À propos')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
            title: const Text('Avertissement Important'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const WarningDetailsScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.bug_report, color: Colors.orange),
            title: const Text('Erreurs'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ErrorsScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.code_outlined),
            title: const Text('Code source'),
            subtitle: const Text('github.com/crazycat256/Emargator'),
            trailing: const Icon(Icons.open_in_new),
            onTap: _openGitHub,
          ),
          const ListTile(
            leading: Icon(Icons.gavel),
            title: Text('Licence'),
            subtitle: Text('GNU General Public License v3.0'),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: Text(_version.isEmpty ? 'Chargement...' : _version),
          ),
        ],
      ),
    );
  }
}
