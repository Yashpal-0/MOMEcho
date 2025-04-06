// frontend/lib/home_page.dart
import 'package:flutter/material.dart';
import 'dart:math'; // Added for pi constant

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 1; // Default to Home tab

  void _onItemTapped(int index) {
    // Check if the selected index corresponds to the Sleep tab (index 2)
    if (index == 2) {
      Navigator.pushNamed(context, '/sleep'); // Navigate to SleepPage route
    } else {
      // Handle other tabs or just update the index if they are part of HomePage itself
      // Prevent rebuilding the HomePage if the tapped index is already selected for non-navigating items
      if (index != _selectedIndex) {
         setState(() {
          _selectedIndex = index;
          // Example: if Camera/Settings were separate pages and needed navigation:
          // if (index == 0) Navigator.pushNamed(context, '/camera');
          // if (index == 3) Navigator.pushNamed(context, '/settings');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: () {}),
        actions: [
          IconButton(icon: const Icon(Icons.notifications_none), onPressed: () {})
        ],
        backgroundColor: Colors.white, // Or transparent
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView( // Use ListView to allow scrolling if content overflows
        children: const [
          _HeaderSection(),
          SizedBox(height: 20),
          _TemperatureSection(),
          SizedBox(height: 30),
          _FeaturesGrid(),
          SizedBox(height: 20),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.videocam_outlined), label: 'Camera'),
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.bedtime_outlined), label: 'Sleep'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.amber[800], // Theme color
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true, // Show labels for all items
        type: BottomNavigationBarType.fixed, // Ensure all labels are visible
        onTap: _onItemTapped,
        backgroundColor: const Color(0xFFFFF0D8), // Light yellow/orange background
        elevation: 5,
      ),
       backgroundColor: Colors.white, // Main background
    );
  }
}

// --- Sections for HomePage ---

class _HeaderSection extends StatelessWidget {
  const _HeaderSection();

  @override
  Widget build(BuildContext context) {
    // Placeholder for the curved background and baby image
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF0D8), // Light yellow/orange
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hello,', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
              Text('Mom', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.redAccent)),
            ],
          ),
          // Placeholder for baby image
          Transform.rotate(
             angle: -22 * pi / 180, // Rotate 45 degrees left (negative angle)
             child:Image.asset("assets/baby_sleeping.png"),
          ),
        ],
      ),
    );
  }
}

class _TemperatureSection extends StatelessWidget {
  const _TemperatureSection();

  @override
  Widget build(BuildContext context) {
    // Placeholder for the circular temperature gauge
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
             BoxShadow(color: Colors.grey.withOpacity(0.3), spreadRadius: 2, blurRadius: 5)
          ],
          border: Border.all(color: Colors.blue.shade100, width: 8)
        ),
        child: const Column(
          children: [
            Text('24°', style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.redAccent)),
            Text('Room Temperature', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _FeaturesGrid extends StatelessWidget {
  const _FeaturesGrid();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true, // Important for GridView inside ListView
        physics: const NeverScrollableScrollPhysics(), // Disable GridView's scrolling
        crossAxisSpacing: 15,
        mainAxisSpacing: 15,
        children: const [
          // Navigate on tap
          _FeatureButton(label: 'Rocking\nPatterns', icon: Icons.chair_outlined, routeName: '/rocking_simulation', isHighlighted: true),
          _FeatureButton(label: 'Smart\nSystems', icon: Icons.home_work_outlined, routeName: null), // Add routes later
          _FeatureButton(label: 'Air\nQuality', icon: Icons.air, routeName: null),
          _FeatureButton(label: 'Trackers', icon: Icons.track_changes, routeName: null),
          _FeatureButton(label: 'Light\nDiffuser', icon: Icons.lightbulb_outline, routeName: null),
          // Add an empty container or another button if needed for alignment
        ],
      ),
    );
  }
}

class _FeatureButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? routeName; // Route to navigate to on tap
  final bool isHighlighted;

  const _FeatureButton({
    required this.label,
    required this.icon,
    this.routeName,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (routeName != null) {
          Navigator.pushNamed(context, routeName!);
        } else {
          // Optional: Show a snackbar or message for unimplemented features
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$label feature not implemented yet.'))
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: isHighlighted ? const Color(0xFFFFF0D8) : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
             BoxShadow(color: Colors.grey.withOpacity(0.2), spreadRadius: 1, blurRadius: 3)
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Colors.grey[800]),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
