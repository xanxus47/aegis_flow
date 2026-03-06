// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'check_in_screen.dart';
import 'check_out_screen.dart';

class HomeScreen extends StatelessWidget {
  final String? userName;
  final VoidCallback onSignOut;

  const HomeScreen({
    super.key,
    required this.userName,
    required this.onSignOut,
  });

  // Modern Color Palette mapped to login
  final Color _primaryColor = const Color(0xFF3B82F6);
  final Color _checkInColor = const Color(0xFF10B981); 
  final Color _checkOutColor = const Color(0xFFF59E0B); 

  void _navigateToCheckIn(BuildContext context) {
    Navigator.push(
      context, 
      MaterialPageRoute(builder: (_) => CheckInScreen(userName: userName, onSignOut: onSignOut))
    );
  }

  void _navigateToCheckOut(BuildContext context) {
    Navigator.push(
      context, 
      MaterialPageRoute(builder: (_) => CheckOutScreen(userName: userName, onSignOut: onSignOut))
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
                        onSignOut(); 
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), 
      body: SafeArea(
        child: ListView(
          // Adjusted padding to standard margins now that the bottom nav is gone
          padding: const EdgeInsets.all(24.0), 
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.security_rounded, color: _primaryColor, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'MDRRMO', 
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.blueGrey.shade500, letterSpacing: 1.5)
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dashboard', 
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.blueGrey.shade900)
                    ),
                  ],
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.blueGrey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                    ]
                  ),
                  child: IconButton(
                    onPressed: () => _showLogoutConfirmation(context),
                    icon: Icon(Icons.power_settings_new_rounded, color: Colors.blueGrey.shade700),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 40), 
            
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