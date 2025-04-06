// frontend/lib/sleep_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';
import 'rocking_simulation_page.dart' show BabyState; // For enum comparison
// Potentially import a charting library later, e.g.:
// import 'package:fl_chart/fl_chart.dart';

// Represents a single sleep/wake period
class SleepInterval {
  final DateTime start;
  final DateTime end;
  final bool isAsleep;

  SleepInterval({required this.start, required this.end, required this.isAsleep});

  Duration get duration => end.difference(start);
}

class SleepPage extends StatefulWidget {
  const SleepPage({super.key});

  @override
  State<SleepPage> createState() => _SleepPageState();
}

class _SleepPageState extends State<SleepPage> {
  // State variables for selected tab and day (can be expanded later)
  int _selectedTimeRangeIndex = 2; // 0: Weekly, 1: Month, 2: Day
  int _selectedDayIndex = 4; // Index for Friday

  final List<bool> _timeRangeSelection = [false, false, true]; // Default to Day selected
  final List<String> _daysOfWeek = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
  final List<String> _dates = ['19', '20', '21', '22', '23', '24', '25'];

  List<SleepInterval> _processedIntervals = [];
  Duration _totalSleepDuration = Duration.zero;
  int _wakeUps = 0;
  DateTime? _lastWakeUpTime;
  DateTime? _displayDayStart; // Store the start of the displayed day period

  // Represents the compressed 24-hour cycle (10 minutes real time)
  final Duration _compressedDayDuration = const Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _loadAndProcessHistory();
  }

  Future<void> _loadAndProcessHistory() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? historyJson = prefs.getStringList('stateHistory');
    List<(String, String)> history = [];

    if (historyJson != null) {
        print("Loaded ${historyJson.length} history entries from JSON."); // DEBUG
        history = historyJson.map((item) {
             try {
                final decoded = jsonDecode(item) as Map<String, dynamic>;
                return (decoded['ts'] as String, decoded['st'] as String);
             } catch (e) { 
                print("Error decoding history item: $item, Error: $e"); // DEBUG
                return null; 
             }
        }).where((item) => item != null).cast<(String, String)>().toList();
    } else {
        print("No history JSON found in SharedPreferences."); // DEBUG
    }

    if (history.isEmpty) {
        print("History is empty after loading/parsing."); // DEBUG
        if (mounted) setState(() {});
        return;
    }
    print("Parsed ${history.length} valid history entries."); // DEBUG

    // Sort history by timestamp
    history.sort((a, b) => DateTime.parse(a.$1).compareTo(DateTime.parse(b.$1)));

    List<SleepInterval> intervals = [];
    Duration currentTotalSleep = Duration.zero;
    int currentWakeUps = 0;
    DateTime? lastWakeTime;

    // Process the history into intervals
    print("--- Processing all intervals ---"); // DEBUG
    for (int i = 0; i < history.length; i++) {
        final currentTimestamp = DateTime.parse(history[i].$1);
        final currentStateStr = history[i].$2;
        final bool currentlyAsleep = currentStateStr == BabyState.asleep.toString().split('.').last;

        // Determine the end time (either next event or now)
        final DateTime endTime = (i + 1 < history.length)
            ? DateTime.parse(history[i + 1].$1)
            : DateTime.now(); // Assume current state continues until now

        // DEBUG: Print each raw interval
        // print("Interval ${i}: Start=${currentTimestamp}, End=${endTime}, State=${currentStateStr}, IsAsleep=${currentlyAsleep}");

        intervals.add(SleepInterval(
            start: currentTimestamp,
            end: endTime,
            isAsleep: currentlyAsleep
        ));

        if (currentlyAsleep) {
            currentTotalSleep += endTime.difference(currentTimestamp);
        }

        // Track wake-ups: transition from asleep to not asleep
        if (i > 0) {
           final previousStateStr = history[i-1].$2;
           final bool wasAsleep = previousStateStr == BabyState.asleep.toString().split('.').last;
           if (wasAsleep && !currentlyAsleep) {
               currentWakeUps++;
               lastWakeTime = currentTimestamp;
           }
        }
    }
    print("--- Finished processing all intervals (${intervals.length}) ---"); // DEBUG

    // --- Calculate Date Range based on Latest History Entry ---
    if (history.isEmpty) { // Should not happen due to earlier check, but safe guard
       print("Cannot determine date range, history is empty.");
       return; 
    }
    // Get the timestamp of the very last recorded event
    DateTime lastEventTime = DateTime.parse(history.last.$1);

    // Define the 24-hour window ending at the last event
    DateTime targetDayEnd = lastEventTime;
    DateTime targetDayStart = targetDayEnd.subtract(const Duration(hours: 24));
    print("Filtering for latest 24h: Start=$targetDayStart, End=$targetDayEnd"); // DEBUG
    // --- End Date Range Calculation ---

    List<SleepInterval> dayIntervals = intervals.where((interval) =>
        interval.start.isBefore(targetDayEnd) && interval.end.isAfter(targetDayStart)
    ).toList();
    print("Found ${dayIntervals.length} intervals potentially within the target day."); // DEBUG

    // Adjust intervals to fit within the target day boundaries
    dayIntervals = dayIntervals.map((interval) {
        DateTime start = interval.start.isBefore(targetDayStart) ? targetDayStart : interval.start;
        DateTime end = interval.end.isAfter(targetDayEnd) ? targetDayEnd : interval.end;
        // DEBUG: Print adjusted interval
        // print("Adjusted Interval: Start=$start, End=$end, IsAsleep=${interval.isAsleep}");
        return SleepInterval(start: start, end: end, isAsleep: interval.isAsleep);
    }).toList();


    // Calculate metrics for the selected day
    Duration daySleepDuration = Duration.zero;
    int dayWakeUps = 0;
    DateTime? dayLastWakeUp;

    print("--- Calculating metrics for filtered day intervals ---"); // DEBUG
    for(int i = 0; i < dayIntervals.length; i++) {
        final interval = dayIntervals[i];
        if (interval.isAsleep) {
             daySleepDuration += interval.duration;
             print("Adding sleep duration: ${interval.duration} (Total: $daySleepDuration)"); // DEBUG
        }
         // Track wake-ups within the day
        if (i > 0) {
           final prevInterval = dayIntervals[i-1];
           if (prevInterval.isAsleep && !interval.isAsleep) {
               dayWakeUps++;
               dayLastWakeUp = interval.start;
               print("Wake up detected at ${interval.start}"); // DEBUG
           }
        }
    }
    print("--- Finished calculating day metrics ---"); // DEBUG


    if (mounted) {
      setState(() {
        _processedIntervals = dayIntervals;
        _displayDayStart = targetDayStart; // Store the calculated start time

        // --- Scale the calculated sleep duration --- 
        const double scaleFactor = 144.0; // 24 hours / 10 minutes
        Duration compressedSleepDuration = Duration(
             microseconds: (daySleepDuration.inMicroseconds * scaleFactor).round()
        );
        _totalSleepDuration = compressedSleepDuration; // Store the scaled duration
        // --- End Scaling ---

        _wakeUps = dayWakeUps;
        _lastWakeUpTime = dayLastWakeUp;
      });
    }
    print("Processed Sleep Data - Real Total: $daySleepDuration, Scaled Total: ${_totalSleepDuration}, Wakeups: $_wakeUps"); // Updated debug print
  }

  // Helper to format duration
  String _formatDuration(Duration d) {
    d = d + Duration(microseconds: 999999); // Round up to nearest second
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8), // Light background for the page
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Sleep', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.black), // Or other appropriate icon
            onPressed: () {
              // Handle menu action if needed
            },
          ),
        ],
        backgroundColor: const Color(0xFFF8F8F8), // Match page background
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView( // Use ListView for scrollability
        children: [
          _buildTopSection(),
          _buildMainContent(),
        ],
      ),
    );
  }

  // Builds the top section with baby icon and sleep summary card
  Widget _buildTopSection() {
    // Format sleep duration
    String formattedSleep = "${_formatDuration(_totalSleepDuration)}\nHrs";

    // Calculate and Format scaled wake up time
    String lastWakeUpStr = 'Last Woke Up: N/A';
    if (_lastWakeUpTime != null && _displayDayStart != null) {
        // 1. Calculate real duration from the start of the period
        Duration realDurationSinceStart = _lastWakeUpTime!.difference(_displayDayStart!);
        
        // 2. Scale the duration
        const double scaleFactor = 144.0;
        Duration scaledDuration = Duration(microseconds: (realDurationSinceStart.inMicroseconds * scaleFactor).round());

        // 3. Apply scaled duration to the start time (or a nominal start for formatting)
        // We only care about the time part, so adding to a fixed date is fine for formatting
        DateTime nominalDayStart = DateTime(_displayDayStart!.year, _displayDayStart!.month, _displayDayStart!.day); // Use date part only
        DateTime scaledWakeUpDateTime = nominalDayStart.add(scaledDuration);

        // 4. Format the scaled time
        lastWakeUpStr = 'Last Woke Up: ${_formatTime(scaledWakeUpDateTime)}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Baby Icon Placeholder
          Image.asset("assets/baby_sleeping.png"),
          const SizedBox(width: 20),
          // Hours of Sleep Card
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.blue.shade100.withOpacity(0.6), // Light blue
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hours of Sleep',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 10),
                  Container(
                     padding: const EdgeInsets.all(15),
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Colors.white),
                      child: Text(
                        formattedSleep, // Use calculated sleep duration
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    lastWakeUpStr, // Use calculated wake up time
                     style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  Text(
                    'Wake Ups During Night : $_wakeUps', // Use calculated wake ups
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper to format time
  String _formatTime(DateTime dt) {
      String period = dt.hour < 12 ? 'Am' : 'Pm';
      int hour = dt.hourOfPeriod;
      if (hour == 0) hour = 12; // Handle midnight
      String minute = dt.minute.toString().padLeft(2, '0');
      return '$hour.$minute $period';
  }

  // Builds the main content area with rounded top
  Widget _buildMainContent() {
    return Container(
       margin: const EdgeInsets.only(top: 20), // Margin from top section
       padding: const EdgeInsets.all(20.0),
       decoration: const BoxDecoration(
         color: Color(0xFFFFF0D8), // Light yellow/orange background from design
         borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
       ),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.stretch, // Make children fill width
         children: [
           _buildTimeRangeSelector(),
           const SizedBox(height: 20),
           _buildDaySelector(),
           const SizedBox(height: 20),
           _buildSleepGraph(),
           const SizedBox(height: 30),
           _buildMetricsGrid(),
           const SizedBox(height: 20), // Padding at the bottom
         ],
       ),
    );
  }

  // Builds the Weekly/Month/Day toggle buttons
  Widget _buildTimeRangeSelector() {
    return Container(
       decoration: BoxDecoration(
         color: Colors.white.withOpacity(0.5),
         borderRadius: BorderRadius.circular(10),
       ),
       child: ToggleButtons(
         isSelected: _timeRangeSelection,
         onPressed: (int index) {
           setState(() {
             for (int i = 0; i < _timeRangeSelection.length; i++) {
               _timeRangeSelection[i] = i == index;
             }
             _selectedTimeRangeIndex = index;
             // Add logic to fetch/update data based on selection
           });
         },
         borderRadius: BorderRadius.circular(10),
         selectedColor: Colors.white,
         fillColor: Colors.blue.shade300, // Selected background color
         color: Colors.black54, // Unselected text color
         constraints: BoxConstraints(minHeight: 40.0, minWidth: (MediaQuery.of(context).size.width - 80) / 3), // Adjust width calculation as needed
         children: const <Widget>[
           Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('Weekly')),
           Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('Month')),
           Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('Day')),
         ],
       ),
    );
  }

 // Builds the horizontal day selector
  Widget _buildDaySelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(_daysOfWeek.length, (index) {
        bool isSelected = index == _selectedDayIndex;
        return GestureDetector(
           onTap: () {
             setState(() {
               _selectedDayIndex = index;
                // Add logic to update graph/data for selected day
             });
           },
           child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    _daysOfWeek[index],
                    style: TextStyle(
                       fontSize: 12,
                       color: isSelected ? Colors.white : Colors.black54,
                       fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 4),
                   Text(
                     _dates[index],
                      style: TextStyle(
                         fontSize: 14,
                         color: isSelected ? Colors.white : Colors.black,
                         fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      ),
                   ),
                ],
              ),
           ),
        );
      }),
    );
  }

  // Builds the sleep graph based on processed intervals
  Widget _buildSleepGraph() {
    if (_processedIntervals.isEmpty) {
       return Container(
         height: 100,
         alignment: Alignment.center,
         child: const Text("No sleep data for selected day."),
       );
    }

    // Calculate the total duration for the graph (our compressed day)
    DateTime graphStartTime = _processedIntervals.first.start;
    DateTime graphEndTime = graphStartTime.add(_compressedDayDuration);
    Duration totalGraphDuration = graphEndTime.difference(graphStartTime);

    if (totalGraphDuration <= Duration.zero) {
        return Container( height: 100, alignment: Alignment.center, child: const Text("Invalid time range."));
    }

    // Create bars representing sleep/wake intervals
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
         color: Colors.white.withOpacity(0.7),
         borderRadius: BorderRadius.circular(15),
         // ... (optional shadow)
      ),
      child: Row(
        children: _processedIntervals.map((interval) {
           // Map real interval duration to compressed graph duration
           Duration realDuration = interval.duration;
           // Scale factor: 10 mins (graph) / 24 hrs (real)
           double scaleFactor = _compressedDayDuration.inMicroseconds / (const Duration(hours: 24)).inMicroseconds;
           Duration graphDuration = Duration(microseconds: (realDuration.inMicroseconds * scaleFactor).round());

           double flexFactor = graphDuration.inMicroseconds / totalGraphDuration.inMicroseconds;
           if (flexFactor.isNaN || flexFactor.isInfinite || flexFactor < 0) flexFactor = 0;

           return Expanded(
             flex: (flexFactor * 1000).toInt().clamp(1, 1000), // Use flex to represent duration
             child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 0.5), // Tiny gap
                decoration: BoxDecoration(
                  color: interval.isAsleep ? Colors.blue.shade700 : Colors.orange.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
             ),
           );
        }).toList(),
      ),
    );
  }

  // Builds the grid of summary metrics
  Widget _buildMetricsGrid() {
    // Use dummy data for now
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 15,
      mainAxisSpacing: 15,
      childAspectRatio: 2.5, // Adjust aspect ratio for card shape
      children: [
        _MetricCard(label: 'Hours Slept', value: "${_formatDuration(_totalSleepDuration)}\nHrs", valueColor: Colors.green),
        _MetricCard(label: 'Oxygen', value: '90%', valueColor: Colors.green),
        _MetricCard(label: 'Heart Rate', value: '72', valueColor: Colors.redAccent),
        _MetricCard(label: 'Temperature', value: '98', valueColor: Colors.orange), // Using F
      ],
    );
  }
}

// Helper widget for the metric cards at the bottom
class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(15),
         boxShadow: [
           BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
         ]
      ),
      child: Row(
         mainAxisAlignment: MainAxisAlignment.spaceBetween,
         children: [
           Text(
             label,
             style: const TextStyle(color: Colors.black54, fontSize: 14, fontWeight: FontWeight.w500),
           ),
           Text(
             value,
             style: TextStyle(color: valueColor, fontSize: 22, fontWeight: FontWeight.bold),
           ),
         ],
      ),
    );
  }
}

// Extension for Hour of Period (1-12)
extension DateTimeHourOfPeriod on DateTime {
  int get hourOfPeriod {
    int h = hour % 12;
    return h == 0 ? 12 : h;
  }
}
