// coverage:ignore-file

import 'dart:convert';

/// Default indentation for JSON string
const kJsonIndent = '  ';

/// JSON encoder with default indent
const jsonEncoder = JsonEncoder.withIndent(kJsonIndent);
