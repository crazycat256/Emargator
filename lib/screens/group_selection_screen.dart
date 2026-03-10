import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/planning_state.dart';
import '../models/index/formation.dart';
import '../models/index/year.dart';
import '../models/index/group.dart';

/// Screen that lets the user pick their ENSIBS formation → year → TP group.
class GroupSelectionScreen extends StatefulWidget {
  const GroupSelectionScreen({super.key});

  @override
  State<GroupSelectionScreen> createState() => _GroupSelectionScreenState();
}

class _GroupSelectionScreenState extends State<GroupSelectionScreen> {
  EnsiFormation? _formation;
  EnsiYear? _year;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlanningState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Choisir un groupe')),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : !state.indexLoaded
          ? _buildError()
          : _buildSelection(context, state),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Impossible de charger l\'index des formations.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => context.read<PlanningState>().initialize(),
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelection(BuildContext context, PlanningState state) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Formation
        const Text(
          'Formation',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildDropdown<EnsiFormation>(
          value: _formation,
          items: state.formations,
          hint: 'Choisir une formation',
          labelFn: (f) => f.name,
          onChanged: (f) {
            setState(() {
              _formation = f;
              _year = null;
            });
          },
        ),

        if (_formation != null) ...[
          const SizedBox(height: 24),
          const Text(
            'Année',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildDropdown<EnsiYear>(
            value: _year,
            items: _formation!.years,
            hint: 'Choisir une année',
            labelFn: (y) => y.name,
            onChanged: (y) {
              setState(() {
                _year = y;
              });
            },
          ),
        ],

        if (_year != null) ...[
          const SizedBox(height: 24),
          const Text(
            'Groupe de TP',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._year!.groups.map((group) => _buildGroupTile(context, group)),
        ],
      ],
    );
  }

  Widget _buildDropdown<T>({
    required T? value,
    required List<T> items,
    required String hint,
    required String Function(T) labelFn,
    required void Function(T?) onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: hint,
      ),
      items: items
          .map(
            (item) => DropdownMenuItem(value: item, child: Text(labelFn(item))),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildGroupTile(BuildContext context, EnsiGroup group) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.group),
        title: Text(group.name),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          await context.read<PlanningState>().selectGroup(
            _formation!,
            _year!,
            group,
          );
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        },
      ),
    );
  }
}
