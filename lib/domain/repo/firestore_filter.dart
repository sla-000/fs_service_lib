/// Comparison operator for Firestore field queries.
enum FirestoreOperator {
  isEqualTo,
  isNotEqualTo,
  isLessThan,
  isLessThanOrEqualTo,
  isGreaterThan,
  isGreaterThanOrEqualTo,
  arrayContains,
  isIn,
  isNotIn,
}

/// Filter condition for querying a collection field.
class FirestoreFilter {
  const FirestoreFilter({
    required this.field,
    required this.op,
    required this.value,
  });

  final String field;
  final FirestoreOperator op;
  final dynamic value;
}
