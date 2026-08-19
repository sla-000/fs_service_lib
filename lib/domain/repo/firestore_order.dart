/// Ordering specification for querying collection fields.
class FirestoreOrder {
  const FirestoreOrder({required this.field, this.descending = true});

  final String field;
  final bool descending;
}
