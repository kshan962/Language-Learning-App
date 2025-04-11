const mongoose = require('mongoose');

const FlashcardSchema = new mongoose.Schema({
  arabic: {
    type: String,
    required: true,
    trim: true
  },
  transliteration: {
    type: String,
    required: true,
    trim: true
  },
  translation: {
    type: String,
    required: true,
    trim: true
  },
  example: {
    arabic: {
      type: String,
      trim: true
    },
    transliteration: {
      type: String,
      trim: true
    },
    translation: {
      type: String,
      trim: true
    }
  },
  category: {
    type: String,
    enum: ['Greeting', 'Food', 'Travel', 'Shopping', 'Family', 'Numbers', 'Time', 'Weather', 'Common Phrases', 'Question Words', 'Verbs', 'Adjectives', 'Other'],
    default: 'Common Phrases'
  },
  difficulty: {
    type: String,
    enum: ['Beginner', 'Intermediate', 'Advanced'],
    default: 'Beginner'
  },
  audioUrl: {
    type: String,
    default: ''
  },
  imageUrl: {
    type: String,
    default: ''
  },
  // Fields for spaced repetition algorithm
  interval: {
    type: Number,
    default: 0
  },
  repetition: {
    type: Number,
    default: 0
  },
  efactor: {
    type: Number,
    default: 2.5
  },
  dueDate: {
    type: Date,
    default: Date.now
  },
  // Creation and update timestamps
  createdBy: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  }
}, {
  timestamps: true
});

// Index for efficient queries
FlashcardSchema.index({ category: 1, difficulty: 1 });
FlashcardSchema.index({ dueDate: 1 });

const Flashcard = mongoose.model('Flashcard', FlashcardSchema);

module.exports = Flashcard;