import 'package:flutter/material.dart';
// For Color.lerp
import 'dart:async'; // Import for Stream

// Need to import the state enum definition
import 'rocking_simulation_page.dart' show BabyState, stateToString;

const int GRID_SIZE = 32; // Increased from 16

class HeatmapPage extends StatefulWidget {
  // Accept the combined stream and initial data
  final Stream<(List<List<int>>, BabyState)> matrixAndStateStream;
  final (List<List<int>>, BabyState) initialData;

  const HeatmapPage({super.key, required this.matrixAndStateStream, required this.initialData});

  @override
  State<HeatmapPage> createState() => _HeatmapPageState();
}

class _HeatmapPageState extends State<HeatmapPage> {
  // Function to map pressure value (0-255) to 8 discrete colors
  Color _getColorFromPressure(int pressure) {
    // Define 8 color levels
    const List<Color> colorLevels = [
      Colors.grey, // Level 0 (No/Very low pressure)
      Color(0xFF00FFFF), // Level 1: Cyan
      Color(0xFF00CCFF), // Level 2: Light Blue
      Color(0xFF0099FF), // Level 3: Blue
      Color(0xFF00FF00), // Level 4: Green
      Color(0xFFFFFF00), // Level 5: Yellow
      Color(0xFFFF9900), // Level 6: Orange
      Color(0xFFFF0000), // Level 7: Red (Highest pressure)
    ];

    // Determine the level based on pressure value (0-255)
    int level = (pressure / 32).floor().clamp(0, colorLevels.length - 1);

    // Special case for very low pressure - map to the lowest visible color level (Cyan)
    if (pressure < 10) {
        // Return Cyan (Level 1) instead of Transparent (Level 0)
        return colorLevels[0];
    }

    return colorLevels[level];

    /* Previous continuous gradient logic:
    // Normalize pressure to 0.0 - 1.0
    double normalized = pressure.clamp(0, 255) / 255.0;
    // Linear interpolation: Blue (low) -> Green (mid) -> Red (high)
    if (normalized < 0.5) {
      // Interpolate between blue and green
      return Color.lerp(Colors.blue, Colors.green, normalized * 2) ?? Colors.grey;
    } else {
      // Interpolate between green and red
      return Color.lerp(Colors.green, Colors.red, (normalized - 0.5) * 2) ?? Colors.grey;
    }
    */
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pressure Heatmap & State (Live)'), // Updated title
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      // Use StreamBuilder with the combined record type
      body: StreamBuilder<(List<List<int>>, BabyState)>(
        stream: widget.matrixAndStateStream,
        initialData: widget.initialData,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // Extract matrix and state from the snapshot data (record)
          final currentMatrix = snapshot.data!.$1; // Access matrix via .$1
          final currentState = snapshot.data!.$2; // Access state via .$2
          final List<int> flatList = currentMatrix.expand((row) => row).toList();

          return Column( // Use Column to stack heatmap and state text
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
                Padding(
                  padding: const EdgeInsets.all(16.0), // Add padding around heatmap
                  child: AspectRatio( // Maintain square aspect ratio
                    aspectRatio: 1.0,
                    child: GridView.builder(
                      itemCount: GRID_SIZE * GRID_SIZE,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: GRID_SIZE,
                        mainAxisSpacing: 1.0, // Small spacing between cells
                        crossAxisSpacing: 1.0,
                      ),
                      itemBuilder: (context, index) {
                        int pressure = flatList[index];
                        return Container(
                          color: _getColorFromPressure(pressure),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20), // Spacing
                // Display the current baby state
                Text(
                  'Baby State: ${stateToString(currentState)}', 
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                ),
                const SizedBox(height: 20), // Bottom padding
             ],
          );
        },
      ),
    );
  }
} 