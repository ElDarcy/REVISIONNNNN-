import 'package:flutter/material.dart';

import '../../../models/engagement_models.dart';
import '../../../services/business_configuration_service.dart';

/// Admin-only configuration surface. It changes optional business values,
/// never the verified-weight, payment, machine, delivery, or queue safeguards.
class BusinessConfigurationScreen extends StatelessWidget {
  const BusinessConfigurationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = BusinessConfigurationService();
    return Scaffold(
      appBar: AppBar(title: const Text('Business Configuration')),
      body: StreamBuilder<BusinessFeatures>(
        stream: service.watchFeatures(),
        builder: (context, snapshot) {
          final features = snapshot.data ?? const BusinessFeatures();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: service.ensureInitialConfiguration,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Initialize defaults'),
                ),
              ),
              const Text(
                'Customer Features',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              _toggle(
                service,
                'Real-Time Transaction Tracking',
                'realTimeTrackingEnabled',
                features.realTimeTrackingEnabled,
              ),
              _toggle(
                service,
                'Premium Membership',
                'membershipEnabled',
                features.membershipEnabled,
              ),
              _toggle(
                service,
                'Promotions',
                'promotionsEnabled',
                features.promotionsEnabled,
              ),
              _toggle(
                service,
                'Loyalty Program',
                'loyaltyEnabled',
                features.loyaltyEnabled,
              ),
              _toggle(
                service,
                'Loyalty Redemption',
                'loyaltyRedemptionEnabled',
                features.loyaltyRedemptionEnabled,
              ),
              _toggle(
                service,
                'Priority Scheduling',
                'prioritySchedulingEnabled',
                features.prioritySchedulingEnabled,
              ),
              const Divider(height: 32),
              const Text(
                'Laundry Pricing',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              StreamBuilder<List<ServicePricing>>(
                stream: service.watchPricing(),
                builder: (context, snapshot) {
                  final values = snapshot.data ?? const <ServicePricing>[];
                  if (values.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'No pricing records yet. Create service_pricing records in Firestore.',
                      ),
                    );
                  }
                  return Column(
                    children: values
                        .map(
                          (pricing) => ListTile(
                            title: Text(pricing.name),
                            subtitle: Text(
                              '₱${pricing.pricePerLoad.toStringAsFixed(2)} / '
                              '${pricing.includedWeightKg.toStringAsFixed(0)}kg '
                              '• ${pricing.status}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () =>
                                  _editPrice(context, service, pricing),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const Divider(height: 32),
              const Text(
                'Membership',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              StreamBuilder<List<MembershipPlan>>(
                stream: service.watchPlans(),
                builder: (context, snapshot) {
                  final plans = snapshot.data ?? const <MembershipPlan>[];
                  return Column(
                    children: plans
                        .map(
                          (plan) => ListTile(
                            title: Text(plan.name),
                            subtitle: Text(
                              '₱${plan.price.toStringAsFixed(0)}/month '
                              '• ${plan.discountPercent.toStringAsFixed(0)}% discount '
                              '• ${plan.loyaltyMultiplier.toStringAsFixed(1)}x points '
                              '• ${plan.status}',
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const Divider(height: 32),
              const Text(
                'Promotions & Rewards',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              StreamBuilder<List<Promotion>>(
                stream: service.watchPromotions(),
                builder: (context, snapshot) {
                  final promotions = snapshot.data ?? const <Promotion>[];
                  return Column(
                    children: promotions
                        .map(
                          (promotion) => SwitchListTile(
                            title: Text(promotion.code),
                            subtitle: Text(
                              '${promotion.type} • '
                              '${promotion.value.toStringAsFixed(0)} • '
                              '${promotion.status}',
                            ),
                            value: promotion.status == 'Active',
                            onChanged: (value) => service.savePromotion(
                              promotion.id,
                              {'status': value ? 'Active' : 'Inactive'},
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _toggle(
    BusinessConfigurationService service,
    String title,
    String field,
    bool value,
  ) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      onChanged: (enabled) => service.setFeature(field, enabled),
    );
  }

  Future<void> _editPrice(
    BuildContext context,
    BusinessConfigurationService service,
    ServicePricing pricing,
  ) async {
    final controller = TextEditingController(
      text: pricing.pricePerLoad.toStringAsFixed(2),
    );
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Edit ${pricing.name}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Price per 8kg load'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final value = double.tryParse(controller.text);
              if (value != null && value >= 0) {
                await service.savePricing(
                  ServicePricing(
                    id: pricing.id,
                    name: pricing.name,
                    pricePerLoad: value,
                    includedWeightKg: pricing.includedWeightKg,
                    status: pricing.status,
                  ),
                );
                if (dialog.mounted) {
                  Navigator.pop(dialog);
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
