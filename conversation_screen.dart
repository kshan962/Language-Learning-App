import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/tts_service.dart';
import '../services/stt_service.dart';
import '../widgets/conversation_bubble.dart';
import 'package:logger/logger.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Message> _messages = [];
  bool _isLoading = false;
  bool _isListening = false;

  // Flag to track initialization errors
  bool _hasInitError = false;
  String _initErrorMessage = '';

  ApiService? _apiService;
  DatabaseService? _databaseService;
  late TTSService _ttsService;
  late STTService _sttService;
  final _logger = Logger();

  @override
  void initState() {
    super.initState();
    // Only initialize TTS and STT services in initState
    _ttsService = TTSService();
    _sttService = STTService();

    // Everything else will be initialized in didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Only initialize once
    if (_apiService == null) {
      _initializeServices();
    }
  }

  void _initializeServices() {
    try {
      _apiService = Provider.of<ApiService>(context, listen: false);
      _databaseService = Provider.of<DatabaseService>(context, listen: false);

      _loadConversationHistory();

      // Delayed welcome message
      Future.delayed(Duration.zero, () {
        if (_messages.isEmpty) {
          _addBotMessage(
              'مرحبا! أنا هنا لمساعدتك على ممارسة اللغة العربية.\n\nHello! I\'m here to help you practice Arabic. I\'ll use words you already know.');
        }
      });
    } catch (e) {
      _logger.e('Error initializing services', error: e);

      // Store error but don't show snackbar yet
      setState(() {
        _hasInitError = true;
        _initErrorMessage = 'Failed to initialize conversation services';
      });
    }
  }

  Future<void> _loadConversationHistory() async {
    try {
      if (_databaseService == null) return;

      final messages = await _databaseService!.getConversationHistory();

      if (!mounted) return;

      setState(() {
        _messages.clear();
        _messages.addAll(messages);
      });

      _scrollToBottom();
    } catch (e) {
      _logger.e('Error loading conversation history', error: e);

      if (mounted) {
        setState(() {
          _hasInitError = true;
          _initErrorMessage = 'Could not load conversation history';
        });
      }
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _apiService == null) return;

    _messageController.clear();

    final userMessage = Message(
      text: text,
      isUser: true,
    );

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      // Add timeout to API call
      final response = await _apiService!
          .getAIResponse(text, _messages)
          .timeout(const Duration(seconds: 10),
              onTimeout: () => throw TimeoutException('Connection timed out'));

      if (!mounted) return;

      final botMessage = Message(
        text: response,
        isUser: false,
      );

      setState(() {
        _messages.add(botMessage);
        _isLoading = false;
      });

      if (_databaseService != null) {
        await _databaseService!.saveConversation([userMessage, botMessage]);
      }

      _scrollToBottom();
      _speakArabicFromResponse(response);
    } on TimeoutException {
      _handleConnectionError(
          'The connection timed out. Please check your network.');
    } catch (e) {
      _handleConnectionError('Unable to send message. Please try again.');
      _logger.e('Message send error', error: e);
    }
  }

  void _speakArabicFromResponse(String response) {
    // Extract Arabic text from response (typically before the English part)
    final parts = response.split('\n\n');
    if (parts.isNotEmpty) {
      // Assume the first part is Arabic
      _ttsService.speak(parts[0]);
    }
  }

  // Rest of methods remain the same

  @override
  Widget build(BuildContext context) {
    // Show error from initialization if needed
    if (_hasInitError) {
      // Schedule the SnackBar to appear after the build completes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_initErrorMessage),
            backgroundColor: Colors.red,
          ),
        );
        // Reset the flag to avoid showing multiple times
        setState(() {
          _hasInitError = false;
        });
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversation Practice'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _showClearConfirmDialog,
            tooltip: 'Clear Conversation',
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages area
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return ConversationBubble(
                  message: message,
                  onTapSpeak: () {
                    if (!message.isUser) {
                      _speakArabicFromResponse(message.text);
                    }
                  },
                );
              },
            ),
          ),

          // Typing indicator
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text('Typing...'),
                ],
              ),
            ),

          // Input area
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(13),
                  blurRadius: 5,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Row(
              children: [
                // Microphone button
                IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: _isListening ? Colors.red : null,
                  ),
                  onPressed: _isListening ? _stopListening : _startListening,
                  tooltip: _isListening ? 'Stop listening' : 'Start listening',
                ),

                // Text input
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type your message...',
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (text) {
                      if (text.trim().isNotEmpty) {
                        _sendMessage(text);
                      }
                    },
                  ),
                ),

                // Send button
                IconButton(
                  icon: const Icon(Icons.send),
                  color: Theme.of(context).primaryColor,
                  onPressed: () {
                    if (_messageController.text.trim().isNotEmpty) {
                      _sendMessage(_messageController.text);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showClearConfirmDialog() {
    if (_databaseService == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Conversation'),
        content: const Text(
            'Are you sure you want to clear the entire conversation history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _databaseService!.clearConversationHistory();
              setState(() {
                _messages.clear();
              });

              // Show welcome message
              _addBotMessage(
                  'مرحبا! أنا هنا لمساعدتك على ممارسة اللغة العربية.\n\nHello! I\'m here to help you practice Arabic. I\'ll use words you already know.');
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _ttsService.dispose();
    super.dispose();
  }

  // Add missing method implementations
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _handleConnectionError(String errorMessage) {
    setState(() {
      _isLoading = false;
      _messages.add(Message(
        text: errorMessage,
        isUser: false,
      ));
    });

    _showErrorSnackBar(errorMessage);
    _scrollToBottom();
  }

  void _addBotMessage(String text) {
    setState(() {
      _messages.add(Message(
        text: text,
        isUser: false,
      ));
    });

    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startListening() async {
    final bool available = await _sttService.isAvailable();

    if (!mounted) return;

    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition not available')),
      );
      return;
    }

    setState(() {
      _isListening = true;
    });

    await _sttService.startListening(
      onResult: (text) {
        if (!mounted) return;
        _messageController.text = text;
      },
      onListeningComplete: () {
        if (!mounted) return;
        setState(() {
          _isListening = false;
        });
      },
    );
  }

  void _stopListening() {
    _sttService.stopListening();
    setState(() {
      _isListening = false;
    });
  }
}
