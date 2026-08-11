// coverage:ignore-file

import 'package:fs_service_lib/data/mappers/document_mapper.dart';
import 'package:fs_service_lib/data/repo/firestore_repo_impl.dart';
import 'package:fs_service_lib/data/utils/firestore_path_utils.dart';
import 'package:fs_service_lib/domain/mappers/value_mapper.dart';
import 'package:fs_service_lib/utils/caching_http_client.dart';
import 'package:fs_service_lib/utils/firestore_api_provider.dart';
import 'package:fs_service_lib/utils/path_utils.dart';

export 'package:fs_service_lib/domain/repo/firestore_filter.dart';
export 'package:fs_service_lib/domain/repo/firestore_repo.dart';
export 'package:fs_service_lib/domain/repo/firestore_write.dart';
export 'package:fs_service_lib/utils/caching_http_client.dart';
export 'package:fs_service_lib/utils/firestore_api_provider.dart';

/// Example of initialization for your project:
/// ```dart
/// final fsServiceLib = FsServiceLib();
///
/// Future<void> initFsServiceLib() async {
///   fsServiceLib.init(
///     projectId: 'projectId',
///     databaseId: 'databaseId',
///   );
/// }
/// ```
///
/// Add document example:
/// ```dart
/// Future<void> addDocumentExample() async {
///   /// see [test/jsons] directory of the package
///   await fsServiceLib.db.addDocument(
///     collectionPath: '/temp',
///     json: {
///       'textField': 'value1',
///       'doubleField': 1234.5432,
///       'integerField': 8765,
///       'geopoint': 'location://34.3456/-23.432',
///       'timestamp': 'datetime://2023-10-21T11:26:40.152Z',
///       r'$name': 'documentId1',
///     },
///   );
/// }
/// ```
class FsServiceLib {
  late FirestoreRepoImpl db;

  Future<void> init({
    required String projectId,
    String databaseId = '(default)',
    String? metaPrefix,
    String? locationPrefix,
    String? referencePrefix,
    String? bytesPrefix,
    String? datetimePrefix,
    bool enableCache = true,
    Duration cacheTtl = const Duration(minutes: 5),
    CacheInvalidationStrategy invalidationStrategy =
        CacheInvalidationStrategy.smart,
    void Function(String url, CacheStats stats)? onCacheHit,
  }) async {
    const pathUtils = PathUtils();

    db = FirestoreRepoImpl(
      documentMapper: DocumentMapper(
        valueUtils: ValueMapper()
          ..init(
            locationPrefix: locationPrefix,
            referencePrefix: referencePrefix,
            bytesPrefix: bytesPrefix,
            datetimePrefix: datetimePrefix,
          ),
        pathUtils: pathUtils,
      )..init(
          metaPrefix: metaPrefix,
        ),
      firestoreApiProvider: FirestoreApiProviderImpl(
        enableCache: enableCache,
        cacheTtl: cacheTtl,
        invalidationStrategy: invalidationStrategy,
        onCacheHit: onCacheHit,
      ),
      firestorePathUtils: FirestorePathUtils()
        ..init(
          projectId: projectId,
          databaseId: databaseId,
        ),
      pathUtils: pathUtils,
    );

    await db.init(
      projectId: projectId,
      databaseId: databaseId,
    );
  }

  Future<void> dispose() async => db.dispose();
}
