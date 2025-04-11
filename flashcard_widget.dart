import 'package:flutter/material.dart';
import 'package:flip_card/flip_card.dart';
import '../models/flashcard.dart';

class FlashcardWidget extends StatelessWidget {
  final Flashcard flashcard;
  final VoidCallback onTapAudio;
  final GlobalKey<FlipCardState> cardKey = GlobalKey<FlipCardState>();

  FlashcardWidget({
    super.key,
    required this.flashcard,
    required this.onTapAudio,
  });

  @override
  Widget build(BuildContext context) {
    return FlipCard(
      key: cardKey,
      direction: FlipDirection.HORIZONTAL,
      speed: 400,
      front: _buildFrontCard(context),
      back: _buildBackCard(context),
    );
  }

  Widget _buildFrontCard(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.8),
              Theme.of(context).colorScheme.primary.withOpacity(0.6),
            ],
          ),
        ),
        // Make content scrollable
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Arabic Text
              Text(
                flashcard.arabic,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontFamily: 'Cairo',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Audio and Flip buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Audio button
                  ElevatedButton.icon(
                    onPressed: onTapAudio,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    icon: const Icon(Icons.volume_up),
                    label: const Text('Listen'),
                  ),
                  const SizedBox(width: 16),

                  // Flip button
                  OutlinedButton.icon(
                    onPressed: () {
                      cardKey.currentState?.toggleCard();
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.3),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                    ),
                    icon: const Icon(Icons.flip),
                    label: const Text('Flip'),
                  ),
                ],
              ),

              // Hint
              const Padding(
                padding: EdgeInsets.only(top: 20.0),
                child: Text(
                  'Tap or swipe card to flip',
                  style: TextStyle(color: Colors.white70),
                ),
              ),

              // Category and Difficulty
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Chip(
                      label: Text(flashcard.category),
                      backgroundColor: Colors.white.withOpacity(0.3),
                      labelStyle: const TextStyle(color: Colors.white),
                      padding: const EdgeInsets.all(4),
                    ),
                    const SizedBox(width: 8),
                    Chip(
                      label: Text(flashcard.difficulty),
                      backgroundColor: Colors.white.withOpacity(0.3),
                      labelStyle: const TextStyle(color: Colors.white),
                      padding: const EdgeInsets.all(4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackCard(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
        ),
        // Make content scrollable
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Transliteration
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Transliteration',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      flashcard.transliteration,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Translation
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).primaryColor.withOpacity(0.5),
                  ),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Translation',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      flashcard.translation,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Example
              if (flashcard.example.arabic.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Example',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        flashcard.example.arabic,
                        style: const TextStyle(
                          fontSize: 20,
                          fontFamily: 'Cairo',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        flashcard.example.transliteration,
                        style: const TextStyle(
                          fontSize: 16,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        flashcard.example.translation,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

              // Flip button
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: ElevatedButton.icon(
                  onPressed: () {
                    cardKey.currentState?.toggleCard();
                  },
                  icon: const Icon(Icons.flip),
                  label: const Text('Flip Back'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
