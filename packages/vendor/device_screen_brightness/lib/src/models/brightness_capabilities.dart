import '../brightness_mode.dart';

/// Runtime feature set reported by the active brightness backend.
final class BrightnessCapabilities {
  BrightnessCapabilities({
    required this.canRead,
    required this.canWrite,
    required this.canObserve,
    required this.writeSupport,
    required Set<BrightnessMode> supportedModes,
    required this.requiresWriteSettingsPermission,
    required this.backend,
  }) : supportedModes = Set.unmodifiable(supportedModes);

  final bool canRead;
  final bool canWrite;
  final bool canObserve;
  final BrightnessWriteSupport writeSupport;
  final Set<BrightnessMode> supportedModes;
  final bool requiresWriteSettingsPermission;
  final String backend;

  factory BrightnessCapabilities.fromPlatform(Map<Object?, Object?> map) {
    final modes = <BrightnessMode>{};
    final rawModes = map['supportedModes'];
    if (rawModes is List) {
      for (final rawMode in rawModes) {
        for (final mode in BrightnessMode.values) {
          if (mode.name == rawMode?.toString()) modes.add(mode);
        }
      }
    }
    return BrightnessCapabilities(
      canRead: map['canRead'] == true,
      canWrite: map['canWrite'] == true,
      canObserve: map['canObserve'] == true,
      writeSupport: BrightnessWriteSupport.values.firstWhere(
        (support) => support.name == map['writeSupport']?.toString(),
        orElse: () => BrightnessWriteSupport.unsupported,
      ),
      supportedModes: modes,
      requiresWriteSettingsPermission:
          map['requiresWriteSettingsPermission'] == true,
      backend: map['backend']?.toString() ?? 'unknown',
    );
  }
}

/// Reliability of brightness writes reported by the native backend.
enum BrightnessWriteSupport {
  /// Writes are implemented and verifiable on the current backend.
  supported,

  /// The platform exposes an API, but hardware or OS policy may reject writes.
  bestEffort,

  /// No writable brightness backend is currently available.
  unsupported,
}
