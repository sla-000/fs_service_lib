import 'dart:io';

import 'package:fs_service_lib/fs_service_lib.dart';

late final FsServiceLib fsServiceLib;

void main() async {
  fsServiceLib = FsServiceLib();

  await fsServiceLib.init(
    projectId: 'ella500',
    // databaseId: 'databaseId',
  );

  await fsServiceLib.db.addDocument(
    collectionPath: '/test',
    json: {
      'textField': 'value1', // a String field
      'doubleField': 1234.5432, // a floating point number field
      'integerField': 8765, // an integer number field
      'geopoint': 'location://34.3456/-23.432', // a location point field
      'timestamp': 'datetime://2023-10-21T11:26:40.152Z', // a timestamp field
      'docReference':
          'reference://projects/ella500/databases/(default)/documents/'
              'test/test-34f22dd23', // a reference field
      'blobData': 'bytes://AAECAwQFBg==', // a binary data field
      r'$name': 'test-1000', // name of the document
    },
  );

  await fsServiceLib.db.addDocument(
    collectionPath: '/test',
    json: {
      'textField': 'value2', // a String field
      r'$name': 'test-2000', // name of the document
    },
  );

  final test1000Doc =
      await fsServiceLib.db.getDocument(documentPath: '/test/test-1000');

  stdout.writeln('test1000Doc=`$test1000Doc`'); // test1000Doc=`{
  // textField: value1, integerField: 8765, blobData: bytes://AAECAwQFBg==,
  // docReference: reference://projects/ella500/databases/(default)/documents/test/test-34f22dd23,
  // timestamp: datetime://2023-10-21T11:26:40.152Z, geopoint: location://34.3456/-23.432,
  // doubleField: 1234.5432, $name: test-1000, $createTime: 2025-06-29T11:39:30.294544Z,
  // $updateTime: 2025-06-29T11:39:30.294544Z
  // }`
}
