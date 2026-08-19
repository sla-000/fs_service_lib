import 'dart:async';

import 'package:fs_service_lib/domain/repo/firestore_filter.dart';
import 'package:fs_service_lib/domain/repo/firestore_order.dart';
import 'package:fs_service_lib/domain/repo/firestore_write.dart';

typedef JsonObject = Map<String, dynamic>;

/// Interface for a Firestore repository.
abstract class FirestoreRepo {
  FutureOr<void> init({
    required String projectId,
    String databaseId = '(default)',
  });

  FutureOr<void> dispose();

  FutureOr<JsonObject> getCollection({
    required String collectionPath,
    String? changeRootName,
    int? pageSize,
    String? orderBy,
    bool includeSubcollections = true,
  });

  FutureOr<List<JsonObject>> queryCollection({
    required String collectionPath,
    List<FirestoreFilter>? filters,
    List<FirestoreOrder>? orders,
    List<String>? selectFields,
    int? limit,
    int? offset,
    String? orderBy,
    bool descending = true,
  });

  FutureOr<List<JsonObject>> getCollectionGroup({
    required String collectionId,
    List<FirestoreFilter>? filters,
    List<FirestoreOrder>? orders,
    List<String>? selectFields,
    int? limit,
    int? offset,
    String? orderBy,
    bool descending = true,
  });

  FutureOr<JsonObject> getDocument({
    required String documentPath,
    bool includeSubcollections = true,
  });

  FutureOr<List<JsonObject>> getDocumentsByIds({
    required String collectionPath,
    required List<String> documentIds,
  });

  FutureOr<bool> documentExists({required String documentPath});

  FutureOr<void> addDocument({
    required String collectionPath,
    required JsonObject json,
    String? changeRootName,
  });

  FutureOr<void> updateDocument({
    required String documentPath,
    required JsonObject json,
  });

  FutureOr<void> batchWrite({required List<FirestoreWrite> writes});

  FutureOr<void> addCollection({
    required String documentPath,
    required JsonObject json,
    String? changeRootName,
  });

  FutureOr<void> deleteDocument({
    String absolutePath = '',
    String documentPath = '',
  });

  FutureOr<void> deleteCollection({required String collectionPath});

  FutureOr<int> countCollection({
    required String collectionPath,
    List<FirestoreFilter>? filters,
  });

  FutureOr<int> countCollectionGroup({
    required String collectionId,
    List<FirestoreFilter>? filters,
  });

  FutureOr<List<String>> getCollectionIds({required String documentPath});
}
