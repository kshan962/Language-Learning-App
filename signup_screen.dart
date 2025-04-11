import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import '/services/api_service.dart';
import '/services/auth_service.dart';
import '/config/app_config.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => SignupScreenState();
}

class SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _logger = Logger();

  // Default to empty - forcing user to make a selection
  String? _selectedLearningGoal;
  String? _selectedLanguage = 'English';
  String? _selectedLevel = 'Beginner';
  int _dailyGoal = 10;

  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Name Input
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your full name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Email Input
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        // Basic email validation
                        final emailRegex =
                            RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                        if (!emailRegex.hasMatch(value)) {
                          return 'Please enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Password Input
                    TextFormField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock),
                      ),
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Native Language Dropdown
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Native Language',
                        prefixIcon: Icon(Icons.language),
                      ),
                      value: _selectedLanguage,
                      items: const [
                        DropdownMenuItem(
                            value: 'English', child: Text('English')),
                        DropdownMenuItem(
                            value: 'Spanish', child: Text('Spanish')),
                        DropdownMenuItem(
                            value: 'French', child: Text('French')),
                        DropdownMenuItem(
                            value: 'German', child: Text('German')),
                        DropdownMenuItem(
                            value: 'Chinese', child: Text('Chinese')),
                        DropdownMenuItem(
                            value: 'Japanese', child: Text('Japanese')),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedLanguage = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Arabic Level Dropdown
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Arabic Level',
                        prefixIcon: Icon(Icons.grade),
                      ),
                      value: _selectedLevel,
                      items: AppConfig.arabicLevels.map((level) {
                        return DropdownMenuItem<String>(
                          value: level,
                          child: Text(level),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedLevel = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Learning Goal Dropdown
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Learning Goal',
                        prefixIcon: Icon(Icons.school),
                        hintText: 'Why are you learning Arabic?',
                      ),
                      value: _selectedLearningGoal,
                      items: AppConfig.learningGoals.map((goal) {
                        return DropdownMenuItem<String>(
                          value: goal,
                          child: Text(goal),
                        );
                      }).toList(),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please select your learning goal';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        setState(() {
                          _selectedLearningGoal = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Daily Goal Slider
                    Text(
                      'Daily Goal: $_dailyGoal flashcards',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Slider(
                      min: AppConfig.minDailyGoal.toDouble(),
                      max: AppConfig.maxDailyGoal.toDouble(),
                      divisions:
                          AppConfig.maxDailyGoal - AppConfig.minDailyGoal,
                      value: _dailyGoal.toDouble(),
                      onChanged: (value) {
                        setState(() {
                          _dailyGoal = value.round();
                        });
                      },
                    ),
                    const SizedBox(height: 24),

                    // Error message display
                    if (_errorMessage.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _errorMessage,
                          style: TextStyle(color: Colors.red.shade900),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    // Signup Button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _signup,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Sign Up'),
                    ),

                    // Login Option
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacementNamed('/login');
                      },
                      child: const Text('Already have an account? Log In'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Verify learning goal is selected
    if (_selectedLearningGoal == null) {
      setState(() {
        _errorMessage = 'Please select your learning goal';
      });
      return;
    }

    // Clear any previous error
    setState(() {
      _errorMessage = '';
      _isLoading = true;
    });

    try {
      _logger.d(
          'Attempting registration with learning goal: $_selectedLearningGoal');

      // Use Firebase Auth for initial user creation
      final userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Create user profile in your backend
      if (userCredential.user != null) {
        try {
          await _createUserProfile(userCredential.user!);

          // Refresh user data after successful signup
          final authService = Provider.of<AuthService>(context, listen: false);
          await authService.refreshUserData();

          // Let the AuthWrapper handle navigation
          if (mounted) {
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/', (route) => false);
          }
        } catch (profileError) {
          // If backend profile creation fails, delete the Firebase user to maintain consistency
          _logger.e('Error creating user profile', error: profileError);
          await userCredential.user?.delete();
          throw Exception(
              'Failed to create user profile: ${profileError.toString()}');
        }
      }
    } on FirebaseAuthException catch (e) {
      _logger.e('Firebase auth error during signup', error: e);
      if (mounted) {
        setState(() {
          _errorMessage = _getErrorMessage(e);
        });
      }
    } catch (e) {
      _logger.e('Unexpected error during signup', error: e);
      if (mounted) {
        setState(() {
          _errorMessage = 'An unexpected error occurred: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createUserProfile(User firebaseUser) async {
    final apiService = Provider.of<ApiService>(context, listen: false);

    // Set display name in Firebase Auth
    await firebaseUser.updateDisplayName(_nameController.text.trim());

    // Make sure to include the password and Firebase UID in your request
    final userData = {
      'username': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'password': _passwordController.text.trim(),
      'firebaseUid': firebaseUser.uid,
      'nativeLanguage': _selectedLanguage ?? 'English',
      'arabicLevel': _selectedLevel ?? 'Beginner',
      'learningGoal': _selectedLearningGoal ?? 'Travel',
      'dailyGoal': _dailyGoal,
    };

    // Send to backend
    await apiService.register(userData);

    _logger.i(
        'User profile created successfully with learning goal: $_selectedLearningGoal');
  }

  String _getErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'The password is too weak.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'invalid-email':
        return 'The email address is not valid.';
      default:
        return 'Signup failed: ${e.message}';
    }
  }
}
