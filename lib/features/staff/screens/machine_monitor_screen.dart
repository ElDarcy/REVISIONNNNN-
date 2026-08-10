import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/machine_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/machine_provider.dart';

/// Staff real-time machine monitoring screen.
///
/// Displays all 18 machines (9 washing, 9 drying) with live status from
/// Firestore. Updates automatically whenever any machine document changes.
/// Staff can view machine availability and report issues.
class MachineMonitorScreen extends StatelessWidget {
  const MachineMonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Machine Monitor'),
        actions: [
          IconButton(
            tooltip: 'Seed machines',
            icon: const Icon(Icons.add_to_queue),
            onPressed: () async {
              await context.read<MachineProvider>().seedDefaultMachines();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Machines seeded / verified in Firestore'),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<List<MachineModel>>(
        stream: context.read<MachineProvider>().streamMachines(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final machines = snapshot.data ?? [];
          if (machines.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_laundry_service,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text('No machines found', style: TextStyle(fontSize: 18)),
                  SizedBox(height: 8),
                  Text(
                    'Tap the seed icon in the top-right to create the 18 '
                    'default machines.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final washers =
              machines
                  .where((m) => m.type == AppConstants.machineWasher)
                  .toList()
                ..sort((a, b) => a.machineNumber.compareTo(b.machineNumber));
          final dryers =
              machines
                  .where((m) => m.type == AppConstants.machineDryer)
                  .toList()
                ..sort((a, b) => a.machineNumber.compareTo(b.machineNumber));

          final washerAvailable = washers.where((m) => m.isAvailable).length;
          final washerInUse = washers.where((m) => m.isInUse).length;
          final dryerAvailable = dryers.where((m) => m.isAvailable).length;
          final dryerInUse = dryers.where((m) => m.isInUse).length;

          return RefreshIndicator(
            onRefresh: () => context.read<MachineProvider>().loadMachines(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Summary chips
                _buildSummaryRow(
                  washerAvailable,
                  washerInUse,
                  dryerAvailable,
                  dryerInUse,
                ),
                const SizedBox(height: 20),
                // Washing machines section
                _buildSectionHeader(
                  'Washing Machines',
                  Icons.wash,
                  AppColors.processingColor,
                ),
                const SizedBox(height: 8),
                ...washers.map((m) => _MachineCard(machine: m)),
                const SizedBox(height: 20),
                // Dryer machines section
                _buildSectionHeader(
                  'Dryer Machines',
                  Icons.air,
                  Colors.deepPurple,
                ),
                const SizedBox(height: 8),
                ...dryers.map((m) => _MachineCard(machine: m)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryRow(
    int washerAvailable,
    int washerInUse,
    int dryerAvailable,
    int dryerInUse,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            'Washers',
            '🟢 $washerAvailable available',
            '🔵 $washerInUse in use',
            AppColors.processingColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            'Dryers',
            '🟢 $dryerAvailable available',
            '🟣 $dryerInUse in use',
            Colors.deepPurple,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    String title,
    String line1,
    String line2,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Text(line1, style: const TextStyle(fontSize: 12)),
            Text(line2, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _MachineCard extends StatefulWidget {
  final MachineModel machine;

  const _MachineCard({required this.machine});

  @override
  State<_MachineCard> createState() => _MachineCardState();
}

class _MachineCardState extends State<_MachineCard> {
  Timer? _ticker;

  MachineModel get machine => widget.machine;

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  @override
  void didUpdateWidget(covariant _MachineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.machine.currentOrderId != machine.currentOrderId ||
        oldWidget.machine.status != machine.status) {
      _startTicker();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (machine.isInUse && machine.currentOrderId != null) {
      // Refresh remaining time every second for live countdown.
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (color, emoji, statusText) = _statusStyle();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
        title: Text(
          machine.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              machine.currentOrderId != null
                  ? 'Order #${machine.currentOrderId!.substring(0, 6).toUpperCase()}'
                  : 'No active order',
            ),
            Text(
              'Usage: ${machine.usageCount} cycles',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            _buildRemainingTime(),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Report issue',
              icon: const Icon(Icons.report_problem_outlined),
              color: AppColors.error,
              onPressed: () => _showReportIssueDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Staff submit a machine issue. Staff can view status and report issues
  /// but CANNOT change status to maintenance/inactive directly.
  void _showReportIssueDialog(BuildContext context) {
    final machineProvider = context.read<MachineProvider>();
    final authProvider = context.read<AuthProvider>();
    String? selectedCategory = AppConstants.issueCategoryMechanical;
    final descriptionCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Report Issue - ${machine.displayName}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Issue Category',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: AppConstants.issueCategoryMechanical,
                      child: Text('Mechanical'),
                    ),
                    DropdownMenuItem(
                      value: AppConstants.issueCategoryElectrical,
                      child: Text('Electrical'),
                    ),
                    DropdownMenuItem(
                      value: AppConstants.issueCategoryOther,
                      child: Text('Other'),
                    ),
                  ],
                  onChanged: (v) => selectedCategory = v,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descriptionCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Describe the issue',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter a description' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final id = await machineProvider.reportMachineIssue(
                  machineId: machine.id,
                  issueCategory: selectedCategory ?? 'Other',
                  description: descriptionCtrl.text.trim(),
                  reportedBy: authProvider.user?.name ?? 'Staff',
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        id != null
                            ? 'Issue reported. Machine set to Under Inspection.'
                            : 'Failed to report issue.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }

  /// Live remaining time for machines that are actively washing/drying.
  /// Reads the associated order's `estimatedFinish` timestamp. Reserved
  /// machines (not yet started) show "Awaiting start".
  Widget _buildRemainingTime() {
    if (!machine.isInUse) return const SizedBox.shrink();
    if (machine.currentOrderId == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .doc(machine.currentOrderId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final finish = _parseDate(data?['estimatedFinish']);
        if (finish == null) {
          return Text(
            machine.status == AppConstants.machineReserved
                ? 'Awaiting start'
                : 'Timer not set',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          );
        }

        final remaining = finish.difference(DateTime.now());
        if (remaining.isNegative) {
          return Text(
            'Time elapsed',
            style: const TextStyle(fontSize: 12, color: AppColors.error),
          );
        }

        final h = remaining.inHours;
        final m = remaining.inMinutes % 60;
        final s = remaining.inSeconds % 60;
        final text = h > 0
            ? '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s'
            : '${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';

        return Text(
          'Remaining: $text',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.processingColor,
            fontWeight: FontWeight.w600,
          ),
        );
      },
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  (Color, String, String) _statusStyle() {
    switch (machine.status) {
      case AppConstants.machineAvailable:
        return (AppColors.success, '🟢', 'Available');
      case AppConstants.machineReserved:
        return (AppColors.warning, '🟡', 'Reserved');
      case AppConstants.machineWashing:
        return (AppColors.processingColor, '🔵', 'Washing');
      case AppConstants.machineDrying:
        return (Colors.deepPurple, '🟣', 'Drying');
      case AppConstants.machineMaintenance:
        return (AppColors.error, '🔴', 'Maintenance');
      default:
        return (Colors.grey, '⚪', machine.status);
    }
  }
}
