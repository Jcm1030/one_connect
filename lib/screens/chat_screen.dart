import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../formatting.dart';
import '../models/chat_room.dart';
import '../models/message.dart';
import '../models/profile.dart';
import '../widgets/animations.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/screen_body.dart';
import '../ui_feedback.dart';
import '../widgets/swipe_to_reply.dart';

// The chat itself: message bubbles, a text box and a send button.
// Opening the chat marks the other person's messages as "seen",
// just like the Java version.
class ChatScreen extends StatefulWidget {
  final AppState appState;
  final ChatRoom room;

  const ChatScreen({super.key, required this.appState, required this.room});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _latestMessageKey = GlobalKey();

  // How many messages were already there when the chat opened. Only messages
  // added after that pop in with an animation.
  late final int _initialMessageCount;
  late int _lastObservedMessageCount;

  // The messages from the other room member that you had not seen yet when the chat
  // opened. They glow for a moment, with a "New messages" line above them.
  late final Set<String> _newMessageIds;
  String? _firstNewMessageId;

  // The message the person is answering right now, or null.
  Message? _replyingTo;

  // True while messages are being marked as seen, so two runs never overlap.
  bool _markingSeen = false;
  int _scrollRequest = 0;

  static const _reactionEmojis = ['👍', '❤️', '😄', '😮', '😢', '🤝'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(_onInputFocusChanged);
    _initialMessageCount = widget.room.messages.length;
    _lastObservedMessageCount = _initialMessageCount;
    final me = widget.appState.currentUser!;
    final fresh = widget.room.messages
        .where((message) => message.sender != me && !message.seen)
        .toList();
    _newMessageIds = {for (final message in fresh) message.id};
    _firstNewMessageId = fresh.isEmpty ? null : fresh.first.id;
    widget.appState.addListener(_onAppStateChanged);
    _markSeen();
    _scrollToBottom(animate: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.appState.removeListener(_onAppStateChanged);
    _focusNode.removeListener(_onInputFocusChanged);
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onInputFocusChanged() {
    if (_focusNode.hasFocus) {
      _scrollToBottom();
    }
  }

  @override
  void didChangeMetrics() {
    if (_focusNode.hasFocus) {
      _scrollToBottom();
    }
  }

  // Runs whenever the app's data changes (for example a new message arrives
  // while this chat is open).
  void _onAppStateChanged() {
    if (!mounted) {
      return;
    }
    final messageCount = widget.room.messages.length;
    if (messageCount > _lastObservedMessageCount) {
      _scrollToBottom();
    }
    _lastObservedMessageCount = messageCount;

    // The other person left: a reply can no longer be sent, so drop it.
    if (widget.room.closed && _replyingTo != null) {
      setState(() => _replyingTo = null);
    }
    final me = widget.appState.currentUser;
    if (me == null) {
      return;
    }
    final hasUnread = widget.room.messages.any(
      (message) => message.sender != me && !message.seen,
    );
    if (hasUnread) {
      _markSeen();
    }
  }

  // Opening the chat means you have now seen the other person's messages.
  // We only save if there was something new to mark.
  Future<void> _markSeen() async {
    if (_markingSeen) {
      return;
    }
    _markingSeen = true;
    try {
      final changed = await widget.appState.markMessagesAsSeen(widget.room);
      if (!mounted) {
        return;
      }
      if (changed && !widget.room.online) {
        await context.saveAndWarn(widget.appState);
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        context.showAppMessage(
          'Could not update read status: ${error.message ?? error.code}',
        );
      }
    } finally {
      _markingSeen = false;
    }
  }

  // Waits until the list has been drawn, then scrolls to the newest message.
  void _scrollToBottom({bool animate = true}) {
    final request = ++_scrollRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_continueScrollToBottom(request, animate: animate));
    });
  }

  Future<void> _continueScrollToBottom(
    int request, {
    required bool animate,
  }) async {
    final duration = animationDuration(context, 200);
    for (
      var attempt = 0;
      attempt < 4 &&
          mounted &&
          request == _scrollRequest &&
          _scrollController.hasClients;
      attempt++
    ) {
      final position = _scrollController.position;
      final bottom = position.maxScrollExtent;
      if (position.pixels < bottom - 1) {
        if (animate) {
          await _scrollController.animateTo(
            bottom,
            duration: duration,
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(bottom);
        }
      }

      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || request != _scrollRequest) {
        return;
      }

      final latestContext = _latestMessageKey.currentContext;
      if (latestContext != null && latestContext.mounted) {
        await Scrollable.ensureVisible(
          latestContext,
          alignment: 1,
          duration: duration,
          curve: Curves.easeOut,
        );
        await WidgetsBinding.instance.endOfFrame;
        if (_scrollController.hasClients) {
          final latestPosition = _scrollController.position;
          final latestBottom = latestPosition.maxScrollExtent;
          if (latestPosition.pixels < latestBottom - 1) {
            if (animate) {
              await _scrollController.animateTo(
                latestBottom,
                duration: duration,
                curve: Curves.easeOut,
              );
            } else {
              _scrollController.jumpTo(latestBottom);
            }
            await WidgetsBinding.instance.endOfFrame;
          }
        }
        return;
      }
    }
  }

  Future<void> _send() async {
    // Line breaks would break the one-line-per-record save file,
    // so they are turned into spaces.
    final text = _textController.text
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    if (text.isEmpty) {
      context.showAppMessage("Message can't be empty.");
      return;
    }
    if (text.length > ChatRoom.maxMessageLength) {
      context.showAppMessage(
        "Message can't be longer than ${ChatRoom.maxMessageLength} characters.",
      );
      return;
    }

    final Message? message;
    try {
      message = await widget.appState.sendMessage(
        widget.room,
        text,
        replyTo: _replyingTo,
      );
    } on FirebaseException catch (error) {
      if (mounted) {
        context.showAppMessage(
          'Could not send message: ${error.message ?? error.code}',
        );
      }
      return;
    } on StateError catch (error) {
      if (mounted) {
        context.showAppMessage(error.message);
      }
      return;
    } on FormatException catch (error) {
      if (mounted) {
        context.showAppMessage('Could not verify encryption keys: $error');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    if (message == null) {
      context.showAppMessage('You are not a member of this room.');
      return;
    }

    _textController.clear();
    setState(() => _replyingTo = null);
    _scrollToBottom();
    _focusNode.requestFocus();
    if (!widget.room.online) {
      await context.saveAndWarn(widget.appState);
    }
  }

  Future<void> _showSafetyCode() async {
    final String? code;
    try {
      code = await widget.appState.roomSafetyCode(widget.room);
    } on FormatException catch (error) {
      if (mounted) {
        context.showAppMessage('Could not verify encryption keys: $error');
      }
      return;
    } on StateError catch (error) {
      if (mounted) {
        context.showAppMessage(error.message);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final safetyCode = code;
    if (safetyCode == null) {
      context.showAppMessage('The other member’s encryption key is missing.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verify encryption safety code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Compare this code in person or over a trusted call. '
              'Only continue if it matches the other person’s code.',
            ),
            const SizedBox(height: 16),
            SelectableText(
              safetyCode,
              textAlign: TextAlign.center,
              style: Theme.of(dialogContext).textTheme.titleLarge,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await widget.appState.verifyRoomKey(widget.room);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              } on FirebaseException catch (error) {
                if (mounted && dialogContext.mounted) {
                  context.showAppMessage(
                    'Could not save verification: '
                    '${error.message ?? error.code}',
                  );
                }
              } on FormatException catch (error) {
                if (mounted && dialogContext.mounted) {
                  context.showAppMessage(
                    'Could not verify encryption keys: $error',
                  );
                }
              }
            },
            child: const Text('I compared the codes'),
          ),
        ],
      ),
    );
  }

  Widget _buildEncryptionBanner() {
    final room = widget.room;
    if (!room.online) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    if (room.members.length < 2) {
      return Card(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Waiting for the other person to join.'),
        ),
      );
    }
    if (widget.appState.isRoomKeyVerified(room)) {
      return const SizedBox.shrink();
    }
    final uid = widget.appState.currentUser?.accountId;
    final hasVerified = room.keyVerifiedUids.contains(uid);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hasVerified
                  ? 'Waiting for the other person to verify their safety code.'
                  : 'Compare safety codes before sending encrypted messages.',
            ),
            if (!hasVerified) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _showSafetyCode,
                child: const Text('Show safety code'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------- Replies and reactions ----------

  Message? _findMessage(String? id) {
    if (id == null) {
      return null;
    }
    for (final message in widget.room.messages) {
      if (message.id == id) {
        return message;
      }
    }
    return null;
  }

  Future<void> _react(Message message, String emoji) async {
    try {
      await widget.appState.reactToMessage(widget.room, message, emoji);
    } on FirebaseException catch (error) {
      if (mounted) {
        context.showAppMessage(
          'Could not react: ${error.message ?? error.code}',
        );
      }
    }
  }

  void _startReply(Message message) {
    setState(() => _replyingTo = message);
    _focusNode.requestFocus();
  }

  // Long-press a message: pick a reaction, or reply to it.
  // Long-press a message: a small emoji bar floats next to it, like Messenger.
  // [anchor] is the message's position on the screen.
  Future<void> _showReactionPicker(Message message, Rect anchor) async {
    final room = widget.room;
    if (!room.online || room.closed) {
      return;
    }
    final me = widget.appState.currentUser;
    final myUid = me?.accountId;
    final mine = message.sender == me;

    HapticFeedback.selectionClick();

    final emoji = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: animationDuration(context, 160),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final colors = Theme.of(dialogContext).colorScheme;
        final screen = MediaQuery.of(dialogContext).size;
        final safe = MediaQuery.of(dialogContext).padding;

        const barHeight = 52.0;
        const gap = 8.0;
        final barWidth = (_reactionEmojis.length * 48.0 + 16)
            .clamp(0.0, screen.width - 16)
            .toDouble();

        // Line the bar up with the bubble's side, but keep it on the screen.
        final left = (mine ? anchor.right - barWidth : anchor.left)
            .clamp(8.0, screen.width - barWidth - 8)
            .toDouble();

        // Above the message if there is room, otherwise below it.
        final above = anchor.top - barHeight - gap;
        final top =
            (above < safe.top + kToolbarHeight ? anchor.bottom + gap : above)
                .clamp(
                  safe.top + 8,
                  screen.height - safe.bottom - barHeight - 8,
                )
                .toDouble();

        return Stack(
          children: [
            // A copy of the selected message, lifted above the dimmed screen.
            Positioned(
              left: anchor.left,
              top: anchor.top,
              width: anchor.width,
              child: IgnorePointer(
                child: Material(
                  type: MaterialType.transparency,
                  child: _buildBubble(message, me!, interactive: false),
                ),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: barWidth,
              height: barHeight,
              child: ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                ),
                alignment: mine ? Alignment.bottomRight : Alignment.bottomLeft,
                child: FadeTransition(
                  opacity: animation,
                  child: Material(
                    elevation: 6,
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(barHeight / 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final emoji in _reactionEmojis)
                          IconButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(emoji),
                            style: message.reactions[myUid] == emoji
                                ? IconButton.styleFrom(
                                    backgroundColor: colors.primaryContainer,
                                  )
                                : null,
                            icon: Text(
                              emoji,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (emoji == null || !mounted) {
      return;
    }
    await _react(message, emoji);
  }

  // The small quoted box at the top of a reply bubble.
  Widget _buildQuote(Message message, Color foreground) {
    final original = _findMessage(message.replyToId);
    final me = widget.appState.currentUser!;
    final name = original == null
        ? ''
        : (original.sender == me ? 'You' : original.sender.name);
    final snippet = original?.text ?? 'Original message unavailable';
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: foreground.withAlpha(30),
        border: Border(
          left: BorderSide(color: foreground.withAlpha(160), width: 3),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (name.isNotEmpty)
              Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: foreground,
                ),
              ),
            Text(
              snippet,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: foreground.withAlpha(220)),
            ),
          ],
        ),
      ),
    );
  }

  // The reaction chips under a bubble. Tap one to add or remove yours.
  Widget _buildReactions(Message message) {
    if (message.reactions.isEmpty) {
      return const SizedBox.shrink();
    }
    final myUid = widget.appState.currentUser?.accountId;
    final colors = Theme.of(context).colorScheme;
    final counts = <String, int>{};
    for (final emoji in message.reactions.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Wrap(
        spacing: 4,
        children: [
          for (final entry in counts.entries)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.room.closed
                  ? null
                  : () => _react(message, entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: message.reactions[myUid] == entry.key
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  entry.value > 1 ? '${entry.key} ${entry.value}' : entry.key,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // The bar above the text box while you are answering a message.
  Widget _buildReplyPreview() {
    final replying = _replyingTo;
    if (replying == null) {
      return const SizedBox.shrink();
    }
    final me = widget.appState.currentUser!;
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(colors.onSurface.withAlpha(16), colors.surface),
        border: Border(left: BorderSide(color: colors.primary, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  replying.sender == me
                      ? 'Replying to yourself'
                      : 'Replying to ${replying.sender.name}',
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  replying.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel reply',
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  // ---------- Look ----------

  Widget _buildNewMessagesDivider() {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: color.withAlpha(120))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'New messages',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(child: Divider(color: color.withAlpha(120))),
        ],
      ),
    );
  }

  // The day label above the first message of each day, like Telegram.
  Widget _buildDayLabel(DateTime day) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            colors.onSurface.withAlpha(24),
            colors.surface,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          formatDayLabel(day, DateTime.now()),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.onSurface.withAlpha(180),
          ),
        ),
      ),
    );
  }

  // "glow" goes from 1 (full glow) down to 0 (none). New messages use it.
  Widget _buildBubble(
    Message message,
    Profile user, {
    double glow = 0,
    bool interactive = true,
  }) {
    final mine = message.sender == user;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    // Your bubbles are in the app color. The other person's are a soft grey.
    final Color background;
    final Color foreground;

    if (mine) {
      background = dark ? colors.primaryContainer : colors.primary;
      foreground = dark ? colors.onPrimaryContainer : colors.onPrimary;
    } else {
      background = Color.alphaBlend(
        colors.onSurface.withAlpha(24),
        colors.surface,
      );
      foreground = colors.onSurface;
    }

    final time = formatMessageTime(message.timestamp);
    final faint = TextStyle(fontSize: 11, color: foreground.withAlpha(180));

    final bubble = Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        // The bubble grows with its text, up to most of the screen width.
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.of(context).size.width * 0.78)
              .clamp(0.0, 320.0)
              .toDouble(),
        ),
        child: Builder(
          builder: (bubbleContext) => GestureDetector(
            onLongPress:
                interactive && widget.room.online && !widget.room.closed
                ? () {
                    final box = bubbleContext.findRenderObject() as RenderBox;
                    final rect = box.localToGlobal(Offset.zero) & box.size;
                    _showReactionPicker(message, rect);
                  }
                : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.fromLTRB(12, 7, 10, 5),
                  decoration: BoxDecoration(
                    color: background,
                    boxShadow: glow > 0
                        ? [
                            BoxShadow(
                              color: colors.primary.withAlpha(
                                (170 * glow).round(),
                              ),
                              blurRadius: 4 + 16 * glow,
                              spreadRadius: glow,
                            ),
                          ]
                        : null,
                    // The corner next to the sender is flatter, like in chat apps.
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(mine ? 20 : 4),
                      bottomRight: Radius.circular(mine ? 4 : 20),
                    ),
                  ),
                  // IntrinsicWidth makes the bubble only as wide as its widest
                  // line, so the time row below can't stretch a short message.
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!mine)
                          Text(
                            message.sender.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: colors.primary,
                            ),
                          ),
                        if (message.replyToId != null)
                          _buildQuote(message, foreground),
                        Text(
                          message.text,
                          style: TextStyle(fontSize: 16, color: foreground),
                        ),
                        const SizedBox(height: 2),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(time, style: faint),
                              // Only your own messages show Sent / Seen, as a
                              // single check (sent) or a double check (seen).
                              if (mine) ...[
                                const SizedBox(width: 4),
                                Tooltip(
                                  message: message.seen ? 'Seen' : 'Sent',
                                  child: AnimatedSwitcher(
                                    duration: animationDuration(context, 250),
                                    child: Icon(
                                      message.seen
                                          ? Icons.done_all
                                          : Icons.done,
                                      key: ValueKey(message.seen),
                                      size: 14,
                                      color: foreground.withAlpha(180),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildReactions(message),
              ],
            ),
          ),
        ),
      ),
    );

    if (!interactive) {
      return bubble;
    }

    // Swipe sideways to reply. Same rules as the long-press "Reply" action.
    return SwipeToReply(
      enabled:
          widget.room.online &&
          !widget.room.closed &&
          widget.appState.isRoomKeyVerified(widget.room),
      swipeLeft: mine,
      onReply: () => _startReply(message),
      child: bubble,
    );
  }

  // The pop-up menu of the message box, without Copy and Cut.
  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final allowed = editableTextState.contextMenuButtonItems.where((item) {
      return item.type != ContextMenuButtonType.copy &&
          item.type != ContextMenuButtonType.cut;
    }).toList();
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: allowed,
    );
  }

  Widget _buildInputBar({required bool enabled}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 100,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7F4),
        border: Border.all(color: const Color(0xFFE7E7E1), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'In future updates',
            onPressed: () => context.showAppMessage('In future updates'),
          ),
          Expanded(
            child: TextField(
              enabled: enabled,
              controller: _textController,
              focusNode: _focusNode,
              maxLength: ChatRoom.maxMessageLength,
              // The counter only appears when you get close to the limit.
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    required maxLength,
                  }) => currentLength > 400
                  ? Text('$currentLength/$maxLength')
                  : null,
              textInputAction: TextInputAction.send,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [
                FilteringTextInputFormatter.singleLineFormatter,
              ],
              contextMenuBuilder: _buildContextMenu,
              decoration: InputDecoration(
                hintText: enabled
                    ? 'Type a message'
                    : 'Verify the safety code to chat',
                filled: true,
                fillColor: Color.alphaBlend(
                  colors.onSurface.withAlpha(16),
                  colors.surface,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: const Icon(Icons.send),
            tooltip: 'Send',
            onPressed: enabled ? _send : null,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final user = widget.appState.currentUser!;
    final messages = widget.room.messages;
    final colors = Theme.of(context).colorScheme;
    final otherMember = widget.room.otherMemberOf(user);
    final canSend =
        !widget.room.online || widget.appState.isRoomKeyVerified(widget.room);
    final subtitleColor = Theme.of(
      context,
    ).appBarTheme.foregroundColor?.withAlpha(200);

    return Scaffold(
      // A very light tint of the app color behind the messages.
      backgroundColor: Color.alphaBlend(
        colors.primary.withAlpha(14),
        colors.surface,
      ),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            ProfileAvatar(
              appState: widget.appState,
              profile: otherMember,
              radius: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    otherMember?.name ?? roomMemberLabel(widget.room, user),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    otherMember == null
                        ? 'Room ${widget.room.code}'
                        : '@${otherMember.username}',
                    style: TextStyle(fontSize: 12, color: subtitleColor),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton.icon(
            onPressed: () =>
                context.showAppMessage('Adding contacts is coming soon.'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('add'),
          ),
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (value) {
              if (value == 'room-code') {
                context.showAppMessage('Room code: ${widget.room.code}');
              } else if (value == 'safety-code') {
                _showSafetyCode();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'room-code', child: Text('Room code')),
              if (widget.room.online)
                const PopupMenuItem(
                  value: 'safety-code',
                  child: Text('Verify safety code'),
                ),
            ],
          ),
        ],
      ),
      body: ScreenBody(
        maxWidth: 600,
        child: Column(
          children: [
            _buildEncryptionBanner(),
            Expanded(
              child: messages.isEmpty
                  ? const Center(child: Text('No messages yet. Say hello!'))
                  : ListView.builder(
                      controller: _scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.all(12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        Widget item;
                        if (_newMessageIds.contains(message.id)) {
                          // Messages that were waiting for you glow for a
                          // moment, then settle down.
                          item = TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 1, end: 0),
                            duration: animationDuration(context, 2400),
                            curve: Curves.easeOut,
                            builder: (context, glow, _) =>
                                _buildBubble(message, user, glow: glow),
                          );
                        } else if (index < _initialMessageCount) {
                          item = _buildBubble(message, user);
                        } else {
                          // A message you just sent pops in, growing from
                          // its bottom corner.
                          item = PopIn(
                            alignment: message.sender == user
                                ? Alignment.bottomRight
                                : Alignment.bottomLeft,
                            child: _buildBubble(message, user),
                          );
                        }
                        // A line above the first new message.
                        if (message.id == _firstNewMessageId) {
                          item = Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [_buildNewMessagesDivider(), item],
                          );
                        }
                        // A day label above the first message of each day.
                        final previous = index == 0
                            ? null
                            : messages[index - 1];
                        if (previous == null ||
                            !isSameDay(previous.timestamp, message.timestamp)) {
                          item = Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [_buildDayLabel(message.timestamp), item],
                          );
                        }
                        return index == messages.length - 1
                            ? KeyedSubtree(key: _latestMessageKey, child: item)
                            : item;
                      },
                    ),
            ),
            _buildReplyPreview(),
            _buildInputBar(enabled: canSend),
          ],
        ),
      ),
    );
  }
}
