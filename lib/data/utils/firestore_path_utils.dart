/// Helper to handle Firestore paths.
class FirestorePathUtils {
  FirestorePathUtils();

  late String _projectId;
  late String _databaseId;

  /// Initialize the util.
  void init({required String projectId, String databaseId = '(default)'}) {
    _projectId = projectId;
    _databaseId = databaseId;
  }

  String absolutePathFromRelative(String relativePath) {
    final path = relativePath.trim();

    if (path.isEmpty || path.startsWith('/')) {
      return '$rootPath'
          '$path';
    } else {
      return '$rootPath'
          '/'
          '$path';
    }
  }

  String relativePathFromAbsolute(String absolutePath) {
    final segments = absolutePath.split(RegExp('^$rootPath/'));

    if (segments.length < 2) {
      return '';
    }

    return segments[1];
  }

  /// The Firestore database resource path:
  /// `projects/{projectId}/databases/{databaseId}`
  String get databasePath => 'projects/$_projectId/databases/$_databaseId';

  String get rootPath => '$databasePath/documents';
}
