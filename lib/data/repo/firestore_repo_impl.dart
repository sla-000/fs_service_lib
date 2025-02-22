// coverage:ignore-file

import 'dart:async';

import 'package:fs_service_lib/data/mappers/document_mapper.dart';
import 'package:fs_service_lib/data/utils/firestore_path_utils.dart';
import 'package:fs_service_lib/domain/repo/firestore_repo.dart';
import 'package:fs_service_lib/utils/firestore_api_provider.dart';
import 'package:fs_service_lib/utils/path_utils.dart';
import 'package:googleapis/firestore/v1.dart';

/// Implementation of the [FirestoreRepo] interface.
class FirestoreRepoImpl implements FirestoreRepo {
  FirestoreRepoImpl({
    required this.documentMapper,
    required this.firestoreApiProvider,
    required this.firestorePathUtils,
    required this.pathUtils,
  });

  final DocumentMapper documentMapper;
  final FirestoreApiProvider firestoreApiProvider;
  final FirestorePathUtils firestorePathUtils;
  final PathUtils pathUtils;

  ProjectsDatabasesDocumentsResource get firestore =>
      firestoreApiProvider.api.projects.databases.documents;

  /// Initialize FirestoreRepoImpl with the given [projectId] and [databaseId].
  ///
  /// [projectId] is the ID of the Google Cloud Project.
  /// [databaseId] is the ID of the Firestore Database. By default, it's (default).
  ///
  /// It also initializes [documentMapper], [firestoreApiProvider] and [firestorePathUtils].
  @override
  Future<void> init({
    required String projectId,
    String databaseId = '(default)',
  }) async {
    documentMapper.init();

    await firestoreApiProvider.init();

    firestorePathUtils.init(
      projectId: projectId,
      databaseId: databaseId,
    );
  }

  /// Dispose the FirestoreRepoImpl.
  ///
  /// It disposes the [firestoreApiProvider].
  @override
  Future<void> dispose() async => firestoreApiProvider.dispose();

  /// Get the collection at [collectionPath] as [JsonObject].
  ///
  /// If [changeRootName] is provided, it will be used as the root name for the change.
  @override
  Future<JsonObject> getCollection({
    required String collectionPath,
    String? changeRootName,
  }) async {
    final collectionParent = pathUtils.parent(collectionPath);
    final collectionName = pathUtils.name(collectionPath);

    final collectionDocuments = await _getCollectionDocuments(
      documentPath:
          firestorePathUtils.absolutePathFromRelative(collectionParent),
      collectionName: collectionName,
    );

    final colJson = JsonObject();
    final docsArrayJson = <JsonObject>[];

    // 1 go through all the documents in the initial collection
    for (final collectionDocument in collectionDocuments) {
      // 2 parse the document
      final docJson = await _getDocumentJson(
        document: collectionDocument,
        json: JsonObject(),
      );

      docsArrayJson.add(docJson);
    }

    colJson[documentMapper.metaName] = collectionName;
    colJson[documentMapper.metaDocuments] = docsArrayJson;

    return colJson;
  }

  /// Get all the documents in a collection.
  ///
  /// [documentPath] is the path to the parent document.
  /// [collectionName] is the name of the collection.
  ///
  /// Returns a list of [Document] instances representing the documents in the
  /// collection.
  Future<List<Document>> _getCollectionDocuments({
    required String documentPath,
    required String collectionName,
  }) async {
    final documents = <Document>[];
    String? pageToken;

    while (true) {
      final listDocumentsResponse = await firestore.listDocuments(
        documentPath,
        collectionName,
        pageToken: pageToken,
        showMissing: true,
      );

      final listDocuments = listDocumentsResponse.documents;
      final nextPageToken = listDocumentsResponse.nextPageToken;

      if (listDocuments != null) {
        documents.addAll(listDocuments);
      }

      if (listDocuments == null || nextPageToken == null) {
        break;
      }

      pageToken = listDocumentsResponse.nextPageToken;
    }

    return documents;
  }

  /// Get a document at [documentPath] as [JsonObject].
  ///
  /// Returns a [JsonObject] representing the document. It also contains
  /// sub-collections if any.
  @override
  Future<JsonObject> getDocument({required String documentPath}) async {
    final docPath = firestorePathUtils.absolutePathFromRelative(documentPath);

    var document = Document(name: docPath);
    try {
      document = await firestore.get(docPath);
    } on DetailedApiRequestError catch (error, _) {
      // Even if document is empty (returns 404) it still can have collections!
      if (error.status != 404) {
        rethrow;
      }
    }

    return _getDocumentJson(document: document, json: JsonObject());
  }

  /// Get a document and all it's sub-collections as [JsonObject].
  ///
  /// [document] is the document to parse.
  /// [json] is the [JsonObject] to fill with the document and sub-collections data.
  ///
  Future<JsonObject> _getDocumentJson({
    required Document document,
    required JsonObject json,
  }) async {
    final documentJson = documentMapper.documentToJson(document);
    json.addAll(documentJson);

    final documentName = document.name!;
    final collectionNames =
        await _getDocumentCollectionNames(absolutePath: documentName);

    if (collectionNames.isEmpty) {
      return json;
    }

    final allCollectionsArray = await _iterateAllCollectionsOfDocument(
      collectionNames,
      documentName,
    );

    if (allCollectionsArray.isEmpty) {
      return json;
    }

    json[documentMapper.metaCollections] = allCollectionsArray;

    return json;
  }

  /// Iterate all the collections of a document.
  ///
  /// [collectionNames] is the list of collection names.
  /// [documentName] is the name of the document.
  ///
  /// Returns a list of [JsonObject] representing the collections.
  Future<List<JsonObject>> _iterateAllCollectionsOfDocument(
    List<String> collectionNames,
    String documentName,
  ) async {
    final allCollectionsArray = <JsonObject>[];

    for (final collectionName in collectionNames) {
      final collectionDocuments = await _getCollectionDocuments(
        documentPath: documentName,
        collectionName: collectionName,
      );

      if (collectionDocuments.isEmpty) {
        continue;
      }

      final allDocumentsInCollection =
          await _iterateAllDocumentsOfCollection(collectionDocuments);

      if (allDocumentsInCollection.isEmpty) {
        continue;
      }

      final oneCollectionJson = JsonObject();
      oneCollectionJson[documentMapper.metaName] = collectionName;
      oneCollectionJson[documentMapper.metaDocuments] =
          allDocumentsInCollection;

      allCollectionsArray.add(oneCollectionJson);
    }

    return allCollectionsArray;
  }

  /// Iterate all the documents of a collection.
  ///
  /// [collectionDocuments] is the list of [Document] instances representing the
  /// documents in the collection.
  ///
  /// Returns a list of [JsonObject] representing the documents in the collection.
  Future<List<JsonObject>> _iterateAllDocumentsOfCollection(
    List<Document> collectionDocuments,
  ) async {
    final allDocumentsInCollection = <JsonObject>[];

    for (final collectionDocument in collectionDocuments) {
      final documentJson = await _getDocumentJson(
        document: collectionDocument,
        json: JsonObject(),
      );

      allDocumentsInCollection.add(documentJson);
    }
    return allDocumentsInCollection;
  }

  /// Get all the collection names of a document.
  ///
  /// [absolutePath] is the absolute path to the document.
  /// [path] is the relative path to the document.
  ///
  /// Only one of [absolutePath] or [path] must be provided.
  /// Returns a list of collection names.
  Future<List<String>> _getDocumentCollectionNames({
    String absolutePath = '',
    String path = '',
  }) async {
    assert(
      absolutePath.isNotEmpty != path.isNotEmpty,
      'Only one parameter of absPath or relPath must be used',
    );

    var docPath = absolutePath;

    if (docPath.isEmpty) {
      docPath = firestorePathUtils.absolutePathFromRelative(path);
    }

    final response =
        await firestore.listCollectionIds(ListCollectionIdsRequest(), docPath);

    return response.collectionIds ?? [];
  }

  /// Add a document to a collection.
  ///
  /// [collectionPath] is the path to the collection.
  /// [json] is the [JsonObject] representing the document data.
  /// [changeRootName] is the root name for the change.
  ///
  @override
  Future<void> addDocument({
    required String collectionPath,
    required JsonObject json,
    String? changeRootName,
  }) async {
    await documentMapper.jsonToDocument(
      path: collectionPath,
      json: json,
      onParsed: _onDocumentParsed,
      changeRootName: changeRootName,
    );
  }

  /// Callback function called when a document is parsed by [documentMapper].
  ///
  /// [documentPath] is the path to the document.
  /// [documentId] is the ID of the document.
  /// [document] is the [Document] instance representing the document data.
  ///
  /// It creates the document in Firestore.
  Future<void> _onDocumentParsed(
    String documentPath,
    String? documentId,
    Document document,
  ) async {
    final documentParent = pathUtils.parent(documentPath);
    final absoluteParent =
        firestorePathUtils.absolutePathFromRelative(documentParent);
    final documentName = pathUtils.name(documentPath);

    await firestore.createDocument(
      document,
      absoluteParent,
      documentName,
      documentId: documentId,
    );
  }

  /// Update a document.
  ///
  /// [documentPath] is the path to the document.
  /// [json] is the [JsonObject] representing the document data.
  ///
  @override
  FutureOr<void> updateDocument({
    required String documentPath,
    required JsonObject json,
  }) async {
    final absolutePath =
        firestorePathUtils.absolutePathFromRelative(documentPath);

    final fields = Map.fromEntries(
      json.entries.map(
        (e) => MapEntry(
          e.key,
          documentMapper.valueUtils.fromJsonObject(e.value),
        ),
      ),
    );

    await firestore.patch(
      Document(fields: fields),
      absolutePath,
    );
  }

  /// Add a collection.
  ///
  /// [documentPath] is the path to the document.
  /// [json] is the [JsonObject] representing the collection data.
  /// [changeRootName] is the root name for the change.
  ///
  @override
  Future<void> addCollection({
    required String documentPath,
    required JsonObject json,
    String? changeRootName,
  }) async {
    await documentMapper.jsonToCollection(
      path: documentPath,
      json: json,
      onParsed: _onDocumentParsed,
      changeRootName: changeRootName,
    );
  }

  /// Delete a document.
  ///
  /// [absolutePath] is the absolute path to the document.
  /// [documentPath] is the relative path to the document.
  ///
  /// Only one of [absolutePath] or [documentPath] must be provided.
  @override
  Future<void> deleteDocument({
    String absolutePath = '',
    String documentPath = '',
  }) async {
    assert(
      absolutePath.isNotEmpty != documentPath.isNotEmpty,
      'Only one parameter of absolutePath or documentPath must be used',
    );

    var docPath = absolutePath;

    if (docPath.isEmpty) {
      docPath = firestorePathUtils.absolutePathFromRelative(documentPath);
    }

    final collectionNames =
        await _getDocumentCollectionNames(absolutePath: docPath);

    for (final collectionName in collectionNames) {
      final collectionPath = pathUtils.join(docPath, collectionName);

      await deleteCollection(absolutePath: collectionPath);
    }

    await firestore.delete(docPath);
  }

  /// Delete a collection.
  ///
  /// [absolutePath] is the absolute path to the collection.
  /// [collectionPath] is the relative path to the collection.
  ///
  /// Only one of [absolutePath] or [collectionPath] must be provided.
  @override
  Future<void> deleteCollection({
    String absolutePath = '',
    String collectionPath = '',
  }) async {
    assert(
      absolutePath.isNotEmpty != collectionPath.isNotEmpty,
      'Only one parameter of absolutePath or documentPath must be used',
    );

    var colPath = absolutePath;

    if (colPath.isEmpty) {
      colPath = firestorePathUtils.absolutePathFromRelative(collectionPath);
    }

    final collectionParent = pathUtils.parent(colPath);
    final collectionName = pathUtils.name(colPath);

    final documents = await _getCollectionDocuments(
      documentPath: collectionParent,
      collectionName: collectionName,
    );

    for (final document in documents) {
      if (document.name != null) {
        await deleteDocument(absolutePath: document.name!);
      }
    }
  }
}
