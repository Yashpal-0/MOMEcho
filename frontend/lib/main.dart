import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';
import 'dart:ui'; // Import for lerpDouble

/// Size of the pressure mat grid.
const int GRID_SIZE = 16;

void main() {
  runApp(const MyApp());
}

/// The root widget of the application.
/// Sets up the MaterialApp theme and the home page.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MomEcho Flutter Sim',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlue),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'MomEcho RL Cradle Simulator'),
    );
  }
}

/// The main stateful widget representing the home page of the application.
/// Hosts the simulation state and UI.
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

// Define baby states and amplitudes
enum BabyState { asleep, awake, cranky }
enum CradleAction { no_action, rock_gentle, rock_strong, bounce_gentle, bounce_strong }

const Map<BabyState, double> stateAmplitudes = {
  BabyState.asleep: 0.0,
  BabyState.awake: 25.0, // Adjusted amplitude for screen size
  BabyState.cranky: 60.0, // Adjusted amplitude for screen size
};

/// Maps [CradleAction] to the visual amplitude of the rocking motion.
const Map<CradleAction, double> actionRockAmplitudes = {
  CradleAction.no_action: 0.0,
  CradleAction.rock_gentle: 25.0,
  CradleAction.rock_strong: 60.0,
  CradleAction.bounce_gentle: 0.0, // No horizontal movement for bounce actions
  CradleAction.bounce_strong: 0.0,
};

/// Maps [CradleAction] to the visual amplitude of the bouncing motion.
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
    case BabyState.asleep:
      return 'Asleep';
    case BabyState.awake:
      return 'Awake';
    case BabyState.cranky:
      return 'Cranky';
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

/// The state associated with [MyHomePage].
/// Manages the simulation state, RL agent logic, and UI updates.
class _MyHomePageState extends State<MyHomePage> {
  // Simulation State
  /// The current state of the baby (part of the RL environment's state).
  BabyState _babyState = BabyState.awake; // Start awake for learning
  /// Current phase angle for the sine wave used in rocking animation (0 to 2*pi).
  double _rockingPhase = 0.0;
  /// Current phase angle for the sine wave used in bouncing animation (0 to 2*pi).
  double _bouncingPhase = 0.0;
  /// Flag indicating if the automatic RL learning loop is active.
  bool _isAuto = false;
  /// Timer responsible for updating the rocking animation phase periodically.
  Timer? _animationTimer;
  /// Timer responsible for triggering the RL agent's learn/act cycle periodically when _isAuto is true.
  Timer? _simulationTimer;
  /// Random number generator for stochastic parts (transitions, exploration).
  final Random _random = Random();
  /// The last action chosen by the RL agent.
  CradleAction _lastAction = CradleAction.no_action;
  /// The *current* rocking amplitude applied to the cradle visual (interpolated).
  double _currentRockAmplitude = actionRockAmplitudes[CradleAction.no_action]!;
  /// The *target* rocking amplitude based on the last chosen action.
  double _targetRockAmplitude = actionRockAmplitudes[CradleAction.no_action]!;
  /// The *current* bouncing amplitude applied to the cradle visual (interpolated).
  double _currentBounceAmplitude = actionBounceAmplitudes[CradleAction.no_action]!;
  /// The *target* bouncing amplitude based on the last chosen action.
  double _targetBounceAmplitude = actionBounceAmplitudes[CradleAction.no_action]!;
  /// Stores the current pressure readings for the grid.
  late List<List<int>> _pressureMatrix;

  // Q-Learning Parameters
  /// The Q-table storing the learned state-action values.
  /// `_qTable[state][action]` holds the estimated future reward for taking `action` in `state`.
  late Map<BabyState, Map<CradleAction, double>> _qTable;
  /// Learning rate (alpha): Controls how much new information overrides old information.
  final double _learningRate = 0.1; // Alpha
  /// Discount factor (gamma): Controls the importance of future rewards (0=short-sighted, 1=far-sighted).
  final double _discountFactor = 0.9; // Gamma
  /// Exploration rate (epsilon): Probability of choosing a random action instead of the best known one.
  final double _epsilon = 0.1; // Exploration rate

  @override
  void initState() {
    super.initState();
    _initializeQTable();
    _pressureMatrix = _generatePressureMatrix(_babyState);
    // Initialize target amplitudes based on initial action
    _targetRockAmplitude = actionRockAmplitudes[_lastAction]!;
    _targetBounceAmplitude = actionBounceAmplitudes[_lastAction]!;
    // Initialize current amplitudes to match target initially
    _currentRockAmplitude = _targetRockAmplitude;
    _currentBounceAmplitude = _targetBounceAmplitude;
    _startAnimation();
    _startSimulationTimer();
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    _simulationTimer?.cancel();
    super.dispose();
  }

  /// Initializes the Q-table with all state-action values set to 0.0.
  void _initializeQTable() {
    _qTable = {};
    for (var state in BabyState.values) {
      _qTable[state] = {};
      for (var action in CradleAction.values) {
        _qTable[state]![action] = 0.0; // Initialize all Q-values to 0
      }
    }
  }

  /// Starts the periodic timer for updating animation phases and interpolating amplitudes.
  void _startAnimation() {
    _animationTimer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (mounted) {
        setState(() {
          // Update phases
          _rockingPhase += 0.1;
          if (_rockingPhase > 2 * pi) _rockingPhase -= 2 * pi;
          _bouncingPhase += 0.15;
          if (_bouncingPhase > 2 * pi) _bouncingPhase -= 2 * pi;

          // Interpolate current amplitudes towards target amplitudes
          // The factor (e.g., 0.1) controls the speed of the transition
          _currentRockAmplitude = _lerp(_currentRockAmplitude, _targetRockAmplitude, 0.08); // Slower transition
          _currentBounceAmplitude = _lerp(_currentBounceAmplitude, _targetBounceAmplitude, 0.08);

          // Optional: Snap to target if very close to avoid tiny fluctuations
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

  /// Linear interpolation helper function.
  double _lerp(double a, double b, double t) {
    return a + (b - a) * t;
  }

  /// Starts the periodic timer that triggers the RL simulation step when auto-learning is enabled.
  void _startSimulationTimer() {
     _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
       if (mounted && _isAuto) {
         _performRlStep();
       } else if (!mounted) {
         timer.cancel();
       }
    });
  }

  // --- Q-Learning Core Logic ---

  /// Finds the action with the highest Q-value for the given [state].
  /// This represents the "best" action currently known by the agent.
  CradleAction _getBestAction(BabyState state) {
    final actions = _qTable[state]!;
    // Find the action with the maximum Q-value
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

  /// Selects an action for the given [state] using the epsilon-greedy strategy.
  /// With probability `_epsilon`, it explores by choosing a random action.
  /// With probability `1 - _epsilon`, it exploits by choosing the best known action.
  CradleAction _chooseAction(BabyState state) {
    if (_random.nextDouble() < _epsilon) {
      // Explore: Choose a random action
      return CradleAction.values[_random.nextInt(CradleAction.values.length)];
    } else {
      // Exploit: Choose the best known action
      return _getBestAction(state);
    }
  }

  /// Updates the Q-value for a given state-action pair based on the observed reward and next state.
  /// Implements the Q-learning update rule:
  /// `Q(s, a) = Q(s, a) + alpha * (reward + gamma * max Q(s', a') - Q(s, a))`
  void _updateQValue(BabyState state, CradleAction action, double reward, BabyState nextState) {
    // Q(s, a) = Q(s, a) + alpha * (reward + gamma * max Q(s', a') - Q(s, a))
    final oldQValue = _qTable[state]![action]!;
    final maxNextQ = _qTable[nextState]![_getBestAction(nextState)]!;
    final newQValue = oldQValue + _learningRate * (reward + _discountFactor * maxNextQ - oldQValue);
    _qTable[state]![action] = newQValue;
  }

  // --- Simulation Model (Environment: Transitions, Rewards, Pressure) ---

  /// Generates a pressure matrix based on the baby's state.
  List<List<int>> _generatePressureMatrix(BabyState state) {
    // Create a base matrix filled with zeros
    List<List<int>> matrix = List.generate(GRID_SIZE, (_) => List.filled(GRID_SIZE, 0));
    // Define the active area mask (relative to GRID_SIZE)
    // Adjusted for 16x16 grid to be proportionally larger
    int r_start = 4, r_end = 10; // Approx 3/8ths of the rows (6 rows)
    int c_start = 6, c_end = 10; // Approx 2/8ths of the columns (4 columns), centered

    for (int i = 0; i < GRID_SIZE; i++) {
      for (int j = 0; j < GRID_SIZE; j++) {
        // Apply mask
        if (i >= r_start && i < r_end && j >= c_start && j < c_end) {
          double basePressure;
          double scale;
          // Use different distributions based on state (approximated)
          switch (state) {
            case BabyState.asleep:
              basePressure = 80.0;
              scale = 6.0; // Corresponds to scale=3 in normal, approx 2*sigma
              break;
            case BabyState.awake:
              basePressure = 100.0;
              scale = 20.0; // Corresponds to scale=10
              break;
            case BabyState.cranky:
              basePressure = 120.0;
              scale = 60.0; // Corresponds to scale=30
              break;
          }
          // Generate value: base + random variation scaled
          // Simple uniform approximation: base +/- (scale / 2)
          double pressureValue = basePressure + (_random.nextDouble() - 0.5) * scale;
          // Clip and convert to int
          matrix[i][j] = pressureValue.clamp(0, 255).toInt();
        }
      }
    }
    return matrix;
  }

  /// Simulates the baby's state transition based on the [currentState] and the agent's chosen [action].
  /// Returns the [BabyState] the baby transitions into.
  /// **Note:** These transition probabilities are defined heuristically and are crucial
  /// for the agent's learning behavior. Tuning these is key to realistic simulation.
  BabyState _getNextState(BabyState currentState, CradleAction action) {
    double rand = _random.nextDouble();
    // Define transition probabilities P(next_state | currentState, action)
    // These probabilities are crucial and need careful tuning!
    switch (currentState) {
      case BabyState.asleep:
        if (action == CradleAction.no_action) {
          return rand < 0.05 ? BabyState.awake : BabyState.asleep; // 5% wake up
        } else if (action == CradleAction.rock_gentle) {
          return rand < 0.15 ? BabyState.awake : BabyState.asleep; // 15% wake up
        } else if (action == CradleAction.rock_strong) {
          return rand < 0.30 ? BabyState.awake : BabyState.asleep; // 30% wake up
        } else if (action == CradleAction.bounce_gentle) {
          return rand < 0.20 ? BabyState.awake : BabyState.asleep; // 20% wake up (bouncing more disruptive)
        } else { // bounce_strong
          return rand < 0.40 ? BabyState.awake : BabyState.asleep; // 40% wake up
        }
      case BabyState.awake:
        if (action == CradleAction.no_action) {
          if (rand < 0.05) return BabyState.asleep;
          if (rand < 0.25) return BabyState.cranky; // 20% chance -> cranky
          return BabyState.awake;
        } else if (action == CradleAction.rock_gentle) {
           if (rand < 0.15) return BabyState.asleep;
           if (rand < 0.25) return BabyState.cranky; // 10% chance -> cranky
           return BabyState.awake;
        } else if (action == CradleAction.rock_strong) {
           if (rand < 0.30) return BabyState.asleep;
           if (rand < 0.35) return BabyState.cranky; // 5% chance -> cranky
           return BabyState.awake;
        } else if (action == CradleAction.bounce_gentle) {
           if (rand < 0.12) return BabyState.asleep; // 12% sleep (slightly less effective than gentle rock?)
           if (rand < 0.22) return BabyState.cranky; // 10% cranky
           return BabyState.awake;
        } else { // bounce_strong
           if (rand < 0.25) return BabyState.asleep; // 25% sleep (less effective than strong rock?)
           if (rand < 0.30) return BabyState.cranky; // 5% cranky
           return BabyState.awake;
        }
      case BabyState.cranky:
        if (action == CradleAction.no_action) {
          return rand < 0.20 ? BabyState.awake : BabyState.cranky; // 80% stay cranky
        } else if (action == CradleAction.rock_gentle) {
          if (rand < 0.10) return BabyState.asleep;
          if (rand < 0.40) return BabyState.awake; // 30% -> awake
          return BabyState.cranky;
        } else if (action == CradleAction.rock_strong) {
          if (rand < 0.40) return BabyState.asleep;
          if (rand < 0.60) return BabyState.awake; // 20% -> awake
          return BabyState.cranky;
        } else if (action == CradleAction.bounce_gentle) {
          if (rand < 0.15) return BabyState.asleep; // Gentle bounce helps a bit
          if (rand < 0.50) return BabyState.awake; // 35% -> awake
          return BabyState.cranky;
        } else { // bounce_strong
          if (rand < 0.45) return BabyState.asleep; // Strong bounce quite effective
          if (rand < 0.70) return BabyState.awake; // 25% -> awake
          return BabyState.cranky;
        }
    }
  }

  /// Calculates the reward signal for the agent based on the transition.
  /// The reward guides the learning process.
  /// Positive rewards for desirable states (asleep), negative for undesirable (cranky).
  /// Penalties can be added for potentially disruptive actions or effort.
  double _getReward(BabyState previousState, BabyState currentState, CradleAction action) {
    double reward = 0;

    // Reward based on resulting state
    if (currentState == BabyState.asleep) reward += 10;
    if (currentState == BabyState.awake) reward += 0;
    if (currentState == BabyState.cranky) reward -= 10;

    // Penalty for potentially disturbing actions when baby is asleep
    if (previousState == BabyState.asleep) {
      if (action == CradleAction.rock_gentle) reward -= 1;
      if (action == CradleAction.rock_strong) reward -= 3;
      if (action == CradleAction.bounce_gentle) reward -= 2; // Bouncing more disruptive
      if (action == CradleAction.bounce_strong) reward -= 5;
    }

    // Small penalty for effort (optional)
    // if (action == CradleAction.rock_gentle || action == CradleAction.bounce_gentle) reward -= 0.1;
    // if (action == CradleAction.rock_strong || action == CradleAction.bounce_strong) reward -= 0.5;

    return reward;
  }

  // --- RL Step Execution & Control ---

  /// Performs one full step of the Reinforcement Learning cycle:
  /// 1. Agent observes current state (`_babyState`).
  /// 2. Agent chooses an action (`_chooseAction`).
  /// 3. Environment reacts: Simulates state transition (`_getNextState`).
  /// 4. Environment provides reward (`_getReward`).
  /// 5. Agent learns: Updates Q-table (`_updateQValue`).
  /// 6. State updates for the next cycle.
  void _performRlStep() {
     if (!mounted) return;
     final currentState = _babyState;

     // 1. Choose action
     final chosenAction = _chooseAction(currentState);
     _lastAction = chosenAction;

     // 2. Simulate environment reaction (get next state)
     final nextState = _getNextState(currentState, chosenAction);

     // 3. Calculate reward
     final reward = _getReward(currentState, nextState, chosenAction);

     // 4. Learn: Update Q-Table
     _updateQValue(currentState, chosenAction, reward, nextState);

     // 5. Update state & visuals
     setState(() {
       _babyState = nextState;
       _pressureMatrix = _generatePressureMatrix(nextState);
       // Set the *target* amplitudes based on the new action
       _updateTargetAmplitudes();
     });
  }

  /// Updates the *target* visual amplitudes based on the last action taken.
  void _updateTargetAmplitudes(){
      _targetRockAmplitude = actionRockAmplitudes[_lastAction]!;
      _targetBounceAmplitude = actionBounceAmplitudes[_lastAction]!;
  }

  /// Helper function to print the current Q-table values to the console for debugging.
  // void printQTable() {
  //   print("--- Q-Table ---");
  //   _qTable.forEach((state, actions) {
  //     actions.forEach((action, value) {
  //       print("Q(${stateToString(state)}, ${actionToString(action)}): ${value.toStringAsFixed(2)}");
  //     });
  //   });
  //   print("---------------");
  // }

  /// Toggles the automatic learning mode (`_isAuto`).
  void _toggleAuto() {
    setState(() {
      _isAuto = !_isAuto;
      // Optionally reset phase or state when toggling auto?
    });
  }

  @override
  Widget build(BuildContext context) {
    // Calculate visual offsets using the *interpolated current* amplitudes
    double currentDx = sin(_rockingPhase) * _currentRockAmplitude;
    double currentDy = sin(_bouncingPhase) * _currentBounceAmplitude;
    // Calculate reasonable size for the grid based on screen width
    double screenWidth = MediaQuery.of(context).size.width;
    double gridViewSize = min(screenWidth * 0.8, 300.0); // Limit max size
    double cellSize = gridViewSize / GRID_SIZE;

    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: SingleChildScrollView(
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
               const SizedBox(height: 20), // Add padding top
               // Display current Baby State
               Text(
                'Baby State:',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
               Text(
                stateToString(_babyState), // Display current state string
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _babyState == BabyState.cranky ? Colors.red : (_babyState == BabyState.awake ? Colors.orange : Colors.green)
                ),
              ),
              const SizedBox(height: 10),
              // Display the action the agent chose
              Text(
                'Agent Action:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                actionToString(_lastAction),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.blueGrey
                ),
              ),
              const SizedBox(height: 20),

              // CustomPaint widget to draw the rocking cradle
              CustomPaint(
                size: const Size(200, 100),
                painter: CradlePainter(dxOffset: currentDx, dyOffset: currentDy),
              ),

              const SizedBox(height: 30),

              // --- Pressure Mat Grid --- 
            Text(
                'Pressure Mat:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: gridViewSize,
                height: gridViewSize,
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: GRID_SIZE,
                    mainAxisSpacing: 1, // Small spacing between cells
                    crossAxisSpacing: 1,
                  ),
                  itemCount: GRID_SIZE * GRID_SIZE,
                  physics: const NeverScrollableScrollPhysics(), // Disable scrolling within grid
                  itemBuilder: (context, index) {
                    int row = index ~/ GRID_SIZE;
                    int col = index % GRID_SIZE;
                    int pressureValue = _pressureMatrix[row][col];
                    // Map pressure value (0-255) to grayscale color
                    Color cellColor = pressureValue == 0
                        ? Colors.white // White for zero pressure
                        : Color.fromRGBO(pressureValue, pressureValue, pressureValue, 1.0);
                    return Container(
                      width: cellSize,
                      height: cellSize,
                      decoration: BoxDecoration(
                        color: cellColor,
                        border: Border.all(color: Colors.grey.shade300, width: 0.5),
                      ),
                    );
                  },
                ),
              ),
              // --- End Pressure Mat Grid --- 

              const SizedBox(height: 30),

              // Control buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _performRlStep,
                    child: const Text('Perform RL Step'),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: _toggleAuto,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isAuto ? Colors.blue[100] : null,
                    ),
                    child: Text('Auto Learn: ${_isAuto ? "ON" : "OFF"}'),
                  ),
                ],
              ),
               const SizedBox(height: 20), // Add padding bottom
            ],
          ),
        ),
      ),
    );
  }
}


/// A [CustomPainter] responsible for drawing the cradle visual.
/// Takes a horizontal offset [dxOffset] and a vertical offset [dyOffset] to create the rocking animation.
class CradlePainter extends CustomPainter {
  /// The horizontal offset (displacement) from the center, used for rocking.
  final double dxOffset;
  /// The vertical offset (displacement) from the center, used for bouncing.
  final double dyOffset;

  CradlePainter({required this.dxOffset, required this.dyOffset});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint standPaint = Paint()
      ..color = Colors.brown[700]! // saddlebrown approx
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke; // Use stroke for lines

     final Paint basketPaint = Paint()
      ..color = Colors.brown[300]! // burlywood approx
      ..style = PaintingStyle.fill;

     final Paint basketOutlinePaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;


    // Dimensions (relative to the CustomPaint size)
    double canvasCenterX = size.width / 2;
    double canvasCenterY = size.height / 2; // Use center Y for vertical positioning
    double cradleBodyWidth = size.width * 0.6; // Relative width
    double cradleBodyHeight = size.height * 0.5;
    double standHeight = size.height * 0.2;
    double standWidth = cradleBodyWidth + size.width * 0.15;
    double totalCradleHeight = cradleBodyHeight + standHeight;

    // Calculate current center based on offset
    double currentCenterX = canvasCenterX + dxOffset;
    double currentCenterY = canvasCenterY + dyOffset;

    // Calculate base Y position (bottom of the stand)
    double standBaseY = size.height * 0.9 + dyOffset; // Apply bounce offset here
    double standTopY = standBaseY - standHeight;
    double basketBottomY = standTopY; // Basket sits on top of stand line
    double basketTopY = basketBottomY - cradleBodyHeight;


    // Basket coordinates
    double basketLeftX = currentCenterX - cradleBodyWidth / 2;
    double basketRightX = currentCenterX + cradleBodyWidth / 2;
    Rect basketRect = Rect.fromPoints(Offset(basketLeftX, basketTopY), Offset(basketRightX, basketBottomY + cradleBodyHeight * 0.2)); // Extend rect down for fuller arc

    // Draw basket body (filled chord)
    canvas.drawArc(basketRect, 0, pi, true, basketPaint);
    // Draw basket rim (stroke arc)
    canvas.drawArc(basketRect, 0, pi, false, basketOutlinePaint);


    // Stand coordinates
    double standLeftBaseX = currentCenterX - standWidth / 2;
    double standRightBaseX = currentCenterX + standWidth / 2;
    // Stand top points connect near the basket ends
    double standLeftTopX = currentCenterX - cradleBodyWidth / 2;
    double standRightTopX = currentCenterX + cradleBodyWidth / 2;

    // Draw stand legs
    canvas.drawLine(Offset(standLeftBaseX, standBaseY), Offset(standLeftTopX, standTopY), standPaint);
    canvas.drawLine(Offset(standRightBaseX, standBaseY), Offset(standRightTopX, standTopY), standPaint);
    // Draw stand top bar
    canvas.drawLine(Offset(standLeftTopX, standTopY), Offset(standRightTopX, standTopY), standPaint);

  }

  @override
  bool shouldRepaint(covariant CradlePainter oldDelegate) {
    // Repaint only if the offset changes
    return oldDelegate.dxOffset != dxOffset || oldDelegate.dyOffset != dyOffset;
  }
}
