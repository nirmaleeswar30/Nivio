import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/providers/watch_party_provider.dart';
import 'package:nivio/core/theme.dart';

class WatchPartyParticipantsSheet extends ConsumerWidget {
  const WatchPartyParticipantsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(watchPartySessionProvider);
    final session = sessionAsync.value;
    final service = ref.read(watchPartyServiceProvider);

    if (session == null || service == null) {
      return const SizedBox.shrink();
    }

    final isHost = session.hostId == service.userId;
    final currentControllerId = session.controllerId;

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(24.0)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
            child: Material(
              color: const Color(0x99101010),
              child: SizedBox(
                width: 350,
                height: double.infinity,
                child: SafeArea(
                  left: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Watch Party',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Row(
                          children: [
                            Text(
                              'Session Code: ${session.sessionCode}',
                              style: const TextStyle(
                                color: NivioTheme.netflixLightGrey,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: session.sessionCode));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Session Code Copied!'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: const Icon(Icons.copy, color: NivioTheme.netflixLightGrey, size: 16),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          itemCount: session.participants.length,
                          itemBuilder: (context, index) {
                            final p = session.participants[index];
                            final isMe = p.id == service.userId;
                            final hasControl = p.id == currentControllerId || (p.isHost && currentControllerId == null);

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.white24,
                                backgroundImage: p.photoUrl != null ? NetworkImage(p.photoUrl!) : null,
                                child: p.photoUrl == null
                                    ? Text(
                                        p.name.substring(0, 1).toUpperCase(),
                                        style: const TextStyle(color: Colors.white),
                                      )
                                    : null,
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      p.name,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isMe)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 6.0),
                                      child: Text(
                                        '(You)',
                                        style: TextStyle(color: Colors.white54, fontSize: 12),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Row(
                                children: [
                                  if (p.isHost)
                                    Container(
                                      margin: const EdgeInsets.only(right: 6, top: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: NivioTheme.accentColorOf(context),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('Host', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                    ),
                                  if (hasControl)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blueAccent,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('Controller', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                              trailing: (isHost && !p.isHost) 
                                ? PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, color: Colors.white70),
                                    color: Colors.grey[900],
                                    onSelected: (val) {
                                      if (val == 'give') {
                                        service.setPlaybackController(p.id);
                                      } else if (val == 'revoke') {
                                        service.setPlaybackController(null);
                                      }
                                    },
                                    itemBuilder: (context) {
                                      if (p.id == currentControllerId) {
                                        return [
                                          const PopupMenuItem(
                                            value: 'revoke',
                                            child: Text('Revoke Control', style: TextStyle(color: Colors.white)),
                                          ),
                                        ];
                                      } else {
                                        return [
                                          const PopupMenuItem(
                                            value: 'give',
                                            child: Text('Give Control', style: TextStyle(color: Colors.white)),
                                          ),
                                        ];
                                      }
                                    },
                                  )
                                : null,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
