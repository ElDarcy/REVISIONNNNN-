import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseService {
  static FirebaseService? _instance;
  late FirebaseApp _app;
  late FirebaseAuth _auth;
  late FirebaseFirestore _firestore;
  late FirebaseStorage _storage;

  FirebaseService._internal();

  static FirebaseService get instance {
    _instance ??= FirebaseService._internal();
    return _instance!;
  }

  FirebaseAuth get auth => _auth;
  FirebaseFirestore get firestore => _firestore;
  FirebaseStorage get storage => _storage;

  Future<void> initialize() async {
    _app = await Firebase.initializeApp();
    _auth = FirebaseAuth.instance;
    _firestore = FirebaseFirestore.instance;
    _storage = FirebaseStorage.instance;

    // Enable offline persistence
    _firestore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> signOut() async {
    await _auth.signOut();
  }

  CollectionReference get usersCollection => _firestore.collection('users');

  CollectionReference get ordersCollection => _firestore.collection('orders');

  CollectionReference get servicesCollection =>
      _firestore.collection('services');

  CollectionReference get paymentsCollection =>
      _firestore.collection('payments');

  CollectionReference get transactionsCollection =>
      _firestore.collection('transactions');

  CollectionReference get deliveriesCollection =>
      _firestore.collection('deliveries');

  CollectionReference get machinesCollection =>
      _firestore.collection('machines');

  CollectionReference get notificationsCollection =>
      _firestore.collection('notifications');

  CollectionReference get promosCollection => _firestore.collection('promos');

  CollectionReference get receiptsCollection =>
      _firestore.collection('receipts');

  CollectionReference get soapsCollection => _firestore.collection('soaps');
}
