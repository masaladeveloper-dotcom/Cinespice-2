# VLC player inspection and Cinespice controls

Inspected VLC-iOS revision `749cf8be5f3abe0a044f1680a471999d714eb9e3`
and the pinned VLCKit 3.7.4 revision
`54bba6d95502d0f3f7a9da581727935b21d55fb2`.

VLC-iOS application code is GPLv2-or-later/MPLv2; VLCKit is a separate dependency.
This implementation uses original SwiftUI controls and VLCKit rather than copying
VLC's full app, assets, media library or service stack. It is not an embedded copy
of every VLC application feature.

## UI and option map

| VLC iOS area | Cinespice implementation / status |
| --- | --- |
| Top navigation: close, filename, rotate, queue, PiP, renderer | Explicit close action, filename, manual rotation; queue/PiP/renderers deferred |
| Orange timeline, elapsed/remaining time | Implemented with seeking when VLC reports seekable |
| Play/pause and skip controls | Bottom transport with ±10 seconds; double taps also seek |
| Audio/subtitle track card | Separate Audio and Subtitles tabs, track selection/off, local external files and delay |
| Subtitle settings | Five persistent relative sizes, applied to VLC's text renderer |
| Aspect control and orientation lock | Fit/Fill, 16:9/4:3/21:9, optional screen edges; explicit portrait/landscape lock |
| Speed controls | 0.25× through 4× presets |
| More and interface lock | Custom bottom options panel and lock/unlock; speed/tracks/size/picture/download shortcuts |
| Sleep timer, chapters, bookmarks, A–B repeat | Planned, not implemented |
| Equalizer and video filters | Planned, not implemented |
| Repeat/shuffle/previous/next queue | Planned with an intentional queue, not exposed for the single-video flow |
| Brightness/volume gestures, long-press speed | Not implemented; use device volume controls for now |
| Online subtitles, dual subtitles, PiP/casting | Not implemented or verified against this dependency |

The layout follows VLC's navigation/timeline/bottom transport/track card model,
with Cinespice's ember accent and Telegram download actions. Portrait stacks the
transport and shortcuts; landscape places track/rotate and picture/more beside
transport. Menus have a height bound based on available safe-area geometry and
scroll rather than extending below compact landscape screens.

## Sources inspected

Under `Sources/Playback/Player/VideoPlayer-iOS/`:

- `VideoPlayerViewController.swift`, `VideoPlayerViewController+ControlsDelegate.swift`,
  `VideoPlayerControls.swift` and its XIB: navigation, transport, gestures, rotation,
  aspect handling, notch constraints and closing.
- `TrackSelector/TrackSelectorView.swift`: separate audio/subtitle tabs, Off,
  external files, subtitle lookup and synchronization.
- `MediaMoreOptionsActionSheet.swift` and `Subviews/MediaPlayerActionSheet.swift`:
  option inventory, conditionally exposed chapters and child cards.
- `Subviews/MediaNavigationBar.swift`, `OptionsNavigationBar.swift`,
  `PlaybackSpeedControlsView.swift`, `PlaybackDelayView.swift`,
  `SleepTimerControlsView.swift`, `VideoFiltersControlsView.swift`, `EqualizerView.swift`.

Also inspected `Sources/Playback/Control/VLCPlaybackService.m`,
`Sources/Settings/Model/SettingsSection.swift` and
`Resources/iOS/Settings.bundle/Root.plist`.

## Subtitle size compatibility

VLC iOS defines relative renderer sizes 20/18/16/12/6, labelled
Smallest/Small/Normal/Large/Largest. These are divisors, not point sizes.
Cinespice saves the choice in local preferences and applies it once playback
starts, when the user changes size, and after a subtitle track change.

VLCKit 3.7.4 implements `setTextRendererFontSize:` in `Sources/VLCMediaPlayer.m`,
and VLC iOS calls that selector from its playback service. It is **not declared
in the public VLCKit header**. Cinespice uses the same guarded runtime selector:
if a future framework removes it, the app shows an unsupported-setting message.
No Apple private API is involved. No framework fork or dependency was added.
Actual rendering still requires a device check. Bitmap subtitles and some styled
ASS/SSA subtitles can retain their authored size regardless of this preference.

## Close and opening behavior

The down arrow calls a closure which clears the library's actual full-screen
selection binding. The video surface does not consume touch events. The local
range server is stopped before VLC teardown, and teardown remains idempotent.
On leaving the view, portrait and the idle timer are restored. The video surface
is attached once instead of reassigning `drawable` on every SwiftUI update.
Pinned VLCKit's `setDrawable:` synchronously dispatches to its background queue;
removing repeated assignments avoids that unnecessary main-thread wait while
progress and track state updates redraw the controls.

A play tap immediately shows a blocking, cancellable Loading media card. Duplicate
taps cannot initiate another player. Cancel invalidates the opening token; an old
request completing late cannot open a video. After presentation, Opening media
remains visible until VLC reports playing or an error/end. Genuine later stalls
retain the existing progress-based buffering indicator.

TDLib revision `c15d3f5a5de6e3ba5839822c451152e5e18bb700`,
`VideosManager::get_video_object` and `DocumentsManager::get_document_object`,
construct their File objects through the current FileManager. `getMessage`
therefore already returns that file state, so preparation
no longer performs a serial `getFile`. Playback starts before the metadata save /
whole-library snapshot refresh. The save still runs and reports failures. Deleted
messages remain errors; old saved paths are never trusted without a current message.
Download/export callers retain their default persistence behavior.

These changes remove known work from the critical path. No measured startup time,
rendering, touch, close or throughput improvement is claimed until the signed app
is exercised on an iPhone/iPad.

## October UI redesign

The options panel now uses a compact dark surface, capped width and internal
scrolling; landscape anchors it at the trailing bottom edge. No full-screen dim
layer or engine/service branding. All existing controls remain. See
[the UI dimensions and device gates](UI-README.md#player). Native layout/touch
verification remains outstanding for this patch.
