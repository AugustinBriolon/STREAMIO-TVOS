import Testing
@testable import StremioTV

/// Track names taken from real files returned by the user's addon (ffprobe titles).
struct TrackSelectorTests {
    let remuxAudio = [
        MediaTrack(id: -1, name: "Disable"),
        MediaTrack(id: 1, name: "DTS-HD Master Audio 5.1 - Français (VFF) @ 3584 kb/s - [French]"),
        MediaTrack(id: 2, name: "AC3 / Dolby Digital 5.1 - Français (VFQ) @ 640 kb/s - [French]"),
        MediaTrack(id: 3, name: "TrueHD Atmos 7.1 - Anglais (VO) @ 3462 kb/s - [English]"),
        MediaTrack(id: 4, name: "EAC3 / Dolby Digital Plus Atmos - Anglais (VO) @ 768 kbps - [English]"),
        MediaTrack(id: 5, name: "DTS 2.0 - Français (VFF Audio Description) @ 768 kb/s - [French]"),
        MediaTrack(id: 6, name: "DTS 2.0 - Anglais (Commentaire Réalisateur) @ 255 kb/s - [English]"),
    ]

    let remuxSubtitles = [
        MediaTrack(id: -1, name: "Disable"),
        MediaTrack(id: 10, name: "PGS Français (VFF) [Forced] - [French]"),
        MediaTrack(id: 11, name: "PGS Français (VFF) [Full] - [French]"),
        MediaTrack(id: 12, name: "SRT Français (VFF) [Forced] - [French]"),
        MediaTrack(id: 13, name: "SRT Français (VFF) [Full] - [French]"),
        MediaTrack(id: 14, name: "SRT Français (VFF) [SDH] - [French]"),
        MediaTrack(id: 15, name: "SRT Anglais [Full] - [English]"),
        MediaTrack(id: 16, name: "SRT Français (VFF) [Commentaire Réalisateur] - [French]"),
    ]

    @Test func picksFrenchMainAudioAndNeverDescriptionOrCommentary() {
        let audio = TrackSelector.preferredAudio(remuxAudio)
        #expect(audio?.id == 1)
    }

    @Test func frenchAudioGetsOnlyForcedTextSubtitles() {
        let audio = TrackSelector.preferredAudio(remuxAudio)
        #expect(TrackSelector.preferredSubtitle(remuxSubtitles, audio: audio)?.id == 12)
    }

    @Test func originalAudioGetsFullFrenchTextSubtitles() {
        let english = [MediaTrack(id: 1, name: "E-AC3 5.1 - [English]")]
        let subtitles = [
            MediaTrack(id: 2, name: "English - [English]"),
            MediaTrack(id: 3, name: "English SDH - [English]"),
            MediaTrack(id: 4, name: "French Canadian - [French]"),
            MediaTrack(id: 5, name: "French European - [French]"),
        ]
        let audio = TrackSelector.preferredAudio(english)
        #expect(audio?.id == 1)
        #expect(TrackSelector.preferredSubtitle(subtitles, audio: audio)?.id == 5)
    }

    @Test func noMatchingSubtitleMeansOff() {
        let audio = MediaTrack(id: 1, name: "English - [English]")
        #expect(TrackSelector.preferredSubtitle([MediaTrack(id: 2, name: "Deutsch - [German]")], audio: audio) == nil)
        #expect(TrackSelector.preferredSubtitle([], audio: audio) == nil)
    }

    @Test func prefersDolbyOverDTSAtSameLanguage() {
        let tracks = [MediaTrack(id: 1, name: "DTS 5.1 - [French]"), MediaTrack(id: 2, name: "AC3 5.1 - [French]")]
        #expect(TrackSelector.preferredAudio(tracks)?.id == 2)
    }

    @Test func subtitleModeOffAlwaysReturnsNil() {
        let audio = TrackSelector.preferredAudio(remuxAudio)
        let sub = TrackSelector.preferredSubtitle(remuxSubtitles, audio: audio, mode: .off, language: "fr", audioLanguage: "fr")
        #expect(sub == nil)
    }

    @Test func subtitleModeAlwaysOnPicksFullEvenWithMatchingAudio() {
        let audio = TrackSelector.preferredAudio(remuxAudio)
        let sub = TrackSelector.preferredSubtitle(remuxSubtitles, audio: audio, mode: .alwaysOn, language: "fr", audioLanguage: "fr")
        // Should select full French subtitle (id: 13, SRT VFF Full), NOT forced (id: 12)
        #expect(sub?.id == 13)
    }

    @Test func picksEnglishAudioWhenRequested() {
        let audio = TrackSelector.preferredAudio(remuxAudio, language: "en")
        // Tracks 3 and 4 are English; 4 is EAC3 Dolby which gets +20 over TrueHD track 3
        #expect(audio?.id == 4)
    }
}

/// Names taken from real files returned by the user's addon.
struct TrackDisplayTests {
    @Test(arguments: [
        ("DTS-HD Master Audio 5.1 - Français (VFF) @ 3584 kb/s - [French]", "DTS-HD Master Audio 5.1 - Français (VFF)"),
        ("EAC3 / Dolby Digital Plus Atmos - Anglais (VO) @ 768 kbps - [English]", "EAC3 / Dolby Digital Plus Atmos - Anglais (VO)"),
        ("TrueHD Atmos 7.1 - Anglais (VO) @ 3462 kb/s - [English]", "TrueHD Atmos 7.1 - Anglais (VO)"),
        ("PGS Français (VFF) [Forced] - [French]", "PGS Français (VFF) [Forced]"),
        ("SRT Anglais [SDH] - [English]", "SRT Anglais [SDH]"),
        ("English", "English"),
        ("Track 1 - [French]", "Français · Piste 1"),
        ("Track 4 - [French]", "Français · Piste 4"),
        ("European - [Spanish]", "Espagnol (Européen)"),
        ("Forced - [French]", "Français (Forcés)"),
        ("Track 4", "Piste 4"),
        ("European", "Européen"),
    ])
    func formatsTrackNamesWithoutLosingLanguage(raw: String, expected: String) {
        #expect(TrackDisplay.title(raw) == expected)
    }

    @Test func neverReturnsAnEmptyTitle() {
        #expect(TrackDisplay.title(" - [French]") == "Français")
        #expect(!TrackDisplay.title("   ").isEmpty)
    }
}
