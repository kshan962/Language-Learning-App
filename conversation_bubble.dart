import 'package:flutter/material.dart';
import '../models/conversation.dart';

class ConversationBubble extends StatelessWidget {
  final Message message;
  final VoidCallback onTapSpeak;

  const ConversationBubble({
    super.key,
    required this.message,
    required this.onTapSpeak,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar for bot messages
          if (!isUser) _buildAvatar(context),

          // Message bubble
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(
              color: isUser
                  ? Theme.of(context).primaryColor
                  : Theme.of(context).cardColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
                bottomRight: isUser ? Radius.zero : const Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Message content
                _buildMessageContent(context),

                // Timestamp
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: isUser ? Colors.white70 : Colors.grey,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),

          // Avatar for user messages
          if (isUser) _buildAvatar(context),
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      margin: const EdgeInsets.only(right: 8.0, left: 8.0),
      decoration: BoxDecoration(
        color: message.isUser
            ? Theme.of(context).primaryColor.withOpacity(0.2)
            : Theme.of(context).colorScheme.secondary.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          message.isUser ? Icons.person : Icons.language,
          size: 20,
          color: message.isUser
              ? Theme.of(context).primaryColor
              : Theme.of(context).colorScheme.secondary,
        ),
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context) {
    // For bot messages, we need to handle Arabic and English parts
    if (!message.isUser) {
      // Try to split by double newline (common separator between Arabic and English)
      final parts = message.text.split('\n\n');

      if (parts.length > 1) {
        // We have both Arabic and English parts
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Arabic part with speak button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    parts[0],
                    style: const TextStyle(
                      fontSize: 18,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.volume_up, size: 20),
                  onPressed: onTapSpeak,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: Theme.of(context).primaryColor,
                ),
              ],
            ),
            const Divider(),
            // English part
            Text(
              parts.sublist(1).join('\n\n'),
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ],
        );
      }
    }

    // Regular message (user message or simple bot message)
    return Text(
      message.text,
      style: TextStyle(
        color: message.isUser
            ? Colors.white
            : Theme.of(context).textTheme.bodyLarge?.color,
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate =
        DateTime(timestamp.year, timestamp.month, timestamp.day);

    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final time = '$hour:$minute';

    if (messageDate == today) {
      return time;
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, $time';
    } else {
      final day = timestamp.day.toString().padLeft(2, '0');
      final month = timestamp.month.toString().padLeft(2, '0');
      return '$day/$month, $time';
    }
  }
}
