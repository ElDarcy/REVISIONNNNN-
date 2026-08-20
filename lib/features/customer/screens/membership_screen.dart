import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../models/engagement_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/business_configuration_service.dart';
import '../../../services/engagement_customer_service.dart';
import '../../../services/membership_service.dart';

class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  final BusinessConfigurationService _config = BusinessConfigurationService();
  final EngagementCustomerService _engageApi = EngagementCustomerService();
  final MembershipService _membershipService = MembershipService();

  StreamSubscription<BusinessFeatures>? _featuresSub;
  StreamSubscription<List<MembershipPlan>>? _plansSub;
  StreamSubscription<Map<String, dynamic>?>? _subSub;

  bool _featuresEnabled = true;
  List<MembershipPlan> _plans = [];
  Map<String, dynamic>? _subscription;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _featuresSub = _config.watchFeatures().listen((f) {
      if (!mounted) return;
      setState(() => _featuresEnabled = f.membershipEnabled ?? true);
    }, onError: (e) { if (mounted) setState(() => _error = 'Failed to load features'); });

    _plansSub = _config.watchPlans().listen((plans) {
      if (!mounted) return;
      setState(() => _plans = plans.where((p) => p.status == 'Active').toList());
    }, onError: (e) { if (mounted) setState(() => _error = 'Failed to load plans'); });

    final user = context.read<AuthProvider>().user;
    if (user != null) {
      _subSub = _engageApi.subscription(user.id).listen((sub) {
        if (!mounted) return;
        setState(() { _subscription = sub; _error = null; });
      }, onError: (e) { if (mounted) setState(() => _error = 'Failed to load subscription'); });
    }
  }

  @override
  void dispose() {
    _featuresSub?.cancel();
    _plansSub?.cancel();
    _subSub?.cancel();
    super.dispose();
  }

  Future<void> _subscribe(MembershipPlan plan) async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    setState(() => _loading = true);
    try {
      final id = await _membershipService.createPendingSubscription(
        customerId: user.id,
        planId: plan.id,
      );
      if (mounted) {
        await _uploadProof(id, user.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _uploadProof(String subscriptionId, String customerId) async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 60);
    if (image == null) { setState(() => _loading = false); return; }
    setState(() => _loading = true);
    try {
      final base64Img = base64Encode(await File(image.path).readAsBytes());
      await _membershipService.uploadPaymentProof(
        subscriptionId: subscriptionId,
        customerId: customerId,
        imageBase64: base64Img,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment proof submitted for verification.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Sign in to manage membership.')));
    }

    if (!_featuresEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Premium Membership')),
        body: const Center(child: Text('Membership is currently unavailable.')),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Premium Membership')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => setState(() => _error = null), child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_plans.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Premium Membership')),
        body: const Center(child: Text('No membership plan is available.')),
      );
    }

    final plan = _plans.first;
    final status = _subscription?['status'] ?? 'Not Enrolled';
    final expiry = _date(_subscription?['expiryDate']);
    final days = expiry?.difference(DateTime.now()).inDays;

    return Scaffold(
      appBar: AppBar(title: const Text('Premium Membership')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        status == 'Active' ? Icons.workspace_premium : Icons.card_membership,
                        color: status == 'Active' ? const Color(0xFFFFB300) : Colors.grey,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          plan.name,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                      _StatusChip(status: status),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '₱${plan.price.toStringAsFixed(2)}/month',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  // Benefits
                  _benefitTile(Icons.local_laundry_service, '${plan.discountPercent.toStringAsFixed(0)}% laundry discount'),
                  if (plan.prioritySchedulingEnabled)
                    _benefitTile(Icons.priority_high, 'Priority scheduling'),
                  _benefitTile(Icons.stars, '${plan.loyaltyMultiplier.toStringAsFixed(0)}x loyalty points'),
                  const Divider(height: 24),
                  // Expiry info
                  if (expiry != null) ...[
                    Text(
                      _expiryText(status, days),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _expiryColor(status, days),
                      ),
                    ),
                    if (days != null && days >= 0 && days <= 7 && status == 'Active')
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Your membership is expiring soon. Renew now to keep your benefits!',
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Expires: ${_formatDate(expiry)}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ] else if (status == 'Not Enrolled') ...[
                    const Text(
                      'Subscribe to enjoy premium benefits!',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Action buttons
                  if (status == 'Not Enrolled' || status == 'Expired' || status == 'Rejected')
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : () => _subscribe(plan),
                        child: _loading
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(status == 'Expired' || status == 'Rejected' ? 'Resubscribe' : 'Subscribe'),
                      ),
                    ),
                  if (status == 'Active' && days != null && days <= 7)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : () => _subscribe(plan),
                        child: _loading
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Renew Now'),
                      ),
                    ),
                  if (status == 'Pending') ...[
                    const Text(
                      'Your subscription is awaiting admin verification.',
                      style: TextStyle(color: Colors.orange),
                    ),
                    const SizedBox(height: 8),
                    if (_subscription?['paymentProofId'] == null)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _loading ? null : () async {
                            final subId = _subscription?['id'];
                            if (subId != null) await _uploadProof(subId, user.id);
                          },
                          child: _loading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Upload Payment Proof'),
                        ),
                      )
                    else
                      const Text(
                        'Payment proof uploaded. Awaiting verification.',
                        style: TextStyle(color: Colors.blue, fontSize: 13),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _date(dynamic v) {
    if (v is DateTime) return v;
    if (v != null && v is Timestamp) return v.toDate();
    return null;
  }

  String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';

  String _expiryText(String status, int? days) {
    if (status == 'Not Enrolled') return 'Not Enrolled';
    if (days == null) return status;
    if (days < 0) return 'Expired ${-days} day(s) ago';
    if (days == 0) return 'Expires today';
    if (days <= 7) return 'Expires in $days day(s)';
    return 'Active — $days day(s) remaining';
  }

  Color _expiryColor(String status, int? days) {
    if (status == 'Expired' || (days != null && days < 0)) return Colors.red;
    if (days != null && days <= 7) return Colors.orange;
    if (status == 'Active') return Colors.green;
    if (status == 'Pending') return Colors.blue;
    return Colors.grey;
  }

  Widget _benefitTile(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF1565C0)),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'Active' => ('Active', Colors.green),
      'Pending' => ('Pending', Colors.blue),
      'Expired' => ('Expired', Colors.red),
      'Rejected' => ('Rejected', Colors.red),
      _ => ('Not Enrolled', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
