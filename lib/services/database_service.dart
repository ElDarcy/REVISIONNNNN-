import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Generic CRUD
  Future<DocumentReference> addDocument(
    String collection,
    Map<String, dynamic> data,
  ) {
    return _firestore.collection(collection).add(data);
  }

  Future<void> setDocument(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) {
    return _firestore.collection(collection).doc(docId).set(data);
  }

  Future<DocumentSnapshot> getDocument(String collection, String docId) {
    return _firestore.collection(collection).doc(docId).get();
  }

  Future<QuerySnapshot> getDocuments(String collection) {
    return _firestore.collection(collection).get();
  }

  Future<QuerySnapshot> getDocumentsWhere(
    String collection,
    String field,
    dynamic value,
  ) {
    return _firestore
        .collection(collection)
        .where(field, isEqualTo: value)
        .get();
  }

  Future<QuerySnapshot> getDocumentsWithOrder(
    String collection,
    String orderBy, {
    bool descending = false,
  }) {
    return _firestore
        .collection(collection)
        .orderBy(orderBy, descending: descending)
        .get();
  }

  Future<QuerySnapshot> getDocumentsWhereAndOrder(
    String collection,
    String field,
    dynamic value,
    String orderBy, {
    bool descending = false,
  }) {
    return _firestore
        .collection(collection)
        .where(field, isEqualTo: value)
        .orderBy(orderBy, descending: descending)
        .get();
  }

  Future<void> updateDocument(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) {
    return _firestore.collection(collection).doc(docId).update(data);
  }

  Future<void> deleteDocument(String collection, String docId) {
    return _firestore.collection(collection).doc(docId).delete();
  }

  // Real-time streams
  Stream<DocumentSnapshot> streamDocument(String collection, String docId) {
    return _firestore.collection(collection).doc(docId).snapshots();
  }

  Stream<QuerySnapshot> streamCollection(String collection) {
    return _firestore.collection(collection).snapshots();
  }

  Stream<QuerySnapshot> streamWhere(
    String collection,
    String field,
    dynamic value,
  ) {
    return _firestore
        .collection(collection)
        .where(field, isEqualTo: value)
        .snapshots();
  }

  // Batch operations
  Future<void> batchWrite(List<Map<String, dynamic>> operations) async {
    final batch = _firestore.batch();
    for (final op in operations) {
      final ref = _firestore.collection(op['collection']).doc(op['docId']);
      if (op['type'] == 'set') {
        batch.set(ref, op['data'] as Map<String, dynamic>);
      } else if (op['type'] == 'update') {
        batch.update(ref, op['data'] as Map<String, dynamic>);
      } else if (op['type'] == 'delete') {
        batch.delete(ref);
      }
    }
    await batch.commit();
  }

  // Increment a field value
  Future<void> incrementField(
    String collection,
    String docId,
    String field,
    num value,
  ) {
    return _firestore.collection(collection).doc(docId).update({
      field: FieldValue.increment(value),
    });
  }

  // Generate unique ID
  String generateId(String collection) {
    return _firestore.collection(collection).doc().id;
  }
}
