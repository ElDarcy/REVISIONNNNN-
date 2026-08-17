import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/engagement_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/business_configuration_service.dart';
import '../../../services/engagement_customer_service.dart';

class LoyaltyScreen extends StatelessWidget {
  const LoyaltyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Sign in required.')));
    }

    final api = EngagementCustomerService();
    return Scaffold(
      appBar: AppBar(title: const Text('My Loyalty Points')),
      body: StreamBuilder<BusinessFeatures>(
        stream: BusinessConfigurationService().watchFeatures(),
        builder: (context, features) {
          if (!(features.data?.loyaltyEnabled ?? true)) {
            return const Center(
              child: Text('Loyalty is currently unavailable.'),
            );
          }

          return StreamBuilder(
            stream: api.balance(user.id),
            builder: (context, balance) {
              final points =
                  (balance.data?.data()?['points'] as num?)?.toInt() ?? 0;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '$points pts',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  StreamBuilder(
                    stream: api.rewards(),
                    builder: (context, rewards) => Column(
                      children: (rewards.data?.docs ?? []).map((d) {
                        final reward = d.data();
                        return Card(
                          child: ListTile(
                            title: Text(reward['name'] ?? 'Reward'),
                            subtitle: Text(
                              '${reward['requiredPoints'] ?? 0} points',
                            ),
                            trailing: FilledButton(
                              onPressed:
                                  !(features.data?.loyaltyRedemptionEnabled ??
                                      true)
                                  ? null
                                  : () => api.requestReward(
                                      customerId: user.id,
                                      rewardId: d.id,
                                    ),
                              child: const Text('Redeem'),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
