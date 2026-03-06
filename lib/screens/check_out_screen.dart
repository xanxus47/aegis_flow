// lib/screens/check_out_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '/services/profile_service.dart';
import '/services/supabase_service.dart';

class CheckOutScreen extends StatefulWidget {
  final String? userName;
  final VoidCallback onSignOut;
  const CheckOutScreen(
      {super.key, required this.userName, required this.onSignOut});

  @override
  State<CheckOutScreen> createState() => _CheckOutScreenState();
}

class _CheckOutScreenState extends State<CheckOutScreen> {
  MobileScannerController? _controller;
  bool _isProcessing = false;

  final ProfileService _profileService = ProfileService();
  final SupabaseService _supabaseService = SupabaseService();
  final Map<String, DateTime> _scanCooldowns = {};

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
  }

  void _handleScan(String rawData) async {
    if (_isProcessing) return;

    if (_scanCooldowns.containsKey(rawData)) {
      if (DateTime.now().difference(_scanCooldowns[rawData]!).inSeconds < 5) {
        return;
      }
    }
    _scanCooldowns[rawData] = DateTime.now();

    setState(() => _isProcessing = true);
    _controller?.stop();

    try {
      final id = _profileService.extractProfileId(rawData);
      if (id == null) throw "Invalid QR Code";

      final List<dynamic> checkInRecord = await Supabase.instance.client
          .from('evacuee_details')
          .select()
          .eq('profile_id', id)
          .eq('is_checked_in', true)
          .limit(1);

      if (checkInRecord.isEmpty) {
        throw "This person is NOT checked in (Database Record Not Found).";
      }

      final String fullName = checkInRecord[0]['full_name'] ?? "Unknown";
      final String centerId =
          checkInRecord[0]['evacuation_center_id']?.toString() ?? "";

      if (centerId.isEmpty) {
        throw "Could not determine which evacuation center this person is in.";
      }

      if (mounted) _showCheckOutDialog(fullName, id, centerId);
    } catch (e) {
      if (e.toString().contains('JWT') || e.toString().contains('Auth')) {
        if (!mounted) return; // ✅ FIXED: Added mounted check
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Session expired. Please log in again.'),
            backgroundColor: Colors.red));
        widget.onSignOut();
        return;
      }

      if (mounted) {
        _showErrorDialog(
            "Scan Error", e.toString().replaceAll("Exception: ", ""));
      }
    }
  }

  Future<void> _processCheckOut(
      String fullName, String id, String centerId) async {
    setState(() => _isProcessing = true);

    try {
      // 1. Call Lester's API
      final apiRes = await _profileService.checkOutEvacuee(id, centerId);

      if (apiRes['success'] != true) {
        if (apiRes['message'].toString().contains('Session expired')) {
          if (!mounted) return; // ✅ FIXED: Added mounted check
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Session expired. Please log in again.'),
              backgroundColor: Colors.red));
          widget.onSignOut();
          return;
        }
        // 🔧 Show full API error details
        throw 'API Error: ${apiRes['message']}';
      }

      // 2. Sync with Supabase
      await _supabaseService.trackEvacueeCheckOut(profileId: id);

      if (mounted) _showSuccessDialog(fullName);
    } catch (e) {
      print("CHECK-OUT ERROR: $e");

      if (e.toString().contains('JWT') || e.toString().contains('Auth')) {
        if (!mounted) return; // ✅ FIXED: Added mounted check
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Session expired. Please log in again.'),
            backgroundColor: Colors.red));
        widget.onSignOut();
        return;
      }

      if (mounted) {
        _showErrorDialog("Check-Out Failed",
            e.toString().replaceAll("Exception: ", ""));
      }
    }
  }

  // ----------------------------------------------------------------
  // DIALOGS
  // ----------------------------------------------------------------
  void _showCheckOutDialog(String name, String id, String centerId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildModernDialog(
        title: "Confirm Check Out",
        icon: Icons.logout_rounded,
        iconColor: Colors.amber,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              "Are you sure you want to check out this evacuee?",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetScanner();
            },
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _processCheckOut(name, id, centerId);
            },
            child:
                const Text("Confirm", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String name) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildModernDialog(
        title: "Success",
        icon: Icons.check_circle_rounded,
        iconColor: Colors.green,
        content:
            Text("$name has been checked out.", textAlign: TextAlign.center),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(context);
                _resetScanner();
              },
              child:
                  const Text("Scan Next", style: TextStyle(color: Colors.white)),
            ),
          )
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildModernDialog(
        title: title,
        icon: Icons.error_outline_rounded,
        iconColor: Colors.red,
        content:
            SingleChildScrollView(child: Text(msg, textAlign: TextAlign.center)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetScanner();
            },
            child: const Text("Dismiss"),
          )
        ],
      ),
    );
  }

  Widget _buildModernDialog({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget content,
    required List<Widget> actions,
  }) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: iconColor),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 20)),
        ],
      ),
      content: content,
      actions: actions,
      contentPadding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
    );
  }

  void _resetScanner() {
    if (mounted) {
      setState(() => _isProcessing = false);
      _controller?.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 254, 254),
      appBar: AppBar(
        title: const Text("Check-Out",
            style: TextStyle(color: Colors.white)),
        backgroundColor: _primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.flash_on, color: Colors.white),
              onPressed: () => _controller?.toggleTorch()),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
              controller: _controller!,
              onDetect: (c) {
                if (c.barcodes.isNotEmpty) {
                  _handleScan(c.barcodes.first.rawValue!);
                }
              }),
          Container(
            decoration: ShapeDecoration(
              shape: CheckOutOverlayShape(
                cutoutWidth: 280,
                cutoutHeight: 280,
                overlayColor: _overlayColor,
              ),
            ),
          ),
          Center(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white54, width: 2),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.5),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                "Scan to Check Out",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                  child: CircularProgressIndicator(color: Colors.white)),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

class CheckOutOverlayShape extends ShapeBorder {
  final double cutoutWidth;
  final double cutoutHeight;
  final Color overlayColor;

  const CheckOutOverlayShape({
    this.cutoutWidth = 300,
    this.cutoutHeight = 300,
    this.overlayColor = const Color(0x99000000),
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: rect.center,
              width: cutoutWidth,
              height: cutoutHeight),
          const Radius.circular(20)));
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRect(rect)
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: rect.center,
              width: cutoutWidth,
              height: cutoutHeight),
          const Radius.circular(20)))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    canvas.drawPath(getOuterPath(rect), Paint()..color = overlayColor);
  }

  @override
  ShapeBorder scale(double t) => this;
}