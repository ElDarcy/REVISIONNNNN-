import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/machine_model.dart';
import '../../../providers/machine_provider.dart';

/// Admin machine analytics dashboard.
///
/// Displays usage per machine, most/least used, in-use & maintenance counts,
/// total wash/dry cycles, average daily usage, and maintenance
/// recommendations based on a configurable usage threshold.
class MachineAnalyticsScreen extends StatefulWidget {
  const MachineAnalyticsScreen({super.key});

  @override
  State<MachineAnalyticsScreen> createState() => _MachineAnalyticsScreenState();
}

class _MachineAnalyticsScreenState extends State<MachineAnalyticsScreen> {
  int _threshold = AppConstants.maintenanceThreshold;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Machine Analytics')),
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
                  Icon(Icons.analytics_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No machines found', style: TextStyle(fontSize: 18)),
                ],
              ),
            );
          }

          final sorted = [...machines]
            ..sort((a, b) {
              final typeCompare = a.type.compareTo(b.type);
              if (typeCompare != 0) return typeCompare;
              return a.machineNumber.compareTo(b.machineNumber);
            });

          final washers = sorted
              .where((m) => m.type == AppConstants.machineWasher)
              .toList();
          final dryers = sorted
              .where((m) => m.type == AppConstants.machineDryer)
              .toList();

          final totalWashCycles = washers.fold<int>(
            0,
            (sum, m) => sum + m.usageCount,
          );
          final totalDryCycles = dryers.fold<int>(
            0,
            (sum, m) => sum + m.usageCount,
          );

          final inUseMachines = sorted.where((m) => m.isInUse).toList();
          final maintenanceMachines = sorted
              .where((m) => m.isMaintenance)
              .toList();

          MachineModel? mostUsed;
          MachineModel? leastUsed;
          if (sorted.isNotEmpty) {
            final byUsage = [...sorted]
              ..sort((a, b) => b.usageCount.compareTo(a.usageCount));
            mostUsed = byUsage.first;
            leastUsed = byUsage.last;
          }

          final recommendedForMaintenance = sorted
              .where((m) => m.usageCount >= _threshold)
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildMaintenanceThresholdCard(),
              const SizedBox(height: 16),
              _buildSummaryGrid(
                machines,
                inUseMachines.length,
                maintenanceMachines.length,
              ),
              const SizedBox(height: 16),
              _buildCycleTotals(totalWashCycles, totalDryCycles, machines),
              const SizedBox(height: 16),
              if (mostUsed != null && leastUsed != null)
                _buildMostLeastUsed(mostUsed, leastUsed),
              const SizedBox(height: 16),
              _buildMaintenanceRecommendations(recommendedForMaintenance),
              const SizedBox(height: 16),
              _buildUsageList(sorted),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMaintenanceThresholdCard() {
    return Card(
      color: AppColors.warning.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Maintenance Threshold',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Machines with at least $_threshold uses are recommended for '
              'maintenance.',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<int>(
                    value: _threshold,
                    isExpanded: true,
                    items: [100, 150, 200, 250, 300]
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text('$v uses'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _threshold = v);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryGrid(
    List<MachineModel> all,
    int inUseCount,
    int maintenanceCount,
  ) {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            'Total Machines',
            all.length.toString(),
            Icons.precision_manufacturing,
            AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCard(
            'In Use',
            inUseCount.toString(),
            Icons.play_circle,
            AppColors.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCard(
            'Maintenance',
            maintenanceCount.toString(),
            Icons.build,
            AppColors.error,
          ),
        ),
      ],
    );
  }

  Widget _buildCycleTotals(
    int totalWashCycles,
    int totalDryCycles,
    List<MachineModel> machines,
  ) {
    // Average daily usage across all machines (fallback: use hours since
    // machine creation, max 1 day denominator to avoid divide-by-zero).
    double avgDaily = 0;
    if (machines.isNotEmpty) {
      final oldest = machines
          .map((m) => m.createdAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final days = DateTime.now().difference(oldest).inDays;
      final denominator = days > 0 ? days : 1;
      final total = machines.fold<int>(0, (sum, m) => sum + m.usageCount);
      avgDaily = total / denominator;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Machine Usage Summary',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Wash Cycles'),
                Text(
                  '$totalWashCycles',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Dry Cycles'),
                Text(
                  '$totalDryCycles',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Average Daily Usage'),
                Text(
                  avgDaily.toStringAsFixed(1),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMostLeastUsed(MachineModel most, MachineModel least) {
    return Row(
      children: [
        Expanded(
          child: Card(
            color: AppColors.success.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Most Used',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    most.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '${most.usageCount} uses',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Card(
            color: AppColors.warning.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Least Used',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    least.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '${least.usageCount} uses',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMaintenanceRecommendations(List<MachineModel> recommended) {
    if (recommended.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success),
              SizedBox(width: 8),
              Text('No maintenance recommended at current threshold.'),
            ],
          ),
        ),
      );
    }

    return Card(
      color: AppColors.error.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Maintenance Recommended',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 8),
            ...recommended.map(
              (m) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• ${m.displayName} — ${m.usageCount} uses'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageList(List<MachineModel> sorted) {
    return Card(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Machine Usage',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          ...sorted.map((m) {
            final color = m.isMaintenance
                ? AppColors.error
                : m.isInUse
                ? AppColors.processingColor
                : AppColors.success;
            return ListTile(
              dense: true,
              leading: Icon(
                m.type == AppConstants.machineWasher ? Icons.wash : Icons.air,
                color: color,
              ),
              title: Text(m.displayName),
              subtitle: Text(
                m.isMaintenance
                    ? '${m.usageCount} uses — Maintenance'
                    : m.currentOrderId != null
                    ? '${m.usageCount} uses — Order '
                          '#${m.currentOrderId!.substring(0, 6).toUpperCase()}'
                    : '${m.usageCount} uses — Available',
              ),
              trailing: Text(
                '${m.usageCount}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: color,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
