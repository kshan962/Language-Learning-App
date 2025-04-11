import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _isLoading = true;
  User? _user;
  int _dueFlashcards = 0;
  int _knownWords = 0;
  int _currentStreak = 0;

  // Add a flag to prevent multiple simultaneous data loads
  bool _isDataLoading = false;

  // Add logger
  final _logger = Logger();

  @override
  void initState() {
    super.initState();
    // Register observer for app lifecycle events
    WidgetsBinding.instance.addObserver(this);
    // Delay API calls slightly to avoid competing with initial render
    Future.microtask(() => _loadUserData(forceRefresh: true));
    // Check for force refresh flag on startup
    Future.microtask(() => _checkForceRefreshFlag());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkForceRefreshFlag();
    // Reload user data when dependencies change (including auth state)
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser != null) {
      _loadUserData(forceRefresh: true);
    }
  }

  // Check for force refresh flag when screen becomes visible
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkForceRefreshFlag();
    }
  }

  // Check if we need to force refresh data (e.g., after reset progress)
  Future<void> _checkForceRefreshFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final forceRefresh = prefs.getBool('force_refresh_home') ?? false;

      if (forceRefresh) {
        _logger.i('Force refresh flag detected, reloading data');
        // Clear the flag
        await prefs.setBool('force_refresh_home', false);
        // Reload data with force refresh
        _loadUserData(forceRefresh: true);
      }
    } catch (e) {
      _logger.e('Error checking force refresh flag: $e');
    }
  }

  Future<void> _loadUserData({bool forceRefresh = false}) async {
    // Prevent multiple simultaneous data loads, unless force refresh is requested
    if (_isDataLoading && !forceRefresh) {
      _logger.d('Data already loading, ignoring request');
      return;
    }

    _logger.i('Loading user data');
    setState(() {
      _isDataLoading = true;
    });

    try {
      // First try to get data from local database for immediate display
      final databaseService =
          Provider.of<DatabaseService>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentFirebaseUser = authService.currentUser;

      if (currentFirebaseUser != null) {
        _logger.d('Firebase user found, loading local data');
        // Load local data first, bypassing cache to ensure fresh data
        final localUser = await databaseService.getUser(currentFirebaseUser.uid,
            bypassCache: true);
        final dueCards = await databaseService.getFlashcards(dueOnly: true);
        final knownCards = await databaseService.getKnownFlashcards();

        _logger.d(
            'Local data loaded: user=${localUser?.username}, dueCards=${dueCards.length}, knownCards=${knownCards.length}');

        // Update UI with local data immediately
        if (mounted) {
          setState(() {
            _user = localUser;
            _dueFlashcards = dueCards.length;
            _knownWords = knownCards.length;
            _currentStreak = localUser?.streak ?? 0;
            _isLoading = false;
          });
        }

        // Then fetch fresh data from API in background
        _fetchRemoteData();
      } else {
        _logger.w('No Firebase user found');
        setState(() {
          _isLoading = false;
          _isDataLoading = false;
        });
      }
    } catch (e) {
      _logger.e('Error loading initial user data: $e');

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isDataLoading = false;
        });
      }
    }
  }

  // Separate method to fetch remote data after local data is displayed
  // Fixed version to avoid using BuildContext across async gaps
  // Separate method to fetch remote data after local data is displayed
  Future<void> _fetchRemoteData() async {
    try {
      _logger.d('Fetching remote data from API');

      // Store the context and services before any async operation
      final apiService = Provider.of<ApiService>(context, listen: false);
      final databaseService =
          Provider.of<DatabaseService>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);

      // Check if user is authenticated before making API call
      if (authService.currentUser == null) {
        _logger.w('User not authenticated, skipping remote data fetch');
        if (mounted) {
          setState(() {
            _isDataLoading = false;
          });
        }
        return;
      }

      try {
        // Now we can use await without the risk of context changing
        final user = await apiService.getUserProfile();
        _logger.d('Remote user data received: ${user.username}');

        // Save the user data to the database to ensure it's up to date
        await databaseService.saveUser(user);
        _logger.d('User data saved to database');

        // Get updated flashcard counts
        final dueCards = await databaseService.getFlashcards(dueOnly: true);
        final knownCards = await databaseService.getKnownFlashcards();
        _logger.d(
            'Remote flashcard counts: due=${dueCards.length}, known=${knownCards.length}');

        // Check if mounted before using setState
        if (mounted) {
          setState(() {
            _user = user;
            _dueFlashcards = dueCards.length;
            _knownWords = knownCards.length;
            _currentStreak = user.streak;
            _isDataLoading = false;
          });
          _logger.i('Home screen updated with remote data');
        }
      } catch (apiError) {
        // Handle "User not found" error specifically
        if (apiError.toString().contains('User not found')) {
          _logger.w(
              'User not found in backend API, attempting to register Google user');

          // Try to register the Google user in the backend
          bool registered = await authService.registerGoogleUserInBackend();

          if (registered) {
            _logger.i(
                'Google user registered successfully, fetching profile again');

            // Try to fetch the profile again after registration
            try {
              final user = await apiService.getUserProfile();
              _logger.d(
                  'Successfully fetched profile after registration: ${user.username}');

              // Save the user data
              await databaseService.saveUser(user);

              // Get updated flashcard counts
              final dueCards =
                  await databaseService.getFlashcards(dueOnly: true);
              final knownCards = await databaseService.getKnownFlashcards();

              // Update the UI
              if (mounted) {
                setState(() {
                  _user = user;
                  _dueFlashcards = dueCards.length;
                  _knownWords = knownCards.length;
                  _currentStreak = user.streak;
                  _isDataLoading = false;
                });
                _logger.i(
                    'Home screen updated with remote data after registration');
                return;
              }
            } catch (e) {
              _logger.e('Still failed to get user after registration: $e');
            }
          }

          _logger.w('User not found in backend API, using local data only');
        } else {
          _logger.e('API error: $apiError');
        }

        // Continue with local data only
        if (mounted) {
          setState(() {
            _isDataLoading = false;
          });
        }
      }
    } catch (e) {
      _logger.e('Error loading remote user data: $e');

      // No need to show error if we already have local data
      if (mounted) {
        setState(() {
          _isDataLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arabic Learning'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              _logger.d('Navigating to settings screen');
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: _isLoading
          ? _buildLoadingView()
          : RefreshIndicator(
              onRefresh: () => _loadUserData(forceRefresh: true),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWelcomeSection(),
                    const SizedBox(height: 24),
                    _buildProgressSection(),
                    const SizedBox(height: 24),
                    _buildActionButtons(),
                    const SizedBox(height: 24),
                    _buildLearningTips(),
                  ],
                ),
              ),
            ),
    );
  }

  // Enhanced loading view with shimmer effect for better UX during loading
  Widget _buildLoadingView() {
    _logger.d('Building loading view');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome section skeleton
          _buildSkeletonText(width: 200, height: 30),
          const SizedBox(height: 8),
          _buildSkeletonText(width: 280, height: 18),

          const SizedBox(height: 24),

          // Progress section skeleton
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSkeletonText(width: 120, height: 24),
                      _buildSkeletonText(width: 100, height: 20),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSkeletonProgressItem(),
                      _buildSkeletonProgressItem(),
                      _buildSkeletonProgressItem(),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Action buttons skeleton
          _buildSkeletonText(width: 180, height: 24),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildSkeletonButton(height: 120)),
              const SizedBox(width: 16),
              Expanded(child: _buildSkeletonButton(height: 120)),
            ],
          ),

          const SizedBox(height: 24),

          // Tips skeleton
          _buildSkeletonText(width: 150, height: 24),
          const SizedBox(height: 16),
          _buildSkeletonTipItem(),
          const SizedBox(height: 12),
          _buildSkeletonTipItem(),
        ],
      ),
    );
  }

  // Skeleton widgets for loading state
  Widget _buildSkeletonText({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildSkeletonProgressItem() {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 8),
        _buildSkeletonText(width: 40, height: 24),
        const SizedBox(height: 4),
        _buildSkeletonText(width: 60, height: 14),
      ],
    );
  }

  Widget _buildSkeletonButton({required double height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  Widget _buildSkeletonTipItem() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSkeletonText(width: 100, height: 16),
                  const SizedBox(height: 8),
                  _buildSkeletonText(width: double.infinity, height: 14),
                  const SizedBox(height: 4),
                  _buildSkeletonText(width: double.infinity, height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The rest of the methods remain the same as in your original code
  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.person,
                    size: 30,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Arabic Companion',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Home'),
            onTap: () {
              _logger.d('Home selected in drawer');
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.style),
            title: const Text('Flashcards'),
            onTap: () {
              _logger.d('Flashcards selected in drawer');
              Navigator.pop(context);
              Navigator.pushNamed(context, '/flashcards');
            },
          ),
          ListTile(
            leading: const Icon(Icons.chat),
            title: const Text('Conversation Practice'),
            onTap: () {
              _logger.d('Conversation selected in drawer');
              Navigator.pop(context);
              Navigator.pushNamed(context, '/conversation');
            },
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profile'),
            onTap: () {
              _logger.d('Profile selected in drawer');
              Navigator.pop(context);
              Navigator.pushNamed(context, '/profile');
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              _logger.d('Settings selected in drawer');
              Navigator.pop(context);
              Navigator.pushNamed(context, '/settings');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.exit_to_app),
            title: const Text('Sign Out'),
            onTap: () async {
              _logger.i('User signing out');
              Navigator.pop(context);
              await Provider.of<AuthService>(context, listen: false).signOut();
              // Navigation is handled by AuthWrapper in main.dart
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeSection() {
    final greeting = _getGreeting();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting!',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Continue your Arabic learning journey.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildProgressSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Your Progress',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  'Level: ${_user?.arabicLevel ?? 'Beginner'}',
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildProgressItem(
                  icon: Icons.style,
                  value: '$_dueFlashcards',
                  label: 'Due Today',
                  color: Colors.orange,
                ),
                _buildProgressItem(
                  icon: Icons.check_circle,
                  value: '$_knownWords',
                  label: 'Words Learned',
                  color: Colors.green,
                ),
                _buildProgressItem(
                  icon: Icons.local_fire_department,
                  value: '$_currentStreak',
                  label: 'Day Streak',
                  color: Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          color: color,
          size: 32,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Continue Learning',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.style,
                label: 'Review Flashcards',
                color: Colors.blue,
                onTap: () {
                  _logger.d('Review Flashcards button tapped');
                  Navigator.pushNamed(context, '/flashcards');
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildActionButton(
                icon: Icons.chat,
                label: 'Practice Conversation',
                color: Colors.green,
                onTap: () {
                  _logger.d('Practice Conversation button tapped');
                  Navigator.pushNamed(context, '/conversation');
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withAlpha(26),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withAlpha(77),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: color,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLearningTips() {
    final List<Map<String, dynamic>> tips = [
      {
        'title': 'Practice Daily',
        'description':
            'Consistency is key to language learning. Even 5 minutes a day makes a difference.',
        'icon': Icons.calendar_today,
      },
      {
        'title': 'Listen Carefully',
        'description':
            'Pay attention to native pronunciation and try to mimic it accurately.',
        'icon': Icons.hearing,
      },
      {
        'title': 'Use in Conversation',
        'description':
            'Apply new vocabulary in the conversation practice to reinforce learning.',
        'icon': Icons.chat_bubble,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Learning Tips',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        ...tips.map((tip) => _buildTipItem(
              title: tip['title'],
              description: tip['description'],
              icon: tip['icon'],
            )),
      ],
    );
  }

  Widget _buildTipItem({
    required String title,
    required String description,
    required IconData icon,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: Theme.of(context).primaryColor,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning';
    } else if (hour < 17) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }

  @override
  void dispose() {
    _logger.d('Disposing HomeScreen');
    // Remove observer when widget is disposed
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
