// googleapis 17+ deprecates firestore/v1 in favor of google_cloud_firestore_v1.
// ignore_for_file: deprecated_member_use

import 'package:fs_service_lib/utils/path_utils.dart';
import 'package:googleapis/firestore/v1.dart';

extension DocumentExt on Document {
  /// Get document Id
  String? id(PathUtils pathUtils) => name != null ? pathUtils.name(name) : null;
}
