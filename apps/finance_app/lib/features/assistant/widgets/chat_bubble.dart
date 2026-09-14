import 'package:flutter/material.dart';

/// Who produced a chat message.
enum ChatRole { user, assistant }

/// One bubble in the conversation.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    required this.text,
    required this.role,
    this.footer,
    super.key,
  });

  final String text;
  final ChatRole role;

  /// Optional trace line, used to show which intent produced an answer.
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = role == ChatRole.user;
    final scheme = theme.colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: isUser ? scheme.primary : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SelectableText(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isUser ? scheme.onPrimary : scheme.onSurface,
                  height: 1.35,
                ),
              ),
              if (footer != null) ...<Widget>[
                const SizedBox(height: 7),
                Text(
                  footer!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
