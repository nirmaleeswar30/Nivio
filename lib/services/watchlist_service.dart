import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../models/watchlist_item.dart';
import 'auth_service.dart';

/// Service for managing user's watchlist
class WatchlistService {
  final AuthService _authService;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _boxName = 'watchlist';

  WatchlistService(this._authService);

  /// Get watchlist box
  Box<WatchlistItem> get _box => Hive.box<WatchlistItem>(_boxName);

  /// Initialize watchlist box
  static Future<void> init() async {
    await Hive.openBox<WatchlistItem>(_boxName);
  }

  /// Check if item is in watchlist
  bool isInWatchlist(int mediaId) {
    return _box.containsKey(mediaId);
  }

  /// Get all watchlist items
  List<WatchlistItem> getAllItems() {
    return _box.values.toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt)); // Most recent first
  }

  /// Add item to watchlist
  Future<void> addToWatchlist(WatchlistItem item) async {
    try {
      print('📝 Adding to watchlist: ${item.title}');
      
      // Save locally
      await _box.put(item.id, item);
      
      // Sync to cloud if user is signed in
      if (_authService.isSignedIn) {
        await _syncToCloud(item);
      }
      
      print('✅ Added to watchlist successfully');
    } catch (e) {
      print('❌ Error adding to watchlist: $e');
      rethrow;
    }
  }

  /// Remove item from watchlist
  Future<void> removeFromWatchlist(int mediaId) async {
    try {
      print('🗑️ Removing from watchlist: $mediaId');
      
      // Remove locally
      await _box.delete(mediaId);
      
      // Remove from cloud if user is signed in
      if (_authService.isSignedIn) {
        await _removeFromCloud(mediaId);
      }
      
      print('✅ Removed from watchlist successfully');
    } catch (e) {
      print('❌ Error removing from watchlist: $e');
      rethrow;
    }
  }

  /// Toggle watchlist status
  Future<void> toggleWatchlist(WatchlistItem item) async {
    if (isInWatchlist(item.id)) {
      await removeFromWatchlist(item.id);
    } else {
      await addToWatchlist(item);
    }
  }

  /// Sync item to cloud (Firestore)
  Future<void> _syncToCloud(WatchlistItem item) async {
    try {
      // Check if user is anonymous (guest mode)
      final user = _authService.currentUser;
      if (user?.isAnonymous == true) {
        // Skip cloud sync for anonymous users
        return;
      }

      final uid = _authService.uid;
      if (uid == null) return;

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('watchlist')
          .doc(item.id.toString())
          .set(item.toJson());
      
      print('☁️ Synced to cloud: ${item.title}');
    } catch (e) {
      print('❌ Error syncing to cloud: $e');
      // Don't rethrow - local save succeeded
    }
  }

  /// Remove item from cloud
  Future<void> _removeFromCloud(int mediaId) async {
    try {
      // Check if user is anonymous (guest mode)
      final user = _authService.currentUser;
      if (user?.isAnonymous == true) {
        // Skip cloud sync for anonymous users
        return;
      }

      final uid = _authService.uid;
      if (uid == null) return;

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('watchlist')
          .doc(mediaId.toString())
          .delete();
      
      print('☁️ Removed from cloud: $mediaId');
    } catch (e) {
      print('❌ Error removing from cloud: $e');
      // Don't rethrow - local delete succeeded
    }
  }

  /// Sync all local items to cloud
  Future<void> syncAllToCloud() async {
    if (!_authService.isSignedIn) {
      print('⚠️ Cannot sync: User not signed in');
      return;
    }

    // Check if user is anonymous (guest mode)
    final user = _authService.currentUser;
    if (user?.isAnonymous == true) {
      print('⚠️ Cannot sync: Guest mode (anonymous user)');
      return;
    }

    print('🔄 Syncing all items to cloud...');
    
    final items = getAllItems();
    for (final item in items) {
      await _syncToCloud(item);
    }
    
    print('✅ Sync complete: ${items.length} items');
  }

  /// Download watchlist from cloud and merge with local
  Future<void> downloadFromCloud() async {
    if (!_authService.isSignedIn) {
      print('⚠️ Cannot download: User not signed in');
      return;
    }

    // Check if user is anonymous (guest mode)
    final user = _authService.currentUser;
    if (user?.isAnonymous == true) {
      print('⚠️ Cannot download: Guest mode (anonymous user)');
      return;
    }

    try {
      print('⬇️ Downloading watchlist from cloud...');
      
      final uid = _authService.uid;
      if (uid == null) return;

      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('watchlist')
          .get();

      int merged = 0;
      for (final doc in snapshot.docs) {
        final item = WatchlistItem.fromJson(doc.data());
        if (!isInWatchlist(item.id)) {
          await _box.put(item.id, item);
          merged++;
        }
      }
      
      print('✅ Download complete: $merged items merged');
    } catch (e) {
      print('❌ Failed to pull from cloud: $e');
    }
  }

  /// Clear all watchlist items (local only)
  Future<void> clearAll() async {
    await _box.clear();
    print('🗑️ Watchlist cleared');
  }

  /// Get watchlist count
  int get count => _box.length;
}
