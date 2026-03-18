import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import 'turna_countries.dart';
import 'turna_device_context.dart';

void _turnaContactsLog(String message, [Object? error]) {
  if (!kDebugMode) return;
  final suffix = error == null ? '' : ' | $error';
  debugPrint('[turna-mobile] $message$suffix');
}

class TurnaContactSyncEntry {
  const TurnaContactSyncEntry({
    required this.displayName,
    required this.phones,
  });

  final String displayName;
  final List<String> phones;

  Map<String, dynamic> toMap() => {
    'displayName': displayName,
    'phones': phones,
  };
}

class TurnaContactsDirectory {
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final List<String> _knownDialCodes =
      kTurnaCountries
          .map((item) => item.dialCode.replaceAll(RegExp(r'\D+'), ''))
          .toSet()
          .toList()
        ..sort((left, right) => right.length.compareTo(left.length));

  static Future<void>? _pendingLoad;
  static Map<String, String> _labelsByPhoneKey = <String, String>{};
  static List<TurnaContactSyncEntry> _syncEntries =
      const <TurnaContactSyncEntry>[];
  static bool _permissionGranted = false;

  static bool get permissionGranted => _permissionGranted;

  static List<TurnaContactSyncEntry> snapshotForSync() {
    return List<TurnaContactSyncEntry>.unmodifiable(_syncEntries);
  }

  static Future<void> ensureLoaded({bool force = false}) async {
    if (!force && _permissionGranted) return;
    if (_pendingLoad != null) {
      await _pendingLoad;
      return;
    }

    final future = _loadContacts();
    _pendingLoad = future;
    try {
      await future;
    } finally {
      if (identical(_pendingLoad, future)) {
        _pendingLoad = null;
      }
    }
  }

  static String resolveDisplayLabel({
    String? phone,
    required String fallbackName,
  }) {
    final label = lookupLabel(phone);
    if (label == null || label.trim().isEmpty) return fallbackName;
    return label;
  }

  static String? lookupLabel(String? phone) {
    for (final key in _phoneLookupKeys(
      phone,
      defaultCountryIso: TurnaDeviceContext.countryIso,
    )) {
      final label = _labelsByPhoneKey[key];
      if (label != null && label.trim().isNotEmpty) {
        return label;
      }
    }
    return null;
  }

  static Future<void> _loadContacts() async {
    try {
      await TurnaDeviceContext.ensureLoaded();
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        _permissionGranted = false;
        return;
      }

      final defaultCountryIso = TurnaDeviceContext.countryIso;
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      final next = <String, String>{};
      final syncEntries = <TurnaContactSyncEntry>[];
      for (final contact in contacts) {
        final displayName = contact.displayName.trim();
        if (displayName.isEmpty) continue;
        final phones = <String>[];
        final canonicalPhones = <String>{};
        for (final phone in contact.phones) {
          final canonicalPhone = _canonicalPhoneLookupKey(
            phone.number,
            defaultCountryIso: defaultCountryIso,
          );
          if (canonicalPhone != null && canonicalPhones.add(canonicalPhone)) {
            phones.add(canonicalPhone);
          }
          for (final key in _phoneLookupKeys(
            phone.number,
            defaultCountryIso: defaultCountryIso,
          )) {
            next.putIfAbsent(key, () => displayName);
          }
        }
        if (phones.isNotEmpty) {
          syncEntries.add(
            TurnaContactSyncEntry(displayName: displayName, phones: phones),
          );
        }
      }

      final changed =
          next.length != _labelsByPhoneKey.length ||
          next.entries.any(
            (entry) => _labelsByPhoneKey[entry.key] != entry.value,
          ) ||
          syncEntries.length != _syncEntries.length ||
          !_permissionGranted;
      _permissionGranted = true;
      _labelsByPhoneKey = next;
      _syncEntries = syncEntries;
      if (changed) {
        revision.value++;
      }
    } catch (error) {
      _turnaContactsLog('contacts load failed', error);
    }
  }

  static String? _countryDialCodeDigits(String? countryIso) {
    final normalized = countryIso?.trim().toUpperCase();
    if (normalized == null || normalized.isEmpty) return null;

    for (final country in kTurnaCountries) {
      if (country.iso == normalized) {
        return country.dialCode.replaceAll(RegExp(r'\D+'), '');
      }
    }

    return null;
  }

  static String? _detectInternationalDialCode(String digits) {
    for (final dialCode in _knownDialCodes) {
      if (!digits.startsWith(dialCode)) continue;
      final national = digits.substring(dialCode.length);
      if (national.length >= 4) {
        return dialCode;
      }
    }

    return null;
  }

  static String? _canonicalPhoneLookupKey(
    String? raw, {
    String? defaultCountryIso,
  }) {
    final source = raw?.trim() ?? '';
    if (source.isEmpty) return null;

    final digits = source.replaceAll(RegExp(r'\D+'), '');
    if (digits.length < 7) return null;

    if (source.startsWith('+')) {
      return digits;
    }

    if (digits.startsWith('00') && digits.length > 2) {
      return digits.substring(2);
    }

    if (digits.length > 10) {
      final detectedDialCode = _detectInternationalDialCode(digits);
      if (detectedDialCode != null) {
        return digits;
      }
    }

    final defaultDialCode = _countryDialCodeDigits(defaultCountryIso);
    if (defaultDialCode == null || defaultDialCode.isEmpty) {
      return digits;
    }

    final nationalDigits = digits.replaceFirst(RegExp(r'^0+'), '');
    if (digits.startsWith('0')) {
      return nationalDigits.length >= 4
          ? '$defaultDialCode$nationalDigits'
          : null;
    }

    if (digits.length <= 10) {
      return nationalDigits.length >= 4
          ? '$defaultDialCode$nationalDigits'
          : null;
    }

    return digits;
  }

  static List<String> _phoneLookupKeys(
    String? raw, {
    String? defaultCountryIso,
  }) {
    final source = raw?.trim() ?? '';
    if (source.isEmpty) return const <String>[];

    final digits = source.replaceAll(RegExp(r'\D+'), '');
    if (digits.length < 7) return const <String>[];

    final keys = <String>[];
    void addKey(String value) {
      final normalized = value.trim();
      if (normalized.length < 7 || keys.contains(normalized)) return;
      keys.add(normalized);
    }

    final canonical = _canonicalPhoneLookupKey(
      raw,
      defaultCountryIso: defaultCountryIso,
    );
    if (canonical != null) {
      addKey(canonical);
    }
    addKey(digits);

    final internationalDigits = canonical ?? digits;
    final dialCode =
        _detectInternationalDialCode(internationalDigits) ??
        _countryDialCodeDigits(defaultCountryIso);
    if (dialCode != null && internationalDigits.startsWith(dialCode)) {
      final nationalDigits = internationalDigits
          .substring(dialCode.length)
          .replaceFirst(RegExp(r'^0+'), '');
      if (nationalDigits.length >= 4) {
        addKey(nationalDigits);
        addKey('0$nationalDigits');
      }
    }

    return keys;
  }
}
