// ignore_for_file: avoid_redundant_argument_values

import 'dart:io';

import 'package:fs_service_lib/fs_service_lib.dart';
import 'package:hive_ce/hive.dart';

void main() async {
  final fsServiceLib = FsServiceLib();

  // 1. Initialize Hive for persistent disk HTTP caching
  // Note: In Cloud Run / Cloud Functions without a mounted volume, local disk
  // uses RAM (tmpfs). Keep maxSizeBytes within your container's RAM budget.
  final cacheDir = Directory.systemTemp.path;
  Hive.init(cacheDir);
  final hiveBox = await Hive.openBox<dynamic>('fs_service_http_cache');

  // 2. Initialize the library with CachingHttpClientHive
  stdout.writeln('--- Initializing FsServiceLib with Hive HTTP Cache ---');
  await fsServiceLib.init(
    projectId: 'your-firebase-project-id',
    databaseId: '(default)',
    cachingClient: CachingHttpClientHive(
      box: hiveBox,
      ttl: const Duration(minutes: 30),
      maxSizeBytes: 50 * 1024 * 1024, // 50 MB max disk cache
      maxEntrySizeBytes: 2 * 1024 * 1024, // 2 MB max single entry size
      invalidationStrategy: CacheInvalidationStrategy.smart,
      onCacheHit:
          (url, stats) => stdout.writeln(
            'CACHE HIT: $url (Ratio: ${stats.hitRatioPercentage})',
          ),
    ),
  );

  const testCollectionPath = '/example_collection';
  const testDocId = 'doc-1000';
  const testDocPath = '$testCollectionPath/$testDocId';

  // 2. Add a new document with various typed fields
  stdout.writeln('\n--- 1. addDocument ---');
  await fsServiceLib.db.addDocument(
    collectionPath: testCollectionPath,
    json: {
      r'$name': testDocId, // Document ID
      'textField': 'Sample text',
      'doubleField': 1234.56,
      'integerField': 42,
      'booleanField': true,
      'geopoint': 'location://37.7749/-122.4194', // Location mapping
      'timestamp': 'datetime://2026-08-05T18:00:00.000Z', // Timestamp mapping
      'docReference':
          'reference://projects/your-firebase-project-id/databases/(default)/documents/users/user-1',
      'blobData': 'bytes://AAECAwQFBg==', // Binary data mapping
    },
  );
  stdout.writeln('Document created at $testDocPath');

  // 3. Get a single document by path
  stdout.writeln('\n--- 2. getDocument ---');
  final docJson = await fsServiceLib.db.getDocument(documentPath: testDocPath);
  stdout.writeln('Fetched document: $docJson');

  // 4. Update fields in an existing document
  stdout.writeln('\n--- 3. updateDocument ---');
  await fsServiceLib.db.updateDocument(
    documentPath: testDocPath,
    json: {'textField': 'Updated text value', 'doubleField': 9876.54},
  );
  final updatedDocJson = await fsServiceLib.db.getDocument(
    documentPath: testDocPath,
  );
  stdout.writeln('Updated document: $updatedDocJson');

  // 5. Fetch a collection of documents with pagination and sorting
  stdout.writeln('\n--- 4. getCollection ---');
  final collectionData = await fsServiceLib.db.getCollection(
    collectionPath: testCollectionPath,
    pageSize: 10,
    orderBy: 'integerField desc',
  );
  stdout.writeln('Fetched collection data: $collectionData');

  // 6. Fetch documents across a collection group
  stdout.writeln('\n--- 5. getCollectionGroup ---');
  final groupDocs = await fsServiceLib.db.getCollectionGroup(
    collectionId: 'posts',
    limit: 10,
    orderBy: 'timestamp',
    descending: true,
  );
  stdout.writeln('Fetched ${groupDocs.length} collection group documents.');

  // 7. Add a nested subcollection to a document
  stdout.writeln('\n--- 6. addCollection ---');
  await fsServiceLib.db.addCollection(
    documentPath: testDocPath,
    json: {
      r'$name': 'subcollection_1',
      r'$documents': [
        {r'$name': 'sub_doc_1', 'subField': 'Subdocument value 1'},
        {r'$name': 'sub_doc_2', 'subField': 'Subdocument value 2'},
      ],
    },
  );
  stdout.writeln('Added subcollection to $testDocPath');

  // 8. Query collection with filters
  stdout.writeln('\n--- 7. queryCollection ---');
  final filteredDocs = await fsServiceLib.db.queryCollection(
    collectionPath: testCollectionPath,
    filters: [
      const FirestoreFilter(
        field: 'integerField',
        op: FirestoreOperator.isGreaterThan,
        value: 10,
      ),
    ],
    limit: 5,
    orderBy: 'integerField',
    descending: false,
  );
  stdout.writeln('Queried ${filteredDocs.length} matching documents.');

  // 9. Batch write operations
  stdout.writeln('\n--- 8. batchWrite ---');
  await fsServiceLib.db.batchWrite(
    writes: [
      const UpdateWrite(
        documentPath: testDocPath,
        json: {'textField': 'Batch updated text'},
      ),
      const DeleteWrite(documentPath: '$testCollectionPath/doc-old'),
    ],
  );
  stdout.writeln('Batch write operation completed.');

  // 10. Get multiple documents by IDs
  stdout.writeln('\n--- 9. getDocumentsByIds ---');
  final docsByIds = await fsServiceLib.db.getDocumentsByIds(
    collectionPath: testCollectionPath,
    documentIds: [testDocId, 'doc-2000'],
  );
  stdout.writeln('Fetched ${docsByIds.length} documents by IDs.');

  // 11. Check if document exists
  stdout.writeln('\n--- 10. documentExists ---');
  final exists = await fsServiceLib.db.documentExists(
    documentPath: testDocPath,
  );
  stdout.writeln('Document exists: $exists');

  // 12. Count documents in collection
  stdout.writeln('\n--- 11. countCollection ---');
  final totalCount = await fsServiceLib.db.countCollection(
    collectionPath: testCollectionPath,
  );
  stdout.writeln('Total documents in collection: $totalCount');

  // 13. Get subcollection IDs under document
  stdout.writeln('\n--- 12. getCollectionIds ---');
  final subcollectionIds = await fsServiceLib.db.getCollectionIds(
    documentPath: testDocPath,
  );
  stdout.writeln('Subcollections of $testDocPath: $subcollectionIds');

  // 14. Delete a single document
  stdout.writeln('\n--- 13. deleteDocument ---');
  await fsServiceLib.db.deleteDocument(documentPath: testDocPath);
  stdout.writeln('Deleted document at $testDocPath');

  // 15. Delete an entire collection
  stdout.writeln('\n--- 14. deleteCollection ---');
  await fsServiceLib.db.deleteCollection(collectionPath: testCollectionPath);
  stdout.writeln('Deleted collection at $testCollectionPath');

  // 16. Dispose of resources
  stdout.writeln('\n--- Disposing FsServiceLib ---');
  await fsServiceLib.dispose();
  await hiveBox.close();
  stdout.writeln('FsServiceLib disposed successfully.');
}
