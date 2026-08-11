import 'package:fs_service_lib/domain/repo/firestore_repo.dart';

/// Sealed class representing atomic write operations for batch commits.
sealed class FirestoreWrite {
  const FirestoreWrite();
}

/// Update or patch document operation.
class UpdateWrite extends FirestoreWrite {
  const UpdateWrite({
    required this.documentPath,
    required this.json,
  });

  final String documentPath;
  final JsonObject json;
}

/// Delete document operation.
class DeleteWrite extends FirestoreWrite {
  const DeleteWrite({
    required this.documentPath,
  });

  final String documentPath;
}
