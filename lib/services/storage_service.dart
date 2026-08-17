import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Uuid _uuid = const Uuid();

  Future<String> uploadFile({
    required File file,
    required String path,
    String? fileName,
  }) async {
    final finalName =
        fileName ?? '${_uuid.v4()}_${DateTime.now().millisecondsSinceEpoch}';
    final ref = _storage.ref().child('$path/$finalName');
    final uploadTask = ref.putFile(file);
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  Future<String> uploadImage({
    required File imageFile,
    required String folder,
  }) async {
    final fileName = '${_uuid.v4()}.jpg';
    final ref = _storage.ref().child('$folder/$fileName');

    // Compress/optimize image options
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: {'uploaded': DateTime.now().toIso8601String()},
    );

    if (kIsWeb) {
      final bytes = await imageFile.readAsBytes();
      final uploadTask = ref.putData(bytes, metadata);
      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    }

    final uploadTask = ref.putFile(imageFile, metadata);
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  Future<String> uploadReceiptImage({
    required File receiptFile,
    required String userId,
    required String orderId,
  }) async {
    return await uploadImage(
      imageFile: receiptFile,
      folder: 'receipts/$userId/$orderId',
    );
  }

  Future<String> uploadProfileImage({
    required File imageFile,
    required String userId,
  }) async {
    return await uploadImage(imageFile: imageFile, folder: 'profiles/$userId');
  }

  Future<void> deleteFile(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
    } catch (e) {
      // File might not exist
    }
  }

  Future<String> getDownloadUrl(String path) async {
    final ref = _storage.ref().child(path);
    return await ref.getDownloadURL();
  }

  Future<List<String>> listFiles(String folder) async {
    final ref = _storage.ref().child(folder);
    final result = await ref.listAll();
    final urls = <String>[];
    for (final item in result.items) {
      urls.add(await item.getDownloadURL());
    }
    return urls;
  }
}
