import 'package:googleapis/firestore/v1.dart';

/// Mapper from firestore value to json and vice versa.
class ValueMapper {
  static const kLocationPrefix = 'location://';
  static const kReferencePrefix = 'reference://';
  static const kBytesPrefix = 'bytes://';
  static const kDatetimePrefix = 'datetime://';

  late String _locationPrefix;
  late String _referencePrefix;
  late String _bytesPrefix;
  late String _datetimePrefix;

  /// Initializes the prefixes used for encoding specific data types.
  ///
  /// This method allows you to customize the prefixes used to identify
  /// different types of data when converting to and from JSON. If no prefixes
  /// are provided, default prefixes are used.
  ///
  /// [locationPrefix]: Prefix for location data.
  /// [referencePrefix]: Prefix for reference data.
  /// [bytesPrefix]: Prefix for bytes data.
  /// [datetimePrefix]: Prefix for datetime data.
  void init({
    String? locationPrefix,
    String? referencePrefix,
    String? bytesPrefix,
    String? datetimePrefix,
  }) {
    _locationPrefix = locationPrefix ?? kLocationPrefix;
    _referencePrefix = referencePrefix ?? kReferencePrefix;
    _bytesPrefix = bytesPrefix ?? kBytesPrefix;
    _datetimePrefix = datetimePrefix ?? kDatetimePrefix;
  }

  /// Converts a Firestore [Value] to its corresponding JSON representation.
  ///
  /// This method recursively converts a [Value] object from Firestore into a
  /// JSON-compatible object. It handles various data types such as GeoPoints,
  /// maps, arrays, doubles, integers, nulls, references, strings, timestamps,
  /// booleans, and bytes.
  dynamic toJsonObject(Value value) {
    if (value.geoPointValue != null) {
      final geoPointValue = value.geoPointValue!;
      return '$_locationPrefix${geoPointValue.latitude}'
          '/'
          '${geoPointValue.longitude}';
    }

    if (value.mapValue != null) {
      final map = <String, dynamic>{};
      final entries = value.mapValue!.fields?.entries;
      if (entries != null) {
        for (final entry in entries) {
          map[entry.key] = toJsonObject(entry.value);
        }
      }
      return map;
    }

    if (value.arrayValue != null) {
      final list = <dynamic>[];
      final values = value.arrayValue!.values;
      if (values != null) {
        for (final value in values) {
          list.add(toJsonObject(value));
        }
      }
      return list;
    }

    if (value.doubleValue != null) {
      return value.doubleValue;
    }

    if (value.integerValue != null) {
      return int.parse(value.integerValue!);
    }

    if (value.nullValue != null) {
      return null;
    }

    if (value.referenceValue != null) {
      return '$_referencePrefix${value.referenceValue}';
    }

    if (value.stringValue != null) {
      return value.stringValue;
    }

    if (value.timestampValue != null) {
      final datetime =
          DateTime.parse(value.timestampValue!).toUtc().toIso8601String();

      return '$_datetimePrefix$datetime';
    }

    if (value.booleanValue != null) {
      return value.booleanValue;
    }

    if (value.bytesValue != null) {
      return '$_bytesPrefix${value.bytesValue}';
    }

    throw FormatException('Unknown data type: value=$value, '
        'toJson=${value.toJson()}');
  }

  /// Converts a JSON object to its corresponding Firestore [Value] representation.
  ///
  /// This method recursively converts a JSON object into a Firestore [Value]
  /// object. It handles various JSON data types such as doubles, integers,
  /// booleans, maps, arrays, and strings, including those encoded with custom
  /// prefixes for locations, references, bytes, and datetimes.
  Value fromJsonObject(dynamic json) {
    if (json is double) {
      return Value(doubleValue: json);
    }

    if (json is int) {
      return Value(integerValue: json.toString());
    }

    if (json is bool) {
      return Value(booleanValue: json);
    }

    if (json is Map<String, dynamic>) {
      final map = <String, Value>{};
      for (final entry in json.entries) {
        map[entry.key] = fromJsonObject(entry.value);
      }
      return Value(mapValue: MapValue(fields: map));
    }

    if (json is List<dynamic>) {
      final list = <Value>[];
      for (final entry in json) {
        list.add(fromJsonObject(entry));
      }
      return Value(arrayValue: ArrayValue(values: list));
    }

    if (json is String) {
      if (json.startsWith(_locationPrefix)) {
        final strings = json.substring(_locationPrefix.length).split('/');
        final lat = double.parse(strings[0]);
        final lon = double.parse(strings[1]);
        return Value(geoPointValue: LatLng(latitude: lat, longitude: lon));
      }

      if (json.startsWith(_referencePrefix)) {
        final ref = json.substring(_referencePrefix.length);
        return Value(referenceValue: ref);
      }

      if (json.startsWith(_bytesPrefix)) {
        final bytes = json.substring(_bytesPrefix.length);
        return Value(bytesValue: bytes);
      }

      if (json.startsWith(_datetimePrefix)) {
        final datetimeRaw = json.substring(_datetimePrefix.length);
        final datetimeFormatted = DateTime.parse(datetimeRaw).toIso8601String();
        return Value(timestampValue: datetimeFormatted);
      }

      return Value(stringValue: json);
    }

    if (json == null) {
      return Value(nullValue: 'NULL_VALUE');
    }

    throw FormatException('Unknown data type: json=$json');
  }
}
