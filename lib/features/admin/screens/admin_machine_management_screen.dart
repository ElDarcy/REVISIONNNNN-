import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/machine_model.dart';
import '../../../models/maintenance_record_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/machine_provider.dart';

/// Admin machine management screen.
///
/// Admin-only screen to:
///  - View all washing machines and dryers.
///  - Update machine status (Available / Busy / Maintenance / Inactive /
///    Under Inspection).
///  - Add maintenance records.
///  - Complete maintenance and return a machine to Available.
class AdminMachineManagementScreen extends StatefulWidget {
  const AdminMachineManagementScreen({super.key});

  @override
  State<AdminMachineManagementScreen> createState() =>
      _AdminMachineManagementScreenState();
}

class _AdminMachineManagementScreenState
    extends State<AdminMachineManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().isAdmin;
    final machineProvider = context.read<MachineProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Machine Management'),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Restore Deleted Machines',
              icon: const Icon(Icons.restore),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Restore Machines?'),
                    content: const Text(
                      'This will recreate the default set of 18 machines (9 washers, 9 dryers). Existing machines will not be modified.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Restore'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  await machineProvider.seedDefaultMachines();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Machines collection restored successfully.'),
                      ),
                    );
                  }
                }
              },
            ),
        ],
      ),
      body: StreamBuilder<List<MachineModel>>(
        stream: machineProvider.streamMachines(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final machines = snapshot.data ?? [];
          if (machines.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.precision_manufacturing_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No machines found', style: TextStyle(fontSize: 18)),
                  if (isAdmin) ...[
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await machineProvider.seedDefaultMachines();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Machines collection restored successfully.')),
                          );
                        }
                      },
                      icon: const Icon(Icons.restore),
                      label: const Text('Seed Default Machines'),
                    ),
                  ],
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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!isAdmin)
                const Card(
                  color: AppColors.error,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'You do not have permission to manage machines.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              _buildSectionHeader('Washing Machines', Icons.wash),
              const SizedBox(height: 8),
              ...washers.map(
                (m) => _MachineAdminCard(
                  machine: m,
                  isAdmin: isAdmin,
                  onCompleteMaintenance: (maintenanceId) async {
                    await machineProvider.completeMaintenance(
                      maintenanceId: maintenanceId,
                      machineId: m.id,
                      isAdmin: isAdmin,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${m.displayName} returned to Available',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 20),
              _buildSectionHeader('Dryers', Icons.air),
              const SizedBox(height: 8),
              ...dryers.map(
                (m) => _MachineAdminCard(
                  machine: m,
                  isAdmin: isAdmin,
                  onCompleteMaintenance: (maintenanceId) async {
                    await machineProvider.completeMaintenance(
                      maintenanceId: maintenanceId,
                      machineId: m.id,
                      isAdmin: isAdmin,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${m.displayName} returned to Available',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 20),
              _buildMaintenanceRecordsSection(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildMaintenanceRecordsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.build, color: AppColors.error, size: 22),
            const SizedBox(width: 8),
            const Text(
              'Maintenance Records',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Add maintenance record',
              icon: const Icon(Icons.add),
              onPressed: () => _showAddMaintenanceDialog(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<MaintenanceRecordModel>>(
          stream: context.read<MachineProvider>().streamMaintenanceRecords(),
          builder: (context, snapshot) {
            final records = snapshot.data ?? [];
            if (records.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No maintenance records yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              );
            }
            return Column(
              children: records.map((r) {
                return Card(
                  child: ListTile(
                    leading: Icon(
                      r.isCompleted ? Icons.check_circle : Icons.build,
                      color: r.isCompleted
                          ? AppColors.success
                          : AppColors.error,
                    ),
                    title: Text('Machine: ${r.machineId}'),
                    subtitle: Text(
                      '${r.reason}\nStatus: ${r.status} · Reported by '
                      '${r.reportedBy}',
                    ),
                    isThreeLine: true,
                    trailing: r.isCompleted
                        ? null
                        : TextButton(
                            onPressed: () => _completeMaintenanceRecord(
                              machineId: r.machineId,
                              maintenanceId: r.maintenanceId,
                            ),
                            child: const Text('Complete'),
                          ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _completeMaintenanceRecord({
    required String machineId,
    required String maintenanceId,
  }) async {
    final provider = context.read<MachineProvider>();
    final isAdmin = context.read<AuthProvider>().isAdmin;
    await provider.completeMaintenance(
      maintenanceId: maintenanceId,
      machineId: machineId,
      isAdmin: isAdmin,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maintenance completed for $machineId')),
      );
    }
  }

  void _showAddMaintenanceDialog() {
    final machineProvider = context.read<MachineProvider>();
    final isAdmin = context.read<AuthProvider>().isAdmin;
    final reportedBy = context.read<AuthProvider>().user?.name ?? 'Admin';
    String? selectedMachineId;
    String? type;
    final reasonCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final expectedCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Maintenance Record'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StreamBuilder<List<MachineModel>>(
                    stream: machineProvider.streamMachines(),
                    builder: (context, snapshot) {
                      final machines = snapshot.data ?? [];
                      return DropdownButtonFormField<String>(
                        initialValue: selectedMachineId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Machine',
                          border: OutlineInputBorder(),
                        ),
                        items: machines
                            .map(
                              (m) => DropdownMenuItem(
                                value: m.id,
                                child: Text(m.displayName),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          selectedMachineId = v;
                          final m = machines.firstWhere(
                            (x) => x.id == v,
                            orElse: () => MachineModel(
                              id: '',
                              machineId: '',
                              machineNumber: 0,
                              type: AppConstants.machineWasher,
                            ),
                          );
                          type = m.type;
                        },
                        validator: (v) => v == null ? 'Select a machine' : null,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter reason' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: expectedCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Expected completion (yyyy-mm-dd)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate() ||
                    selectedMachineId == null) {
                  return;
                }
                DateTime? expected;
                if (expectedCtrl.text.trim().isNotEmpty) {
                  expected =
                      DateTime.tryParse(expectedCtrl.text.trim()) ??
                      DateTime.now().add(const Duration(days: 1));
                }
                final id = await machineProvider.addMaintenanceRecord(
                  machineId: selectedMachineId!,
                  machineType: type ?? '',
                  reason: reasonCtrl.text.trim(),
                  reportedBy: reportedBy,
                  isAdmin: isAdmin,
                  expectedCompletionDate: expected,
                  notes: notesCtrl.text.trim(),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        id != null
                            ? 'Maintenance record created'
                            : 'Failed to create maintenance record',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ).then((_) {
      reasonCtrl.dispose();
      notesCtrl.dispose();
      expectedCtrl.dispose();
    });
  }
}

class _MachineAdminCard extends StatelessWidget {
  final MachineModel machine;
  final bool isAdmin;
  final Future<void> Function(String maintenanceId) onCompleteMaintenance;

  const _MachineAdminCard({
    required this.machine,
    required this.isAdmin,
    required this.onCompleteMaintenance,
  });

  @override
  Widget build(BuildContext context) {
    final (color, emoji, statusText) = _statusStyle();
    final hasPendingMaintenance =
        machine.status == AppConstants.machineMaintenance;

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
        subtitle: Text(
          '${machine.type == AppConstants.machineWasher ? 'Washer' : 'Dryer'} '
          '· Usage: ${machine.usageCount} cycles'
          '${machine.currentOrderId != null ? ' · Transaction active' : ''}',
        ),
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
            if (isAdmin) ...[
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                onSelected: (status) async {
                  await context.read<MachineProvider>().updateMachineStatus(
                    machineId: machine.id,
                    status: status,
                    isAdmin: isAdmin,
                  );
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: AppConstants.machineAvailable,
                    child: Text('Available'),
                  ),
                  const PopupMenuItem(
                    value: AppConstants.machineBusy,
                    child: Text('Busy'),
                  ),
                  const PopupMenuItem(
                    value: AppConstants.machineMaintenance,
                    child: Text('Maintenance'),
                  ),
                  const PopupMenuItem(
                    value: AppConstants.machineInactive,
                    child: Text('Inactive'),
                  ),
                  const PopupMenuItem(
                    value: AppConstants.machineUnderInspection,
                    child: Text('Under Inspection'),
                  ),
                ],
                child: const Icon(Icons.more_vert),
              ),
              if (hasPendingMaintenance)
                IconButton(
                  tooltip: 'Complete maintenance',
                  icon: const Icon(
                    Icons.check_circle,
                    color: AppColors.success,
                  ),
                  onPressed: () async {
                    // Find the latest incomplete maintenance record for this
                    // machine and complete it.
                    final snap = await FirebaseFirestore.instance
                        .collection('maintenanceRecords')
                        .where('machineId', isEqualTo: machine.id)
                        .where('status', isNotEqualTo: 'Completed')
                        .limit(1)
                        .get();
                    if (snap.docs.isNotEmpty) {
                      await onCompleteMaintenance(snap.docs.first.id);
                    }
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  (Color, String, String) _statusStyle() {
    switch (machine.status) {
      case AppConstants.machineAvailable:
        return (AppColors.success, '🟢', 'Available');
      case AppConstants.machineBusy:
        return (AppColors.warning, '🟡', 'Busy');
      case AppConstants.machineReserved:
        return (AppColors.warning, '🟡', 'Reserved');
      case AppConstants.machineWashing:
        return (AppColors.processingColor, '🔵', 'Washing');
      case AppConstants.machineDrying:
        return (Colors.deepPurple, '🟣', 'Drying');
      case AppConstants.machineMaintenance:
        return (AppColors.error, '🔴', 'Maintenance');
      case AppConstants.machineInactive:
        return (Colors.grey, '⚪', 'Inactive');
      case AppConstants.machineUnderInspection:
        return (Colors.orange, '🟠', 'Under Inspection');
      default:
        return (Colors.grey, '⚪', machine.status);
    }
  }
}
