import 'package:flutter_dotenv/flutter_dotenv.dart';

const String kTurnaStadiaRasterStyle = 'alidade_smooth';
const int kTurnaLiveLocationUpdateDistanceMeters = 15;
const int kTurnaLiveLocationUpdateIntervalSeconds = 15;

class TurnaAppConfig {
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {}
    _loaded = true;
  }

  static String get stadiaMapsApiKey =>
      (dotenv.env['STADIA_MAPS_API_KEY'] ?? '').trim();

  static bool get hasStadiaMapsKey => stadiaMapsApiKey.isNotEmpty;
}
