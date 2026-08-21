import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';
import '../models/role_model.dart';
import '../models/address_model.dart';
import '../engines/auth_routing.dart';
import '../services/notification_service.dart';
import '../services/pickup_reconciliation_service.dart';

class AuthProvider extends ChangeNotifier {
  // Lazy so widget tests can subclass without touching Firebase.
  late final firebase_auth.FirebaseAuth _auth;
  late final FirebaseFirestore _firestore;
  late final GoogleSignIn _googleSignIn;

  UserModel? _user;
  bool _isLoading = false;
  bool _initialized = false;
  String? _error;
  bool _profileWriteInProgress = false;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _user?.role == UserRole.admin;
  bool get isStaff => _user?.role == UserRole.staff;
  bool get isCustomer => _user?.role == UserRole.customer;

  /// Whether the initial Firebase auth-state snapshot has been resolved.
  /// The Splash screen waits on this so there is never a blank/decision jump.
  bool get isInitialized => _initialized;

  Stream<firebase_auth.User?> get authState => _auth.authStateChanges();

  AuthProvider() {
    subscribeToAuthChanges();
  }

  /// Subscribes to Firebase auth-state changes. Overridable in tests.
  @protected
  void subscribeToAuthChanges() {
    _auth = firebase_auth.FirebaseAuth.instance;
    _firestore = FirebaseFirestore.instance;
    _googleSignIn = GoogleSignIn();
    _startAuthStateListener();
  }

  /// Applies web-only persistence, then listens to [authStateChanges].
  ///
  /// On Flutter Web, previous browser sessions must not auto-restore after a
  /// fresh launch or refresh. [Persistence.NONE] keeps the user signed in only
  /// while this tab stays open. Native platforms keep the default persistence.
  Future<void> _startAuthStateListener() async {
    try {
      await _configureWebAuthPersistence();
    } catch (e) {
      debugPrint('Web auth persistence skipped: $e');
    }
    _auth.authStateChanges().listen((firebaseUser) {
      _handleAuthState(firebaseUser);
    });
  }

  Future<void> _configureWebAuthPersistence() async {
    if (!kIsWeb) return;

    await _auth.setPersistence(firebase_auth.Persistence.NONE);

    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('Google sign-out skipped: $e');
    }

    if (_auth.currentUser != null) {
      await _auth.signOut();
    }
  }

  /// Marks the initial auth snapshot as resolved. Overridable/callable in tests.
  @protected
  void completeInitialization() {
    _initialized = true;
    notifyListeners();
  }

  Future<void> _handleAuthState(firebase_auth.User? firebaseUser) async {
    try {
      if (firebaseUser != null) {
        await _loadUser(firebaseUser.uid);
        try {
          await NotificationService().requestPermission();
          await NotificationService().registerToken(firebaseUser.uid);
        } catch (e) {
          debugPrint('Notification setup skipped: $e');
        }
        // The Admin Web app is the primary pickup-task reconciler: while an
        // admin session is open it periodically creates/repairs pickup queue
        // entries and assigns delivery staff. No-ops for other roles and stops
        // automatically on logout. Delivery Staff run their own pass as a
        // secondary safety net.
        if (_user?.role == UserRole.admin) {
          PickupReconciliationService.instance.start();
        } else {
          PickupReconciliationService.instance.stop();
        }
      } else {
        PickupReconciliationService.instance.stop();
        _user = null;
      }
    } finally {
      completeInitialization();
    }
  }

  /// Route a fully-loaded user to the correct start screen.
  ///
  /// Customers with an incomplete delivery location are sent to Location
  /// Setup first, then the dashboard.
  String startRouteFor(UserModel user) => AuthRouting.routeFor(user);

  /// Reloads `users/{uid}` for the currently signed-in Firebase user.
  Future<void> reloadCurrentUser() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _loadUser(uid);
  }

  Future<void> _loadUser(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        _user = UserModel.fromMap(doc.data()!, doc.id);
      } else {
        debugPrint('User document not found for uid: $uid');
        // A concurrent register/Google profile write owns the first document.
        // Do not wipe a profile that is in-flight or was just loaded.
        if (!_profileWriteInProgress && _user?.id != uid) {
          _user = null;
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading user data: $e');
      _error = 'Failed to load user data. Please try again.';
      if (!_profileWriteInProgress) {
        _user = null;
      }
      notifyListeners();
    }
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _loadUser(result.user!.uid);
      if (_user == null) {
        await _loadUser(result.user!.uid);
      }
      return true;
    } on firebase_auth.FirebaseAuthException catch (e) {
      _error = _getAuthErrorMessage(e);
      return false;
    } catch (e) {
      _error = 'An error occurred. Please try again.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Google Sign-In with profile de-duplication.
  ///
  /// The Firebase account uid is the single identity key: if the Google
  /// account already maps to an existing `users/{uid}` document, that profile
  /// is loaded and never duplicated. If it is a brand-new Google customer, a
  /// minimal customer profile is created WITHOUT any location data — they are
  /// then sent to Location Setup by [startRouteFor].
  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    _error = null;
    _profileWriteInProgress = true;
    notifyListeners();

    var googleAccountChosen = false;
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _error = null;
        return false;
      }
      googleAccountChosen = true;

      final authentication = await googleUser.authentication;
      final credential = firebase_auth.GoogleAuthProvider.credential(
        idToken: authentication.idToken,
        accessToken: authentication.accessToken,
      );

      final result = await _auth.signInWithCredential(credential);
      final uid = result.user!.uid;

      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) {
        final userModel = UserModel(
          id: uid,
          name: googleUser.displayName?.trim() ?? '',
          email: googleUser.email.trim(),
          phone: '',
          role: UserRole.customer,
          address: null,
          photoUrl: googleUser.photoUrl,
          createdAt: DateTime.now(),
        );
        // New customer profile — location fields are intentionally NOT
        // written here; they are set only when the customer completes
        // Location Setup.
        await _firestore.collection('users').doc(uid).set(userModel.toMap());
      }

      await _loadUser(uid);
      if (_user == null) {
        await _loadUser(uid);
      }
      return true;
    } catch (e) {
      if (_isGoogleCancel(e)) {
        _error = null;
        return false;
      }
      if (googleAccountChosen) {
        await _cleanupGoogleSession();
      }
      if (e is firebase_auth.FirebaseAuthException) {
        _error = _getAuthErrorMessage(e);
      } else {
        _error = 'Google sign-in failed. Please try again.';
      }
      return false;
    } finally {
      _profileWriteInProgress = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
    required String phone,
    double latitude = 0,
    double longitude = 0,
    String address = '',
    AddressModel? addressModel,
  }) async {
    _isLoading = true;
    _error = null;
    _profileWriteInProgress = true;
    notifyListeners();

    try {
      final trimmedEmail = email.trim();
      final firebaseUser = await _resolveRegisterAuthUser(
        email: trimmedEmail,
        password: password,
      );

      // Create user profile. Location data is included ONLY when the
      // customer explicitly completed Location Setup during registration.
      final userModel = UserModel(
        id: firebaseUser.uid,
        name: name,
        email: trimmedEmail,
        phone: phone,
        role: UserRole.customer,
        address: addressModel,
        createdAt: DateTime.now(),
      );

      final docRef = _firestore.collection('users').doc(firebaseUser.uid);
      final existingDoc = await docRef.get();
      if (!existingDoc.exists) {
        await docRef.set({
          ...userModel.toMap(),
          if (addressModel != null) ...{
            // Flat legacy fields kept for backward compatibility.
            'latitude': addressModel.latitude,
            'longitude': addressModel.longitude,
          },
        });
      }

      await _loadUser(firebaseUser.uid);
      if (_user == null) {
        await _loadUser(firebaseUser.uid);
      }
      return true;
    } on firebase_auth.FirebaseAuthException catch (e) {
      _error = _getAuthErrorMessage(e);
      return false;
    } catch (e) {
      _error = 'Registration failed. Please try again.';
      return false;
    } finally {
      _profileWriteInProgress = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Saves the customer's completed/edited delivery location.
  ///
  /// This is the ONLY path that writes location fields to `users/{uid}` for an
  /// existing account. It is triggered exclusively by the customer explicitly
  /// completing or editing Location Setup.
  Future<bool> updateCustomerLocation(AddressModel address) async {
    final user = _user;
    if (user == null) return false;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updated = user.copyWith(address: address);
      await _firestore.collection('users').doc(user.id).set({
        ...updated.toMap(),
        // Flat legacy fields kept for backward compatibility.
        'latitude': address.latitude,
        'longitude': address.longitude,
      }, SetOptions(merge: true));

      _user = updated;
      return true;
    } catch (e) {
      _error = 'Failed to save your location. Please try again.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _cleanupGoogleSession();
    await _auth.signOut();
    _user = null;
    notifyListeners();
  }

  Future<bool> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return true;
    } catch (e) {
      _error = 'Failed to send reset email.';
      notifyListeners();
      return false;
    }
  }

  Future<String?> getUserRole(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      return doc.data()?['role'] ?? 'customer';
    }
    return 'customer';
  }

  /// Creates the Auth user, or reuses the already-signed-in account when a
  /// previous attempt created Auth but failed before the Firestore profile.
  Future<firebase_auth.User> _resolveRegisterAuthUser({
    required String email,
    required String password,
  }) async {
    final current = _auth.currentUser;
    if (current != null &&
        current.email != null &&
        current.email!.toLowerCase() == email.toLowerCase()) {
      return current;
    }

    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user!;
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        final signedIn = _auth.currentUser;
        if (signedIn != null &&
            signedIn.email != null &&
            signedIn.email!.toLowerCase() == email.toLowerCase()) {
          return signedIn;
        }
      }
      rethrow;
    }
  }

  Future<void> _cleanupGoogleSession() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('Google sign-out skipped: $e');
    }
  }

  bool _isGoogleCancel(Object error) {
    String? code;
    if (error is firebase_auth.FirebaseAuthException) {
      code = error.code;
    } else if (error is PlatformException) {
      code = error.code;
    }
    if (code != null && _isGoogleCancelCode(code)) return true;

    final text = error.toString().toLowerCase();
    return text.contains('popup-closed-by-user') ||
        text.contains('sign_in_canceled') ||
        text.contains('sign_in_cancelled') ||
        (text.contains('canceled') && text.contains('google'));
  }

  bool _isGoogleCancelCode(String code) {
    switch (code) {
      case 'canceled':
      case 'cancelled':
      case 'popup-closed-by-user':
      case 'sign_in_canceled':
      case 'sign_in_cancelled':
      case '12501':
        return true;
      default:
        return false;
    }
  }

  String _getAuthErrorMessage(firebase_auth.FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'Email is already registered.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'invalid-credential':
        return 'Invalid credentials.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email. Try signing in with your password instead.';
      case 'popup-closed-by-user':
      case 'canceled':
        return 'Google sign-in was cancelled.';
      case 'sign_in_failed':
      case 'sign_in_canceled':
        return 'Google sign-in failed. Please try again.';
      default:
        return e.message ?? 'Login failed.';
    }
  }
}