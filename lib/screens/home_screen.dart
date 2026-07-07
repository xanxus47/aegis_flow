// lib/screens/home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'check_in_screen.dart';
import 'check_out_screen.dart';
import '../refugeex_offline/roster_sync_service.dart';
import '../refugeex_offline/sync_manager.dart';
import '../refugeex_offline/sync_state.dart';

class HomeScreen extends StatefulWidget {
  final String? userName;
  final VoidCallback onSignOut;

  const HomeScreen({
    super.key,
    required this.userName,
    required this.onSignOut,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Color _primaryColor = const Color(0xFF3B82F6);
  final Color _checkInColor = const Color(0xFF10B981);
  final Color _checkOutColor = const Color(0xFFF59E0B);

  StreamSubscription? _connectivitySub;
  StreamSubscription<SyncState>? _syncSub;
  bool _isDownloading = false;
  bool _wasSyncing = false;

  @override
  void initState() {
    super.initState();
    _tryAutoDownload();
    
    // Listen for roster downloads
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) async {
      final bool online = results.any((r) => r != ConnectivityResult.none);
      if (online && !_isDownloading) {
        final count = await RosterSyncService.instance.getRosterCount();
        if (count == 0) await _downloadRoster();
      }
    });

    // Listen for offline queue sync (check-ins / check-outs)
    _syncSub = SyncManager.instance.stateStream.listen((state) {
      if (!mounted) return;
      
      // If it was syncing and now it finished
      if (_wasSyncing && !state.isSyncing) {
        if (state.pendingActions == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.cloud_done_rounded, color: Colors.white),
                  SizedBox(width: 8),
                  Text('All offline records synced successfully!'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.cloud_off_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Sync paused. ${state.pendingActions} records still pending.')),
                ],
              ),
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
      _wasSyncing = state.isSyncing;
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _tryAutoDownload() async {
    try {
      final count = await RosterSyncService.instance.getRosterCount();
      if (count > 0) return;
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.any((r) => r != ConnectivityResult.none)) {
        await _downloadRoster();
      }
    } catch (_) {}
  }

  Future<void> _downloadRoster() async {
    if (_isDownloading || !mounted) return;
    setState(() => _isDownloading = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Downloading offline roster...'),
          duration: Duration(seconds: 60)),
    );
    try {
      await RosterSyncService.instance.downloadAndSyncRoster();
      final count = await RosterSyncService.instance.getRosterCount();
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showDownloadSuccessDialog(count);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Offline roster sync failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showDownloadSuccessDialog(int count) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                child: Icon(Icons.download_done_rounded, size: 32, color: Colors.green.shade400),
              ),
              const SizedBox(height: 24),
              Text(
                'Roster Downloaded!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade900),
              ),
              const SizedBox(height: 8),
              Text(
                '$count profiles are now available offline. You can scan anyone even without internet.',
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade500,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Got it!', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToCheckIn(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CheckInScreen(userName: widget.userName, onSignOut: widget.onSignOut))
    );
  }

  void _navigateToCheckOut(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CheckOutScreen(userName: widget.userName, onSignOut: widget.onSignOut))
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32), 
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                child: Icon(Icons.logout_rounded, size: 32, color: Colors.red.shade400),
              ),
              const SizedBox(height: 24),
              Text(
                'Sign Out', 
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade900)
              ),
              const SizedBox(height: 8),
              Text(
                'End your current session?', 
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 15)
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text('Cancel', style: TextStyle(color: Colors.blueGrey.shade400, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade500,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () { 
                        Navigator.pop(context); 
                        widget.onSignOut(); 
                      },
                      child: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: _primaryColor,
            ),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Image.asset(
                    'assets/vitality.png',
                    width: 56,
                    height: 56,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'RefugeeX',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Developed By: Argerin R. Quijano',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _checkInColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.login_rounded, color: _checkInColor, size: 20),
            ),
            title: const Text('Check In', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _navigateToCheckIn(context);
            },
          ),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _checkOutColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.logout_rounded, color: _checkOutColor, size: 20),
            ),
            title: const Text('Check Out', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _navigateToCheckOut(context);
            },
          ),
          const Spacer(),
          const Divider(height: 1),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.power_settings_new_rounded, color: Colors.red.shade400, size: 20),
            ),
            title: Text(
              'Logout',
              style: TextStyle(
                color: Colors.red.shade600,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              _showLogoutConfirmation(context);
            },
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), 
      drawer: _buildDrawer(context),
      body: SafeArea(
        child: ListView(
          // Adjusted padding to standard margins now that the bottom nav is gone
          padding: const EdgeInsets.all(24.0), 
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Builder(
                  builder: (context) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.blueGrey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                        ]
                      ),
                      child: IconButton(
                        onPressed: () => Scaffold.of(context).openDrawer(),
                        icon: _isDownloading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(Icons.menu_rounded, color: Colors.blueGrey.shade700),
                      ),
                    );
                  }
                ),
              ],
            ),
            
            const SizedBox(height: 20), 

            Text(
              'Dashboard', 
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.blueGrey.shade900)
            ),
            
            const SizedBox(height: 16),

            Text(
              'QUICK ACTIONS', 
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.blueGrey.shade400, letterSpacing: 1.5)
            ),
            const SizedBox(height: 16),

            // Action Cards
            _buildActionCard('Check In', 'Scan QR to admit evacuee', Icons.login_rounded, _checkInColor, () => _navigateToCheckIn(context)),
            const SizedBox(height: 16),
            _buildActionCard('Check Out', 'Scan QR to release evacuee', Icons.logout_rounded, _checkOutColor, () => _navigateToCheckOut(context)),
          ],
        ),
      )
    );
  }

  Widget _buildActionCard(String title, String sub, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _primaryColor.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20), 
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade900)),
                      const SizedBox(height: 4),
                      Text(sub, style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade400)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_forward_ios_rounded, color: Colors.blueGrey.shade300, size: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}