import CoreAudio
import Dispatch

func property<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T {
    var addr = address(selector)
    var value = initial, size = UInt32(MemoryLayout<T>.size)
    _ = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0) }
    return value
}

func objectList(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
    var addr = address(selector)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size)
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &ids)
    return ids
}

/// Runs `block` on `queue` whenever the property changes. Core Audio drops the listener when the object goes away.
func listen(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, on queue: DispatchQueue, _ block: @escaping () -> Void) {
    var addr = address(selector)
    AudioObjectAddPropertyListenerBlock(id, &addr, queue) { _, _ in block() }
}

private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
}
