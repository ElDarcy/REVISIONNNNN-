import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/engagement_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/business_configuration_service.dart';
import '../../../services/engagement_customer_service.dart';

class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});
  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  final EngagementCustomerService _api = EngagementCustomerService();
  final BusinessConfigurationService _config = BusinessConfigurationService();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Sign in required.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Loyalty Points')),
      body: StreamBuilder<BusinessFeatures>(
        stream: _config.watchFeatures(),
        builder: (context, features) {
          if (!(features.data?.loyaltyEnabled ?? true)) {
            return const Center(child: Text('Loyalty is currently unavailable.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Points Balance ──
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _api.balance(user.id),
                builder: (context, balanceSnap) {
                  final points =
                      (balanceSnap.data?.data()?['points'] as num?)?.toInt() ?? 0;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const Icon(Icons.star, size: 48, color: Color(0xFFFFC107)),
                          const SizedBox(height: 8),
                          Text(
                            '$points pts',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text('Your Loyalty Balance', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // ── Available Rewards ──
              const Text(
                'Available Rewards',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _api.balance(user.id),
                builder: (context, balanceSnap) {
                  final myPoints =
                      (balanceSnap.data?.data()?['points'] as num?)?.toInt() ?? 0;

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _api.rewards(),
                    builder: (context, rewardsSnap) {
                      final rewards = rewardsSnap.data?.docs ?? [];
                      if (rewards.isEmpty) {
                        return const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No rewards available yet.'),
                          ),
                        );
                      }
                      return Column(
                        children: rewards.map((d) {
                          final r = d.data();
                          final required = (r['requiredPoints'] ?? 0) as int;
                          final hasEnough = myPoints >= required;
                          final redeemEnabled =
                              (features.data?.loyaltyRedemptionEnabled ?? true) &&
                              hasEnough;

                          return Card(
                            child: ListTile(
                              leading: Icon(
                                _rewardIcon(r['type'] ?? ''),
                                color: hasEnough ? Colors.green : Colors.grey,
                              ),
                              title: Text(r['name'] ?? 'Reward'),
                              subtitle: Text('$required points required'),
                              trailing: FilledButton(
                                onPressed: redeemEnabled
                                    ? () => _redeem(context, user.id, d.id, r['name'] ?? 'Reward', required, myPoints)
                                    : null,
                                child: hasEnough
                                    ? const Text('Redeem')
                                    : const Text('Locked', style: TextStyle(color: Colors.white)),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  );
                },
              ),

              // ── Points History ──
              const SizedBox(height: 24),
              const Text(
                'Recent Activity',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('loyalty_transactions')
                    .where('customerId', isEqualTo: user.id)
                    .orderBy('createdAt', descending: true)
                    .limit(20)
                    .snapshots(),
                builder: (context, txSnap) {
                  final txs = txSnap.data?.docs ?? [];
                  if (txs.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No transactions yet. Complete transactions to earn points!'),
                      ),
                    );
                  }
                  return Card(
                    child: Column(
                      children: txs.map((d) {
                        final tx = d.data();
                        final pts = (tx['points'] as num?)?.toInt() ?? 0;
                        final ts = tx['createdAt'] as Timestamp?;
                        return ListTile(
                          leading: Icon(
                            pts >= 0 ? Icons.add_circle : Icons.remove_circle,
                            color: pts >= 0 ? Colors.green : Colors.red,
                          ),
                          title: Text(
                            pts >= 0 ? '+$pts points' : '$pts points',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: pts >= 0 ? Colors.green : Colors.red,
                            ),
                          ),
                          subtitle: Text(
                            tx['type'] ?? (tx['orderId'] != null ? 'Transaction ${tx['orderId'].toString().substring(0, 8)}' : 'Transaction'),
                          ),
                          trailing: ts != null
                              ? Text(
                                  '${ts.toDate().month}/${ts.toDate().day}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                )
                              : null,
                        );
                      }).toList(),
                    ),
                  );
                },
              ),

              // ── Redemption History ──
              const SizedBox(height: 16),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('loyalty_redemptions')
                    .where('customerId', isEqualTo: user.id)
                    .orderBy('createdAt', descending: true)
                    .limit(10)
                    .snapshots(),
                builder: (context, redSnap) {
                  final redemptions = redSnap.data?.docs ?? [];
                  if (redemptions.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Past Redemptions',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: Column(
                          children: redemptions.map((d) {
                            final r = d.data();
                            final pts = (r['pointsDeducted'] as num?)?.toInt() ?? 0;
                            return ListTile(
                              leading: const Icon(Icons.redeem, color: Colors.purple),
                              title: Text(r['rewardName'] ?? 'Reward'),
                              subtitle: Text('-$pts points'),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
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

  Future<void> _redeem(
    BuildContext context,
    String customerId,
    String rewardId,
    String rewardName,
    int requiredPoints,
    int myPoints,
  ) async {
    if (myPoints < requiredPoints) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Insufficient points. You need $requiredPoints but have $myPoints.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Redemption'),
        content: Text('Redeem "$rewardName" for $requiredPoints points?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Redeem')),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    try {
      final requestId = await _api.requestReward(
        customerId: customerId,
        rewardId: rewardId,
      );

      // Listen briefly for the Cloud Function to process the redemption
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Redemption submitted! Processing...'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Redemption failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
