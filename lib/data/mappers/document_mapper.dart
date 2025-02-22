import 'dart:async';

import 'package:fs_service_lib/data/utils/document_ext.dart';
import 'package:fs_service_lib/domain/mappers/value_mapper.dart';
import 'package:fs_service_lib/domain/repo/firestore_repo.dart';
import 'package:fs_service_lib/utils/path_utils.dart';
import 'package:googleapis/firestore/v1.dart';

/// Callback that is called on each parsed Firestore document.
typedef OnParsedCallback = Future<void> Function(
  String relativePath,
  String? documentId,
  Document document,
);

/// Mapper for Firestore documents and collections to JSON and vice versa.
class DocumentMapper {
  DocumentMapper({
    required this.valueUtils,
    required this.pathUtils,
  });

  final ValueMapper valueUtils;
  final PathUtils pathUtils;

  /// Prefix for special fields in Firestore documents.
  static const kDefaultMetaPrefix = r'$';

  late String _metaPrefix;

  void init({
    String? metaPrefix,
  }) {
    _metaPrefix = metaPrefix ?? kDefaultMetaPrefix;
  }

  /// Document name
  String get metaName => '${_metaPrefix}name';

  /// Document inner collections
  String get metaCollections => '${_metaPrefix}collections';

  /// Collection documents
  String get metaDocuments => '${_metaPrefix}documents';

  /// Creation datetime
  String get metaCreateTime => '${_metaPrefix}createTime';

  /// Last update datetime
  String get metaUpdateTime => '${_metaPrefix}updateTime';

  /// Converts a Firestore [Document] to a JSON object.
  ///
  /// This function extracts the fields from the Firestore document, converts
  /// them to JSON objects using the [valueUtils], and adds metadata fields.
  JsonObject documentToJson(Document document) {
    final docJson = <String, dynamic>{};

    final entries = document.fields?.entries ?? [];

    for (final entry in entries) {
      docJson[entry.key] = valueUtils.toJsonObject(entry.value);
    }

    docJson[metaName] = document.id(pathUtils);

    if (document.createTime != null) {
      final createTime =
          DateTime.tryParse(document.createTime!)?.toUtc().toIso8601String();
      docJson[metaCreateTime] = createTime;
    }

    if (document.updateTime != null) {
      final updateTime =
          DateTime.tryParse(document.updateTime!)?.toUtc().toIso8601String();
      docJson[metaUpdateTime] = updateTime;
    }

    return docJson;
  }

  /// Converts a collection of Firestore [Document]s to a JSON object.
  ///
  /// This function takes a list of documents and converts each one to JSON
  /// using [documentToJson]. It then wraps the list of document JSON objects
  /// into a collection JSON object that includes the collection path and
  /// the list of documents.
  JsonObject collectionToJson({
    required String path,
    List<Document> documents = const [],
  }) {
    final docsJson = JsonObject();

    docsJson[metaName] = path;
    docsJson[metaDocuments] =
        documents.map(documentToJson).toList(growable: false);

    return docsJson;
  }

  /// Converts a JSON object to a Firestore document and its inner collections.
  ///
  /// This function recursively processes a JSON object representing a Firestore
  /// document and its inner collections. It converts the JSON object to a
  /// Firestore [Document] and then calls the [onParsed] callback with the
  /// document's path, ID, and the document itself. It then processes any inner
  /// collections recursively.
  ///
  /// - [path]: The path to the document or collection.
  /// - [json]: The JSON object to convert.
  /// - [onParsed]: The callback to call for each parsed document.
  Future<void> jsonToDocument({
    required String path,
    required JsonObject json,
    required OnParsedCallback onParsed,
    String? changeRootName,
  }) async {
    final (id, document) = _jsonToDocument(json);

    final name = changeRootName ?? id;

    await onParsed(path, name, document);

    final rawDocumentCollections = json[metaCollections] ?? [];
    if (rawDocumentCollections is! List<dynamic>) {
      throw FormatException(
          'Wrong `$metaCollections` value=`$rawDocumentCollections` '
          'in json=`$json`');
    }

    final documentCollections = rawDocumentCollections.cast<JsonObject>();

    final documentPath = pathUtils.join(path, name);

    for (final documentCollection in documentCollections) {
      final documentCollectionName =
          documentCollection[metaName] as String? ?? '';
      if (documentCollectionName.isEmpty) {
        continue;
      }

      await jsonToCollection(
        path: documentPath,
        json: documentCollection,
        onParsed: onParsed,
      );
    }
  }

  /// Converts an inner JSON to a Firestore [Document] object.
  ///
  /// This function takes a JSON object representing a Firestore document,
  /// extracts the fields and metadata, and returns a Firestore [Document].
  ///
  /// - [inJson]: The JSON object to convert.
  (String? id, Document document) _jsonToDocument(JsonObject inJson) {
    final jsonCopy = Map.of(inJson);

    final name = jsonCopy[metaName];
    if (name is! String?) {
      throw FormatException('Wrong `$metaName` value=`$name` '
          'in json=`$inJson`');
    }

    // Meta data is not meant to be stored in the cloud as the document values
    jsonCopy.remove(metaName);
    jsonCopy.remove(metaCreateTime);
    jsonCopy.remove(metaUpdateTime);
    jsonCopy.remove(metaCollections);

    final fields = <String, Value>{};

    for (final entry in jsonCopy.entries) {
      fields[entry.key] = valueUtils.fromJsonObject(entry.value);
    }

    final id = (name?.isEmpty ?? true) ? null : pathUtils.name(name);

    return (
      id,
      Document(fields: fields),
    );
  }

  /// Converts an inner JSON collection to a list of JSON documents.
  ///
  /// This function takes a JSON object representing a Firestore collection,
  /// extracts the documents, and returns a list of JSON objects.
  ///
  /// - [json]: The JSON object representing the collection.
  List<JsonObject> _jsonCollectionToDocuments(JsonObject json) {
    final name = json[metaName];
    if (name is! String || name.isEmpty) {
      throw FormatException('Wrong `$metaName` value=`$name` '
          'in json=`$json`');
    }

    final documents = json[metaDocuments];
    if (documents is! List<dynamic>?) {
      throw FormatException('Wrong `$metaDocuments` value=`$documents` '
          'in json=`$json`');
    }

    return (documents ?? []).cast<JsonObject>();
  }

  /// Converts a JSON object to a Firestore collection and its documents.
  ///
  /// This function recursively processes a JSON object representing a Firestore
  /// collection and its inner documents. It processes each document in the
  /// collection, converting it to a Firestore [Document] and calling the
  /// [onParsed] callback.
  ///
  /// - [path]: The path to the collection.
  /// - [json]: The JSON object to convert.
  /// - [onParsed]: The callback to call for each parsed document.
  Future<void> jsonToCollection({
    required String path,
    required JsonObject json,
    required OnParsedCallback onParsed,
    String? changeRootName,
  }) async {
    final collectionName = changeRootName ?? (json[metaName] as String?) ?? '';
    if (collectionName.isEmpty) {
      throw FormatException('Wrong `$metaName` value=`$collectionName` '
          'in json=`$json`');
    }

    final collectionPath = pathUtils.join(
      path,
      collectionName,
    );

    final innerDocuments = _jsonCollectionToDocuments(json);

    for (final innerDocument in innerDocuments) {
      await jsonToDocument(
        path: collectionPath,
        json: innerDocument,
        onParsed: onParsed,
      );
    }
  }
}
