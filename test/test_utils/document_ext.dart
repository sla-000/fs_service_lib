// googleapis 17+ deprecates firestore/v1 in favor of google_cloud_firestore_v1.
// ignore_for_file: deprecated_member_use

import 'package:googleapis/firestore/v1.dart';

import 'value_ext.dart';

extension DocumentTestExt on Document {
  Map<String, dynamic> get asMap {
    final result = <String, dynamic>{};

    final convertedMap = fields?.map(
      (key, value) => MapEntry(key, value.asString),
    );
    if (convertedMap != null) {
      result.addAll(convertedMap);
    }

    result['name'] = name;
    result['updateTime'] = updateTime;
    result['createTime'] = createTime;

    return result;
  }
}
