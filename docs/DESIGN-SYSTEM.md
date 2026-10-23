# Cinespice: Cinema design system

## Direction

An artwork-led personal cinema, with familiar iOS controls and a quiet visual
hierarchy. Preserve the existing Telegram library and playback behavior. This is
an Apple-inspired implementation, not an Apple product or a claim of visual parity.

## References inspected

- [Apple: Color](https://developer.apple.com/design/human-interface-guidelines/color):
  semantic foreground colors, consistent action colors, light/dark accessibility.
- [Apple: Typography](https://developer.apple.com/design/human-interface-guidelines/typography):
  readable system text styles, Dynamic Type and restrained font weights.
- [Apple: Materials](https://developer.apple.com/design/human-interface-guidelines/materials):
  reserve Liquid Glass for navigation and controls; use solid content surfaces.
- [Apple: Motion](https://developer.apple.com/design/human-interface-guidelines/motion):
  purposeful feedback, continuity and respect for Reduce Motion.
- [Apple: Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars):
  few clearly labeled destinations, consistent symbols and visible navigation.
- [Apple: Custom Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views):
  the existing availability-guarded native glass dock and its older-system fallback.

## Visual rules

| Element | Treatment |
| --- | --- |
| Default palette | Cinema: background `#08090B`, surface `#1C1C1E`, accent `#F5F5F7` |
| Foregrounds | UIKit semantic label, secondary label and separator colors |
| Existing preferences | Ember, Midnight, Pearl and Sage remain available; saved choices remain valid |
| Text | System large title, headline, body, subheadline and caption styles |
| Spacing | 20–24 pt screen gutters, 16 pt card gaps, 32 pt Home section gaps |
| Content shapes | 14 pt poster corners; 18–24 pt grouped surfaces; 30 pt login mark |
| Primary video action | 34 pt round Play graphic inside a 44 pt minimum touch target |
| Glass | Floating four-destination dock; content cards remain solid |
| Motion | Short damped press feedback and dock selection; no autoplaying carousel |
| Accessibility | Reduce Motion, Reduce Transparency, semantic foregrounds, scalable poster widths and larger hero at accessibility text sizes |

## Screen composition

- **Home:** recently added/daily/search hero positions, existing reserved catalogue
  positions, Continue Watching, then one horizontal portrait row per channel.
  Rows keep the 15-title cap and collection arrow; launch variation stays intact.
- **Library:** New Releases first, with Favorites, Watchlist and History. Release
  order remains based on filename-year hints until catalogue metadata is connected.
- **Search:** one solid, readable search field, concise guidance and poster results.
- **Downloads:** compact rows with portrait artwork, file size, real download state,
  round Play and Info controls. Shared context menus retain all file actions.
- **Details:** poster/title introduction, grouped file information and caption.
- **Login:** consistent cinema mark, large title, 56 pt input surfaces and full-width
  Continue control. Existing phone, code, password, email, resend and restart flows.
- **Channels and account:** grouped surfaces, concise explanations, readable rows,
  familiar native pickers and destructive-action confirmations.
- **Player:** black video surface, neutral white controls, circular transport and
  compact charcoal option panels. All track, timing, orientation and close actions
  retain their handlers. Press feedback still informs the control-hide timer.

## Implementation boundaries

The existing four-tab and seven-slot hero contracts remain. Player chrome changes
from orange to neutral white; the option panel replaces its orange border with a
subtle neutral separator. A new default palette is introduced without rewriting
saved preferences. No networking, matching, storage or playback-engine changes.

Swift syntax parsing does not establish SDK compilation or native appearance.
The required native build remains the existing GitHub Actions iOS workflow.
