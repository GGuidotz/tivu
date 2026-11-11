// Da dove esce l'audio del Mac: se l'uscita scelta è HDMI (o DisplayPort, cioè un adattatore verso HDMI), il suono va
// alla TV e i tasti volume della tastiera, che su HDMI macOS disattiva, possono comandare lei.
// Nessuna lettura continua: macOS avvisa quando l'uscita cambia.

import CoreAudio
import Foundation

@MainActor
final class AudioOutput: ObservableObject {
    @Published private(set) var isHDMI = false

    init() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
        else { isHDMI = false; return }
        var transport = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr
        else { isHDMI = false; return }
        let hdmi = transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort
        if hdmi != isHDMI { isHDMI = hdmi }
    }
}
