// lib/services/profile_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../models/profile_model.dart';
import '../models/evacuation_center_model.dart';

class ProfileService {
  static const String baseUrl = 'https://citrusapi-dev-svex.onrender.com/api/v1';
  final AuthService _authService = AuthService();

  // 4P's HOUSEHOLD TRACKING (STATIC)
  static Set<String> _fourPsHouseholds = {};
  static bool _fourPsLoaded = false;

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
      response = await _doRequest(method, uri, headers, body);
    } catch (e) {
      print('🌐 Network error during request: $e');
      return http.Response('{"message": "Network Error"}', 500);
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
      final response = await _authenticatedRequest('GET', '/profile/$profileId');

      print('📡 GET Profile Status: ${response.statusCode}');
      print('📦 GET Profile Body: ${response.body}');

      if (response.statusCode == 200) {
        final decodedBody = jsonDecode(response.body);
        Map<String, dynamic> profileJson = {};

        // 🚨 UNWRAP THE NESTED JSON (With strict type casting to fix the Map error)
        if (decodedBody is Map) {
          if (decodedBody.containsKey('data') && decodedBody['data'] != null) {
            final dataObj = decodedBody['data'];
            if (dataObj is Map && dataObj.containsKey('result')) {
              profileJson = Map<String, dynamic>.from(dataObj['result'] is List ? dataObj['result'][0] : dataObj['result']);
            } else {
              profileJson = Map<String, dynamic>.from(dataObj is List ? dataObj[0] : dataObj);
            }
          } else if (decodedBody.containsKey('result') && decodedBody['result'] != null) {
            profileJson = Map<String, dynamic>.from(decodedBody['result'] is List ? decodedBody['result'][0] : decodedBody['result']);
          } else {
            // ✅ FIXED MAP CASTING HERE
            profileJson = Map<String, dynamic>.from(decodedBody); 
          }
        }

        return {
          'success': true,
          'data': Profile.fromJson(profileJson)
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

      return {
        'success': false,
        'message': 'Server Error (${response.statusCode})'
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
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
  // 5. CHECK IN  🚨 POST /evacuation-center/{centerId}/evacuee
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
      } else if (response.statusCode == 409) {
        return {'success': false, 'message': 'Already checked in!'};
      } else if (response.statusCode == 401) {
        return {'success': false, 'message': 'Session expired'};
      }

      // 🔧 Show status code + full message
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
  // 6. CHECK OUT  🚨 DELETE /evacuation-evacuee/{EvacueeId}
  // ----------------------------------------------------------------
  Future<Map<String, dynamic>> checkOutEvacuee(
      String profileId, String centerId) async {
    try {
      // Using Lester's simplified global checkout endpoint
      // We no longer need to pass the centerId to the API!
      final response = await _authenticatedRequest(
        'DELETE',
        '/evacuation-evacuee/$profileId', 
      );

      print('📡 Check-out status: ${response.statusCode}');
      print('📦 Check-out response: ${response.body}');

      if (response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 204) {
        return {'success': true, 'message': 'Check-out Successful'};
      } else if (response.statusCode == 401) {
        return {'success': false, 'message': 'Session expired'};
      }

      // 🔧 Show status code + full API response body so we know exactly what failed
      final data =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;
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
  // 7. GET CENTERS (Dynamic Pagination - All Centers)
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
          List dynamicList = [];
          
          if (decodedBody is Map && decodedBody.containsKey('data')) {
            final innerData = decodedBody['data'];
            if (innerData is Map && innerData.containsKey('result') && innerData['result'] is List) {
              dynamicList = innerData['result'];
            }
          } else if (decodedBody is Map && decodedBody.containsKey('result') && decodedBody['result'] is List) {
            dynamicList = decodedBody['result'];
          } else if (decodedBody is List) {
            dynamicList = decodedBody;
          }

          if (dynamicList.isEmpty) {
            hasMoreData = false;
          } else {
            // Parse the current page's centers
            final pageCenters = dynamicList.map((e) => EvacuationCenter.fromJson(e)).toList();
            
            // Add ALL centers directly to the master list (no filter applied)
            allCenters.addAll(pageCenters);

            if (dynamicList.length < rowsPerPage) {
              hasMoreData = false; // Reached the last page
            } else {
              currentPage++; // Move to next page
            }
          }
        } else {
          return {
            'success': false,
            'message': 'API Error on page $currentPage: ${response.statusCode}'
          };
        }
      }

      return {'success': true, 'data': allCenters};
    } catch (e) {
      return {'success': false, 'message': 'Error parsing centers: $e'};
    }
  }

  // ----------------------------------------------------------------
  // 8. LOAD 4P's HOUSEHOLDS
  // ----------------------------------------------------------------
  Future<void> load4PsHouseholds() async {
    if (_fourPsLoaded) {
      print(
          '✅ 4Ps already loaded (${_fourPsHouseholds.length} total)');
      return;
    }

    try {
      print('🔄 Loading 4Ps households from API...');

      final response =
          await _authenticatedRequest('GET', '/profile?is4P=true');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List profiles = data['result'] ?? [];

        _fourPsHouseholds.clear();

        for (var profile in profiles) {
          final household = profile['household'];
          if (household != null && household.toString().isNotEmpty) {
            _fourPsHouseholds.add(household.toString());
          }
        }

        _fourPsLoaded = true;
        print('✅ Loaded ${_fourPsHouseholds.length} 4Ps households');
      } else {
        print('⚠️ Failed to load 4Ps: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error loading 4Ps: $e');
    }
  }

  bool isHousehold4Ps(String? householdId) {
    if (householdId == null || householdId.isEmpty) return false;
    return _fourPsHouseholds.contains(householdId);
  }

  int get fourPsHouseholdCount => _fourPsHouseholds.length;
  bool get fourPsDataLoaded => _fourPsLoaded;
}