import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiService {
  // Android emulator default. For Gmail OAuth, configure a public HTTPS backend
  // URL with --dart-define=MAILMIND_API_BASE=https://your-public-backend.example
  static const String baseUrl = String.fromEnvironment(
    'MAILMIND_API_BASE',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'mailmind_session_token';
  static const _timeout = Duration(seconds: 25);

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<void> exchangeTicket(String ticket) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/mobile-exchange'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'ticket': ticket}),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw ApiException('Sign-in ticket expired. Please connect Gmail again.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['token']?.toString();
    if (token == null || token.isEmpty) {
      throw ApiException('Server did not return a session token.');
    }
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<List<Map<String, dynamic>>> loadEmails(String token) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/emails'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_timeout);

    if (response.statusCode == 401) throw ApiException('Session expired. Reconnect Gmail.');
    if (response.statusCode != 200) throw ApiException('Could not load Gmail messages (${response.statusCode}).');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (data['emails'] as List<dynamic>? ?? []);
    return list.whereType<Map<String, dynamic>>().toList();
  }

  Future<String> analyze({
    required String token,
    required String emailId,
    required String task,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/analyze'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'emailId': emailId, 'task': task}),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 401) throw ApiException('Session expired. Reconnect Gmail.');
    if (response.statusCode != 200) throw ApiException('AI analysis failed (${response.statusCode}).');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['result'] ?? 'No result returned.').toString();
  }

  Future<void> logout(String? token) async {
    if (token != null && token.isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse('$baseUrl/api/logout'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // Clear local session even when offline.
      }
    }
    await clearToken();
  }
}

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
