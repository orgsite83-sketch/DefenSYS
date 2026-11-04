import 'package:flutter/foundation.dart';

/// Shared by legacy and authenticated API callers, including multipart streams.
final apiWriteActivity = ValueNotifier<int>(0);
