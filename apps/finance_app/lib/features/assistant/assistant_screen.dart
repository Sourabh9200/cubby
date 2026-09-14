import 'package:flutter/material.dart';

import '../../data/repository_scope.dart';
import 'context_preview.dart';
import 'local_engine.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/payload_preview_card.dart';

/// A message in the transcript.
class _Message {
  const _Message(this.text, this.role, {this.footer});

  final String text;
  final ChatRole role;
  final String? footer;
}

/// Chat with the assistant.
///
/// The transcript is deliberately thin: what matters on this screen is the
/// preview panel above it, which shows the exact payload a cloud model would
/// receive. The assistant answers from local aggregates, so no request is made
/// at all in this build.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Message> _messages = <_Message>[];

  /// Rebuilt whenever the snapshot changes.
  ///
  /// Not `late final`: `didChangeDependencies` fires again on every database
  /// emission, and a `late final` field cannot be reassigned — which produced a
  /// LateInitializationError on the first write.
  LocalEngine? _engine;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _engine = LocalEngine(RepositoryScope.of(context));
    if (_messages.isEmpty) {
      _messages.add(
        const _Message(
          'Ask me about your spending. I answer from your own data, and this '
          'build never contacts a server.',
          ChatRole.assistant,
          footer: 'local engine · no network',
        ),
      );
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _ask(String question) {
    final engine = _engine;
    if (question.trim().isEmpty || engine == null) {
      return;
    }
    final reply = engine.answer(question);
    setState(() {
      _messages
        ..add(_Message(question, ChatRole.user))
        ..add(
          _Message(
            reply.text,
            ChatRole.assistant,
            footer: reply.sources.isEmpty
                ? 'intent: ${reply.intent}'
                : 'intent: ${reply.intent} · read: '
                      '${reply.sources.join(', ')}',
          ),
        );
    });
    _input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final repository = RepositoryScope.of(context);
    final theme = Theme.of(context);

    return Column(
      children: <Widget>[
        Expanded(
          child: CustomScrollView(
            controller: _scroll,
            slivers: <Widget>[
              const SliverAppBar(pinned: true, title: Text('Assistant')),
              SliverToBoxAdapter(
                child: PayloadPreviewCard(
                  payload: buildSanitizedPreview(repository),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return ChatBubble(
                      text: message.text,
                      role: message.role,
                      footer: message.footer,
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final suggestion in LocalEngine.suggestions)
                        ActionChip(
                          label: Text(suggestion),
                          onPressed: () => _ask(suggestion),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _ask,
                    decoration: const InputDecoration(
                      hintText: 'Ask about your spending…',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: () => _ask(_input.text),
                  icon: const Icon(Icons.arrow_upward_rounded),
                  tooltip: 'Send',
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
              ],
            ),
          ),
        ),
        Container(height: 2, color: theme.colorScheme.surfaceContainerHighest),
      ],
    );
  }
}
