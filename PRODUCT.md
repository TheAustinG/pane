# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## tvOS First

Impeccable has no tvOS platform value, so `ios` stands in. Pane is a tvOS app for Apple TV 4K. Every iOS rule that assumes touch is replaced by the tvOS rule below.

- **10-foot viewing.** The screen is a 65 to 74 inch TV in the living room, read from the couch. The couch distance is not recorded yet.
- **Siri Remote only.** Input is swipes and clicks on the clickpad, plus the Back (Menu), TV, and Play/Pause buttons. There is no touch on the screen, no pointer, and no hover.
- **Focus engine.** Every control is reached by moving focus. The focused item must be obvious at a glance from the couch, and the next focus target must be predictable from the layout. Focus moves to the geometrically nearest control, so stacked actions and focus sections beat wide rows.
- **Rules that do not apply:** 44 pt touch targets, edge-swipe back, notch and Dynamic Island safe areas, and iPhone tab bar conventions. Back is the remote's Back button. Safe-area insets and sizes come from the current Apple tvOS HIG, checked at design time.
- **Text entry.** Standard text fields only, so the iPhone keyboard notification can fill them.
- **Verification.** tvOS Simulator screenshots show layout and focus. Only the real TV shows legibility and motion smoothness from the couch; those checks are batched into an optional device pass and never block a gate.

## Users

One person: the owner, who built Pane for personal use. Nobody else in the room relies on it, and no card needs a guest or privacy mode.

The owner's day with Pane:
- Pane is left open on the living room TV for hours as an ambient display and read in glances: the time, the sky, whether rain is coming, whether the house is in order.
- Most days the owner picks up the remote to press a Home Assistant scene button (Goodnight and similar), so the Home card is a real control surface, not only a readout.
- Radar on demand and Settings are occasional. To watch TV the owner switches to another app.

## Product Purpose

Pane is a calm, always-on dashboard for the living room Apple TV. It shows the time and date, current weather with the next 6 hours, 5 days and the sunrise-to-sunset arc, a Home Assistant card, and a GitHub card. The background follows the real sky. When a storm is coming, radar takes over the screen. It is sideloaded and never distributed.

Success means:
- One glance from the couch answers "what time is it, what is it like outside, is rain coming, is the house in order".
- The screen stays on for hours with no screensaver and no hitches in its motion.
- A storm is impossible to miss, and the screen returns to calm on its own when it passes.
- Nudges appear only when something needs the owner (dry air, an unlocked door late at night, an image built but not redeployed) and clear themselves when the condition clears.

## Positioning

Pane replaces glancing at a phone for weather, home and code status.

Its mechanism:
- One weather scene model (condition, sun altitude, time of day) drives the whole background, so the room's biggest screen reads as a window onto the actual sky.
- Storm mode is triggered by real alerts and minute-by-minute precipitation, not a schedule.
- Home Assistant and GitHub state live beside the weather on one ambient screen, built for the 10-foot view and the Siri Remote.

## Operating Context

- **Hardware.** "Living Room AppleTV", an Apple TV 4K (3rd generation, A15) on tvOS 27, on Wi-Fi, connected to the 65 to 74 inch living room TV. The TV is not OLED, so burn-in is not a concern.
- **Always on.** Pane disables the idle timer. The Apple TV's sleep setting and the TV's own power saving belong to the owner.
- **Services.** WeatherKit (paid developer program), IEM NEXRAD radar tiles with RainViewer as fallback, Home Assistant over WebSocket on the LAN, the GitHub API with a fine-grained token, and Portainer on the LAN for container revisions. Everything runs inside the app; there is no server.
- **Location.** The Apple TV has no GPS. The home location is set once in Settings and stored as coordinates.
- **Setup.** URLs and tokens are entered once on setup screens with the iPhone keyboard and stored in the Keychain.
- **Building.** Each build phase ends at a gate verified in the tvOS Simulator; checks that need the real TV are batched into an optional device pass.

## Capabilities and Constraints

**Planned features**
- Clock and date.
- Weather: current conditions, next 6 hours, 5 days, sunrise-to-sunset arc.
- Storm mode: radar takes over when an alert fires or rain is due within the hour, with hysteresis so it does not flap. Radar can also be opened on demand from the weather card; Back returns.
- Home Assistant card: inside temperature, humidity (thermostat plus a separate sensor), front door lock, lights on, who is home, scene buttons, and nudges. Each nudge can be turned off.
- GitHub card: contribution grid with streak and today count, latest commit line, and a nudge when a container image was built but not redeployed.
- Backgrounds: an animated mesh gradient first; pre-blurred photos later, chosen as Gradient, Photo or Auto.
- Night dim, on a schedule and manually. The Goodnight scene also starts it.
- Settings: location, background mode, night schedule, service setup, nudge toggles, attribution and credits.

**Out of scope for now:** calendar, music, photo blur control and choosing your own photo, the doorbell, and burn-in protection.

**Constraints that shape design**
- **Render budget.** Liquid Glass, an animated mesh gradient and particles together may drop frames on the A15 at 4K. Every render feature sits behind a quality knob (particle count, gradient resolution, glass panel count). Smooth motion beats richer effects.
- **No slider on tvOS.** Any adjustable value is a set of preset steps.
- **Links become QR codes.** The Apple Weather legal page and weather alert details are shown as QR codes, since the TV has no browser.
- **Weather attribution.** The Apple Weather mark is always on screen with weather data. Alert text is shown unaltered.
- **Stale and missing data.** Weather can be stale, Home Assistant can disconnect, and a token can expire. Each state shows on screen; Pane never shows a silent blank card.

**Terminology:** dashboard, card, scene (weather scene), storm mode, radar, nudge, night dim, Home card, GitHub card, scene button (Home Assistant scene).

**Undecided:** the couch distance.

## Brand Commitments

- **Name:** Pane, for the window pane you check the sky through and the dashboard's glass panes.
- **Approved comp:** the mockup canvas "Apple TV Dashboard Mockups" (board A: animated gradient, board B: blurred photo), approved 2026-11-01. It fixes the layout: a large clock and date top left, the current weather card top right, and a bottom row of the forecast, Home and GitHub cards, all as glass panels over the scene background.
- **Voice in the comp:** short, plain, sentence-case lines ("Rain likely after 9 PM", "Dry air", "image built 3h ago, not redeployed").
- **Not yet defined:** the app icon. It is produced in Phase 1 step 1A.

## Evidence on Hand

- The approved mockups are the only design reference. Real entity names, hosts, coordinates and API responses live only at runtime and in the gitignored `local/` folder; committed fixtures, previews and screenshots use synthetic values.
- Phase 0 measurements (render, WeatherKit datasets, radar tiles, network latency) were recorded outside the repo.

## Product Principles

1. **Calm by default.** The resting screen is quiet: one clock, one sky, a few cards. Nothing moves faster than weather does, except a storm.
2. **Readable from the couch.** Every number and word reads on a 65 to 74 inch TV at a glance, and the focused control is obvious.
3. **Speak only when it matters.** Nudges and storm mode interrupt only for something the owner would act on, and leave on their own.
4. **Honest states.** Stale weather, a lost connection and an expired token each look different from fresh data.
5. **Smooth over showy.** If an effect costs frames on the A15, the effect loses.
