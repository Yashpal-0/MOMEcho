// frontend/lib/main.dart
import 'package:flutter/material.dart';
// Import the new pages
import 'home_page.dart';
import 'rocking_simulation_page.dart';
import 'sleep_page.dart'; // Import the new sleep page

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MomEcho', // Changed title
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFFFF0D8)), // Use a color from the design
        useMaterial3: true,
         fontFamily: 'Poppins', // Example font - add to pubspec.yaml if needed
         scaffoldBackgroundColor: Colors.white,
      ),
      // Define the initial route and other routes
      initialRoute: '/',
      routes: {
        '/': (context) => const HomePage(), // Set HomePage as the default route
        '/rocking_simulation': (context) => const RockingSimulationPage(),
        '/sleep': (context) => const SleepPage(), // Add route for SleepPage
        // Add other routes here as needed
      },
    );
  }
}