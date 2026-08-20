import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoyaltyRewardManagementScreen extends StatelessWidget {
  const LoyaltyRewardManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loyalty Rewards')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editReward(context, null, null),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('loyalty_rewards')
            .orderBy('requiredPoints')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No rewards yet. Tap + to create one.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final d = docs[index];
              final data = d.data();
              final isActive = data['status'] == 'Active';
              return Card(
                child: ListTile(
                  leading: Icon(
                    _rewardIcon(data['type'] ?? ''),
                    color: isActive ? Colors.green : Colors.grey,
                  ),
                  title: Text(
                    data['name'] ?? d.id,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${data['requiredPoints'] ?? 0} points'
                    '${data['value'] != null && data['value'] > 0 ? ' • Value: ${data['value']}' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: isActive,
                        onChanged: (v) => d.reference.set({
                          'status': v ? 'Active' : 'Inactive',
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _editReward(context, d.id, data),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Reward?'),
                              content: Text('Delete "${data['name'] ?? d.id}"?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await d.reference.delete();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  IconData _rewardIcon(String type) {
    switch (type) {
      case 'fixed_discount':
        return Icons.attach_money;
      case 'percentage_discount':
        return Icons.percent;
      case 'free_service':
        return Icons.card_giftcard;
      default:
        return Icons.star;
    }
  }

  Future<void> _editReward(
    BuildContext context,
    String? existingId,
    Map<String, dynamic>? existing,
  ) async {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final pointsCtrl = TextEditingController(
      text: existing?['requiredPoints']?.toString() ?? '0',
    );
    final valueCtrl = TextEditingController(
      text: existing?['value']?.toString() ?? '0',
    );
    String type = existing?['type'] ?? 'fixed_discount';

    await showDialog(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existingId == null ? 'Create Reward' : 'Edit Reward'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Reward Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pointsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Required Points'),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'fixed_discount', label: Text('₱ Off')),
                    ButtonSegment(value: 'percentage_discount', label: Text('% Off')),
                    ButtonSegment(value: 'free_service', label: Text('Free')),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => setDialogState(() => type = s.first),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: valueCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Discount Value (0 for free service)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final id = existingId ?? nameCtrl.text.trim().toLowerCase().replaceAll(' ', '_');
                final points = int.tryParse(pointsCtrl.text) ?? 0;
                if (id.isEmpty || points <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Name and points are required.')),
                  );
                  return;
                }
                await FirebaseFirestore.instance
                    .collection('loyalty_rewards')
                    .doc(id)
                    .set({
                  'name': nameCtrl.text.trim(),
                  'requiredPoints': points,
                  'type': type,
                  'value': double.tryParse(valueCtrl.text) ?? 0,
                  'status': existing?['status'] ?? 'Active',
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
                if (dialog.mounted) Navigator.pop(dialog);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
