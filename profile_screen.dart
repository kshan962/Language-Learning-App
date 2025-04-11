import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  Map<String, dynamic> _userProfile = {};
  bool _isLoading = true;
  String _displayName = 'Not set';

  @override
  void initState() {
    super.initState();
    // Initialize display name from Firebase Auth
    if (_currentUser?.displayName != null &&
        _currentUser!.displayName!.isNotEmpty) {
      _displayName = _currentUser!.displayName!;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Call _fetchUserProfile here instead
    _fetchUserProfile();
  }

  Future<void> _fetchUserProfile() async {
    if (_currentUser == null) return;

    try {
      setState(() {
        _isLoading = true;
      });

      // Fetch user profile from Firestore
      DocumentSnapshot? userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .get();

      // Check if widget is still mounted before using setState
      if (mounted) {
        setState(() {
          _userProfile =
              userDoc.exists ? userDoc.data() as Map<String, dynamic> : {};

          // Update display name from Firestore if available
          if (_userProfile.containsKey('name') &&
              _userProfile['name'] != null &&
              _userProfile['name'].toString().isNotEmpty) {
            _displayName = _userProfile['name'];
          } else if (_currentUser?.displayName != null &&
              _currentUser!.displayName!.isNotEmpty) {
            _displayName = _currentUser!.displayName!;
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      // Check if widget is still mounted before using setState
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // Use context directly here instead of storing it
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
      }
    }
  }

  void _editProfile() {
    final TextEditingController nameController = TextEditingController(
      text: _displayName,
    );
    final TextEditingController goalController = TextEditingController(
      text: _userProfile['learningGoal'] ?? '',
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
              ),
            ),
            TextField(
              controller: goalController,
              decoration: const InputDecoration(
                labelText: 'Learning Goal',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _saveProfile(nameController.text, goalController.text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile(String name, String learningGoal) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (_currentUser != null) {
        // Update displayName in Firebase Auth
        await _currentUser!.updateDisplayName(name);

        // Update in Firestore
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .set({
          'name': name,
          'learningGoal': learningGoal,
          'email': _currentUser?.email,
        }, SetOptions(merge: true));

        // Force a refresh of the current user
        await FirebaseAuth.instance.currentUser?.reload();

        // Refresh profile data
        await _fetchUserProfile();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: $e')),
        );
      }
    } finally {
      // Update loading state only if still mounted
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    // Store navigator before any async operations
    final navigator = Navigator.of(context);

    // Now we can safely await without using context afterward
    await FirebaseAuth.instance.signOut();

    // Use the stored navigator reference
    navigator.pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editProfile,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Profile Picture
                  Center(
                    child: CircleAvatar(
                      radius: 60,
                      backgroundImage: _currentUser?.photoURL != null
                          ? NetworkImage(_currentUser!.photoURL!)
                          : null,
                      child: _currentUser?.photoURL == null
                          ? const Icon(Icons.person, size: 60)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // User Details
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Name: $_displayName',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Email: ${_currentUser?.email ?? 'N/A'}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Learning Progress
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Learning Progress',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: (_userProfile['learningProgress'] as num?)
                                    ?.toDouble() ??
                                0.0,
                            backgroundColor: Colors.grey[300],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Words Learned: ${_userProfile['wordsLearned'] ?? 0}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            'Conversation Level: ${_userProfile['conversationLevel'] ?? 'Beginner'}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Learning Goals
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Learning Goals',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _userProfile['learningGoal'] ?? 'No goals set',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
