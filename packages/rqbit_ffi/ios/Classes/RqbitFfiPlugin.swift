// rqbit_ffi is an FFI plugin: all calls go through dart:ffi into the vendored
// rqbit_ffi.framework. This empty class only satisfies CocoaPods/Flutter,
// which expect at least one source file in a plugin pod.
import Foundation

public final class RqbitFfiPlugin: NSObject {}
