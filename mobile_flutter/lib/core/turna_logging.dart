import 'package:flutter/foundation.dart';

const bool kTurnaDebugLogs = kDebugMode;

const int _kTurnaBreadcrumbLimit = 120;
final List<String> _kTurnaBreadcrumbs = <String>[];

List<String> turnaBreadcrumbSnapshot() =>
    List<String>.unmodifiable(_kTurnaBreadcrumbs);

void turnaLog(String message, [Object? data]) {
  final line = data != null
      ? '[turna-mobile] $message | $data'
      : '[turna-mobile] $message';
  final breadcrumb =
      '[turna-mobile][${DateTime.now().toIso8601String()}] '
      '$message${data != null ? ' | $data' : ''}';
  _kTurnaBreadcrumbs.add(breadcrumb);
  if (_kTurnaBreadcrumbs.length > _kTurnaBreadcrumbLimit) {
    _kTurnaBreadcrumbs.removeAt(0);
  }
  if (!kTurnaDebugLogs) return;
  debugPrint(line);
}
