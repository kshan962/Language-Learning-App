import '../models/flashcard.dart';

/// SuperMemo SM-2 algorithm for spaced repetition
class SpacedRepetition {
  /// Calculate the next review interval based on user response quality
  /// Quality is from 0 to 5, where:
  /// 0 = complete blackout
  /// 1 = incorrect response; the correct answer remembered
  /// 2 = incorrect response; the correct answer seemed easy to recall
  /// 3 = correct response, but with difficulty
  /// 4 = correct response, with some hesitation
  /// 5 = perfect response
  static Flashcard calculateNextReview(Flashcard card, int quality) {
    // Ensure quality is between 0 and 5
    quality = quality.clamp(0, 5);

    // Calculate new E-Factor (measure of how easy the card is to remember)
    double newEFactor =
        card.efactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));

    // EFactor should not be less than 1.3
    if (newEFactor < 1.3) newEFactor = 1.3;

    int newInterval;
    int newRepetition;

    if (quality < 3) {
      // If quality is less than 3, reset repetition count
      newInterval = 1;
      newRepetition = 0;
    } else {
      // Increase repetition count
      newRepetition = card.repetition + 1;

      // Calculate next interval
      if (newRepetition == 1) {
        newInterval = 1;
      } else if (newRepetition == 2) {
        newInterval = 6;
      } else {
        // For repetition > 2, use the formula: interval = previous interval * E-Factor
        newInterval = (card.interval * newEFactor).round();
      }
    }

    // Calculate next due date
    final nextDueDate = DateTime.now().add(Duration(days: newInterval));

    // Return updated flashcard
    return card.copyWith(
      interval: newInterval,
      repetition: newRepetition,
      efactor: newEFactor,
      dueDate: nextDueDate,
    );
  }

  /// Get due cards for today
  static List<Flashcard> getDueCards(List<Flashcard> allCards) {
    final now = DateTime.now();
    return allCards.where((card) => card.dueDate.isBefore(now)).toList();
  }

  /// Get the number of cards due in the next n days
  static int getCardsDueInNext(List<Flashcard> allCards, int days) {
    final future = DateTime.now().add(Duration(days: days));
    return allCards.where((card) => card.dueDate.isBefore(future)).length;
  }

  /// Calculate retention rate based on recent reviews
  static double calculateRetentionRate(List<int> recentQualities) {
    if (recentQualities.isEmpty) return 0.0;

    // Count how many responses were 3 or higher (considered "remembered")
    final remembered = recentQualities.where((q) => q >= 3).length;
    return remembered / recentQualities.length * 100;
  }
}
