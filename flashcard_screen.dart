import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import '../models/flashcard.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../services/tts_service.dart';
import '../utils/spaced_repetition.dart';
import '../widgets/flashcard_widget.dart';

class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({super.key});

  @override
  State<FlashcardScreen> createState() {
    return _FlashcardScreenState();
  }
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  List<Flashcard> _flashcards = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isLoadingNextBatch = false;
  bool _isSpeaking = false;
  final TTSService _ttsService = TTSService();
  final _logger = Logger();

  // Configuration for pagination
  static const int batchSize = 10;
  bool _hasMoreCards = true;

  @override
  void initState() {
    super.initState();
    // Use microtask to avoid blocking the UI during initialization
    Future.microtask(() => _initializeAndLoadFlashcards());
  }

  Future<void> _initializeAndLoadFlashcards() async {
    try {
      _logger.i('Initializing flashcard screen');

      // Initialize TTS service in parallel with loading initial flashcards
      final ttsInit = _ttsService.init();

      // Load first batch of flashcards
      await _loadFlashcards();

      // Wait for TTS to complete initialization if needed
      await ttsInit;

      _logger.i('Flashcard screen initialization complete');
    } catch (e) {
      _logger.e('Error during initialization: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during initialization: $e')),
        );
      }
    }
  }

  Future<void> _loadFlashcards() async {
    if (_isLoadingNextBatch) return;

    setState(() {
      _isLoading = true;
      _isLoadingNextBatch = true;
    });

    try {
      _logger.d(
          'Loading flashcards: offset=${_flashcards.length}, limit=$batchSize');

      // Force going to the API instead of using local database
      await _fetchCardsFromApi();
    } catch (e) {
      _logger.e('Error loading flashcards: $e');

      if (mounted) {
        // Show error to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load flashcards: $e')),
        );

        setState(() {
          _isLoadingNextBatch = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchCardsFromApi() async {
    try {
      _logger.d('Fetching flashcards from API');

      final apiService = Provider.of<ApiService>(context, listen: false);
      final databaseService =
          Provider.of<DatabaseService>(context, listen: false);

      // Get flashcards from API - IMPORTANT: NOT using dueOnly filter
      final remoteFlashcards = await apiService.getFlashcards(dueOnly: false);
      _logger.d('Received ${remoteFlashcards.length} flashcards from API');

      // Save to local database for faster access next time
      await databaseService.saveFlashcards(remoteFlashcards);

      if (mounted) {
        setState(() {
          _flashcards = remoteFlashcards;
          _isLoading = false;
          _hasMoreCards = false;
        });
      }
    } catch (e) {
      _logger.e('Error fetching flashcards from API: $e');
      rethrow; // Re-throw to be caught by the parent method
    }
  }

  Future<void> _speakArabic() async {
    if (_currentIndex < _flashcards.length) {
      // Prevent multiple simultaneous playbacks
      if (_isSpeaking) {
        await _ttsService.stop();
      }

      setState(() {
        _isSpeaking = true;
      });

      final arabicText = _flashcards[_currentIndex].arabic;
      _logger.d('Speaking Arabic text: $arabicText');

      // Show a visual indicator that the audio is playing
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.volume_up, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Playing: $arabicText',
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
              ),
            ],
          ),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

      try {
        await _ttsService.speak(arabicText);
        // Add a short delay to ensure audio finishes playing
        await Future.delayed(Duration(seconds: 3));
      } catch (e) {
        _logger.e('Error during speech: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isSpeaking = false;
          });
        }
      }
    }
  }

  // Check if we need to load more cards
  void _checkLoadMoreCards() {
    // If we're near the end of the loaded cards, load more
    if (_hasMoreCards && _currentIndex >= _flashcards.length - 3) {
      _logger.d('Near end of loaded cards, loading more');
      _loadFlashcards();
    }
  }

  Future<void> _rateFlashcard(int quality) async {
    if (_currentIndex >= _flashcards.length || _isSubmitting) return;

    // Stop any audio that might be playing
    if (_isSpeaking) {
      await _ttsService.stop();
      setState(() {
        _isSpeaking = false;
      });
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final currentCard = _flashcards[_currentIndex];
      _logger.d('Rating flashcard ${currentCard.id} with quality $quality');
      _logger.d('Raw flashcard ID before processing: ${currentCard.id}');
      _logger.d('Flashcard data: ${currentCard.toJson()}');

      // Calculate next review using spaced repetition algorithm
      final updatedCard =
          SpacedRepetition.calculateNextReview(currentCard, quality);
      _logger.d(
          'New interval: ${updatedCard.interval}, next due date: ${updatedCard.dueDate}');

      // Update local database immediately
      final databaseService =
          Provider.of<DatabaseService>(context, listen: false);
      await databaseService.updateFlashcard(updatedCard);

      // Update API in the background without waiting
      _updateApiInBackground(currentCard.id, quality);

      // Move to next card
      setState(() {
        _currentIndex++;
        _isSubmitting = false;
      });

      // Check if we need to load more cards
      _checkLoadMoreCards();

      // Check if we've completed all cards
      if (_currentIndex >= _flashcards.length && !_hasMoreCards) {
        _logger.i('All flashcards completed');
        _showCompletionDialog();
      }
    } catch (e) {
      _logger.e('Error rating flashcard: $e');

      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to rate flashcard: $e')),
        );
      }
    }
  }

  // Update API without blocking the UI
  Future<void> _updateApiInBackground(String cardId, int quality) async {
    try {
      _logger.d(
          'Updating flashcard $cardId with quality $quality in API (background)');
      final apiService = Provider.of<ApiService>(context, listen: false);
      await apiService.updateFlashcardProgress(cardId, quality);
      _logger.d('API update completed successfully');
    } catch (e) {
      _logger.w('Failed to update API with flashcard progress: $e');
      // Non-critical error, app can continue functioning
    }
  }

  void _showCompletionDialog() {
    _logger.d('Showing completion dialog');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Great Job!'),
        content: const Text('You\'ve completed all your flashcards for now.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close the dialog
              // Replace named route navigation with this:
              Navigator.of(context).popUntil((route) => route.isFirst);
              _logger.d('User navigated back to home after completion');
            },
            child: const Text('Back to Home'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Reset state and reload flashcards
              setState(() {
                _flashcards = [];
                _currentIndex = 0;
                _hasMoreCards = true;
              });
              _logger.d('User chose to practice more, reloading cards');
              _loadFlashcards();
            },
            child: const Text('Practice More'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flashcards'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Reset state and reload flashcards
              setState(() {
                _flashcards = [];
                _currentIndex = 0;
                _hasMoreCards = true;
              });
              _logger.d('Manual refresh triggered');
              _loadFlashcards();
            },
            tooltip: 'Reload Flashcards',
          ),
        ],
      ),
      body: _isLoading && _flashcards.isEmpty
          ? _buildLoadingState()
          : _flashcards.isEmpty
              ? _buildEmptyState()
              : _buildFlashcardView(),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Loading your flashcards...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    _logger.d('Showing empty state (no cards due)');
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 80,
            color: Colors.green[300],
          ),
          const SizedBox(height: 16),
          Text(
            'All Caught Up!',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              'You\'ve completed all your flashcards for now. Check back later for more!',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              _logger.d('User navigating back to home from empty state');
              Navigator.pop(context); // Return to home screen
            },
            child: const Text('Back to Home'),
          ),
        ],
      ),
    );
  }

  Widget _buildFlashcardView() {
    if (_currentIndex >= _flashcards.length) {
      // Show loading indicator while getting more cards
      if (_hasMoreCards && _isLoadingNextBatch) {
        return const Center(child: CircularProgressIndicator());
      }
      // All cards completed
      return _buildEmptyState();
    }

    final currentCard = _flashcards[_currentIndex];
    _logger.d(
        'Displaying flashcard: ${currentCard.id}, ${_currentIndex + 1}/${_flashcards.length}');

    return SafeArea(
      child: Column(
        children: [
          // Progress indicator
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: (_currentIndex + 1) /
                      (_flashcards.length + (_hasMoreCards ? batchSize : 0)),
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).primaryColor),
                ),
                const SizedBox(height: 4),
                Text(
                  'Card ${_currentIndex + 1} of ${_hasMoreCards ? '${_flashcards.length}+' : _flashcards.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),

          // Flashcard
          // Flashcard
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: FlashcardWidget(
                flashcard: currentCard,
                onTapAudio: () {
                  if (_isSpeaking) {
                    // Show feedback that speech is already in progress
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Audio is already playing'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  } else {
                    _speakArabic();
                  }
                },
              ),
            ),
          ),
          // Show loading indicator below the card if loading next batch
          if (_isLoadingNextBatch && _currentIndex > _flashcards.length - 3)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).primaryColor.withAlpha(128)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Loading more cards...',
                    style: TextStyle(
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withAlpha(179),
                    ),
                  ),
                ],
              ),
            ),

          // Rating buttons
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'How well did you remember this?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildRatingButton(0, Colors.red[700]!, 'Forgot'),
                    _buildRatingButton(3, Colors.orange[700]!, 'Hard'),
                    _buildRatingButton(4, Colors.blue[700]!, 'Good'),
                    _buildRatingButton(5, Colors.green[700]!, 'Easy'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingButton(int quality, Color color, String label) {
    return ElevatedButton(
      onPressed:
          (_isSubmitting || _isSpeaking) ? null : () => _rateFlashcard(quality),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        // Add disabled style for better UX
        disabledBackgroundColor: color.withAlpha(77),
      ),
      child: _isSubmitting
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(label),
    );
  }

  @override
  void dispose() {
    _logger.d('Disposing FlashcardScreen');
    _ttsService.dispose();
    super.dispose();
  }
}
