import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/membership_service.dart';

class MembershipVerificationScreen extends StatelessWidget { const MembershipVerificationScreen({super.key});
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Membership Payments')), body: StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream: FirebaseFirestore.instance.collection('subscriptions').where('paymentStatus', isEqualTo: 'Pending Verification').snapshots(), builder: (context,snap) { if(!snap.hasData) return const Center(child:CircularProgressIndicator()); if(snap.data!.docs.isEmpty) return const Center(child:Text('No pending membership payments.')); return ListView(children:snap.data!.docs.map((doc) => _SubscriptionTile(id:doc.id,data:doc.data())).toList()); }));
}
class _SubscriptionTile extends StatelessWidget { const _SubscriptionTile({required this.id,required this.data}); final String id; final Map<String,dynamic> data;
  @override Widget build(BuildContext context) => Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Customer: ${data['customerId'] ?? ''}'),Text('Plan: ${data['planId'] ?? ''}'),const Text('Status: Pending Verification'),Text('Submitted: ${data['updatedAt'] ?? data['createdAt'] ?? ''}'),if(data['paymentProofId'] != null) FutureBuilder<DocumentSnapshot<Map<String,dynamic>>>(future:FirebaseFirestore.instance.collection('transaction_proofs').doc(data['paymentProofId']).get(),builder:(_,proof){final b64=proof.data?.data()?['image_base64'] as String?; return b64 == null ? const SizedBox() : Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Image.memory(base64Decode(b64),height:140));}),Row(children:[Expanded(child:FilledButton(onPressed:()=>_verify(context,true),child:const Text('Approve'))),const SizedBox(width:8),Expanded(child:OutlinedButton(onPressed:()=>_verify(context,false),child:const Text('Reject')))])])));
  Future<void> _verify(BuildContext context,bool approved) async { final admin=context.read<AuthProvider>().user; if(admin==null)return; await MembershipService().verifyPayment(subscriptionId:id,adminId:admin.id,approved:approved); if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(approved?'Membership activated.':'Membership rejected.'))); }
}
