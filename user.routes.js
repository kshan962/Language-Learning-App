const express = require('express');
const router = express.Router();
const User = require('../models/user.model');
const Flashcard = require('../models/flashcard.model');
const { verifyToken } = require('../middleware/auth.middleware');

// Get user profile - protected route
router.get('/profile', verifyToken, async (req, res) => {
  try {
    // Request should already have user from middleware
    const user = req.user;
    
    // Return user data without sensitive information
    res.json({
      _id: user._id,
      username: user.username,
      email: user.email,
      nativeLanguage: user.nativeLanguage,
      arabicLevel: user.arabicLevel,
      learningGoal: user.learningGoal,
      dailyGoal: user.dailyGoal,
      streak: user.streak,
      lastActive: user.lastActive,
      knownWords: user.knownWords
    });
  } catch (error) {
    console.error('Error fetching user profile:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// Update user profile - protected route
router.put('/profile', verifyToken, async (req, res) => {
  try {
    const userId = req.userId;
    const {
      username,
      email,
      nativeLanguage,
      arabicLevel,
      learningGoal,
      dailyGoal
    } = req.body;
    
    // Update allowed fields only
    const updateData = {};
    if (username) updateData.username = username;
    if (email) updateData.email = email;
    if (nativeLanguage) updateData.nativeLanguage = nativeLanguage;
    if (arabicLevel) updateData.arabicLevel = arabicLevel;
    if (learningGoal) updateData.learningGoal = learningGoal;
    if (dailyGoal) updateData.dailyGoal = dailyGoal;
    
    // Always update lastActive
    updateData.lastActive = new Date();
    
    // Find and update user
    const updatedUser = await User.findByIdAndUpdate(
      userId,
      { $set: updateData },
      { new: true } // Return the updated document
    );
    
    if (!updatedUser) {
      return res.status(404).json({ message: 'User not found' });
    }
    
    // Return updated user data
    res.json({
      _id: updatedUser._id,
      username: updatedUser.username,
      email: updatedUser.email,
      nativeLanguage: updatedUser.nativeLanguage,
      arabicLevel: updatedUser.arabicLevel,
      learningGoal: updatedUser.learningGoal,
      dailyGoal: updatedUser.dailyGoal,
      streak: updatedUser.streak,
      lastActive: updatedUser.lastActive,
      knownWords: updatedUser.knownWords
    });
  } catch (error) {
    console.error('Error updating user profile:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// Get word suggestions based on user level
router.get('/word-suggestions', verifyToken, async (req, res) => {
  try {
    const count = parseInt(req.query.count) || 5;
    const user = req.user;
    
    // In a real implementation, you would query Flashcard model
    // to get appropriate words for the user's level
    // For now, returning a mock response
    
    res.json([
      {
        _id: '60a5f1b5c9e4c234e2b1f5a1',
        arabic: 'مرحبا',
        transliteration: 'marhaban',
        translation: 'Hello',
        category: 'Greeting',
        difficulty: user.arabicLevel
      },
      // Additional suggested words would come from database
    ]);
  } catch (error) {
    console.error('Error getting word suggestions:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// Update user streak and activity
router.post('/activity', verifyToken, async (req, res) => {
  try {
    const userId = req.userId;
    
    // Get user
    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }
    
    const now = new Date();
    const lastActive = user.lastActive;
    
    // Check if this is a new day (in user's local time zone)
    const isNewDay = 
      now.getFullYear() !== lastActive.getFullYear() ||
      now.getMonth() !== lastActive.getMonth() ||
      now.getDate() !== lastActive.getDate();
    
    // If it's a new day and within 24 hours of last activity, increment streak
    const hoursSinceLastActive = (now - lastActive) / (1000 * 60 * 60);
    
    let updatedStreak = user.streak;
    
    if (isNewDay) {
      if (hoursSinceLastActive <= 48) {
        // Increment streak if the user was active within the last 48 hours
        updatedStreak += 1;
      } else {
        // Reset streak if more than 48 hours have passed
        updatedStreak = 1;
      }
    }
    
    // Update user's streak and lastActive
    const updatedUser = await User.findByIdAndUpdate(
      userId,
      { 
        $set: { 
          streak: updatedStreak,
          lastActive: now
        }
      },
      { new: true }
    );
    
    res.json({ 
      streak: updatedUser.streak,
      lastActive: updatedUser.lastActive
    });
  } catch (error) {
    console.error('Error updating user activity:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// Reset user learning progress
router.post('/reset-progress', verifyToken, async (req, res) => {
  try {
    const userId = req.userId;
    
    // Find the user to make sure they exist
    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }
    
    // Reset user's progress
    const updatedUser = await User.findByIdAndUpdate(
      userId,
      { 
        $set: { 
          streak: 0,
          knownWords: [],
          arabicLevel: 'Beginner'
        }
      },
      { new: true }
    );
    
    res.json({ 
      message: 'Learning progress reset successfully',
      user: {
        streak: updatedUser.streak,
        arabicLevel: updatedUser.arabicLevel,
        knownWords: updatedUser.knownWords
      }
    });
  } catch (error) {
    console.error('Error resetting user progress:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// Delete user account and all associated data
router.delete('/account', verifyToken, async (req, res) => {
  try {
    const userId = req.userId;
    
    console.log(`Deleting account for user ID: ${userId}`);
    
    // Find the user to make sure they exist
    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ 
        success: false,
        message: 'User not found' 
      });
    }
    
    // Delete user-created flashcards
    const deletedFlashcards = await Flashcard.deleteMany({ createdBy: userId });
    console.log(`Deleted ${deletedFlashcards.deletedCount} flashcards created by user`);
    
    // Delete the user
    await User.findByIdAndDelete(userId);
    console.log(`User ${userId} deleted successfully`);
    
    // Return success response
    res.status(200).json({
      success: true,
      message: 'Account and all associated data deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting account:', error);
    res.status(500).json({
      success: false,
      message: 'Error deleting account',
      error: error.message
    });
  }
});

module.exports = router;
