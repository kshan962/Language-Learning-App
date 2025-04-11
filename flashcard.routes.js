const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const Flashcard = require('../models/flashcard.model');

// Get all flashcards route
router.get('/', async (req, res) => {
  try {
    // Get all flashcards from the database without any filtering
    const flashcards = await Flashcard.find({});
    console.log(`Sending ${flashcards.length} flashcards to the client`);
    res.json(flashcards);
  } catch (error) {
    console.error('Error fetching flashcards:', error);
    res.status(500).json({
      success: false,
      message: 'Error fetching flashcards',
      error: error.message
    });
  }
});

router.get('/count', async (req, res) => {
  try {
    const count = await Flashcard.countDocuments();
    res.json({ count });
  } catch (error) {
    console.error('Error counting flashcards:', error);
    res.status(500).json({ error: error.message });
  }
});

// Add a new flashcard
router.post('/', async (req, res) => {
  try {
    const {
      arabic,
      transliteration,
      translation,
      example,
      category,
      difficulty
    } = req.body;
    
    // Validate required fields
    if (!arabic || !transliteration || !translation) {
      return res.status(400).json({
        success: false,
        message: 'Arabic text, transliteration, and translation are required'
      });
    }
    
    // Create new flashcard
    const newFlashcard = new Flashcard({
      arabic,
      transliteration,
      translation,
      example: example || {
        arabic: '',
        transliteration: '',
        translation: ''
      },
      category: category || 'Common Phrases',
      difficulty: difficulty || 'Beginner',
      interval: 0,
      repetition: 0,
      efactor: 2.5,
      dueDate: new Date()
    });
    
    // Save to database
    const savedFlashcard = await newFlashcard.save();
    
    res.status(201).json({
      success: true,
      message: 'Flashcard created successfully',
      flashcard: savedFlashcard
    });
  } catch (error) {
    console.error('Error creating flashcard:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while creating flashcard',
      error: error.message
    });
  }
});

// Add endpoint for flashcard progress updates
router.post('/:id/progress', async (req, res) => {
  const flashcardId = req.params.id;
  const { quality } = req.body;
  
  try {
    console.log(`Updating flashcard ${flashcardId} with quality ${quality}`);
    
    // Check if the ID is valid
    if (!mongoose.Types.ObjectId.isValid(flashcardId)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid flashcard ID format',
        error: 'ID must be a valid MongoDB ObjectId'
      });
    }
    
    // Get the flashcard from database
    const flashcard = await Flashcard.findById(flashcardId);
    
    if (!flashcard) {
      return res.status(404).json({ 
        success: false, 
        message: 'Flashcard not found' 
      });
    }
    
    // Calculate new spaced repetition values
    let newInterval, newRepetition, newEFactor;
    
    // Update EFactor (measure of how easy the card is to remember)
    newEFactor = flashcard.efactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
    if (newEFactor < 1.3) newEFactor = 1.3;
    
    if (quality < 3) {
      // If quality is less than 3, reset repetition count
      newInterval = 1;
      newRepetition = 0;
    } else {
      // Increase repetition count
      newRepetition = flashcard.repetition + 1;
      
      // Calculate next interval
      if (newRepetition == 1) {
        newInterval = 1;
      } else if (newRepetition == 2) {
        newInterval = 6;
      } else {
        // For repetition > 2, use the formula: interval = previous interval * E-Factor
        newInterval = Math.round(flashcard.interval * newEFactor);
      }
    }
    
    // Calculate next due date
    const nextDueDate = new Date();
    nextDueDate.setDate(nextDueDate.getDate() + newInterval);
    
    // Update flashcard in database
    const updatedFlashcard = await Flashcard.findByIdAndUpdate(
      flashcardId,
      {
        interval: newInterval,
        repetition: newRepetition,
        efactor: newEFactor,
        dueDate: nextDueDate
      },
      { new: true } // Return the updated document
    );
    
    res.json({ 
      success: true, 
      message: 'Flashcard progress updated successfully',
      flashcard: updatedFlashcard
    });
  } catch (error) {
    console.error('Error updating flashcard progress:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Server error while updating flashcard progress',
      error: error.message
    });
  }
});

module.exports = router;