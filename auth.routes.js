const express = require('express');
const router = express.Router();
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const User = require('../models/user.model');

// Register new user
router.post('/register', async (req, res) => {
  try {
    console.log('Register request body:', req.body);
    
    // Extract user data from request body
    const { username, email, password, nativeLanguage, arabicLevel, learningGoal, dailyGoal, firebaseUid } = req.body;
    
    // If firebaseUid is provided, check if user already exists with this UID
    let existingUser = null;
    if (firebaseUid) {
      existingUser = await User.findOne({ firebaseUid });
      if (existingUser) {
        console.log(`User with firebaseUid ${firebaseUid} already exists`);
        
        // Generate token for existing user
        const token = jwt.sign(
          { id: existingUser._id },
          process.env.JWT_SECRET || 'your_secure_secret_key',
          { expiresIn: process.env.JWT_EXPIRES_IN || '20d' }
        );
        
        return res.status(200).json({ 
          success: true, 
          message: 'User already registered',
          token,
          user: {
            _id: existingUser._id,
            username: existingUser.username,
            email: existingUser.email,
            nativeLanguage: existingUser.nativeLanguage,
            arabicLevel: existingUser.arabicLevel,
            learningGoal: existingUser.learningGoal,
            dailyGoal: existingUser.dailyGoal,
            streak: existingUser.streak,
            lastActive: existingUser.lastActive,
            knownWords: existingUser.knownWords
          }
        });
      }
    }
    
    // Check if user already exists with this email
    existingUser = await User.findOne({ email });
    if (existingUser) {
      // If user exists but doesn't have firebaseUid and we have one, update it
      if (firebaseUid && !existingUser.firebaseUid) {
        console.log(`Updating existing user with firebaseUid: ${firebaseUid}`);
        existingUser.firebaseUid = firebaseUid;
        await existingUser.save();
        
        // Generate token for updated user
        const token = jwt.sign(
          { id: existingUser._id },
          process.env.JWT_SECRET || 'your_secure_secret_key',
          { expiresIn: process.env.JWT_EXPIRES_IN || '20d' }
        );
        
        return res.status(200).json({ 
          success: true, 
          message: 'User updated with Firebase UID',
          token,
          user: {
            _id: existingUser._id,
            username: existingUser.username,
            email: existingUser.email,
            nativeLanguage: existingUser.nativeLanguage,
            arabicLevel: existingUser.arabicLevel,
            learningGoal: existingUser.learningGoal,
            dailyGoal: existingUser.dailyGoal,
            streak: existingUser.streak,
            lastActive: existingUser.lastActive,
            knownWords: existingUser.knownWords
          }
        });
      }
      
      return res.status(400).json({ 
        success: false, 
        message: 'User with this email already exists' 
      });
    }
    
    // Create new user document
    const newUser = new User({
      username: username || 'New User',
      email,
      password, // This will be hashed by the pre-save hook in user.model.js
      firebaseUid, // Store Firebase UID if provided
      nativeLanguage: nativeLanguage || 'English',
      arabicLevel: arabicLevel || 'Beginner',
      learningGoal: learningGoal || 'Travel',
      dailyGoal: dailyGoal || 10,
      streak: 0,
      lastActive: new Date(),
      knownWords: []
    });
    
    // If this is a Google user (has firebaseUid but no password), set a random password
    if (firebaseUid && (!password || password === '')) {
      console.log('Setting random password for Google user');
      const randomPassword = Math.random().toString(36).slice(-8);
      newUser.password = randomPassword;
    }
    
    // Save user to database
    const savedUser = await newUser.save();
    console.log(`New user saved with id: ${savedUser._id}, firebaseUid: ${firebaseUid || 'none'}`);
    
    // Generate JWT token
    const token = jwt.sign(
      { id: savedUser._id },
      process.env.JWT_SECRET || 'your_secure_secret_key',
      { expiresIn: process.env.JWT_EXPIRES_IN || '20d' }
    );
    
    // Return success response with user data and token
    res.status(201).json({
      success: true,
      message: 'User registered successfully',
      token,
      user: {
        _id: savedUser._id,
        username: savedUser.username,
        email: savedUser.email,
        nativeLanguage: savedUser.nativeLanguage,
        arabicLevel: savedUser.arabicLevel,
        learningGoal: savedUser.learningGoal,
        dailyGoal: savedUser.dailyGoal,
        streak: savedUser.streak,
        lastActive: savedUser.lastActive,
        knownWords: savedUser.knownWords
      }
    });
  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({
      success: false,
      message: 'Error during registration',
      error: error.message
    });
  }
});

// Login route
router.post('/login', async (req, res) => {
  try {
    console.log('Login request body:', req.body);
    
    // Extract login credentials
    const { email, password } = req.body;
    
    // Find user by email
    const user = await User.findOne({ email });
    if (!user) {
      return res.status(401).json({
        success: false,
        message: 'Invalid email or password'
      });
    }
    
    // Compare password
    const isPasswordValid = await user.comparePassword(password);
    if (!isPasswordValid) {
      return res.status(401).json({
        success: false,
        message: 'Invalid email or password'
      });
    }
    
    // Generate JWT token
    const token = jwt.sign(
      { id: user._id },
      process.env.JWT_SECRET || 'your_secure_secret_key',
      { expiresIn: process.env.JWT_EXPIRES_IN || '20d' }
    );
    
    // Return success response with user data and token
    res.status(200).json({
      success: true,
      message: 'Login successful',
      token,
      user: {
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
      }
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({
      success: false,
      message: 'Error during login',
      error: error.message
    });
  }
});

module.exports = router;