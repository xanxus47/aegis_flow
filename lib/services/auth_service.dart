// lib/services/auth_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const String baseUrl = 'https://citrusapi-dev-svex.onrender.com/api/v1';
  final storage = const FlutterSecureStorage();

  // ----------------------------------------------------------------
  // 1. LOGIN
  // ----------------------------------------------------------------
  Future<void> login(String username, String password) async {
    print('═══════════════════════════════════════');
    print('🔐 STARTING LOGIN PROCESS');
    print('═══════════════════════════════════════');

    try {
      final uri = Uri.parse('$baseUrl/auth/login');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'UserName': username,
          'Password': password,
        }),
      ).timeout(const Duration(seconds: 60));

      print('📡 Status Code: ${response.statusCode}');

      if (response.body.isEmpty) throw Exception('Server returned empty response');

      final body = jsonDecode(response.body);

      if (response.statusCode == 200 && body['isSuccess'] == true) {
        print('🎉 LOGIN SUCCESSFUL - Status 200');
        print('═══════════════════════════════════════');

        // ✅ FIX: Tokens are nested inside body['data']
        final data = body['data'] as Map<String, dynamic>;

        final accessToken  = data['accessToken']?.toString();
        final refreshToken = data['refreshToken']?.toString();

        if (accessToken == null) {
          throw Exception('No access token in response');
        }

        await storage.write(key: 'access_token',  value: accessToken);
        await storage.write(key: 'refresh_token', value: refreshToken);
        await storage.write(key: 'username',       value: username);
        await storage.write(key: 'is_logged_in',   value: 'true');

        // Store useful user info
        await storage.write(key: 'user_id',    value: data['id']?.toString());
        await storage.write(key: 'first_name', value: data['firstName']?.toString());
        await storage.write(key: 'last_name',  value: data['lastName']?.toString());
        await storage.write(key: 'is_admin',   value: data['isAdmin']?.toString());

        print('✅ Access token stored securely');
        print('✅ LOGIN COMPLETE - User: $username');
        return;
      }

      final message = body['message'] ?? 'Login failed';
      switch (response.statusCode) {
        case 400: throw Exception('Bad request - invalid parameters');
        case 401: throw Exception('Invalid username or password');
        case 403: throw Exception('Access forbidden');
        case 404: throw Exception('Login endpoint not found (404)');
        case 500: throw Exception('Internal server error (500)');
        default:  throw Exception('$message (${response.statusCode})');
      }

    } catch (e) {
      if (e is http.ClientException) throw Exception('Network error: ${e.message}');
      if (e.toString().contains('timed out')) throw Exception('Connection timeout.');
      rethrow;
    }
  }

  // ----------------------------------------------------------------
  // 2. REFRESH TOKEN
  // ----------------------------------------------------------------
  Future<void> refreshToken() async {
    try {
      final storedRefreshToken = await storage.read(key: 'refresh_token');

      if (storedRefreshToken == null) {
        throw Exception('No refresh token available');
      }

      print('🔄 Refreshing token via POST /auth/token/refresh ...');

      final response = await http.post(
        Uri.parse('$baseUrl/auth/token/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'RefreshToken': storedRefreshToken}),
      ).timeout(const Duration(seconds: 30));

      print('📡 Refresh Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'] as Map<String, dynamic>?;

        final newAccessToken  = data?['accessToken']  ?? body['accessToken']  ?? body['token'];
        final newRefreshToken = data?['refreshToken'] ?? body['refreshToken'] ?? body['refresh_token'];

        if (newAccessToken != null) {
          await storage.write(key: 'access_token', value: newAccessToken);
          print('✅ Access token refreshed successfully');
        }
        if (newRefreshToken != null) {
          await storage.write(key: 'refresh_token', value: newRefreshToken);
          print('✅ Refresh token updated');
        }
      } else {
        print('❌ Refresh failed (${response.statusCode}) — logging out');
        await logout();
        throw Exception('Session expired. Please login again.');
      }
    } catch (e) {
      print('❌ Token refresh error: $e');
      rethrow;
    }
  }

  // ----------------------------------------------------------------
  // 3. GET ACCESS TOKEN (with proactive refresh)
  // ----------------------------------------------------------------
  bool _isRefreshing = false; // Prevents multiple overlapping refreshes

  // Returns: 0 (Valid), 1 (Expiring Soon - Background Refresh), 2 (Expired - Must Wait)
  int _tokenStatus(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return 2; 

      String payload = parts[1];
      // Bulletproof Base64 padding (prevents decoding crashes)
      switch (payload.length % 4) {
        case 2: payload += '=='; break;
        case 3: payload += '='; break;
      }

      final resp       = utf8.decode(base64Url.decode(payload));
      final payloadMap = jsonDecode(resp);

      if (payloadMap.containsKey('exp')) {
        // Safe cast to int (prevents silent TypeErrors if API sends a double)
        final int exp = (payloadMap['exp'] as num).toInt() * 1000;
        final expirationDate = DateTime.fromMillisecondsSinceEpoch(exp);
        final now = DateTime.now();

        if (now.add(const Duration(seconds: 15)).isAfter(expirationDate)) {
          return 2; // EXPIRED (or < 15s left): We MUST block and wait for a new one
        } else if (now.add(const Duration(minutes: 5)).isAfter(expirationDate)) {
          return 1; // EXPIRING SOON (< 5 mins left): Use instantly, but refresh in background
        } else {
          return 0; // VALID: Good to go
        }
      }
    } catch (e) {
      print('⚠️ Token check error: $e');
      return 2; // Default to blocking refresh on error
    }
    return 2;
  }

  Future<String> getAccessToken() async {
    String? token = await storage.read(key: 'access_token');

    if (token == null) throw Exception('Not authenticated');

    final int status = _tokenStatus(token);

    if (status == 2) {
      // 🚨 CRITICAL: Token is actually expired. We MUST wait for Render to wake up.
      print('⏳ Token expired. Blocking to refresh...');
      try {
        await refreshToken();
        token = await storage.read(key: 'access_token');
        if (token == null) throw Exception('Token null after refresh');
      } catch (e) {
        await logout();
        throw Exception('Session expired. Please login again.');
      }
    } else if (status == 1) {
      // ⚡ PRO MODE: Token is valid for a few more minutes. 
      // Return it INSTANTLY so the user feels 0 lag, and wake up Render quietly in the background!
      if (!_isRefreshing) {
        _isRefreshing = true;
        print('🔄 Token expiring soon. Waking up server in the background...');
        
        // Notice we do NOT use 'await' here! It runs independently.
        refreshToken().then((_) {
          _isRefreshing = false;
          print('✅ Background refresh complete! New token saved for next time.');
        }).catchError((e) {
          _isRefreshing = false;
          print('❌ Background refresh failed (will retry on next action): $e');
        });
      }
    }

    return token; // Instantly returns for status 0 and 1!
  }

  // ----------------------------------------------------------------
  // 4. LOGOUT
  // ----------------------------------------------------------------
  Future<void> logout() async {
    try {
      final token = await storage.read(key: 'access_token');
      if (token != null) {
        await http.post(
          Uri.parse('$baseUrl/auth/logout'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 10));
        print('✅ Logout API call successful');
      }
    } catch (e) {
      print('⚠️ Logout API call failed (will still clear storage): $e');
    } finally {
      await storage.deleteAll();
      print('✅ Local storage cleared — logged out');
    }
  }

  // ----------------------------------------------------------------
  // 5. HELPERS
  // ----------------------------------------------------------------
  Future<bool> isAuthenticated() async {
    final token = await storage.read(key: 'access_token');
    return token != null;
  }

  Future<String?> getUsername() async {
    return await storage.read(key: 'username');
  }

  Future<String?> getFullName() async {
    final first = await storage.read(key: 'first_name');
    final last  = await storage.read(key: 'last_name');
    if (first == null && last == null) return null;
    return '${first ?? ''} ${last ?? ''}'.trim();
  }

  Future<bool> isAdmin() async {
    final val = await storage.read(key: 'is_admin');
    return val == 'true';
  }

  Future<Map<String, dynamic>?> getUserData() async {
    final userData = await storage.read(key: 'user_data');
    if (userData != null) return jsonDecode(userData);
    return null;
  }
}