import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../formatting.dart';
import '../models/chat_room.dart';
import '../online/online_chat_service.dart';
import '../online/username_service.dart';
import '../widgets/animations.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/screen_body.dart';
import '../ui_feedback.dart';
import 'account_screen.dart';
import 'chat_screen.dart';
import 'edit_profile_dialog.dart';
import 'join_room_dialog.dart';
import 'settings_screen.dart';
import 'username_screen_dialog.dart';

// Shows the current user's rooms and lets them create a room, join a room,
// edit their name, and leave a room.
// A small "Guest room" section above the roommate rooms holds chats started
// from a username search. It can be collapsed.
// The back arrow in the top bar returns to the Profile screen.
class RoomsScreen extends StatefulWidget {
  final AppState appState;

  const RoomsScreen({super.key, required this.appState});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final Map<String, Stream<List<OnlineJoinRequest>>> _joinRequestStreams = {};
  late final _usernameService = UsernameService();

  // Is the guest section open or folded away?
  bool _guestExpanded = true;

  // Talk requests being accepted or declined right now (their buttons wait).
  final Set<String> _busyRequests = {};

  Stream<List<OnlineJoinRequest>> _joinRequestsFor(ChatRoom room) =>
      _joinRequestStreams.putIfAbsent(
        '${widget.appState.currentUser?.accountId}:${room.code}',
        () => widget.appState.watchJoinRequests(room.code),
      );

  // Copies a room code to the clipboard. This is the only thing in the app
  // that can be copied. Chat messages stay uncopyable.
  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      context.showAppMessage('Room code copied.');
    }
  }

  Future<void> _createRoom() async {
    final ChatRoom? room;
    try {
      room = widget.appState.onlineChatService == null
          ? widget.appState.createRoom()
          : await widget.appState.createOnlineRoom();
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }
      context.showAppMessage(
        'Could not create online room: ${error.message ?? error.code}',
      );
      return;
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }
      context.showAppMessage(error.message);
      return;
    }
    if (!mounted) {
      return;
    }
    final createdRoom = room;
    if (createdRoom == null) {
      context.showAppMessage(
        'You are already in a room. Leave it first to start a new one.',
      );
      return;
    }
    await widget.appState.actionSoundEffects?.playSuccess();
    if (!mounted) {
      return;
    }
    if (!createdRoom.online) {
      await context.saveAndWarn(widget.appState);
    }
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Room created!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share this code with your roommate:'),
            const SizedBox(height: 12),
            Text(
              createdRoom.code,
              style: Theme.of(dialogContext).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Tap Copy to paste it into a message, '
              'or read it out to your roommate.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _copyCode(createdRoom.code),
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _joinRoom() async {
    final joined = await showDialog<bool>(
      context: context,
      builder: (_) => JoinRoomDialog(appState: widget.appState),
    );
    if (joined != true || !mounted) {
      return;
    }
    if (widget.appState.onlineChatService != null) {
      context.showAppMessage(
        'Request sent. The room owner must approve before you can chat.',
      );
    } else {
      await context.saveAndWarn(widget.appState);
      if (mounted) {
        context.showAppMessage('You joined the room.');
      }
    }
    await widget.appState.actionSoundEffects?.playSuccess();
  }

  // ---------- Guest chats ----------

  // Search a username, then ask that person to talk.
  Future<void> _findPerson() async {
    final picked = await showDialog<UsernameResult>(
      context: context,
      builder: (_) => UsernameSearchDialog(service: _usernameService),
    );
    if (picked == null || !mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Talk to @${picked.username}?'),
        content: const Text(
          'They will get a request. If they accept, you both join a guest '
          'chat. You must compare safety codes before you can send messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await widget.appState.sendTalkRequest(
        toUid: picked.uid,
        toUsername: picked.username,
      );
      await widget.appState.actionSoundEffects?.playSuccess();
      if (mounted) {
        setState(() => _guestExpanded = true);
        context.showAppMessage('Request sent to @${picked.username}.');
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        context.showAppMessage(
          'Could not send request: ${error.message ?? error.code}',
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        context.showAppMessage(error.message);
      }
    }
  }

  Future<void> _respondToTalkRequest(
    TalkRequest request, {
    required bool accept,
  }) async {
    if (!_busyRequests.add(request.id)) {
      return;
    }
    setState(() {});
    try {
      await widget.appState.respondToTalkRequest(request, accept: accept);
      await widget.appState.actionSoundEffects?.playSuccess();
      if (mounted) {
        context.showAppMessage(
          accept
              ? 'You are now connected with @${request.fromUsername}.'
              : 'Request declined.',
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        context.showAppMessage(
          'Could not answer request: ${error.message ?? error.code}',
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        context.showAppMessage(error.message);
      }
    } on FormatException catch (error) {
      if (mounted) {
        context.showAppMessage('Could not verify the sender’s key: $error');
      }
    } finally {
      _busyRequests.remove(request.id);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<String?> _decideJoinRequest(
    ChatRoom room,
    OnlineJoinRequest request, {
    required bool approve,
  }) async {
    if (!_isRoomOwner(room)) {
      return 'Only the room owner can decide join requests.';
    }
    try {
      await widget.appState.decideJoinRequest(
        room.code,
        request.requesterUid,
        approve: approve,
      );
      await widget.appState.actionSoundEffects?.playSuccess();
      return null;
    } on FirebaseException catch (error) {
      return 'Could not update join request: ${error.message ?? error.code}';
    } on StateError catch (error) {
      return error.message;
    } on FormatException catch (error) {
      return 'Could not verify the joiner’s key: $error';
    }
  }

  // Only the owner of an online room may see and decide join requests.
  bool _isRoomOwner(ChatRoom room) {
    final user = widget.appState.currentUser;
    return user != null &&
        room.online &&
        user.accountId != null &&
        room.ownerUid == user.accountId;
  }

  Future<void> _showJoinRequests(ChatRoom room) async {
    if (!_isRoomOwner(room)) {
      context.showAppMessage('Only the room owner can manage join requests.');
      return;
    }

    String? busyRequesterUid;
    String? actionError;
    String? actionMessage;
    final requestStream = widget.appState.watchJoinRequests(room.code);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> decide(
            OnlineJoinRequest request, {
            required bool approve,
          }) async {
            setDialogState(() {
              busyRequesterUid = request.requesterUid;
              actionError = null;
              actionMessage = null;
            });
            try {
              final error = await _decideJoinRequest(
                room,
                request,
                approve: approve,
              );
              if (dialogContext.mounted) {
                setDialogState(() {
                  actionError = error;
                  actionMessage = error == null
                      ? (approve
                            ? 'Join request approved.'
                            : 'Join request declined.')
                      : null;
                });
              }
            } finally {
              if (dialogContext.mounted) {
                setDialogState(() => busyRequesterUid = null);
              }
            }
          }

          return AlertDialog(
            title: Text('Join requests for ${room.code}'),
            content: SizedBox(
              width: 360,
              height: 280,
              child: Column(
                children: [
                  if (actionError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        actionError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (actionMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        actionMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  Expanded(
                    child: StreamBuilder<List<OnlineJoinRequest>>(
                      stream: requestStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text(
                            'Could not load requests: ${snapshot.error}',
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final requests = snapshot.data!;
                        if (requests.isEmpty) {
                          return const Center(
                            child: Text('No pending requests.'),
                          );
                        }
                        return ListView(
                          children: [
                            for (final request in requests)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(request.displayName),
                                subtitle: Text(
                                  request.username.isEmpty
                                      ? 'Wants to join this room'
                                      : '@${request.username} wants to join',
                                ),
                                trailing:
                                    busyRequesterUid == request.requesterUid
                                    ? const SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: Center(
                                          child: SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        ),
                                      )
                                    : Wrap(
                                        spacing: 4,
                                        children: [
                                          IconButton(
                                            tooltip: 'Approve',
                                            onPressed: busyRequesterUid != null
                                                ? null
                                                : () => decide(
                                                    request,
                                                    approve: true,
                                                  ),
                                            icon: const Icon(Icons.check),
                                          ),
                                          IconButton(
                                            tooltip: 'Decline',
                                            onPressed: busyRequesterUid != null
                                                ? null
                                                : () => decide(
                                                    request,
                                                    approve: false,
                                                  ),
                                            icon: const Icon(Icons.close),
                                          ),
                                        ],
                                      ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busyRequesterUid == null
                    ? () => Navigator.of(dialogContext).pop()
                    : null,
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editProfile() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => EditProfileDialog(appState: widget.appState),
    );
    if (!mounted) {
      return;
    }
    if (changed != true) {
      return;
    }
    await context.saveAndWarn(widget.appState);
    if (mounted) {
      context.showAppMessage('Name updated.');
    }
  }

  // Action sheet that asks the user to confirm leaving a room.
  // Layout matches the design: 300px wide, 276px tall (at minimum),
  // column, 14px padding, left-aligned content.
  Future<bool?> _confirmLeaveRoom(ChatRoom room) {
    final lastPerson = room.members.length == 1;
    final deleteForEveryone = room.online && !room.guest && _isRoomOwner(room);
    final deleteLastGuestRoom = room.online && room.guest && lastPerson;

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colors = theme.colorScheme;

        return Dialog(
          backgroundColor: colors.surface,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 300,
              maxWidth: 300,
              minHeight: 276, // grows if text is larger, never overflows
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    'Leave room ${room.code}?',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    deleteForEveryone
                        ? 'You are the room owner. Leaving will permanently '
                              'delete this room, all messages, and pending '
                              'join requests for everyone. The other person '
                              'will lose access to the conversation. This '
                              'cannot be undone.'
                        : deleteLastGuestRoom
                        ? 'You are the last person in this closed guest chat. '
                              'Leaving will delete the room and its messages.'
                        : room.online && room.guest
                        ? 'Leaving will close this guest chat. The other '
                              'person can still read the existing messages, '
                              'but no one can send new ones.'
                        : lastPerson
                        ? 'Nobody else is in this room, so the room and all '
                              'its messages will be deleted.'
                        : 'Your messages will stay for your roommate. The room '
                              'will be closed to new members.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.error,
                        foregroundColor: colors.onError,
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text(
                        deleteForEveryone
                            ? 'Delete room for everyone'
                            : deleteLastGuestRoom
                            ? 'Delete guest chat'
                            : 'Leave',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _leaveRoom(ChatRoom room) async {
    final confirmed = await _confirmLeaveRoom(room);
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      if (room.online) {
        await widget.appState.leaveOnlineRoom(room);
      } else {
        widget.appState.leaveRoom(room);
        await context.saveAndWarn(
          widget.appState,
          failureMessage: 'You left the room, but it could not be saved.',
        );
      }
      await widget.appState.actionSoundEffects?.playSuccess();
      if (mounted) {
        context.showAppMessage('You left room ${room.code}.');
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        context.showAppMessage(
          'Could not leave room: ${error.message ?? error.code}',
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        context.showAppMessage(error.message);
      }
    }
  }

  // Opens the account screen. An unlinked profile must return to onboarding.
  Future<void> _openAccount() async {
    await Navigator.of(
      context,
    ).push(smoothRoute<void>(AccountScreen(appState: widget.appState)));
    if (!mounted) {
      return;
    }
    if (!widget.appState.hasVerifiedAccount(widget.appState.currentUser!)) {
      Navigator.of(context).pop();
      return;
    }
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(smoothRoute<void>(SettingsScreen(appState: widget.appState)));
  }

  Future<void> _openChat(ChatRoom room) async {
    await Navigator.of(context).push(
      smoothRoute<void>(ChatScreen(appState: widget.appState, room: room)),
    );
  }

  // ---------- Guest section ----------

  // The little number bubble used for unread messages and new requests.
  Widget _countBadge(int count) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: colors.onPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  // Someone asked to talk to me: accept or decline.
  Widget _buildIncomingRequestTile(TalkRequest request) {
    final busy = _busyRequests.contains(request.id);
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: const CircleAvatar(
        radius: 16,
        child: Icon(Icons.person_add_alt_1, size: 16),
      ),
      title: Text('@${request.fromUsername}'),
      subtitle: Text('${request.fromName} wants to talk'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Accept',
            onPressed: busy
                ? null
                : () => _respondToTalkRequest(request, accept: true),
            icon: const Icon(Icons.check),
          ),
          IconButton(
            tooltip: 'Decline',
            onPressed: busy
                ? null
                : () => _respondToTalkRequest(request, accept: false),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  // I asked someone to talk: waiting for their answer.
  Widget _buildOutgoingRequestTile(TalkRequest request) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: const CircleAvatar(
        radius: 16,
        child: Icon(Icons.hourglass_empty, size: 16),
      ),
      title: Text('@${request.toUsername}'),
      subtitle: const Text('Waiting for them to accept'),
    );
  }

  // A guest chat. Smaller than a roommate room tile.
  Widget _buildGuestTile(ChatRoom room) {
    final user = widget.appState.currentUser!;
    final otherMember = room.otherMemberOf(user);
    final unread = room.countUnread(user);

    return Opacity(
      opacity: room.closed ? 0.7 : 1,
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: ProfileAvatar(
          appState: widget.appState,
          profile: otherMember,
          radius: 16,
        ),
        title: Text(
          roomMemberLabel(room, user),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        subtitle: room.closed ? const Text('Closed') : null,
        onTap: () => _openChat(room),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unread > 0) _countBadge(unread),
            IconButton(
              icon: const Icon(Icons.logout, size: 20),
              tooltip: 'Leave guest chat',
              onPressed: () => _leaveRoom(room),
            ),
          ],
        ),
      ),
    );
  }

  // The "Guest room" card above the roommate rooms. Tap the header to fold
  // it away; a badge on the header still shows new requests.
  Widget _buildGuestSection(AppState appState) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final guestRooms = appState.myGuestRooms;
    final incoming = appState.incomingTalkRequests;
    final outgoing = appState.outgoingTalkRequests;
    final isEmpty = guestRooms.isEmpty && incoming.isEmpty && outgoing.isEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _guestExpanded = !_guestExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(Icons.people_outline, size: 20, color: colors.primary),
                    const SizedBox(width: 10),
                    Text('Guest room', style: theme.textTheme.titleSmall),
                    if (guestRooms.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${guestRooms.length}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (incoming.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _countBadge(incoming.length),
                    ],
                    const Spacer(),
                    AnimatedRotation(
                      turns: _guestExpanded ? 0.5 : 0,
                      duration: animationDuration(context, 200),
                      child: const Icon(Icons.expand_more),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: animationDuration(context, 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _guestExpanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(height: 1),
                        if (isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                            child: Text(
                              'No guest chats yet. Tap the search icon to '
                              'find someone by username.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        for (final request in incoming)
                          _buildIncomingRequestTile(request),
                        for (final request in outgoing)
                          _buildOutgoingRequestTile(request),
                        for (final room in guestRooms) _buildGuestTile(room),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Roommate rooms ----------

  Widget _buildRoomTile(ChatRoom room) {
    final user = widget.appState.currentUser!;
    final otherMember = room.otherMemberOf(user);
    final unread = room.countUnread(user);
    final colors = Theme.of(context).colorScheme;

    return AnimatedOpacity(
      // A closed room (the other member left) fades to a softer look.
      opacity: room.closed ? 0.7 : 1,
      duration: animationDuration(context, 300),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        // A room with new messages glows softly until you open it.
        child: GlowPulse(
          active: unread > 0,
          color: colors.primary,
          child: Material(
            // The glow box above paints a background, so the tile needs its own
            // see-through Material for its tap ripple to stay visible.
            type: MaterialType.transparency,
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              leading: ProfileAvatar(
                appState: widget.appState,
                profile: otherMember,
                radius: 26,
              ),
              title: Text(
                roomMemberLabel(room, user),
                style: TextStyle(
                  fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              subtitle: Row(
                children: [
                  Text('Code: ${room.code}'),
                  if (_isRoomOwner(room))
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        'Owner',
                        style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (!room.closed)
                    Tooltip(
                      message: 'Copy room code',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _copyCode(room.code),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.copy, size: 16),
                        ),
                      ),
                    ),
                ],
              ),
              onTap: () => _openChat(room),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isRoomOwner(room))
                    StreamBuilder<List<OnlineJoinRequest>>(
                      stream: _joinRequestsFor(room),
                      builder: (context, snapshot) => GlowPulse(
                        key: ValueKey('join-requests-${room.code}'),
                        active: snapshot.hasData && snapshot.data!.isNotEmpty,
                        color: colors.primary,
                        radius: 24,
                        child: IconButton(
                          icon: const Icon(Icons.person_add_alt_1),
                          tooltip: 'Join requests',
                          onPressed: () => _showJoinRequests(room),
                        ),
                      ),
                    ),
                  // The unread count pops in when it appears or changes.
                  AnimatedSwitcher(
                    duration: animationDuration(context, 250),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: unread > 0
                        ? Container(
                            key: ValueKey(unread),
                            constraints: const BoxConstraints(minWidth: 24),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$unread',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colors.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey(0)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Leave room',
                    onPressed: () => _leaveRoom(room),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final appState = widget.appState;
        final myRooms = appState.myRooms;
        final theme = Theme.of(context);
        final online = appState.onlineChatService != null;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Lobby'),
            actions: [
              // Only shown when an online account system is connected.
              if (appState.accountService != null)
                IconButton(
                  icon: Icon(
                    appState.currentUser!.accountId == null
                        ? Icons.cloud_outlined
                        : Icons.cloud_done,
                  ),
                  tooltip: 'Online account',
                  onPressed: _openAccount,
                ),
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit profile',
                onPressed: _editProfile,
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
                onPressed: _openSettings,
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _createRoom,
            icon: const Icon(Icons.add),
            label: const Text('Create room'),
          ),
          body: ScreenBody(
            maxWidth: 560,
            child: ListView(
              // Extra space at the bottom so the button never hides a room.
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Welcome, ${appState.currentUser}',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Search for a username to start a guest chat.
                      if (online) ...[
                        IconButton.outlined(
                          icon: const Icon(Icons.search),
                          tooltip: 'Find a username',
                          onPressed: _findPerson,
                        ),
                        const SizedBox(width: 8),
                      ],
                      OutlinedButton.icon(
                        icon: const Icon(Icons.login),
                        label: const Text('Join room'),
                        onPressed: _joinRoom,
                      ),
                    ],
                  ),
                ),
                // The guest room sits above the roommate rooms.
                if (online) _buildGuestSection(appState),
                if (myRooms.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'You are not in any rooms yet.\n'
                          'Create one, or join a roommate\'s room with their code.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  for (var i = 0; i < myRooms.length; i++) ...[
                    FadeSlideIn(index: i, child: _buildRoomTile(myRooms[i])),
                    const Divider(height: 1, indent: 80),
                  ],
                if (appState.onlineError != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      appState.onlineError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
