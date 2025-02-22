/// Various path utils
class PathUtils {
  const PathUtils();

  /// Returns the parent path of [resourcePath].
  ///
  /// If [resourcePath] is null or empty, returns an empty string.
  String parent(String? resourcePath) {
    if (resourcePath?.isEmpty ?? true) {
      return '';
    }

    final pathSegments = resourcePath!.split('/');
    pathSegments.removeLast();

    return pathSegments.join('/');
  }

  /// Get resource name from full path
  String name(String? resourcePath) {
    if (resourcePath?.isEmpty ?? true) {
      return '';
    }

    final pathSegments = resourcePath!.split('/');
    return pathSegments.last.trim();
  }

  /// Join paths
  String join(String? path1, String? path2) {
    final $path1 = path1 ?? '';
    final $path2 = path2 ?? '';

    if ($path1.isEmpty) {
      return $path2;
    }

    if ($path2.isEmpty) {
      return $path1;
    }

    return '$path1/$path2';
  }
}
