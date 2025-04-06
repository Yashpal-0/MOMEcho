// frontend/lib/rocking_simulation_page.dart
import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';
import 'dart:ui'; // Import for lerpDouble
import 'dart:convert'; // Import for jsonEncode/Decode
import 'package:shared_preferences/shared_preferences.dart'; // Import for saving
import 'heatmap_page.dart'; // Import the new heatmap page

// --- Simulation & RL Definitions ---
/// Size of the pressure mat grid.
const int GRID_SIZE = 32;

/// Represents the possible states of the baby.
enum BabyState { asleep, awake, cranky }

/// Represents the possible actions the RL agent can take (rocking or bouncing).
enum CradleAction { no_action, rock_gentle, rock_strong, bounce_gentle, bounce_strong }

/// Maps rocking actions to the visual maximum swing *angle* in radians.
// Updated values to represent angles for rotation
const Map<CradleAction, double> actionRockAmplitudes = {
  CradleAction.no_action: 0.0,
  CradleAction.rock_gentle: 0.2, // Approx 11 degrees max swing
  CradleAction.rock_strong: 0.5, // Approx 28 degrees max swing
  CradleAction.bounce_gentle: 0.0, // No rocking angle for bounce actions
  CradleAction.bounce_strong: 0.0,
};

/// Maps bouncing actions to the visual *vertical* amplitude.
const Map<CradleAction, double> actionBounceAmplitudes = {
  CradleAction.no_action: 0.0,
  CradleAction.rock_gentle: 0.0, // No vertical movement for rock actions
  CradleAction.rock_strong: 0.0,
  CradleAction.bounce_gentle: 5.0, // Gentle vertical movement
  CradleAction.bounce_strong: 12.0, // Stronger vertical movement
};

/// Helper function to convert a [BabyState] enum to a readable string.
String stateToString(BabyState state) {
  switch (state) {
    case BabyState.asleep: return 'Asleep';
    case BabyState.awake: return 'Awake';
    case BabyState.cranky: return 'Cranky';
  }
}

/// Helper function to convert a [CradleAction] enum to a readable string.
String actionToString(CradleAction action) {
  switch (action) {
    case CradleAction.no_action: return 'No Action';
    case CradleAction.rock_gentle: return 'Rock Gentle';
    case CradleAction.rock_strong: return 'Rock Strong';
    case CradleAction.bounce_gentle: return 'Bounce Gentle';
    case CradleAction.bounce_strong: return 'Bounce Strong';
  }
}
// --- End Definitions ---

/// The stateful widget for the rocking simulation page.
// Renamed from MyHomePage
class RockingSimulationPage extends StatefulWidget {
  const RockingSimulationPage({super.key}); // Removed title parameter

  @override
  // Renamed from _MyHomePageState
  State<RockingSimulationPage> createState() => _RockingSimulationPageState();
}

/// The state associated with [RockingSimulationPage].
// Renamed from _MyHomePageState
class _RockingSimulationPageState extends State<RockingSimulationPage> {
  // Simulation State
  BabyState _babyState = BabyState.awake;
  double _rockingPhase = 0.0;
  double _bouncingPhase = 0.0;
  final bool _isAuto = true;
  Timer? _animationTimer;
  Timer? _actionTimer;   // Renamed timer for actions (1s)
  Timer? _stateTimer;    // New timer for state/learning (5s)
  final Random _random = Random();
  CradleAction _lastAction = CradleAction.no_action;
  double _currentRockAmplitude = actionRockAmplitudes[CradleAction.no_action]!;
  double _targetRockAmplitude = actionRockAmplitudes[CradleAction.no_action]!;
  double _currentBounceAmplitude = actionBounceAmplitudes[CradleAction.no_action]!;
  double _targetBounceAmplitude = actionBounceAmplitudes[CradleAction.no_action]!;
  late List<List<int>> _pressureMatrix;

  // Stream controller for pressure matrix AND state updates
  final StreamController<(List<List<int>>, BabyState)> _matrixAndStateController = StreamController<(List<List<int>>, BabyState)>.broadcast();
  Stream<(List<List<int>>, BabyState)> get matrixAndStateStream => _matrixAndStateController.stream;

  // Q-Learning Parameters
  Map<BabyState, Map<CradleAction, double>> _qTable = {};
  final double _learningRate = 0.1;
  final double _discountFactor = 0.9;
  final double _epsilon = 0.1;

  // Track time spent in each state for accuracy calculation
  double _timeAsleep = 0.0;
  double _timeAwake = 0.0;
  double _timeCranky = 0.0;
  double _modelAccuracy = 1.0; // Start at 100%

  // Storing previous matrices for movement detection
  List<List<int>>? _pressureMatrixTminus1;
  List<List<int>>? _pressureMatrixTminus2;

  // Store state change history
  List<(String, String)> _stateChangeHistory = []; // Store as (ISO8601 Timestamp, State String)
  final int _maxHistoryDays = 3; // Keep history for ~3 days

  @override
  void initState() {
    super.initState();
    // Make initState async to load Q-Table before proceeding
    _initAsync();
  }

  Future<void> _initAsync() async {
    await _loadQTable(); // Load Q-Table first
    await _loadStateHistory(); // Load state history

    // Initialize other state variables after Q-Table is potentially loaded
    _pressureMatrix = _generatePressureMatrix(_babyState);
    _pressureMatrixTminus1 = _pressureMatrix; // Initialize t-1
    _matrixAndStateController.add((_pressureMatrix, _babyState));
    _targetRockAmplitude = actionRockAmplitudes[_lastAction]!;
    _targetBounceAmplitude = actionBounceAmplitudes[_lastAction]!;
    _currentRockAmplitude = _targetRockAmplitude;
    _currentBounceAmplitude = _targetBounceAmplitude;
    _startAnimation();
    _startTimers(); // Call the new timer starter function
    // Ensure the widget is built after async operations
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    _actionTimer?.cancel(); // Cancel action timer
    _stateTimer?.cancel(); // Cancel state timer
    _matrixAndStateController.close();
    _saveQTable(); // Save Q-Table on dispose
    _saveStateHistory(); // Save state history on dispose
    super.dispose();
  }

  void _initializeQTable() {
    // This function now simply ensures the Q-table is reset to default zeros.
    print("Initializing empty Q-Table structure.");
    _qTable = {}; // Reset to empty map first
    for (var state in BabyState.values) {
      _qTable[state] = {};
      for (var action in CradleAction.values) {
        _qTable[state]![action] = 0.0;
      }
    }
  }

  void _startAnimation() {
    _animationTimer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (mounted) {
        setState(() {
          _rockingPhase += 0.1;
          if (_rockingPhase > 2 * pi) _rockingPhase -= 2 * pi;
          _bouncingPhase += 0.15;
          if (_bouncingPhase > 2 * pi) _bouncingPhase -= 2 * pi;

          _currentRockAmplitude = _lerp(_currentRockAmplitude, _targetRockAmplitude, 0.08);
          _currentBounceAmplitude = _lerp(_currentBounceAmplitude, _targetBounceAmplitude, 0.08);

          if ((_currentRockAmplitude - _targetRockAmplitude).abs() < 0.01) {
            _currentRockAmplitude = _targetRockAmplitude;
          }
          if ((_currentBounceAmplitude - _targetBounceAmplitude).abs() < 0.01) {
            _currentBounceAmplitude = _targetBounceAmplitude;
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  double _lerp(double a, double b, double t) {
    return a + (b - a) * t;
  }

  // New function to start both timers
  void _startTimers() {
     // Action/Visual Timer (every 1 second)
     _actionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
       if (mounted && _isAuto) {
         _performActionUpdateStep(); // Call action step
       } else if (!mounted) {
         timer.cancel();
       }
    });

     // State/Learning Timer (every 5 seconds)
     _stateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
       if (mounted && _isAuto) {
         _performStateUpdateStep(); // Call state step
       } else if (!mounted) {
         timer.cancel();
       }
    });
  }

  CradleAction _getBestAction(BabyState state) {
    final actions = _qTable[state]!;
    CradleAction bestAction = actions.keys.first;
    double maxQ = actions[bestAction]!;
    actions.forEach((action, qValue) {
      if (qValue > maxQ) {
        maxQ = qValue;
        bestAction = action;
      }
    });
    return bestAction;
  }

  CradleAction _chooseAction(BabyState state) {
    if (_random.nextDouble() < _epsilon) {
      return CradleAction.values[_random.nextInt(CradleAction.values.length)];
    } else {
      return _getBestAction(state);
    }
  }

  void _updateQValue(BabyState state, CradleAction action, double reward, BabyState nextState) {
    final oldQValue = _qTable[state]![action]!;
    final maxNextQ = _qTable[nextState]![_getBestAction(nextState)]!;
    final newQValue = oldQValue + _learningRate * (reward + _discountFactor * maxNextQ - oldQValue);
    _qTable[state]![action] = newQValue;
  }

  List<List<int>> _generatePressureMatrix(BabyState state) {
    List<List<int>> matrix = List.generate(GRID_SIZE, (_) => List.filled(GRID_SIZE, 0));

    // --- Base Parameters based on State ---
    double headBase, torsoBase, limbBase, noiseScale, movementFactor, asymmetryFactor;
    switch (state) {
      case BabyState.asleep:
        headBase = 40.0;
        torsoBase = 90.0;
        limbBase = 25.0;  // Lower limb pressure when asleep
        noiseScale = 10.0; // Less noise when asleep
        movementFactor = 0.1; // Minimal movement/shift
        asymmetryFactor = 0.5; // Minimal asymmetry
        break;
      case BabyState.awake:
        headBase = 50.0;
        torsoBase = 110.0;
        limbBase = 35.0;
        noiseScale = 25.0;
        movementFactor = 0.6;
        asymmetryFactor = 1.0; // More potential asymmetry
        break;
      case BabyState.cranky:
        headBase = 55.0;   // Slightly less head pressure if moving torso more
        torsoBase = 150.0; // Higher torso pressure when cranky
        limbBase = 50.0;   // Higher limb pressure (kicking/pushing)
        noiseScale = 45.0;  // More noise/variation
        movementFactor = 1.2; // Higher chance/magnitude of position shift
        asymmetryFactor = 1.5; // Increased asymmetry chance
        break;
    }

    // --- Calculate Center Points with Random Shifts & Asymmetry ---
    // Base centers (scaled for 32x32)
    int headCenterRow = 8;
    int headCenterCol = GRID_SIZE ~/ 2;
    int torsoCenterRow = 18;
    int torsoCenterCol = GRID_SIZE ~/ 2;
    // Base limb positions relative to torso
    int limb1OffsetRow = -3;
    int limb1OffsetCol = -6;
    int limb2OffsetRow = 2;
    int limb2OffsetCol = 5;

    // Apply overall asymmetry shift (horizontal)
    int asymmetryShift = ((_random.nextDouble() - 0.5) * asymmetryFactor * 2).round();
    headCenterCol += asymmetryShift;
    torsoCenterCol += asymmetryShift;

    // Apply random position shifts based on movementFactor
    if (_random.nextDouble() < movementFactor * 0.5) { // Chance to shift
        int rowShift = (_random.nextBool() ? 1 : -1) * (_random.nextDouble() * movementFactor * 1.5).round();
        int colShift = (_random.nextBool() ? 1 : -1) * (_random.nextDouble() * movementFactor * 2.5).round();
        headCenterRow += rowShift;
        headCenterCol += colShift;
        torsoCenterRow += rowShift; // Shift torso with head slightly
        torsoCenterCol += colShift;
    }

    // Calculate final limb positions with their own shifts
    int limb1CenterRow = torsoCenterRow + limb1OffsetRow + (_random.nextBool() ? 1 : -1) * (_random.nextDouble() * movementFactor * 2).round();
    int limb1CenterCol = torsoCenterCol + limb1OffsetCol + (_random.nextBool() ? 1 : -1) * (_random.nextDouble() * movementFactor * 3).round();
    int limb2CenterRow = torsoCenterRow + limb2OffsetRow + (_random.nextBool() ? 1 : -1) * (_random.nextDouble() * movementFactor * 2).round();
    int limb2CenterCol = torsoCenterCol + limb2OffsetCol + (_random.nextBool() ? 1 : -1) * (_random.nextDouble() * movementFactor * 3).round();

    // Clamp all centers to grid bounds
    headCenterRow = headCenterRow.clamp(0, GRID_SIZE - 1);
    headCenterCol = headCenterCol.clamp(0, GRID_SIZE - 1);
    torsoCenterRow = torsoCenterRow.clamp(0, GRID_SIZE - 1);
    torsoCenterCol = torsoCenterCol.clamp(0, GRID_SIZE - 1);
    limb1CenterRow = limb1CenterRow.clamp(0, GRID_SIZE - 1);
    limb1CenterCol = limb1CenterCol.clamp(0, GRID_SIZE - 1);
    limb2CenterRow = limb2CenterRow.clamp(0, GRID_SIZE - 1);
    limb2CenterCol = limb2CenterCol.clamp(0, GRID_SIZE - 1);


    // --- Define Radii (scaled for 32x32) ---
    double headRadius = 5.0;
    double torsoRadius = 8.0;
    double limbRadius = 3.5; // Smaller radius for limbs

    // --- Calculate Pressure Matrix ---
    for (int i = 0; i < GRID_SIZE; i++) {
      for (int j = 0; j < GRID_SIZE; j++) {
        // Calculate distance from centers
        double distHead = sqrt(pow(i - headCenterRow, 2) + pow(j - headCenterCol, 2));
        double distTorso = sqrt(pow(i - torsoCenterRow, 2) + pow(j - torsoCenterCol, 2));
        double distLimb1 = sqrt(pow(i - limb1CenterRow, 2) + pow(j - limb1CenterCol, 2));
        double distLimb2 = sqrt(pow(i - limb2CenterRow, 2) + pow(j - limb2CenterCol, 2));

        double pressure = 0;
        double falloffFactor = 2.0; // How quickly pressure drops (smaller = sharper)

        // Calculate pressure contribution from head
        if (distHead < headRadius * 1.8) { // Increased range slightly
             pressure += headBase * exp(-pow(distHead, falloffFactor) / (2 * pow(headRadius, falloffFactor)));
        }
        // Calculate pressure contribution from torso
        if (distTorso < torsoRadius * 1.8) {
            pressure += torsoBase * exp(-pow(distTorso, falloffFactor) / (2 * pow(torsoRadius, falloffFactor)));
        }
        // Calculate pressure contribution from limb 1
        if (distLimb1 < limbRadius * 1.8) {
            pressure += limbBase * exp(-pow(distLimb1, falloffFactor) / (2 * pow(limbRadius, falloffFactor)));
        }
        // Calculate pressure contribution from limb 2
        if (distLimb2 < limbRadius * 1.8) {
            pressure += limbBase * exp(-pow(distLimb2, falloffFactor) / (2 * pow(limbRadius, falloffFactor)));
        }

        // Add noise - scaled by current calculated pressure to make high-pressure areas noisier
        pressure += (_random.nextDouble() - 0.5) * noiseScale * (pressure / (torsoBase + 1)); // Noise proportional to pressure

        // Assign clamped value to matrix
        matrix[i][j] = pressure.clamp(0, 255).toInt();
      }
    }
    return matrix;
  }

  // Helper function to quantify movement between two matrices
  double _calculateMovementMetric(List<List<int>>? matrix1, List<List<int>>? matrix2) {
    if (matrix1 == null || matrix2 == null || matrix1.length != GRID_SIZE || matrix2.length != GRID_SIZE) {
      return 0.0; // No movement if matrices are invalid or missing
    }

    double totalDifference = 0;
    for (int i = 0; i < GRID_SIZE; i++) {
      for (int j = 0; j < GRID_SIZE; j++) {
        if (matrix1[i].length == GRID_SIZE && matrix2[i].length == GRID_SIZE) {
           totalDifference += (matrix1[i][j] - matrix2[i][j]).abs();
        }
      }
    }

    // Normalize the difference (e.g., by max possible difference)
    double maxPossibleDifference = (GRID_SIZE * GRID_SIZE * 255.0);
    return maxPossibleDifference > 0 ? totalDifference / maxPossibleDifference : 0.0;
  }

  BabyState _getNextState(BabyState currentState, CradleAction action) {
    double rand = _random.nextDouble();
    switch (currentState) {
      case BabyState.asleep:
        if (action == CradleAction.no_action) { return rand < 0.05 ? BabyState.awake : BabyState.asleep; }
        else if (action == CradleAction.rock_gentle) { return rand < 0.15 ? BabyState.awake : BabyState.asleep; }
        else if (action == CradleAction.rock_strong) { return rand < 0.30 ? BabyState.awake : BabyState.asleep; }
        else if (action == CradleAction.bounce_gentle) { return rand < 0.20 ? BabyState.awake : BabyState.asleep; }
        else { return rand < 0.40 ? BabyState.awake : BabyState.asleep; }
      case BabyState.awake:
        if (action == CradleAction.no_action) {
          if (rand < 0.05) return BabyState.asleep; if (rand < 0.40) return BabyState.cranky; return BabyState.awake;
        } else if (action == CradleAction.rock_gentle) {
           if (rand < 0.15) return BabyState.asleep; if (rand < 0.25) return BabyState.cranky; return BabyState.awake;
        } else if (action == CradleAction.rock_strong) {
           if (rand < 0.30) return BabyState.asleep; if (rand < 0.35) return BabyState.cranky; return BabyState.awake;
        } else if (action == CradleAction.bounce_gentle) {
           if (rand < 0.12) return BabyState.asleep; if (rand < 0.22) return BabyState.cranky; return BabyState.awake;
        } else { // bounce_strong
           if (rand < 0.25) return BabyState.asleep; if (rand < 0.30) return BabyState.cranky; return BabyState.awake;
        }
      case BabyState.cranky:
        if (action == CradleAction.no_action) { 
          // No action: Less likely to improve
          return rand < 0.20 ? BabyState.awake : BabyState.cranky; 
        }
        else if (action == CradleAction.rock_gentle) {
          // Gentle rocking: Improved chance vs no action
          if (rand < 0.15) return BabyState.asleep; // Increased from 0.10
          if (rand < 0.60) return BabyState.awake;  // Increased from 0.40 (0.60 - 0.15 = 45% chance awake)
          return BabyState.cranky; // 40% chance stays cranky
        } else if (action == CradleAction.rock_strong) {
          // Strong rocking: Much more likely to soothe
          if (rand < 0.50) return BabyState.asleep; // Increased from 0.40
          if (rand < 0.80) return BabyState.awake;  // Increased from 0.60 (0.80 - 0.50 = 30% chance awake)
          return BabyState.cranky; // 20% chance stays cranky
        } else if (action == CradleAction.bounce_gentle) {
          // Gentle bouncing: Improved chance vs no action
          if (rand < 0.20) return BabyState.asleep; // Increased from 0.15
          if (rand < 0.60) return BabyState.awake;  // Increased from 0.50 (0.60 - 0.20 = 40% chance awake)
          return BabyState.cranky; // 40% chance stays cranky
        } else { // bounce_strong
          // Strong bouncing: Much more likely to soothe
          if (rand < 0.60) return BabyState.asleep; // Increased from 0.45
          if (rand < 0.85) return BabyState.awake;  // Increased from 0.70 (0.85 - 0.60 = 25% chance awake)
          return BabyState.cranky; // 15% chance stays cranky
        }
    }
  }

  double _getReward(BabyState previousState, BabyState currentState, CradleAction action) {
    double reward = 0;
    if (currentState == BabyState.asleep) reward += 10;
    if (currentState == BabyState.awake) reward += 0;
    if (currentState == BabyState.cranky) reward -= 10;
    if (previousState == BabyState.asleep) {
      if (action == CradleAction.rock_gentle) reward -= 1;
      if (action == CradleAction.rock_strong) reward -= 3;
      if (action == CradleAction.bounce_gentle) reward -= 2;
      if (action == CradleAction.bounce_strong) reward -= 5;
    }
    return reward;
  }

  // Updates action & visuals (1 sec interval)
  void _performActionUpdateStep() {
     if (!mounted) return;
     final currentState = _babyState;
     final chosenAction = _chooseAction(currentState);
     _lastAction = chosenAction;
    print("[ActionTimer] State: $currentState, Chosen Action: $chosenAction"); // DEBUG
    _updateTargetAmplitudes();
  }

  // New function for state transitions and learning (5 sec interval)
  void _performStateUpdateStep() {
     if (!mounted) return;

     const stateUpdateInterval = Duration(seconds: 1); // Match the _stateTimer duration

     // === Update Time-in-State Counters ===
     final stateDuringLastInterval = _babyState;
     switch (stateDuringLastInterval) {
        case BabyState.asleep: _timeAsleep += stateUpdateInterval.inSeconds; break;
        case BabyState.awake: _timeAwake += stateUpdateInterval.inSeconds; break;
        case BabyState.cranky: _timeCranky += stateUpdateInterval.inSeconds; break;
     }
     // === End Time Update ===

     // === State Transition Logic ===
     double movementMetric = _calculateMovementMetric(_pressureMatrixTminus1, _pressureMatrixTminus2);
     final previousState = _babyState;
     final actionDuringInterval = _lastAction;
     BabyState nextState = _getNextState(previousState, actionDuringInterval);

     // Adjust based on movement
     double movementThreshold = 0.01;
     if (previousState == BabyState.asleep && movementMetric > movementThreshold) {
         print("--- Movement detected while asleep! Waking up... ---");
         nextState = _random.nextDouble() < 0.3 ? BabyState.cranky : BabyState.awake;
     }
     else if (previousState == BabyState.awake && movementMetric > movementThreshold * 1.5) {
        if (_random.nextDouble() < 0.3) {
            print("--- High movement while awake! Becoming cranky... ---");
            nextState = BabyState.cranky;
        }
     }
     // === End Transition Logic ===

     // === Update Q-Table ===
     final reward = _getReward(previousState, nextState, actionDuringInterval);
     _updateQValue(previousState, actionDuringInterval, reward, nextState);
     // === End Q-Table Update ===

     // === Generate New Pressure Matrix ===
     final newPressureMatrix = _generatePressureMatrix(nextState);
     // === End Pressure Matrix Generation ===

     // === Update State, History, Accuracy and Emit ===
     setState(() {
       // Only record if the state actually changed
       if (nextState != previousState) {
         _stateChangeHistory.add((DateTime.now().toIso8601String(), nextState.toString().split('.').last));
         print("State Changed: $nextState at ${DateTime.now()}"); // Debug print
         _pruneHistory(); // Optional: prune periodically
       }

       _babyState = nextState;
       _pressureMatrix = newPressureMatrix;
       _pressureMatrixTminus2 = _pressureMatrixTminus1;
       _pressureMatrixTminus1 = _pressureMatrix;

       // Calculate Accuracy
       double totalTime = _timeAsleep + _timeAwake + _timeCranky;
       _modelAccuracy = (totalTime > 0) ? (totalTime - _timeCranky) / totalTime : 1.0;

       _matrixAndStateController.add((_pressureMatrix, _babyState));
     });
     // === End State Update ===
  }

  void _updateTargetAmplitudes(){
      _targetRockAmplitude = actionRockAmplitudes[_lastAction]!;
      _targetBounceAmplitude = actionBounceAmplitudes[_lastAction]!;
      // print("[ActionTimer] Setting Targets - Rock: ${_targetRockAmplitude.toStringAsFixed(2)}, Bounce: ${_targetBounceAmplitude.toStringAsFixed(2)}"); // DEBUG
  }

  @override
  Widget build(BuildContext context) {
    // Calculate current angle for the simple baby animation
    double currentAngle = sin(_rockingPhase) * _currentRockAmplitude;

    // Determine status text and color based on baby state
    String statusText = stateToString(_babyState);
    Color statusColor;
    switch (_babyState) {
      case BabyState.asleep: statusColor = Colors.green.shade400; break;
      case BabyState.awake: statusColor = Colors.orange.shade400; break;
      case BabyState.cranky: statusColor = Colors.red.shade400; break;
    }

    // Determine rocking intensity string
    String intensityText;
    switch (_lastAction) {
       case CradleAction.rock_gentle: intensityText = 'Gentle'; break;
       case CradleAction.rock_strong: intensityText = 'Strong'; break;
       case CradleAction.bounce_gentle: intensityText = 'Bounce Gentle'; break; // Include bounce type if needed
       case CradleAction.bounce_strong: intensityText = 'Bounce Strong'; break;
       default: intensityText = 'None';
    }

    return Scaffold(
       backgroundColor: Colors.grey[100],
       appBar: AppBar(
         leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.black), onPressed: () => Navigator.of(context).pop()),
         title: const Text('Automatic Rocking', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
         actions: [ IconButton(icon: const Icon(Icons.menu, color: Colors.black), onPressed: () { /* Handle menu */ }), ],
         backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
       ),
       body: Padding(
         padding: const EdgeInsets.all(20.0),
           child: Column(
             children: <Widget>[
             // Main content card
             Container(
               padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
               decoration: BoxDecoration(
                 color: Colors.white,
                 borderRadius: BorderRadius.circular(30),
                 boxShadow: [ BoxShadow(color: Colors.grey.withOpacity(0.2), spreadRadius: 3, blurRadius: 8, offset: const Offset(0, 4),),],
               ),
               child: Column(
                 children: [
                   const Text('Swing', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 25),

                   // Animation Area Placeholder
                   _buildAnimationArea(currentAngle),
                   const SizedBox(height: 25),

                   // Status Indicator
                   Row(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       Container(
          
                       width: 12, height: 12,
                         decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                       ),
                       const SizedBox(width: 8),
                       Text(statusText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                     ],
                   ),
                   const SizedBox(height: 10),

                   // Rocking Intensity Display
               Row(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                         const Text('Rocking', style: TextStyle(fontSize: 16, color: Colors.grey)),
                         const SizedBox(width: 10),
                         Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                               border: Border.all(color: Colors.grey.shade300),
                               borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(intensityText, style: const TextStyle(fontWeight: FontWeight.w500)),
                         )
                      ],
                   ),
                   const SizedBox(height: 10), // Add some bottom padding inside card

                  // --- Model Accuracy Display ---
                  Padding(
                    padding: const EdgeInsets.only(top: 10.0), // Add some spacing above
                    child: Text(
                      'Model Performance: ${(_modelAccuracy * 100).toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 14, color: Colors.blueGrey[700], fontWeight: FontWeight.w500),
                    ),
                  ),
                  // --- End Accuracy Display ---

                 ],
               ),
             ), // End Main Content Card

             const SizedBox(height: 25),

             // Pressure Status Button
             _buildPressureButton(),

             const SizedBox(height: 30),

             // Quick Access Section
             const Align(
                alignment: Alignment.centerLeft,
                child: Text('Quick Access', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
             ),
             const SizedBox(height: 15),
             _buildQuickAccessButtons(),

             const Spacer(), // Pushes content towards top
           ],
         ),
       ),
    );
  }

  // --- UI Helper Widgets for this page ---

  Widget _buildAnimationArea(double angle) {
    // Y-axis rotation angle (rocking)
    double yRotationAngle = angle * 0.5; // Keep existing rocking intensity

    // Z-axis offset calculation (bouncing) - Scaled down significantly
    double zOffset = sin(_bouncingPhase) * _currentBounceAmplitude * 0.05; // Scale factor added (0.05)

    // --- Debugging ---
    // print('Angle: ${angle.toStringAsFixed(3)}, RockAmp: ${_currentRockAmplitude.toStringAsFixed(3)}, LastAction: $_lastAction, yRotation: ${yRotationAngle.toStringAsFixed(3)}, BounceAmp: ${_currentBounceAmplitude.toStringAsFixed(3)}, zOffset: ${zOffset.toStringAsFixed(3)}');
    // --- End Debugging ---

    // Apply all transformations within a single Matrix4
    return Transform(
      transform: Matrix4.identity()
        ..setEntry(3, 2, -0.01) // Reduced magnitude of concave perspective
        ..translate(0.0, 0.0, 10*zOffset) // Apply Z-translation (bouncing)
        ..rotateY(yRotationAngle),      // Apply Y-rotation (rocking)
      alignment: Alignment.center, // Rotate and translate around the center
      child: Container(
        height: 150,
        width: 120,
        decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300, width: 1.5),
            borderRadius: BorderRadius.circular(60) // Oval shape
            ),
        child: Builder( // Use Builder to get context if needed, or just define var before Stack
          builder: (context) { // Not strictly needed here but safe pattern
            // Determine image based on state
            String babyImagePath = (_babyState == BabyState.cranky)
                ? 'assets/baby_cranky.png'
                : 'assets/baby_sleeping.png';

            return Stack(
              alignment: Alignment.center,
              children: [
                // Faint swinging track (optional) - This will also rotate
                Container(
                  height: 160, width: 130,
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200, width: 1),
                      borderRadius: BorderRadius.circular(65)
                  ),
                ),
                // Baby Icon rotates with the parent Transform
                Image.asset(
                  babyImagePath, // Use the determined path
                  height: 70,
                  width: 70,
                  errorBuilder: (context, error, stackTrace) {
                    String missingImage = (_babyState == BabyState.cranky) ? 'cranky' : 'sleeping';
                    print("Error loading baby image ($missingImage): $error");
                    return const Icon(Icons.error_outline, color: Colors.red, size: 40);
                  },
                ),
                // Rocking indicator below baby
                Positioned(
                   bottom: 25,
                   child: SizedBox(
                      width: 50,
                      height: 15,
                      // Amplify angle more for the indicator visual
                      child: CustomPaint(painter: _RockingIndicatorPainter(angle * 2.5)),
                   ),
                )
              ],
            );
          }
        ),
      ),
    );
  }


  Widget _buildPressureButton() {
     // Static button for now, logic can be added later
     return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
           color: const Color(0xFFFFD700), // Gold background
           borderRadius: BorderRadius.circular(20),
           boxShadow: [ BoxShadow(color: Colors.grey.withOpacity(0.2), spreadRadius: 1, blurRadius: 3)],
        ),
       child: const Row(
           mainAxisSize: MainAxisSize.min, // Fit content
           children: [
              Text('Pressure', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(width: 8),
              Chip( // Use Chip for the 'Safe' part
                 label: Text('Safe', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                 backgroundColor: Colors.white,
                 padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                 labelPadding: EdgeInsets.zero, // Adjust padding if needed
                 visualDensity: VisualDensity(horizontal: 0.0, vertical: -4), // Make chip smaller
              )
           ],
        ),
     );
  }


  Widget _buildQuickAccessButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _QuickAccessButton(
          label: 'Baby\nDashboard',
          icon: Icons.dashboard_customize_outlined, // Replace with actual icons later
          onTap: () { /* Navigate or show message */ }
        ),
         _QuickAccessButton(
          label: 'Pressure\nSensor Heatmap',
          icon: Icons.thermostat_auto, // Replace with actual icons later
          onTap: () {
            // Navigate, passing the combined stream and initial data
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => HeatmapPage(
                  matrixAndStateStream: matrixAndStateStream, 
                  initialData: (_pressureMatrix, _babyState) // Pass initial tuple
                ),
              ),
            );
          }
        ),
         _QuickAccessButton(
          label: 'AI Sleep\nInsights',
          icon: Icons.insights_outlined, // Replace with actual icons later
          onTap: () { /* Navigate or show message */ }
        ),
      ],
    );
  }


  // Helper widget for a single quick access button
  Widget _QuickAccessButton({required String label, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
       onTap: onTap,
       child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), // Adjust padding
          width: MediaQuery.of(context).size.width / 3 - 30, // Approx width for 3 buttons
          decoration: BoxDecoration(
             color: Colors.white,
             borderRadius: BorderRadius.circular(15),
             boxShadow: [ BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 5, offset: const Offset(0, 2))]
          ),
          child: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
                Icon(icon, size: 30, color: Colors.grey[700]),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.black87),
                ),
             ],
          ),
       ),
    );
  }

  // --- Q-Table Persistence Logic ---

  // Helper to get enum from string (case-insensitive)
  T? _enumFromString<T>(List<T> values, String value) {
    try {
        return values.firstWhere((type) => type.toString().split('.').last.toLowerCase() == value.toLowerCase());
    } catch (e) {
        return null;
    }
  }

  // Serialize Q-Table to JSON string
  String _serializeQTable(Map<BabyState, Map<CradleAction, double>> table) {
      Map<String, Map<String, double>> stringMap = {};
      table.forEach((state, actions) {
          String stateKey = state.toString().split('.').last; // e.g., 'asleep'
          Map<String, double> actionMap = {};
          actions.forEach((action, value) {
              String actionKey = action.toString().split('.').last; // e.g., 'rock_gentle'
              actionMap[actionKey] = value;
          });
          stringMap[stateKey] = actionMap;
      });
      return jsonEncode(stringMap);
  }

  // Deserialize JSON string to Q-Table
  Map<BabyState, Map<CradleAction, double>>? _deserializeQTable(String jsonString) {
      try {
          Map<String, dynamic> decodedOuter = jsonDecode(jsonString);
          Map<BabyState, Map<CradleAction, double>> qTable = {};

          for (var stateString in decodedOuter.keys) {
              BabyState? state = _enumFromString(BabyState.values, stateString);
              if (state == null) continue; // Skip if state enum not found

              Map<String, dynamic> decodedInner = decodedOuter[stateString];
              Map<CradleAction, double> actionMap = {};

              for (var actionString in decodedInner.keys) {
                 CradleAction? action = _enumFromString(CradleAction.values, actionString);
                 dynamic value = decodedInner[actionString];
                 if (action != null && value is num) {
                    actionMap[action] = value.toDouble();
                 } // Skip if action enum not found or value is not numeric
              }
              qTable[state] = actionMap;
          }
          // Ensure all states and actions are present, fill with 0.0 if missing
          for (var state in BabyState.values) {
             qTable.putIfAbsent(state, () => {});
             for (var action in CradleAction.values) {
                qTable[state]!.putIfAbsent(action, () => 0.0);
             }
          }
          return qTable;
      } catch (e) {
          print("Error deserializing Q-Table: $e");
          return null; // Return null if deserialization fails
      }
  }

  // Load Q-Table from SharedPreferences
  Future<void> _loadQTable() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        String? qTableJson = prefs.getString('qTable');
        if (qTableJson != null) {
           Map<BabyState, Map<CradleAction, double>>? loadedTable = _deserializeQTable(qTableJson);
           if (loadedTable != null) {
               _qTable = loadedTable;
               print("--- Q-Table loaded successfully ---");
               return; // Use loaded table
           }
        }
        print("--- No valid Q-Table found, initializing new one ---");
      } catch (e) {
        print("Error loading SharedPreferences: $e. Initializing new Q-Table.");
      }
      // Initialize fresh if loading failed, exception occurred, or no data
      _initializeQTable();
  }

  // Save Q-Table to SharedPreferences
  Future<void> _saveQTable() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        String qTableJson = _serializeQTable(_qTable);
        await prefs.setString('qTable', qTableJson);
        print("--- Q-Table saved successfully ---");
      } catch (e) {
         print("Error saving Q-Table to SharedPreferences: $e");
      }
  }

  // --- End Q-Table Persistence Logic ---

  // --- State History Persistence ---
  Future<void> _loadStateHistory() async {
    try {
        final prefs = await SharedPreferences.getInstance();
        List<String>? historyJson = prefs.getStringList('stateHistory');
        if (historyJson != null) {
            _stateChangeHistory = historyJson.map((item) {
                try {
                    final decoded = jsonDecode(item) as Map<String, dynamic>;
                    // Basic validation
                    if (decoded.containsKey('ts') && decoded.containsKey('st')){
                         return (decoded['ts'] as String, decoded['st'] as String);
                    } else {
                        return null; // Invalid format
                    }
                } catch (e) {
                    return null; // JSON decode error
                }
            }).where((item) => item != null).cast<(String, String)>().toList();
            _pruneHistory(); // Prune old entries after loading
            print("--- State history loaded (${_stateChangeHistory.length} entries) ---");
        } else {
             print("--- No state history found. Starting fresh. ---");
             _stateChangeHistory = [];
             // Add the very first state
             _stateChangeHistory.add((DateTime.now().toIso8601String(), _babyState.toString().split('.').last));
        }
    } catch (e) {
        print("Error loading State History: $e. Starting fresh.");
        _stateChangeHistory = [];
        _stateChangeHistory.add((DateTime.now().toIso8601String(), _babyState.toString().split('.').last));
    }
  }

  Future<void> _saveStateHistory() async {
     try {
        _pruneHistory(); // Prune before saving
        final prefs = await SharedPreferences.getInstance();
        // Convert record list to list of JSON strings
        List<String> historyJson = _stateChangeHistory.map((record) => jsonEncode({'ts': record.$1, 'st': record.$2})).toList();
        await prefs.setStringList('stateHistory', historyJson);
        print("--- State history saved (${_stateChangeHistory.length} entries) ---");
     } catch (e) {
        print("Error saving State History: $e");
     }
  }

  void _pruneHistory() {
      final cutoff = DateTime.now().subtract(Duration(days: _maxHistoryDays));
      _stateChangeHistory.removeWhere((item) {
          try {
             return DateTime.parse(item.$1).isBefore(cutoff);
          } catch (e) {
             return true; // Remove if timestamp is unparseable
          }
      });
  }
  // --- End State History Persistence ---
}

// --- Simple Painter for the rocking indicator arc ---
class _RockingIndicatorPainter extends CustomPainter {
   final double angle; // Expects amplified angle for visual clarity
   _RockingIndicatorPainter(this.angle);

  @override
  void paint(Canvas canvas, Size size) {
     final Paint paint = Paint()
       ..color = Colors.black54
       ..style = PaintingStyle.stroke
       ..strokeWidth = 1.5;

     final double radius = size.width * 0.6;
     final double centerX = size.width / 2;
     final double centerY = size.height;

     // Draw arc
     canvas.drawArc(
       Rect.fromCircle(center: Offset(centerX, centerY), radius: radius),
       pi + 0.6, // Start angle
       -1.2,     // Sweep angle
       false,
       paint);

     // REMOVED: Draw the moving dot
     /*
     final double indicatorAngle = -pi / 2 + angle * 1.2; // Increased from 0.8
     final double dotX = centerX + radius * cos(indicatorAngle);
     final double dotY = centerY + radius * sin(indicatorAngle);
     canvas.drawCircle(Offset(dotX, dotY), 3.5, Paint()..color = Colors.black);
     */
  }

  @override
   bool shouldRepaint(covariant _RockingIndicatorPainter oldDelegate) {
     return oldDelegate.angle != angle;
  }
}
