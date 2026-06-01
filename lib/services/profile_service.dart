// lib/services/profile_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../models/profile_model.dart';
import '../models/evacuation_center_model.dart';
import '../refugeex_offline/offline_store.dart';
import '../refugeex_offline/roster_sync_service.dart';

class ProfileService {
  static const String baseUrl = 'https://citrusapi-dev-svex.onrender.com/api/v1';
  final AuthService _authService = AuthService();
  final OfflineStore _offlineStore = OfflineStore.instance;

  // ----------------------------------------------------------------
  // 1. HELPER: Extract ID
  // ----------------------------------------------------------------
  String? extractProfileId(String qrData) {
    final data = qrData.trim();
    try {
      final jsonData = jsonDecode(data);
      if (jsonData is Map) {
        if (jsonData.containsKey('profile_id')) {
          return jsonData['profile_id'].toString();
        }
        if (jsonData.containsKey('id')) return jsonData['id'].toString();
      }
    } catch (_) {}

    if (data.contains('/profile/')) {
      return data
          .split('/profile/')
          .last
          .split('/')
          .first
          .split('?')
          .first;
    }

    final uuidRegex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    if (uuidRegex.hasMatch(data)) return data;

    return data;
  }

  // ----------------------------------------------------------------
  // 2. HELPER: Authenticated Request (GET, POST, DELETE)
  // ----------------------------------------------------------------
  Future<http.Response> _authenticatedRequest(
    String method,
    String endpoint, {
    Object? body,
  }) async {
    String token;

    try {
      token = await _authService.getAccessToken();
    } catch (e) {
      print('🛑 Auth check failed before request: $e');
      return http.Response('{"message": "Session expired"}', 401);
    }

    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Cache-Control': 'no-cache',
    };

    http.Response response;

    try {
      response = await _doRequest(method, uri, headers, body)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      print('🌐 Network error during request: $e');
      throw Exception('Network Error: $e');
    }

    // Reactive Fallback: emergency refresh on 401
    if (response.statusCode == 401) {
      print('⚠️ Server rejected token (401). Attempting emergency refresh...');
      try {
        await _authService.refreshToken();
        token = await _authService.getAccessToken();
        headers['Authorization'] = 'Bearer $token';
        print('✅ Emergency refresh successful. Retrying...');
        response = await _doRequest(method, uri, headers, body);
      } catch (e) {
        print('❌ Emergency Refresh Failed: $e');
      }
    }

    return response;
  }

  Future<http.Response> _doRequest(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) async {
    switch (method) {
      case 'POST':
        return await http.post(uri, headers: headers, body: body);
      case 'DELETE':
        return await http.delete(uri, headers: headers, body: body);
      default:
        return await http.get(uri, headers: headers);
    }
  }

  // ----------------------------------------------------------------
  // 3. GET PROFILE
  // ----------------------------------------------------------------
  Future<Map<String, dynamic>> getProfileDetails(String profileId) async {
    try {
      final response =
          await _authenticatedRequest('GET', '/profile/$profileId');

      print('📡 GET Profile Status: ${response.statusCode}');
      print('📦 GET Profile Body: ${response.body}');

      if (response.statusCode == 200) {
        final decodedBody = jsonDecode(response.body);
        Map<String, dynamic> profileJson = {};

        if (decodedBody is Map) {
          if (decodedBody.containsKey('data') &&
              decodedBody['data'] != null) {
            final dataObj = decodedBody['data'];
            if (dataObj is Map && dataObj.containsKey('result')) {
              profileJson = Map<String, dynamic>.from(
                  dataObj['result'] is List
                      ? dataObj['result'][0]
                      : dataObj['result']);
            } else {
              profileJson = Map<String, dynamic>.from(
                  dataObj is List ? dataObj[0] : dataObj);
            }
          } else if (decodedBody.containsKey('result') &&
              decodedBody['result'] != null) {
            profileJson = Map<String, dynamic>.from(
                decodedBody['result'] is List
                    ? decodedBody['result'][0]
                    : decodedBody['result']);
          } else {
            profileJson = Map<String, dynamic>.from(decodedBody);
          }
        }

        final profile = Profile.fromJson(profileJson);

        // Cache to Hive
        await _offlineStore.cacheProfile(profile);

        // ← Cache head_of_family to SQLite for future offline scans
        await RosterSyncService.instance.updateProfileHeadOfFamily(
          profile.id,
          profile.headOfFamily,
        );

        return {
          'success': true,
          'data': profile,
          'fromCache': false,
        };
      } else if (response.statusCode == 404) {
        return {
          'success': false,
          'message': 'Profile not found in database'
        };
      } else if (response.statusCode == 401) {
        return {
          'success': false,
          'message': 'Session expired. Please re-login.'
        };
      }

      // Non-200/404/401 — try Hive cache
      final cached = _offlineStore.getCachedProfile(profileId);
      if (cached != null) {
        return {
          'success': true,
          'data': cached,
          'fromCache': true,
          'message': 'Loaded from offline cache'
        };
      }

      return {
        'success': false,
        'message': 'Server Error (${response.statusCode})'
      };
    } catch (e) {
      // Network error — try Hive cache first
      final cached = _offlineStore.getCachedProfile(profileId);
      if (cached != null) {
        return {
          'success': true,
          'data': cached,
          'fromCache': true,
          'message': 'Offline cache hit'
        };
      }

      // Fallback to SQLite offline roster
      try {
        final sqliteRow =
            await RosterSyncService.instance.getProfileLocally(profileId);
        if (sqliteRow != null) {
          final profile = Profile.fromJson(sqliteRow);
          return {
            'success': true,
            'data': profile,
            'fromCache': true,
            'message': 'Offline SQLite hit'
          };
        }
      } catch (_) {}

      return {
        'success': false,
        'message':
            'Network error: You are offline and this profile is not cached on your device. Please connect to the internet to scan this ID for the first time.'
      };
    }
  }

  // ----------------------------------------------------------------
  // 4. CHECK STATUS
  // ----------------------------------------------------------------
  Future<Map<String, dynamic>> getEvacueeStatus(String profileId) async {
    try {
      final response = await _authenticatedRequest(
          'GET', '/profile/$profileId/evacuation');

      if (response.statusCode == 404) {
        return {'success': true, 'isCheckedIn': false};
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        bool isCheckedIn = false;

        if (data is List) {
          for (var item in data) {
            if (_isActiveRecord(item)) {
              isCheckedIn = true;
              break;
            }
          }
        } else if (data is Map) {
          if (_isActiveRecord(data)) isCheckedIn = true;
        }

        return {'success': true, 'isCheckedIn': isCheckedIn, 'data': data};
      }

      if (response.statusCode == 401) {
        return {'success': false, 'message': 'Session expired'};
      }

      return {
        'success': false,
        'message': 'Status check failed (${response.statusCode})'
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  bool _isActiveRecord(dynamic item) {
    if (item == null || item is! Map) return false;
    if (item['isActive'] == false) return false;

    final dates = [
      item['dateCheckedOut'],
      item['checkOutDate'],
      item['endDateTime'],
      item['dateDeleted'],
    ];
    for (var date in dates) {
      if (date != null && date.toString().isNotEmpty) return false;
    }
    return true;
  }

  // ----------------------------------------------------------------
  // 5. CHECK IN
  // ----------------------------------------------------------------
  Future<Map<String, dynamic>> checkInEvacuee(
      String profileId, String centerId) async {
    try {
      final body = jsonEncode({
        'EvacueeId': profileId,
        'Purpose': null,
      });

      final response = await _authenticatedRequest(
        'POST',
        '/evacuation-center/$centerId/evacuee',
        body: body,
      );

      print('📡 Check-in status: ${response.statusCode}');
      print('📦 Check-in response: ${response.body}');

      final data =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'message': 'Check-in Successful'};
      } else if (response.statusCode == 409 ||
          (response.statusCode == 400 &&
              data?['message']
                      ?.toString()
                      .toLowerCase()
                      .contains('currently checked-in') ==
                  true)) {
        return {
          'success': true,
          'message': 'Check-in Successful (Already checked in on server)'
        };
      } else if (response.statusCode == 401) {
        return {'success': false, 'message': 'Session expired'};
      }

      return {
        'success': false,
        'message':
            'Status ${response.statusCode}: ${data?['message'] ?? response.body}'
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // ----------------------------------------------------------------
  // 6. CHECK OUT
  // ----------------------------------------------------------------
  Future<Map<String, dynamic>> checkOutEvacuee(
      String profileId, String centerId) async {
    try {
      final response = await _authenticatedRequest(
        'DELETE',
        '/evacuation-evacuee/$profileId',
      );

      print('📡 Check-out status: ${response.statusCode}');
      print('📦 Check-out response: ${response.body}');

      final data =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;

      if (response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 204) {
        return {'success': true, 'message': 'Check-out Successful'};
      } else if (response.statusCode == 400 &&
          data?['message']
                  ?.toString()
                  .toLowerCase()
                  .contains('not checked-in') ==
              true) {
        return {
          'success': true,
          'message': 'Check-out Successful (Already checked out)'
        };
      } else if (response.statusCode == 401) {
        return {'success': false, 'message': 'Session expired'};
      }

      return {
        'success': false,
        'message':
            'Status ${response.statusCode}: ${data?['message'] ?? response.body}'
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // ----------------------------------------------------------------
  // 7. GET CENTERS
  // ----------------------------------------------------------------
  Future<Map<String, dynamic>> getEvacuationCenters() async {
    try {
      List<EvacuationCenter> allCenters = [];
      int currentPage = 1;
      int rowsPerPage = 50;
      bool hasMoreData = true;

      while (hasMoreData) {
        final response = await _authenticatedRequest(
            'GET', '/evacuation-center?page=$currentPage&rows=$rowsPerPage');

        if (response.statusCode == 200) {
          final decodedBody = jsonDecode(response.body);
          print('✅ RAW CENTERS RESPONSE: ${response.body}');

          List dynamicList = [];

          if (decodedBody is Map) {
            if (decodedBody['data'] != null) {
              final d = decodedBody['data'];
              if (d is List) {
                dynamicList = d;
              } else if (d is Map) {
                if (d['result'] is List) dynamicList = d['result'];
                else if (d['items'] is List) dynamicList = d['items'];
                else if (d['centers'] is List) dynamicList = d['centers'];
              }
            } else if (decodedBody['result'] is List) {
              dynamicList = decodedBody['result'];
            } else if (decodedBody['items'] is List) {
              dynamicList = decodedBody['items'];
            }
          } else if (decodedBody is List) {
            dynamicList = decodedBody;
          }

          if (dynamicList.isEmpty) {
            hasMoreData = false;
          } else {
            final pageCenters =
                dynamicList.map((e) => EvacuationCenter.fromJson(e)).toList();
            allCenters.addAll(pageCenters);

            if (dynamicList.length < rowsPerPage) {
              hasMoreData = false;
            } else {
              currentPage++;
            }
          }
        } else {
          return {
            'success': false,
            'message':
                'API Error on page $currentPage: ${response.statusCode}'
          };
        }
      }

      await _offlineStore.cacheEvacuationCenters(allCenters);
      return {'success': true, 'data': allCenters, 'fromCache': false};
    } catch (e) {
      final cachedCenters = _offlineStore.getCachedCenters();
      if (cachedCenters.isNotEmpty) {
        return {
          'success': true,
          'data': cachedCenters,
          'fromCache': true,
          'message': 'Loaded cached centers'
        };
      }
      return {'success': false, 'message': 'Error parsing centers: $e'};
    }
  }
}