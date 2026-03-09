// lib/screens/check_in_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '/services/profile_service.dart';
import '/services/supabase_service.dart';
import '/models/profile_model.dart';
import '/models/evacuation_center_model.dart';

class CheckInScreen extends StatefulWidget {
  final String? userName;
  final VoidCallback onSignOut;

  const CheckInScreen({
    super.key,
    required this.userName,
    required this.onSignOut,
  });

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  bool _isLoadingCenters = true;
  bool _isTorchOn = false;
  bool _isOutsideEc = false;

  final ImagePicker _picker = ImagePicker();
  final ProfileService _profileService = ProfileService();
  final SupabaseService _supabaseService = SupabaseService();

  List<EvacuationCenter> _allCenters = [];
  List<String> _barangayList = [];
  List<EvacuationCenter> _filteredCenters = [];

  String? _selectedBarangay;
  EvacuationCenter? _selectedCenter;

  final Map<String, DateTime> _scanCooldowns = {};

  final List<String> _vulnerabilityOptions = [
    'Pregnant',
    'Lactating Mother',
    'Child-Headed Family',
    'Single-Headed Family',
    'Solo Parent',
    'Person With Disability',
    'Indigenous People',
    "4P's Beneficiaries",
    'LGBTQIA+',
  ];

  final Color _primaryColor = const Color(0xFF2563EB);
  final Color _overlayColor = const Color(0x99000000);

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    _loadCenters();
  }

  Future<void> _loadCenters() async {
    if (!mounted) return;
    setState(() => _isLoadingCenters = true);

    try {
      final res = await _profileService.getEvacuationCenters();
      if (mounted) {
        setState(() {
          if (res['success']) {
            _allCenters = res['data'] as List<EvacuationCenter>;
            final barangays = _allCenters
                .map((c) => c.barangay)
                .where((b) => b.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
            _barangayList = barangays;
          }
          _isLoadingCenters = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCenters = false);
        _showErrorDialog("Connection Error", "Could not connect to server.\n$e");
      }
    }
  }

  void _onBarangayChanged(String? barangay) {
    setState(() {
      _selectedBarangay = barangay;
      _selectedCenter = null;
      _filteredCenters = barangay == null
          ? []
          : _allCenters.where((c) => c.barangay == barangay).toList();
    });
  }

  void _toggleFlash() {
    _controller?.toggleTorch();
    setState(() => _isTorchOn = !_isTorchOn);
  }

  // ----------------------------------------------------------------
  // LOCATION HELPER
  // ----------------------------------------------------------------
  Future<Position?> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint('Location error: $e');
      return null;
    }
  }

  // ----------------------------------------------------------------
  // SCAN HANDLER
  // ----------------------------------------------------------------
  void _handleScan(String rawData) async {
    if (_isProcessing || _selectedCenter == null) return;

    if (_scanCooldowns.containsKey(rawData)) {
      if (DateTime.now().difference(_scanCooldowns[rawData]!).inSeconds < 5) return;
    }
    _scanCooldowns[rawData] = DateTime.now();

    setState(() => _isProcessing = true);
    _controller?.stop();

    try {
      final id = _profileService.extractProfileId(rawData);
      if (id == null) throw "Invalid QR Code format";

      final profileRes = await _profileService.getProfileDetails(id);

      if (!profileRes['success']) {
        final msg = profileRes['message']?.toString() ?? "Profile not found";
        if (msg.contains('Session expired')) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Session expired. Please log in again.'),
                backgroundColor: Colors.red),
          );
          widget.onSignOut();
          return;
        }
        throw msg;
      }

      final Profile profile = profileRes['data'];
      if (mounted) _showVulnerabilityDialog(profile, id);
    } catch (e) {
      if (mounted) _showErrorDialog("Scan Error", e.toString());
    }
  }

  // ----------------------------------------------------------------
  // VULNERABILITY DIALOG
  // ----------------------------------------------------------------
  void _showVulnerabilityDialog(Profile profile, String id) {
    List<String> selectedOptions = [];
    _isOutsideEc = false;
    final TextEditingController hostAddressController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Assessment"),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Text("Profile:",
                        style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                    Text(profile.fullName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: _isOutsideEc
                            ? Colors.orange.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _isOutsideEc ? Colors.orange : Colors.green),
                      ),
                      child: SwitchListTile(
                        title: Text(
                          _isOutsideEc
                              ? "Outside EC (Home-based)"
                              : "Inside Evacuation Center",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _isOutsideEc
                                ? Colors.deepOrange
                                : Colors.green[800],
                          ),
                        ),
                        subtitle: Text(
                          _isOutsideEc
                              ? "Staying at relative's house"
                              : "Physically in center",
                          style: const TextStyle(fontSize: 11),
                        ),
                        value: _isOutsideEc,
                        activeColor: Colors.deepOrange,
                        onChanged: (val) {
                          setDialogState(() {
                            _isOutsideEc = val;
                            // Clear address when toggling back to inside EC
                            if (!val) hostAddressController.clear();
                          });
                        },
                      ),
                    ),

                    // ── HOST ADDRESS FIELD (slides in when Outside EC is ON) ──
                    if (_isOutsideEc) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.home_outlined,
                                    size: 15, color: Colors.deepOrange[400]),
                                const SizedBox(width: 6),
                                Text(
                                  "Host Address / Location",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.deepOrange[700],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "(required)",
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.deepOrange[300]),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: hostAddressController,
                              maxLines: 2,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText:
                                    "e.g. House of Juan dela Cruz, Purok 3, Nicolas",
                                hintStyle: TextStyle(
                                    fontSize: 12, color: Colors.grey[400]),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: Colors.orange.shade300),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: Colors.deepOrange, width: 1.5),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: Colors.orange.shade200),
                                ),
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const Divider(height: 24),
                    Text("Vulnerabilities:",
                        style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                    ..._vulnerabilityOptions.map((option) {
                      final isChecked = selectedOptions.contains(option);
                      return CheckboxListTile(
                        title: Text(option),
                        value: isChecked,
                        dense: true,
                        activeColor: _primaryColor,
                        onChanged: (bool? val) {
                          setDialogState(() {
                            if (val == true) {
                              selectedOptions.add(option);
                            } else {
                              selectedOptions.remove(option);
                            }
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    hostAddressController.dispose();
                    Navigator.pop(context);
                    _resetScanner();
                  },
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Require host address when outside EC
                    if (_isOutsideEc &&
                        hostAddressController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Please enter the host address for outside-EC evacuee.'),
                          backgroundColor: Colors.deepOrange,
                        ),
                      );
                      return;
                    }
                    final String? hostAddress = _isOutsideEc
                        ? hostAddressController.text.trim()
                        : null;
                    hostAddressController.dispose();
                    Navigator.pop(context);
                    _takeProofPhotoAndCheckIn(
                        profile, id, selectedOptions,
                        hostAddress: hostAddress);
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor),
                  child: const Text("Next: Take Photo",
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ----------------------------------------------------------------
  // PHOTO + LOCATION + TIMESTAMP CAPTURE
  // ----------------------------------------------------------------
  Future<void> _takeProofPhotoAndCheckIn(
      Profile profile, String id, List<String> vulnerabilities,
      {String? hostAddress}) async {
    try {
      // Capture timestamp BEFORE opening camera
      final DateTime checkInTimestamp = DateTime.now();

      // Request location BEFORE opening camera (runs in parallel with camera open)
      final Future<Position?> locationFuture = _getCurrentLocation();

      // Stop the scanner and turn off its torch BEFORE handing the camera
      // to image_picker. Both compete for the same hardware — if the scanner
      // torch stays on it holds the camera resource and the native camera
      // flash won't work.
      if (_isTorchOn) {
        await _controller?.toggleTorch();
      }
      await _controller?.stop();

      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 50,
        maxWidth: 800,
      );

      // Scanner will be restarted by _resetScanner() / _processCheckIn flow
      if (photo == null) {
        // User cancelled — restart scanner and restore torch state
        await _controller?.start();
        if (_isTorchOn) await _controller?.toggleTorch();
        _resetScanner();
        return;
      }

      setState(() => _isProcessing = true);

      // Await location result (may already be resolved by now)
      final Position? position = await locationFuture;

      final double? latitude = position?.latitude;
      final double? longitude = position?.longitude;

      debugPrint('📍 Location: $latitude, $longitude');
      debugPrint('🕐 Timestamp: $checkInTimestamp');

      final File file = File(photo.path);
      final String fileName =
          'proof_${id}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await Supabase.instance.client.storage
          .from('checkin-proofs')
          .upload(fileName, file);

      final String proofUrl = Supabase.instance.client.storage
          .from('checkin-proofs')
          .getPublicUrl(fileName);

      await _processCheckIn(
        profile,
        id,
        proofUrl,
        vulnerabilities,
        latitude: latitude,
        longitude: longitude,
        checkInTimestamp: checkInTimestamp,
        hostAddress: hostAddress,
      );
    } catch (e) {
      debugPrint("PHOTO ERROR: $e");

      // Ensure scanner is restarted on any error path
      await _controller?.start();
      if (_isTorchOn) await _controller?.toggleTorch();

      if (e.toString().contains('JWT') || e.toString().contains('Auth')) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Session expired. Please log in again.'),
              backgroundColor: Colors.red),
        );
        widget.onSignOut();
        return;
      }

      if (mounted)
        _showErrorDialog("Photo Error", "Failed to upload proof: $e");
    }
  }

  // ----------------------------------------------------------------
  // PROCESS CHECK-IN (now receives lat/lng + timestamp)
  // ----------------------------------------------------------------
  Future<void> _processCheckIn(
    Profile profile,
    String id,
    String? proofUrl,
    List<String> vulnerabilities, {
    double? latitude,
    double? longitude,
    DateTime? checkInTimestamp,
    String? hostAddress,
  }) async {
    if (_selectedCenter == null) return;

    setState(() => _isProcessing = true);

    try {
      final apiRes = await _profileService.checkInEvacuee(id, _selectedCenter!.id);

      if (apiRes['success'] != true) {
        if (apiRes['message'].toString().contains('Session expired')) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Session expired. Please log in again.'),
                backgroundColor: Colors.red),
          );
          widget.onSignOut();
          return;
        }
        throw apiRes['message'] ?? 'API Check-In Failed';
      }

      await _supabaseService.trackEvacueeCheckIn(
        profileId: id,
        fullName: profile.fullName,
        evacuationCenterId: _selectedCenter!.id,
        evacuationCenterName: _selectedCenter!.name,
        age: profile.age?.toString(),
        sex: profile.sex,
        barangay: profile.barangay,
        household: profile.household,
        proofImage: proofUrl,
        isPregnant: vulnerabilities.contains('Pregnant'),
        isLactating: vulnerabilities.contains('Lactating Mother'),
        isChildHeaded: vulnerabilities.contains('Child-Headed Family'),
        isSingleHeaded: vulnerabilities.contains('Single-Headed Family'),
        isSoloParent: vulnerabilities.contains('Solo Parent'),
        isPwd: vulnerabilities.contains('Person With Disability'),
        isIp: vulnerabilities.contains('Indigenous People'),
        is4Ps: vulnerabilities.contains("4P's Beneficiaries"),
        isLgbt: vulnerabilities.contains('LGBTQIA+'),
        isOutsideEc: _isOutsideEc,
        latitude: latitude,
        longitude: longitude,
        checkInTimestamp: checkInTimestamp,
        hostAddress: hostAddress,
      );

      if (mounted) _showSuccessDialog(profile.fullName, latitude, longitude, checkInTimestamp, hostAddress: hostAddress);
    } catch (e) {
      debugPrint("CHECK-IN ERROR: $e");

      if (e.toString().contains('JWT') || e.toString().contains('Auth')) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Session expired. Please log in again.'),
              backgroundColor: Colors.red),
        );
        widget.onSignOut();
        return;
      }

      if (mounted) _showErrorDialog("Sync Error", "Check-In failed:\n\n$e");
    }
  }

  // ----------------------------------------------------------------
  // SELECT LOCATION SCREEN
  // ----------------------------------------------------------------
  Widget _buildSelectLocationScreen() {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Select Location",
            style: TextStyle(color: Colors.white)),
        backgroundColor: _primaryColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadCenters,
            tooltip: "Refresh",
          ),
        ],
      ),
      body: _isLoadingCenters
          ? const Center(child: CircularProgressIndicator())
          : _allCenters.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_off_outlined,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        "No Active Centers Found",
                        style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Ask admin to open a center\nor try refreshing.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadCenters,
                        icon: const Icon(Icons.refresh),
                        label: const Text("Refresh"),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Where are you scanning?",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Select a barangay first, then choose the evacuation center.",
                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 32),

                      _buildDropdownLabel("Barangay", Icons.map_outlined),
                      const SizedBox(height: 8),
                      _buildDropdown<String>(
                        value: _selectedBarangay,
                        hint: "Select barangay...",
                        items: _barangayList
                            .map((b) => DropdownMenuItem(
                                  value: b,
                                  child: Text(b),
                                ))
                            .toList(),
                        onChanged: _onBarangayChanged,
                      ),

                      const SizedBox(height: 24),

                      _buildDropdownLabel(
                          "Evacuation Center", Icons.location_on_outlined),
                      const SizedBox(height: 8),
                      _buildDropdown<EvacuationCenter>(
                        value: _selectedCenter,
                        hint: _selectedBarangay == null
                            ? "Pick a barangay first..."
                            : _filteredCenters.isEmpty
                                ? "No centers in this barangay"
                                : "Select evacuation center...",
                        items: _filteredCenters
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c.name,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: _filteredCenters.isEmpty
                            ? null
                            : (val) => setState(() => _selectedCenter = val),
                      ),

                      const SizedBox(height: 40),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _selectedCenter == null
                              ? null
                              : () {
                                  setState(() {});
                                  _resetScanner();
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            disabledBackgroundColor: Colors.grey[300],
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(
                            _selectedCenter == null
                                ? "Select a center to continue"
                                : "Start Scanning at ${_selectedCenter!.name}",
                            style: TextStyle(
                              color: _selectedCenter == null
                                  ? Colors.grey[500]
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildDropdownLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _primaryColor),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.grey[700])),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: Text(hint,
              style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          items: items,
          onChanged: onChanged,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: onChanged == null ? Colors.grey[300] : _primaryColor),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // SCANNER SCREEN
  // ----------------------------------------------------------------
  Widget _buildScannerScreen() {
    return Scaffold(
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _handleScan(barcode.rawValue!);
                  break;
                }
              }
            },
          ),
          CustomPaint(
            painter: ScannerOverlayPainter(_overlayColor),
            child: const SizedBox.expand(),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 10,
                bottom: 16,
                left: 20,
                right: 20,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.transparent
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => setState(() {
                      _selectedCenter = null;
                      _isProcessing = false;
                      _isTorchOn = false;
                    }),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Checking in to:",
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        Text(
                          _selectedCenter!.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: _isTorchOn
                          ? Colors.amber.withOpacity(0.3)
                          : Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: _isTorchOn ? Colors.amber : Colors.white24,
                          width: 2),
                    ),
                    child: IconButton(
                      icon: Icon(
                          _isTorchOn ? Icons.flash_on : Icons.flash_off,
                          color: _isTorchOn ? Colors.amber : Colors.white),
                      onPressed: _toggleFlash,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _selectedCenter = null;
                      _selectedBarangay = null;
                      _filteredCenters = [];
                      _isProcessing = false;
                      _isTorchOn = false;
                    }),
                    icon: const Icon(Icons.edit, color: Colors.white, size: 16),
                    label: const Text("Change",
                        style: TextStyle(color: Colors.white)),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white24,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text("Processing...",
                        style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedCenter == null) return _buildSelectLocationScreen();
    return _buildScannerScreen();
  }

  // ----------------------------------------------------------------
  // DIALOGS
  // ----------------------------------------------------------------
  void _showSuccessDialog(
    String name,
    double? latitude,
    double? longitude,
    DateTime? timestamp, {
    String? hostAddress,
  }) {
    final String formattedTime = timestamp != null
        ? '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}  '
          '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}'
        : 'N/A';

    final String locationText = (latitude != null && longitude != null)
        ? '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}'
        : 'Location unavailable';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: hostAddress != null
                        ? Colors.orange.shade50
                        : Colors.green.shade50,
                    shape: BoxShape.circle),
                child: Icon(
                  hostAddress != null ? Icons.home_outlined : Icons.check_rounded,
                  size: 48,
                  color: hostAddress != null ? Colors.deepOrange : Colors.green,
                ),
              ),
              const SizedBox(height: 20),
              const Text("Check-In Successful",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              // Outside EC badge
              if (hostAddress != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.home_outlined,
                          size: 13, color: Colors.deepOrange[700]),
                      const SizedBox(width: 4),
                      Text("Outside EC — Home-based",
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange[700])),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                "$name has been verified and checked in to ${_selectedCenter?.name}.",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey[600], fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 16),

              // ── SUMMARY CARD ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    // Date & Time
                    _buildSummaryRow(
                      icon: Icons.access_time_rounded,
                      iconColor: Colors.grey[500]!,
                      label: "Date & Time",
                      value: formattedTime,
                      valueColor: Colors.black87,
                    ),
                    const SizedBox(height: 10),
                    // Location
                    _buildSummaryRow(
                      icon: latitude != null
                          ? Icons.location_on_rounded
                          : Icons.location_off_rounded,
                      iconColor:
                          latitude != null ? Colors.blue[400]! : Colors.grey[400]!,
                      label: "Location (Lat, Lng)",
                      value: locationText,
                      valueColor:
                          latitude != null ? Colors.black87 : Colors.grey[400]!,
                    ),
                    // Host address (only when outside EC)
                    if (hostAddress != null) ...[
                      const SizedBox(height: 10),
                      _buildSummaryRow(
                        icon: Icons.home_outlined,
                        iconColor: Colors.deepOrange[400]!,
                        label: "Host Address",
                        value: hostAddress,
                        valueColor: Colors.deepOrange[700]!,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _resetScanner();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        hostAddress != null ? Colors.deepOrange : Colors.green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Scan Next Evacuee",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w600)),
              Text(value,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: valueColor)),
            ],
          ),
        ),
      ],
    );
  }

  void _showErrorDialog(String title, String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.red.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.warning_amber_rounded,
                    size: 32, color: Colors.redAccent),
              ),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(msg,
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 14)),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _resetScanner();
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.grey.shade100,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Dismiss"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resetScanner() {
    if (mounted) {
      setState(() => _isProcessing = false);
      _controller?.start();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

// ----------------------------------------------------------------
// SCANNER OVERLAY PAINTER
// ----------------------------------------------------------------
class ScannerOverlayPainter extends CustomPainter {
  final Color overlayColor;

  ScannerOverlayPainter(this.overlayColor);

  @override
  void paint(Canvas canvas, Size size) {
    final double scanAreaSize = size.width * 0.7;
    final Rect scanArea = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: scanAreaSize,
      height: scanAreaSize,
    );

    final Path path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
          RRect.fromRectAndRadius(scanArea, const Radius.circular(24)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, Paint()..color = overlayColor);

    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    const double cornerLength = 30;

    canvas.drawLine(Offset(scanArea.left, scanArea.top + cornerLength),
        Offset(scanArea.left, scanArea.top), borderPaint);
    canvas.drawLine(Offset(scanArea.left, scanArea.top),
        Offset(scanArea.left + cornerLength, scanArea.top), borderPaint);
    canvas.drawLine(Offset(scanArea.right - cornerLength, scanArea.top),
        Offset(scanArea.right, scanArea.top), borderPaint);
    canvas.drawLine(Offset(scanArea.right, scanArea.top),
        Offset(scanArea.right, scanArea.top + cornerLength), borderPaint);
    canvas.drawLine(
        Offset(scanArea.left, scanArea.bottom - cornerLength),
        Offset(scanArea.left, scanArea.bottom),
        borderPaint);
    canvas.drawLine(Offset(scanArea.left, scanArea.bottom),
        Offset(scanArea.left + cornerLength, scanArea.bottom), borderPaint);
    canvas.drawLine(
        Offset(scanArea.right - cornerLength, scanArea.bottom),
        Offset(scanArea.right, scanArea.bottom),
        borderPaint);
    canvas.drawLine(
        Offset(scanArea.right, scanArea.bottom - cornerLength),
        Offset(scanArea.right, scanArea.bottom),
        borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}