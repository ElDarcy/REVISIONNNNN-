import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../models/engagement_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/business_configuration_service.dart';
import '../../../services/engagement_customer_service.dart';
import '../../../services/membership_service.dart';

class MembershipScreen extends StatelessWidget {
  const MembershipScreen({super.key});
  @override Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user; if (user == null) return const Scaffold(body: Center(child: Text('Sign in to manage membership.')));
    final config = BusinessConfigurationService(); final customer = EngagementCustomerService();
    return Scaffold(appBar: AppBar(title: const Text('Premium Membership')), body: StreamBuilder<BusinessFeatures>(stream: config.watchFeatures(), builder: (_, feature) {
      if (!(feature.data?.membershipEnabled ?? true)) return const Center(child: Text('Membership is currently unavailable.'));
      return StreamBuilder<List<MembershipPlan>>(stream: config.watchPlans(), builder: (_, plans) { final plan = (plans.data ?? const <MembershipPlan>[]).where((p) => p.status == 'Active').cast<MembershipPlan?>().firstOrNull; if (plan == null) return const Center(child: Text('No membership plan is available.'));
        return StreamBuilder<Map<String, dynamic>?>(stream: customer.subscription(user.id), builder: (context, sub) => _MembershipCard(plan: plan, subscription: sub.data, customerId: user.id));
      });
    }));
  }
}
class _MembershipCard extends StatelessWidget { const _MembershipCard({required this.plan, required this.subscription, required this.customerId}); final MembershipPlan plan; final Map<String,dynamic>? subscription; final String customerId;
  @override Widget build(BuildContext context) { final status = subscription?['status'] ?? 'Not Enrolled'; final expiry = _date(subscription?['expiryDate']); final days = expiry == null ? null : expiry.difference(DateTime.now()).inDays; return ListView(padding: const EdgeInsets.all(16), children:[Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text(plan.name, style: const TextStyle(fontSize:22,fontWeight:FontWeight.bold)), Text('₱${plan.price.toStringAsFixed(2)}/month'), const SizedBox(height:12), Text('${plan.discountPercent}% laundry discount'), if(plan.prioritySchedulingEnabled) const Text('Priority scheduling'), Text('${plan.loyaltyMultiplier}x loyalty points'), const Divider(), Text('Status: ${days != null && days >= 0 && days <= 7 && status == 'Active' ? 'Expiring Soon' : status}', style: const TextStyle(fontWeight:FontWeight.bold)), if(expiry != null) Text('Expires: ${expiry.toLocal()} (${days! < 0 ? 'Expired' : '$days days remaining'})'), if(subscription?['startDate'] != null) Text('Started: ${_date(subscription!['startDate'])}'), const SizedBox(height:16), if(status == 'Not Enrolled' || status == 'Expired' || status == 'Rejected') FilledButton(onPressed: () async { final id = await MembershipService().createPendingSubscription(customerId: customerId, planId: plan.id); if(context.mounted) await _proof(context,id); }, child: const Text('Subscribe')), if(status == 'Pending') const Text('Subscription created. Upload your payment proof.'), if(status == 'Pending') OutlinedButton(onPressed: () => _proof(context, subscription!['id']), child: const Text('Upload payment proof'))])))]); }
  Future<void> _proof(BuildContext context,String id) async { final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 60); if(image == null) return; final base64 = base64Encode(await File(image.path).readAsBytes()); await MembershipService().uploadPaymentProof(subscriptionId:id, customerId:customerId, imageBase64:base64); if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Proof submitted for admin verification.'))); }
  DateTime? _date(dynamic v) => v is DateTime ? v : v?.toDate?.call();
}
extension _FirstOrNull<T> on Iterable<T> { T? get firstOrNull => isEmpty ? null : first; }
