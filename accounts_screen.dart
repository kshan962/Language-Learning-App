import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/account_token.dart';
import '../services/auth_service.dart';
import 'auth/login_screen.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  bool _isLoading = true;
  List<AccountToken> _accounts = [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    // Use a post-frame callback to ensure the widget is fully mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadAccounts();
      }
    });
  }

  Future<void> _loadAccounts() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final accounts = await authService.getAllAccountTokens();

      if (!mounted) return;

      setState(() {
        _accounts = accounts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Error loading accounts: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteAccount(AccountToken account) async {
    // Store whether this is the current user before starting deletion
    final authService = Provider.of<AuthService>(context, listen: false);
    final isCurrentUser = authService.currentUser?.uid == account.uid;
    final accountEmail = account.email;

    // Create a stateful dialog controller
    BuildContext? loadingDialogContext;
    bool deletionCancelled = false;

    // Show a loading dialog that can be dismissed with back button
    if (mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false, // Prevent dismissal by tapping outside
        builder: (BuildContext context) {
          loadingDialogContext = context; // Store the dialog context
          return PopScope(
            canPop: true, // Allow the dialog to be popped
            onPopInvokedWithResult: (bool didPop, dynamic result) {
              // Handle back button press or other pop attempts
              if (didPop) {
                deletionCancelled = true;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Account deletion cancelled')),
                );
              }
            },
            child: AlertDialog(
              content: Row(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 20),
                  Expanded(child: Text('Deleting account $accountEmail...')),
                ],
              ),
            ),
          );
        },
      );

      // If deletion was cancelled by back button, exit early
      if (deletionCancelled) return;
    }

    try {
      // Perform the account deletion
      final success = await authService.deleteAccountByUid(account.uid);

      // Check if widget is still mounted
      if (!mounted) return;

      // Make sure the loading dialog is dismissed
      if (loadingDialogContext != null &&
          Navigator.canPop(loadingDialogContext!)) {
        Navigator.of(loadingDialogContext!).pop();
      }

      // If this was the current user and deletion was successful,
      // navigate to login screen immediately
      if (success && isCurrentUser) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Account $accountEmail deleted successfully')),
        );

        // Make sure we're not showing any loading indicators
        setState(() {
          _isLoading = false;
        });

        // Ensure any open dialogs are dismissed
        Navigator.of(context).popUntil((route) => route.isFirst);

        // Create a new instance of the login screen directly
        final loginScreen = const LoginScreen();

        // Navigate to login screen with a slight delay to ensure dialogs are closed
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            // Replace the entire navigation stack with the login screen
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => loginScreen),
              (route) => false,
            );
          }
        });
        return; // Exit early
      }

      // For all other cases, update the UI
      if (success) {
        // If not current user but deletion successful
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Token for $accountEmail removed from list')),
        );
        await _loadAccounts(); // Refresh the list
      } else {
        // If deletion failed
        setState(() {
          _errorMessage =
              'Failed to delete account. The token may have expired.';
        });
        await _loadAccounts(); // Refresh the list
      }
    } catch (e) {
      // Check if widget is still mounted
      if (!mounted) return;

      // Make sure the loading dialog is dismissed
      if (loadingDialogContext != null &&
          Navigator.canPop(loadingDialogContext!)) {
        Navigator.of(loadingDialogContext!).pop();
      }

      setState(() {
        _errorMessage = 'Error deleting account: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Accounts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAccounts,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadAccounts,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_accounts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.account_circle_outlined,
                  size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'No accounts found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'When you sign up for new accounts, they will appear here for easy management.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _accounts.length,
      itemBuilder: (context, index) {
        final account = _accounts[index];
        final dateFormat = DateFormat('MMM d, yyyy h:mm a');
        final formattedDate = dateFormat.format(account.createdAt);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text(
              account.email,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Created: $formattedDate'),
                Text('UID: ${account.uid.substring(0, 8)}...'),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _showDeleteConfirmation(account),
              tooltip: 'Delete Account',
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(AccountToken account) {
    // Check if this is the current user
    final authService = Provider.of<AuthService>(context, listen: false);
    final isCurrentUser = authService.currentUser?.uid == account.uid;

    final title = isCurrentUser ? 'Delete Your Account?' : 'Remove Account?';
    final content = isCurrentUser
        ? 'Are you sure you want to delete your account ${account.email}? This will permanently delete your account and all associated data.'
        : 'Are you sure you want to remove ${account.email} from your saved accounts? This will only remove the account from this list, but the account will still exist.';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteAccount(account);
            },
            child: Text(
              isCurrentUser ? 'DELETE' : 'REMOVE',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
