import 'package:dio/dio.dart';

class ServerApi {
  ServerApi({required String baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: _normalizeBaseUrl(baseUrl),
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
            headers: const {'Accept': 'application/json'},
          ),
        );

  final Dio _dio;

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    final withScheme = trimmed.startsWith('http://') ||
            trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed';
    final uri = Uri.tryParse(withScheme);

    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Enter a valid server address and port.');
    }

    return uri.replace(path: '', query: null, fragment: null).toString();
  }

  Future<bool> checkHealth() async {
    final response = await _dio.get<dynamic>('/health');
    return response.statusCode == 200;
  }
}
