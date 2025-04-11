// middleware/auth.middleware.js
const jwt = require('jsonwebtoken');
const { ObjectId } = require('mongodb');
const admin = require('firebase-admin');
const User = require('../models/user.model');

// Your JWT secret (should be in environment variables)
const JWT_SECRET = process.env.JWT_SECRET || 'your_secure_secret_key';

const verifyToken = async (req, res, next) => {
  try {
    // Log request headers for debugging
    console.log('Auth headers:', {
      authorization: req.headers.authorization ? 'Present' : 'Not present',
      'x-firebase-uid': req.headers['x-firebase-uid'] || 'Not present'
    });
    
    const authHeader = req.headers.authorization;
    const firebaseUid = req.headers['x-firebase-uid'];
    
    // First, try to authenticate with Firebase UID from headers (fastest path)
    if (firebaseUid) {
      console.log('Attempting authentication with Firebase UID from headers:', firebaseUid);
      const userByUid = await User.findOne({ firebaseUid });
      
      if (userByUid) {
        console.log('User found by Firebase UID from headers:', userByUid._id);
        req.userId = userByUid._id;
        req.user = userByUid;
        return next();
      }
      
      console.log('No user found with Firebase UID from headers:', firebaseUid);
      // Continue to try other authentication methods
    }
    
    // If no auth header is present, require authentication
    if (!authHeader) {
      console.log('No authorization header provided');
      return res.status(401).json({ message: 'Authentication required' });
    }
    
    // Check token format
    const parts = authHeader.split(' ');
    if (parts.length !== 2 || parts[0] !== 'Bearer') {
      console.log('Malformed token format');
      return res.status(401).json({ message: 'Malformed token format' });
    }
    
    const token = parts[1];
    
    // Handle empty token
    if (!token) {
      console.log('Empty token provided');
      return res.status(401).json({ message: 'Empty token provided' });
    }
    
    // Handle temporary token for development
    if (token === 'temporary_token_for_testing') {
      console.log('Using temporary development token');
      try {
        const testUser = await User.findOne().sort({ createdAt: 1 }).limit(1);
        if (testUser) {
          req.userId = testUser._id;
          req.user = testUser;
          return next();
        } else {
          return res.status(401).json({ message: 'No users found for test token' });
        }
      } catch (dbError) {
        console.error('Database error in auth middleware:', dbError);
        return res.status(500).json({ message: 'Database error' });
      }
    }
    
    // Try to verify as a Firebase token first
    try {
      console.log('Verifying Firebase token...');
      const decodedFirebase = await admin.auth().verifyIdToken(token);
      console.log('Firebase token verified for:', decodedFirebase.email || decodedFirebase.uid);
      
      // Find user by Firebase UID first (most reliable)
      let user;
      if (decodedFirebase.uid) {
        user = await User.findOne({ firebaseUid: decodedFirebase.uid });
        if (user) {
          console.log('User found by Firebase UID from token:', user._id);
        }
      }
      
      // If not found by UID, try email
      if (!user && decodedFirebase.email) {
        user = await User.findOne({ email: decodedFirebase.email });
        if (user) {
          console.log('User found by email from token:', user._id);
          
          // Update the user's firebaseUid if it's not set
          if (!user.firebaseUid && decodedFirebase.uid) {
            console.log('Updating user with Firebase UID:', decodedFirebase.uid);
            await User.findByIdAndUpdate(user._id, { firebaseUid: decodedFirebase.uid });
            // Update the user object as well
            user.firebaseUid = decodedFirebase.uid;
          }
        }
      }
      
      if (!user) {
        console.log(`User not found for Firebase UID: ${decodedFirebase.uid} or email: ${decodedFirebase.email}`);
        return res.status(401).json({ message: 'User not found' });
      }
      
      // Update user's lastActive if not updated in the last hour
      const now = new Date();
      if (!user.lastActive || (now - user.lastActive) / (1000 * 60 * 60) >= 1) {
        console.log('Updating lastActive timestamp for user:', user._id);
        await User.findByIdAndUpdate(user._id, { lastActive: now });
        user.lastActive = now;
      }
      
      req.userId = user._id;
      req.user = user;
      return next();
      
    } catch (firebaseError) {
      console.log('Firebase token verification failed, trying JWT:', firebaseError.message);
      
      // If Firebase verification fails, try JWT
      try {
        const decoded = jwt.verify(token, JWT_SECRET);
        const userId = new ObjectId(decoded.id); // Convert to ObjectId
        
        console.log('JWT token verified for user ID:', userId);
        
        // Fetch user from database
        const user = await User.findById(userId);
        if (!user) {
          console.log('User not found for JWT token ID:', userId);
          return res.status(401).json({ message: 'User not found' });
        }
        
        console.log('User found by JWT token:', user._id);
        
        // Update user's lastActive if not updated in the last hour
        const now = new Date();
        if (!user.lastActive || (now - user.lastActive) / (1000 * 60 * 60) >= 1) {
          console.log('Updating lastActive timestamp for user:', user._id);
          await User.findByIdAndUpdate(user._id, { lastActive: now });
          user.lastActive = now;
        }
        
        req.userId = userId;
        req.user = user;
        
        return next();
      } catch (jwtError) {
        console.error('Error verifying JWT token:', jwtError);
        
        // If both Firebase and JWT verification fail, return unauthorized
        console.log('Both Firebase and JWT verification failed');
        return res.status(401).json({ message: 'Unauthorized: Invalid token' });
      }
    }
  } catch (error) {
    console.error('Auth middleware error:', error);
    return res.status(500).json({ message: 'Server error', error: error.message });
  }
};

module.exports = { verifyToken };