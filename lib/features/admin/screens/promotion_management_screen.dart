import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/engagement_models.dart';
import '../../../services/business_configuration_service.dart';

class PromotionManagementScreen extends StatefulWidget {
  const PromotionManagementScreen({super.key});
  @override
  State<PromotionManagementScreen> createState() => _PromotionManagementScreenState();
}

class _PromotionManagementScreenState extends State<PromotionManagementScreen> {
  final BusinessConfigurationService _service = BusinessConfigurationService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Promotion Management')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editPromo(context, null),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Promotion>>(
        stream: _service.watchPromotions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final promos = snapshot.data ?? const [];
          if (promos.isEmpty) {
            return const Center(child: Text('No promotions yet. Tap + to create one.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: promos.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = promos[index];
              final isActive = p.status == 'Active';
              return Card(
                child: ListTile(
                  leading: Icon(
                    p.type == 'percentage' ? Icons.percent : Icons.attach_money,
                    color: isActive ? Colors.green : Colors.grey,
                  ),
                  title: Text(
                    p.name ?? p.code,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p.type} • ${p.value}${p.type == 'percentage' ? '%' : '₱'}'),
                      if (p.minimumOrderAmount > 0)
                        Text('Min transaction: ₱${p.minimumOrderAmount.toStringAsFixed(0)}'),
                      if (p.memberOnly)
                        const Text('Members only', style: TextStyle(color: Colors.orange)),
                      if (p.startDate != null || p.endDate != null)
                        Text(
                          '${p.startDate != null ? _fmt(p.startDate!) : 'Open'} → ${p.endDate != null ? _fmt(p.endDate!) : 'No end'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: isActive,
                        onChanged: (on) => _service.savePromotion(
                          p.id,
                          {'status': on ? 'Active' : 'Inactive'},
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _editPromo(context, p),
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

  String _fmt(DateTime d) => '${d.month}/${d.day}/${d.year}';

  Future<void> _editPromo(BuildContext context, Promotion? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final codeCtrl = TextEditingController(text: existing?.code ?? '');
    final valueCtrl = TextEditingController(text: existing?.value.toString() ?? '0');
    final minOrderCtrl = TextEditingController(
      text: existing?.minimumOrderAmount.toString() ?? '0',
    );
    final maxDiscountCtrl = TextEditingController(
      text: existing?.maximumDiscount?.toString() ?? '',
    );
    final usageLimitCtrl = TextEditingController(
      text: existing?.usageLimit?.toString() ?? '',
    );
    final custLimitCtrl = TextEditingController(
      text: existing?.customerUsageLimit?.toString() ?? '',
    );
    String type = existing?.type ?? 'percentage';
    bool memberOnly = existing?.memberOnly ?? false;
    DateTime? startDate = existing?.startDate;
    DateTime? endDate = existing?.endDate;

    await showDialog(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Create Promotion' : 'Edit Promotion'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Display Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(labelText: 'Promo Code'),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 8),
                // Type selector
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'percentage', label: Text('% Off')),
                    ButtonSegment(value: 'fixed', label: Text('₱ Off')),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => setDialogState(() => type = s.first),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: valueCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Discount Value',
                    hintText: type == 'percentage' ? 'e.g. 10 for 10%' : 'e.g. 50 for ₱50',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: minOrderCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Minimum Transaction Amount (₱)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: maxDiscountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Max Discount Cap (₱, optional)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: usageLimitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Global Usage Limit (optional)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: custLimitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Per-Customer Limit (optional)'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Members Only'),
                  value: memberOnly,
                  onChanged: (v) => setDialogState(() => memberOnly = v),
                ),
                const SizedBox(height: 8),
                // Date range
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: startDate ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) setDialogState(() => startDate = picked);
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(startDate != null ? _fmt(startDate!) : 'Start Date'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: endDate ?? DateTime.now().add(const Duration(days: 30)),
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) setDialogState(() => endDate = picked);
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(endDate != null ? _fmt(endDate!) : 'End Date'),
                      ),
                    ),
                  ],
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
                final id = existing?.id ?? codeCtrl.text.trim().toLowerCase().replaceAll(' ', '_');
                final value = double.tryParse(valueCtrl.text) ?? 0;
                if (id.isEmpty || value <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Code and value are required.')),
                  );
                  return;
                }
                final data = {
                  'name': nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : id,
                  'code': codeCtrl.text.trim().toUpperCase(),
                  'type': type,
                  'value': value,
                  'minimumOrderAmount': double.tryParse(minOrderCtrl.text) ?? 0,
                  'maximumDiscount': maxDiscountCtrl.text.isNotEmpty
                      ? double.tryParse(maxDiscountCtrl.text)
                      : null,
                  'usageLimit': usageLimitCtrl.text.isNotEmpty
                      ? int.tryParse(usageLimitCtrl.text)
                      : null,
                  'customerUsageLimit': custLimitCtrl.text.isNotEmpty
                      ? int.tryParse(custLimitCtrl.text)
                      : null,
                  'memberOnly': memberOnly,
                  'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
                  'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
                  'status': existing?.status ?? 'Active',
                };
                await _service.savePromotion(id, data);
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
