import 'dart:async';
import 'dart:io';

import 'package:discord_rich_presence/discord_rich_presence.dart';
import 'package:flutter/foundation.dart';

/// Singleton service that manages Discord Rich Presence on desktop platforms.
///
/// Connects to the local Discord client via IPC (named pipe on Windows,
/// Unix domain socket on Linux/macOS) and updates the user's activity
/// status based on what they're doing in Nivio.
class DiscordRpcService {
  DiscordRpcService._();

  /// Global singleton instance.
  static final DiscordRpcService instance = DiscordRpcService._();

  Client? _client;
  String? _clientId;
  bool _connected = false;
  bool _disposed = false;

  /// Whether the service is currently connected to Discord.
  bool get isConnected => _connected;

  // ──────────────────── Lifecycle ────────────────────

  /// Initialize and connect to Discord IPC.
  ///
  /// Does nothing on mobile platforms or if [clientId] is empty.
  /// Silently swallows errors when Discord desktop is not running.
  Future<void> initialize(String clientId) async {
    if (!_isDesktop) return;
    final trimmed = clientId.trim();
    if (trimmed.isEmpty) return;

    _clientId = trimmed;
    _disposed = false;

    try {
      _client = Client(clientId: trimmed);
      await _client!.connect();
      _connected = true;
      debugPrint('[DiscordRPC] Connected to Discord (clientId: $trimmed)');
    } catch (e) {
      _connected = false;
      _client = null;
      debugPrint('[DiscordRPC] Could not connect to Discord: $e');
    }
  }

  /// Disconnect from Discord and clean up.
  Future<void> dispose() async {
    _disposed = true;
    if (!_connected || _client == null) return;

    try {
      await _client!.disconnect();
      debugPrint('[DiscordRPC] Disconnected from Discord');
    } catch (e) {
      debugPrint('[DiscordRPC] Error disconnecting: $e');
    } finally {
      _connected = false;
      _client = null;
    }
  }

  // ──────────────────── Activity Updates ────────────────────

  /// Set status to "Watching: [title]" with optional season/episode info,
  /// poster artwork, and elapsed timer.
  void setWatching({
    required String title,
    String? details,
    String? posterUrl,
    DateTime? startedAt,
  }) {
    if (!_canUpdate) return;

    try {
      _client!.setActivity(Activity(
        name: 'Nivio',
        type: ActivityType.watching,
        details: title,
        state: details,
        timestamps: ActivityTimestamps(
          start: startedAt ?? DateTime.now(),
        ),
        assets: _buildAssets(
          posterUrl: posterUrl,
          largeText: title,
          smallText: details,
        ),
      ));
      debugPrint('[DiscordRPC] Activity → Watching: $title ($details)');
    } catch (e) {
      debugPrint('[DiscordRPC] Failed to set watching activity: $e');
      _handleDisconnect();
    }
  }

  /// Set status to "Paused — [title]".
  void setPaused({String? title}) {
    if (!_canUpdate) return;

    try {
      _client!.setActivity(Activity(
        name: 'Nivio',
        type: ActivityType.watching,
        details: 'Paused',
        state: title,
        assets: _buildAssets(
          largeText: title ?? 'Nivio',
          smallText: 'Paused',
        ),
      ));
      debugPrint('[DiscordRPC] Activity → Paused: $title');
    } catch (e) {
      debugPrint('[DiscordRPC] Failed to set paused activity: $e');
      _handleDisconnect();
    }
  }

  /// Set status to "Browsing Nivio" (idle/default state).
  void setBrowsing() {
    if (!_canUpdate) return;

    try {
      _client!.setActivity(Activity(
        name: 'Nivio',
        type: ActivityType.watching,
        details: 'Browsing',
        state: 'Exploring movies & shows',
        assets: _buildAssets(
          largeText: 'Nivio',
          smallText: 'Browsing',
        ),
      ));
      debugPrint('[DiscordRPC] Activity → Browsing');
    } catch (e) {
      debugPrint('[DiscordRPC] Failed to set browsing activity: $e');
      _handleDisconnect();
    }
  }

  /// Clear the Discord activity (disconnect and optionally reconnect).
  Future<void> clearActivity() async {
    if (!_connected || _client == null) return;

    try {
      // discord_rich_presence doesn't have a clearActivity method,
      // so we disconnect and reconnect to clear the status.
      await _client!.disconnect();
      _connected = false;
      _client = null;

      if (!_disposed && _clientId != null) {
        // Small delay to allow Discord to process the disconnect.
        await Future.delayed(const Duration(milliseconds: 500));
        await initialize(_clientId!);
      }
    } catch (e) {
      debugPrint('[DiscordRPC] Failed to clear activity: $e');
      _connected = false;
      _client = null;
    }
  }

  // ──────────────────── Helpers ────────────────────

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool get _canUpdate => _connected && _client != null && !_disposed;

  ActivityAssets? _buildAssets({
    String? posterUrl,
    String? largeText,
    String? smallText,
  }) {
    if (posterUrl != null && posterUrl.isNotEmpty) {
      return ActivityAssets.fromExternalLink(
        posterUrl,
        text: largeText ?? 'Nivio',
      );
    }
    // When no poster URL, Discord will use the app's default art asset
    // configured in the Developer Portal (if any).
    return null;
  }

  /// Handle an unexpected disconnect — mark as disconnected and attempt
  /// a background reconnect after a delay.
  void _handleDisconnect() {
    _connected = false;
    _client = null;

    if (!_disposed && _clientId != null) {
      Future.delayed(const Duration(seconds: 5), () {
        if (!_disposed && _clientId != null) {
          debugPrint('[DiscordRPC] Attempting reconnect...');
          initialize(_clientId!);
        }
      });
    }
  }
}
