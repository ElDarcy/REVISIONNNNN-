import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'dart:async';

class ErrorHandler {
  static String getFriendlyErrorMessage(dynamic error) {
    if (error is FirebaseAuthException) {
      return _handleAuthError(error);
    } else if (error is FirebaseException) {
      return _handleFirestoreError(error);
    } else if (error is FirebaseException) {
      return _handleStorageError(error);
    } else if (error is PlatformException) {
      return _handlePlatformError(error);
    } else if (error is SocketException) {
      return 'No internet connection. Please check your network.';
    } else if (error is TimeoutException) {
      return 'Connection timed out. Please try again.';
    } else {
      return error.toString();
    }
  }

  static String _handleAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'Email/password login is not enabled.';
      case 'invalid-credential':
        return 'Invalid login credentials.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return 'Authentication error: ${e.message}';
    }
  }

  static String _handleFirestoreError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'You do not have permission to perform this action.';
      case 'not-found':
        return 'The requested data was not found.';
      case 'already-exists':
        return 'This record already exists.';
      case 'resource-exhausted':
        return 'Server is busy. Please try again later.';
      case 'unavailable':
        return 'Service is temporarily unavailable.';
      default:
        return 'Database error: ${e.message}';
    }
  }

  static String _handleStorageError(FirebaseException e) {
    switch (e.code) {
      case 'object-not-found':
        return 'File not found.';
      case 'bucket-not-found':
        return 'Storage bucket not configured.';
      case 'project-not-found':
        return 'Firebase project not found.';
      case 'quota-exceeded':
        return 'Storage quota exceeded.';
      case 'unauthenticated':
        return 'Please login to upload files.';
      case 'unauthorized':
        return 'You do not have permission to upload files.';
      case 'retry-limit-exceeded':
        return 'Upload failed. Please try again.';
      case 'invalid-checksum':
        return 'File corrupted. Please try again.';
      case 'canceled':
        return 'Upload was cancelled.';
      default:
        return 'Storage error: ${e.message}';
    }
  }

  static String _handlePlatformError(PlatformException e) {
    switch (e.code) {
      case 'PERMISSION_DENIED':
        return 'Location permission is required.';
      case 'PERMISSION_DENIED_NEVER_ASK':
        return 'Location permission is permanently denied. Please enable it in settings.';
      case 'SERVICE_STATUS_ERROR':
        return 'Location services are disabled.';
      default:
        return 'Error: ${e.message}';
    }
  }

  static void showSnackBar(
    BuildContext context,
    String message, {
    bool isError = true,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }
}
