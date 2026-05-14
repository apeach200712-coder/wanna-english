import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

// ──────────────────────────────────────────────
// OpenWeatherMap 무료 API 키 발급:
// https://home.openweathermap.org/users/sign_up
// 가입 후 API keys 탭에서 복사해서 아래에 붙여넣기
// ──────────────────────────────────────────────
const String _kApiKey = String.fromEnvironment(
  'OPENWEATHER_API_KEY',
  defaultValue: 'YOUR_OPENWEATHERMAP_API_KEY',
);

// ──────────────────────────────────────────────
// Data model
// ──────────────────────────────────────────────
class WeatherData {
  final String cityName;
  final double tempCelsius;
  final String description;
  final String iconCode; // OWM code, e.g. "01d", "02n"

  const WeatherData({
    required this.cityName,
    required this.tempCelsius,
    required this.description,
    required this.iconCode,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      cityName: json['name'] as String,
      tempCelsius: (json['main']['temp'] as num).toDouble(),
      description: json['weather'][0]['description'] as String,
      iconCode: json['weather'][0]['icon'] as String,
    );
  }

  /// Maps OWM icon code → emoji
  String get emoji {
    final prefix = iconCode.replaceAll(RegExp(r'[dn]$'), '');
    return switch (prefix) {
      '01' => '☀️',
      '02' => '⛅',
      '03' || '04' => '☁️',
      '09' || '10' => '🌧️',
      '11' => '⛈️',
      '13' => '❄️',
      '50' => '🌫️',
      _ => '🌡️',
    };
  }

  /// Formatted temperature string, e.g. "22°"
  String get tempLabel => '${tempCelsius.round()}°';
}

// ──────────────────────────────────────────────
// Service
// ──────────────────────────────────────────────
class WeatherService {
  static const String _baseUrl =
      'https://api.openweathermap.org/data/2.5/weather';
  static const String _fallbackCity = 'Seoul';
  static const double _fallbackLat = 37.5665;
  static const double _fallbackLon = 126.9780;
  static final Set<String> _loggedKeys = <String>{};

  static void _debugOnce(String key, String message) {
    if (!kDebugMode) return;
    if (!_loggedKeys.add(key)) return;
    debugPrint(message);
  }

  /// Returns [WeatherData] for the device's current GPS position,
  /// or null if location permission is denied or the request fails.
  Future<WeatherData?> fetchCurrentWeather() async {
    try {
      final position = await _determinePosition();
      final lat = position?.latitude ?? _fallbackLat;
      final lon = position?.longitude ?? _fallbackLon;

      if (_kApiKey != 'YOUR_OPENWEATHERMAP_API_KEY') {
        if (position != null) {
          final uri = Uri.parse(
            '$_baseUrl'
            '?lat=${position.latitude}'
            '&lon=${position.longitude}'
            '&appid=$_kApiKey'
            '&units=metric'
            '&lang=ko',
          );

          final currentLocationWeather = await _fetchWeatherByUri(uri);
          if (currentLocationWeather != null) return currentLocationWeather;
        }

        final fallbackCityWeather = await _fetchWeatherByCity(_fallbackCity);
        if (fallbackCityWeather != null) return fallbackCityWeather;
      } else {
        _debugOnce(
          'openweather-key-missing',
          'WeatherService: OpenWeather API key is not configured',
        );
      }

      return _fetchWeatherByOpenMeteo(lat: lat, lon: lon);
    } catch (e) {
      _debugOnce('fetch-current-error:$e', 'WeatherService error: $e');
      return _fetchWeatherByOpenMeteo(lat: _fallbackLat, lon: _fallbackLon);
    }
  }

  Future<WeatherData?> _fetchWeatherByCity(String city) async {
    final uri = Uri.parse(
      '$_baseUrl'
      '?q=$city'
      '&appid=$_kApiKey'
      '&units=metric'
      '&lang=ko',
    );
    return _fetchWeatherByUri(uri);
  }

  Future<WeatherData?> _fetchWeatherByUri(Uri uri) async {
    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return WeatherData.fromJson(json);
    }

    _debugOnce(
      'openweather-http-${response.statusCode}',
      'WeatherService: HTTP ${response.statusCode} – ${response.body}',
    );
    return null;
  }

  Future<WeatherData?> _fetchWeatherByOpenMeteo({
    required double lat,
    required double lon,
  }) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat'
        '&longitude=$lon'
        '&current=temperature_2m,weather_code'
        '&timezone=Asia%2FSeoul',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        _debugOnce(
          'openmeteo-http-${response.statusCode}',
          'WeatherService(OpenMeteo): HTTP ${response.statusCode} – ${response.body}',
        );
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final current = json['current'] as Map<String, dynamic>?;
      if (current == null) return null;

      final temp = (current['temperature_2m'] as num?)?.toDouble();
      final code = (current['weather_code'] as num?)?.toInt();
      if (temp == null || code == null) return null;

      final decoded = _decodeOpenMeteoCode(code);
      return WeatherData(
        cityName: _fallbackCity,
        tempCelsius: temp,
        description: decoded.description,
        iconCode: decoded.iconCode,
      );
    } catch (e) {
      _debugOnce('openmeteo-error:$e', 'WeatherService(OpenMeteo) error: $e');
      return null;
    }
  }

  ({String description, String iconCode}) _decodeOpenMeteoCode(int code) {
    return switch (code) {
      0 => (description: '맑음', iconCode: '01d'),
      1 || 2 => (description: '약간 흐림', iconCode: '02d'),
      3 => (description: '흐림', iconCode: '04d'),
      45 || 48 => (description: '안개', iconCode: '50d'),
      51 || 53 || 55 || 56 || 57 => (description: '이슬비', iconCode: '09d'),
      61 ||
      63 ||
      65 ||
      66 ||
      67 ||
      80 ||
      81 ||
      82 => (description: '비', iconCode: '10d'),
      71 || 73 || 75 || 77 || 85 || 86 => (description: '눈', iconCode: '13d'),
      95 || 96 || 99 => (description: '뇌우', iconCode: '11d'),
      _ => (description: '날씨', iconCode: '01d'),
    };
  }

  Future<Position?> _determinePosition() async {
    // Web: browser Geolocation API handles this automatically.
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _debugOnce(
        'location-disabled',
        'WeatherService: location services disabled',
      );
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _debugOnce(
          'location-denied',
          'WeatherService: location permission denied',
        );
        return null;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _debugOnce(
        'location-denied-forever',
        'WeatherService: location permission denied forever',
      );
      return null;
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
    ).timeout(const Duration(seconds: 15));
  }
}
