import 'package:fs_service_lib/data/mappers/document_mapper.dart';
import 'package:fs_service_lib/data/repo/firestore_repo_impl.dart';
import 'package:fs_service_lib/data/utils/firestore_path_utils.dart';
import 'package:fs_service_lib/domain/mappers/value_mapper.dart';
import 'package:fs_service_lib/domain/repo/firestore_filter.dart';
import 'package:fs_service_lib/domain/repo/firestore_write.dart';
import 'package:fs_service_lib/utils/firestore_api_provider.dart';
import 'package:fs_service_lib/utils/path_utils.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDocumentMapper extends Mock implements DocumentMapper {}

class _MockFirestoreApiProvider extends Mock implements FirestoreApiProvider {}

class _MockFirestorePathUtils extends Mock implements FirestorePathUtils {}

class _MockFirestoreApi extends Mock implements FirestoreApi {}

class _MockProjectsResource extends Mock implements ProjectsResource {}

class _MockProjectsDatabasesResource extends Mock
    implements ProjectsDatabasesResource {}

class _MockProjectsDatabasesDocumentsResource extends Mock
    implements ProjectsDatabasesDocumentsResource {}

class _MockPathUtils extends Mock implements PathUtils {}

final _mockDocumentMapper = _MockDocumentMapper();
final _mockFirestoreApiProvider = _MockFirestoreApiProvider();
final _mockFirestorePathUtils = _MockFirestorePathUtils();
final _mockFirestoreApi = _MockFirestoreApi();
final _mockProjectsResource = _MockProjectsResource();
final _mockProjectsDatabasesResource = _MockProjectsDatabasesResource();
final _mockProjectsDatabasesDocumentsResource =
    _MockProjectsDatabasesDocumentsResource();
final _mockPathUtils = _MockPathUtils();

const _projectId = '_projectId';
const _databaseId = '_databaseId';

const _joinedPath = '_joinedPath';
const _name = '_name';
const _parent = '_parent';

final _document1 = Document(name: '_document1');
final _document2 = Document(name: '_document2');

void main() {
  final easyFirestore = FirestoreRepoImpl(
    documentMapper: _mockDocumentMapper,
    firestoreApiProvider: _mockFirestoreApiProvider,
    firestorePathUtils: _mockFirestorePathUtils,
    pathUtils: _mockPathUtils,
  );

  setUpAll(() {
    registerFallbackValue(ListCollectionIdsRequest());
    registerFallbackValue(RunQueryRequest());
    registerFallbackValue(BatchGetDocumentsRequest());
    registerFallbackValue(CommitRequest());
    registerFallbackValue(RunAggregationQueryRequest());
  });

  setUp(() async {
    reset(_mockDocumentMapper);
    reset(_mockFirestoreApiProvider);
    reset(_mockFirestorePathUtils);
    reset(_mockFirestoreApi);
    reset(_mockProjectsResource);
    reset(_mockProjectsDatabasesResource);
    reset(_mockProjectsDatabasesDocumentsResource);
    reset(_mockPathUtils);

    when(_mockFirestoreApiProvider.init).thenAnswer((_) async {});
    when(() => _mockFirestoreApiProvider.api).thenReturn(_mockFirestoreApi);
    when(() => _mockFirestoreApi.projects).thenReturn(_mockProjectsResource);
    when(
      () => _mockProjectsResource.databases,
    ).thenReturn(_mockProjectsDatabasesResource);
    when(
      () => _mockProjectsDatabasesResource.documents,
    ).thenReturn(_mockProjectsDatabasesDocumentsResource);

    when(
      () => _mockProjectsDatabasesDocumentsResource.listCollectionIds(
        any(),
        any(),
      ),
    ).thenAnswer(
      (_) async => ListCollectionIdsResponse(collectionIds: ['sub1', 'sub2']),
    );

    when(() => _mockPathUtils.join(any(), any())).thenReturn(_joinedPath);
    when(() => _mockPathUtils.parent(any())).thenReturn(_parent);
    when(() => _mockPathUtils.name(any())).thenReturn(_name);
    when(
      () => _mockFirestorePathUtils.rootPath,
    ).thenReturn('projects/p/databases/d/documents');
    when(
      () => _mockFirestorePathUtils.absolutePathFromRelative(any()),
    ).thenAnswer(
      (invocation) =>
          'projects/p/databases/d/documents/${invocation.positionalArguments.first}',
    );

    when(
      () => _mockProjectsDatabasesDocumentsResource.listDocuments(
        any(),
        any(),
        pageToken: any(named: 'pageToken'),
        showMissing: true,
      ),
    ).thenAnswer(
      (_) async => ListDocumentsResponse(documents: [_document1, _document2]),
    );

    await easyFirestore.init(projectId: _projectId, databaseId: _databaseId);
  });

  group('EasyFirestore tests - ', () {
    group('queryCollection tests - ', () {
      test(
        'executes runQuery with filters and returns mapped results',
        () async {
          when(() => _mockDocumentMapper.valueUtils).thenReturn(ValueMapper());
          when(
            () =>
                _mockProjectsDatabasesDocumentsResource.runQuery(any(), any()),
          ).thenAnswer(
            (_) async => [RunQueryResponseElement(document: _document1)],
          );
          when(
            () => _mockDocumentMapper.documentToJson(_document1),
          ).thenReturn({'key': 'val1'});

          final results = await easyFirestore.queryCollection(
            collectionPath: 'users',
            filters: [
              const FirestoreFilter(
                field: 'age',
                op: FirestoreOperator.isGreaterThan,
                value: 18,
              ),
            ],
          );

          expect(results, [
            {'key': 'val1'},
          ]);
          verify(
            () =>
                _mockProjectsDatabasesDocumentsResource.runQuery(any(), any()),
          ).called(1);
        },
      );
    });

    group('getDocumentsByIds tests - ', () {
      test('returns empty list for empty IDs', () async {
        final results = await easyFirestore.getDocumentsByIds(
          collectionPath: 'users',
          documentIds: [],
        );
        expect(results, isEmpty);
      });

      test('executes batchGet and maps found documents', () async {
        when(
          () => _mockProjectsDatabasesDocumentsResource.batchGet(any(), any()),
        ).thenAnswer(
          (_) async => [BatchGetDocumentsResponseElement(found: _document1)],
        );
        when(
          () => _mockDocumentMapper.documentToJson(_document1),
        ).thenReturn({'key': 'val1'});

        final results = await easyFirestore.getDocumentsByIds(
          collectionPath: 'users',
          documentIds: ['id1'],
        );

        expect(results, [
          {'key': 'val1'},
        ]);
      });
    });

    group('documentExists tests - ', () {
      test('returns true when document is found', () async {
        when(
          () => _mockProjectsDatabasesDocumentsResource.get(
            any(),
            mask_fieldPaths: any(named: 'mask_fieldPaths'),
          ),
        ).thenAnswer((_) async => _document1);

        final exists = await easyFirestore.documentExists(
          documentPath: 'users/id1',
        );
        expect(exists, isTrue);
      });

      test('returns false when document returns 404 error', () async {
        when(
          () => _mockProjectsDatabasesDocumentsResource.get(
            any(),
            mask_fieldPaths: any(named: 'mask_fieldPaths'),
          ),
        ).thenThrow(DetailedApiRequestError(404, 'Not Found'));

        final exists = await easyFirestore.documentExists(
          documentPath: 'users/id1',
        );
        expect(exists, isFalse);
      });
    });

    group('batchWrite tests - ', () {
      test('returns immediately for empty writes', () async {
        await easyFirestore.batchWrite(writes: []);
        verifyNever(
          () => _mockProjectsDatabasesDocumentsResource.commit(any(), any()),
        );
      });

      test('executes commit with UpdateWrite and DeleteWrite', () async {
        when(() => _mockDocumentMapper.valueUtils).thenReturn(ValueMapper());
        when(
          () => _mockProjectsDatabasesDocumentsResource.commit(any(), any()),
        ).thenAnswer((_) async => CommitResponse());

        await easyFirestore.batchWrite(
          writes: [
            const UpdateWrite(
              documentPath: 'users/id1',
              json: {'name': 'Alice'},
            ),
            const DeleteWrite(documentPath: 'users/id2'),
          ],
        );

        verify(
          () => _mockProjectsDatabasesDocumentsResource.commit(any(), any()),
        ).called(1);
      });
    });

    group('countCollection tests - ', () {
      test('executes runAggregationQuery and returns total count', () async {
        when(
          () => _mockProjectsDatabasesDocumentsResource.runAggregationQuery(
            any(),
            any(),
          ),
        ).thenAnswer(
          (_) async => [
            RunAggregationQueryResponseElement(
              result: AggregationResult(
                aggregateFields: {'total_count': Value(integerValue: '42')},
              ),
            ),
          ],
        );

        final count = await easyFirestore.countCollection(
          collectionPath: 'users',
        );
        expect(count, equals(42));
      });
    });

    group('getCollectionIds tests - ', () {
      test('returns list of collection IDs under document', () async {
        final ids = await easyFirestore.getCollectionIds(
          documentPath: 'users/id1',
        );
        expect(ids, equals(['sub1', 'sub2']));
      });
    });
  });
}
