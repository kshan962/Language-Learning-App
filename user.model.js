const mongoose = require('mongoose');
const bcrypt = require('bcrypt');

const UserSchema = new mongoose.Schema({
  username: {
    type: String,
    required: true,
    unique: true,
    trim: true,
    minlength: 3
  },
  firebaseUid: {
    type: String,
    sparse: true,
    index: true
  },
  email: {
    type: String,
    required: true,
    unique: true,
    trim: true,
    lowercase: true
  },
  password: {
    type: String,
    required: true,
    minlength: 6
  },
  nativeLanguage: {
    type: String,
    required: true,
    default: 'English'
  },
  arabicLevel: {
    type: String,
    enum: ['Beginner', 'Intermediate', 'Advanced'],
    default: 'Beginner'
  },
  learningGoal: {
    type: String,
    enum: ['Travel', 'Business', 'Academic', 'Cultural', 'Religious'],
    default: 'Travel'
  },
  dailyGoal: {
    type: Number,
    default: 10, // Number of flashcards per day
    min: 5,
    max: 100
  },
  knownWords: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Flashcard'
  }],
  streak: {
    type: Number,
    default: 0
  },
  lastActive: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true
});

// Pre-save hook to hash password
UserSchema.pre('save', async function(next) {
  if (!this.isModified('password')) return next();
  
  try {
    const salt = await bcrypt.genSalt(10);
    this.password = await bcrypt.hash(this.password, salt);
    next();
  } catch (error) {
    next(error);
  }
});

// Method to compare passwords
UserSchema.methods.comparePassword = async function(candidatePassword) {
  return bcrypt.compare(candidatePassword, this.password);
};

const User = mongoose.model('User', UserSchema);

module.exports = User;
