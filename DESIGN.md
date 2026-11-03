---
name: Pane
description: A calm tvOS dashboard that turns the living room TV into a window onto the actual sky, with Liquid Glass panes floating over it.
colors:
  ink: "#FFFFFF"
  ink-secondary: "rgba(255, 255, 255, 0.80)"
  ink-tertiary: "rgba(255, 255, 255, 0.72)"
  rule: "rgba(255, 255, 255, 0.20)"
  well: "rgba(255, 255, 255, 0.14)"
  faint: "rgba(255, 255, 255, 0.10)"
  glass-shade: "#0E1024"
  focus-sheen: "rgba(255, 255, 255, 0.16)"
  focus-rim: "rgba(255, 255, 255, 0.75)"
  rain-chance: "#A9DBFF"
  sun: "#FFE6AA"
  nudge-amber: "#FFD27F"
  nudge-ink: "#FFE2A8"
  nudge-fill: "rgba(255, 190, 90, 0.18)"
  nudge-stroke: "rgba(255, 205, 120, 0.40)"
  warning: "#FFA898"
  warning-fill: "rgba(255, 90, 70, 0.24)"
  warning-stroke: "rgba(255, 140, 120, 0.55)"
  sky-night-top: "#050816"
  sky-night-glow: "#3B356A"
  sky-golden-top: "#1E2148"
  sky-golden-glow: "#EFA06A"
  sky-day-top: "#123F75"
  sky-day-glow: "#E4D3A0"
  sky-rain-top: "#1C232D"
  sky-rain-glow: "#6E8094"
typography:
  clock:
    fontFamily: "SF Pro (tvOS system font)"
    fontSize: "300pt"
    fontWeight: 200
    letterSpacing: "-8pt"
  meridiem:
    fontFamily: "SF Pro (tvOS system font)"
    fontSize: "64pt"
    fontWeight: 300
  hero-temperature:
    fontFamily: "SF Pro (tvOS system font)"
    fontSize: "132pt"
    fontWeight: 200
    letterSpacing: "-4pt"
  date:
    fontFamily: "SF Pro (tvOS system font)"
    fontSize: "52pt"
    fontWeight: 400
  screen-title:
    fontFamily: "SF Pro (tvOS system font)"
    fontSize: "52pt"
    fontWeight: 600
  title:
    fontFamily: "SF Pro (tvOS system font)"
    fontSize: "40pt"
    fontWeight: 500
  headline:
    fontFamily: "SF Pro (tvOS system font)"
    fontSize: "36pt"
    fontWeight: 600
  metric:
    fontFamily: "SF Pro (tvOS system font)"
    fontSize: "32pt"
    fontWeight: 500
    fontFeature: "tnum"
  body:
    fontFamily: "SF Pro (tvOS system font)"
    fontSize: "30pt"
    fontWeight: 400
  body-strong:
    fontFamily: "SF Pro (tvOS system font)"
    fontSize: "30pt"
    fontWeight: 500
  callout:
    fontFamily: "SF Pro (tvOS system font)"
    fontSize: "28pt"
    fontWeight: 400
  subhead:
    fontFamily: "SF Pro (tvOS system font)"
    fontSize: "26pt"
    fontWeight: 400
  caption:
    fontFamily: "SF Pro (tvOS system font)"
    fontSize: "24pt"
    fontWeight: 400
  label:
    fontFamily: "SF Pro (tvOS system font)"
    fontSize: "24pt"
    fontWeight: 600
    letterSpacing: "1.9pt"
rounded:
  pane: "40pt"
  alert: "28pt"
  chip: "20pt"
  swatch: "14pt"
spacing:
  xxs: "6pt"
  xs: "10pt"
  s: "14pt"
  m: "18pt"
  l: "28pt"
  xl: "32pt"
  xxl: "40pt"
  margin-vertical: "72pt"
  margin-horizontal: "96pt"
  gutter: "32pt"
components:
  glass-pane:
    backgroundColor: "{colors.glass-shade}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pane}"
    padding: "30pt 40pt"
  glass-pane-focused:
    backgroundColor: "{colors.focus-sheen}"
    textColor: "{colors.ink}"
    rounded: "{rounded.pane}"
  pane-heading:
    textColor: "{colors.ink-tertiary}"
    typography: "{typography.label}"
  status-row-well:
    backgroundColor: "{colors.well}"
    size: "52pt"
  nudge-chip:
    backgroundColor: "{colors.nudge-fill}"
    textColor: "{colors.nudge-ink}"
    typography: "{typography.label}"
    rounded: "{rounded.chip}"
    padding: "8pt 16pt"
  warning-chip:
    backgroundColor: "{colors.warning-fill}"
    textColor: "{colors.warning}"
    typography: "{typography.label}"
    rounded: "{rounded.chip}"
    padding: "8pt 16pt"
  alert-banner:
    backgroundColor: "{colors.warning-fill}"
    textColor: "{colors.ink}"
    typography: "{typography.title}"
    rounded: "{rounded.alert}"
    padding: "28pt"
  precip-chance:
    textColor: "{colors.rain-chance}"
    typography: "{typography.caption}"
---

# Design System: Pane

## Overview

**Creative North Star: "The Window Pane"**

The biggest screen in the room becomes a window onto the actual sky. A mesh-gradient sky fills the frame, its colors set by the real condition and the sun's altitude, and a few Liquid Glass panes float over it with the time, the forecast, the house and the code. Everything is read in a glance from the couch, so the system spends its ambition on the sky and on legibility, never on chrome.

The resting screen is calm: one huge thin clock, one sky, four panes. Motion is slow and continuous, the sky drifting on 34 to 53 second cycles and blending between scenes over about 90 seconds, so nothing moves faster than weather does. The only fast moments are earned: focus lifting a pane when the remote is picked up, a storm swapping the dashboard for radar, a rare flash of lightning.

The panes use the platform's own Liquid Glass and native tvOS controls. Brand lives in the sky, the thin display numerals, the 40 pt continuous corners and the restraint of the signal colors. The approved mockup (board A, animated gradient) is the composition reference.

**Key Characteristics:**
- The sky is the color; panes are glass and ink.
- White ink at three opacities carries all text.
- Each signal color has exactly one job.
- SF Pro Thin only at hero scale, Regular to Semibold everywhere else.
- Native tvOS focus, lists, fields and glass buttons; custom only where the platform has no equivalent.

## Colors

Pane has no brand accent. The sky supplies the color of every screen; the interface itself is white ink on glass, plus four signal colors that each mean one thing.

### Primary
- **The Sky** (scene anchors such as Night Top, Golden Glow, Day Top, Rain Glow): five colors per scene feed the mesh gradient. Anchors are set by sun altitude (night below -12°, blue hour near -4°, golden hour from 0° to 8°, day above 25°) and condition overlays (cloudy, rain, storm, snow, fog) mix over them. The full anchor and overlay table, with each scene's accent and glass shade, lives in `.impeccable/design.json` under `extensions.scenes`.
- **Scene Accent** (per scene, from the same table): tints the contribution grid, so the code pane quietly takes the sky's color.

### Secondary
- **Rain Chance Blue** (#A9DBFF): precipitation probability, nothing else.
- **Sunlight** (#FFE6AA): the sun dot on the daylight arc and its glow.
- **Nudge Amber** (#FFD27F, ink #FFE2A8): nudges only (dry air, a door unlocked late, an image built but not redeployed), always inside a nudge chip.
- **Warning Coral** (#FFA898 on a coral fill): weather warnings and broken connections.

### Neutral
- **Ink** (#FFFFFF): primary text and glyphs.
- **Ink 80%**: secondary lines (hi and lo, details under a status row, captions).
- **Ink 72%**: pane headings and low temperatures.
- **Rule 20%**: dividers inside panes.
- **Well 14%**: the circle behind a status row icon.
- **Faint 10%**: empty contribution cells and placeholders.
- **Glass Shade** (#0E1024): mixed into Liquid Glass as a tint, at 10% on a night sky up to 36% on snow.

### Named Rules
**The Sky Is the Color Rule.** Large fields of color come only from the scene. No pane, button or heading carries a brand color of its own.

**The One Job Rule.** Rain blue means rain chance, amber means a nudge, coral means a warning, sunlight means the sun. A color never appears for decoration or a second meaning.

**The Shade Follows the Sun Rule.** The brighter the sky, the more Glass Shade goes into every pane, so white ink keeps its contrast on a clear afternoon or a snowy morning.

## Typography

**Display Font:** SF Pro (tvOS system font), Thin and Light
**Body Font:** SF Pro (tvOS system font), Regular to Semibold
**Label Font:** SF Pro Semibold, uppercase, tracked

**Character:** one family throughout. The thin numerals of the clock and hero temperature give the screen its quiet, airy voice; everything a viewer reads for information sits at Regular or heavier so it survives the distance to the couch.

### Hierarchy
- **Clock** (Thin 200, 300 pt, -8 pt tracking; meridiem Light 300 at 64 pt): the time, top left. Proportional digits.
- **Hero temperature** (Thin 200, 132 pt, -4 pt tracking): the current temperature in the weather pane.
- **Date** (Regular 400, 52 pt): under the clock.
- **Screen title** (Semibold 600, 52 pt): Settings and setup screens.
- **Title** (Medium 500, 40 pt): the condition ("Partly Cloudy"), alert titles.
- **Headline** (Semibold 600, 36 pt): the streak line.
- **Metric** (Medium 500, 32 pt, tabular): hourly temperatures.
- **Body** (Regular 400 and Medium 500, 30 pt): status row titles, hi and lo, help text.
- **Callout** (Regular 400, 28 pt): the weather note, daily temperatures, alert text.
- **Subhead** (Regular 400 and Semibold 600, 26 pt): the latest commit line.
- **Caption** (Regular 400, 24 pt): hour and day labels, details, arc captions.
- **Label** (Semibold 600, 24 pt, 1.9 pt tracking, uppercase): pane headings and chip text.

### Named Rules
**The Thin Hero Rule.** Thin and Light weights appear only at 64 pt and above (clock, meridiem, hero temperature, compact storm clock). Below that, Regular is the lightest weight.

**The 24-Point Floor Rule.** No text role is smaller than 24 pt. The tvOS HIG puts legibility at 23 pt; the mockup's 22 pt captions were raised to 24.

**The Tabular Numbers Rule.** Temperatures in rows (hourly, daily) use tabular figures so columns do not wobble as values change. The clock stays proportional; it is one line and reads better that way.

## Layout

The canvas is 1920x1080 points, the tvOS screen at 1x.

- **Dashboard:** 72 pt top and bottom margins, 96 pt side margins, 32 pt gutters. Top row 464 pt: the clock block on the left, the current weather pane (600 pt wide) on the right. Bottom row 440 pt: forecast (700 pt), Home (482 pt), GitHub (482 pt). Pane content insets are 30 pt top and bottom and 40 pt at the sides.
- **Storm takeover:** radar fills the whole screen edge to edge, and the weather strip floats over it in one of two layouts chosen in Settings. Side: a 600 pt glass column on the right with conditions (compact clock, temperature, a one-line house status and the Apple Weather mark) and the alerts, stacked, most severe first; the radar timeline floats bottom left. Bottom: a 252 pt glass strip across the bottom with conditions, the alert title and QR code, and two house lines; the timeline floats above it.
- **Night dim:** the whole layout stays in place and is lowered to about 30 percent; particles stop. Storm mode and nudges still raise it.
- **Settings:** a 620 pt left column (screen title and a glass help pane that explains the focused row) and a 1000 pt native list on the right, with 80 pt between them.
- **Setup:** a 680 pt left column (glass icon, screen title, instructions) and an 860 pt right column with fields, a status line and actions stacked vertically, 96 pt apart.
- **Apple Weather mark:** right-aligned in the forecast pane's heading row on the dashboard, and in the conditions pane during storm mode.

**The Stacked Actions Rule.** Buttons under a field stack vertically. tvOS sends focus to the geometrically nearest control, so a side-by-side row under a wide field sends Down to the wrong button.

## Elevation & Depth

There is one surface: Liquid Glass (`glassEffect(.regular)` tinted with Glass Shade) over the sky. Panes have no resting shadow; the glass's own edge light separates them from the sky. Depth appears only as a response to focus.

### Shadow Vocabulary
- **Focus lift** (Glass Shadow #080818 at 45%, 28 pt blur, 26 pt down, masked to fall only outside the pane): under a focused pane. A plain shadow would also shadow the text, and a dark shape behind translucent glass would darken the pane.
- **Sky text shadow** (black at 22%, 15 pt blur, 2 pt down): only on the clock and date, which sit directly on the sky.

### Named Rules
**The Glass Only Rule.** Every container over the sky is Liquid Glass. No opaque cards, no hand-rolled blur, no gradient fills standing in for glass.

**The Flat at Rest Rule.** A pane gains shadow, sheen and rim only while it has focus.

## Shapes

Continuous (squircle) corners throughout. Panes use 40 pt, the alert banner 28 pt, chips 20 pt, swatches and small previews 14 pt. Native buttons keep their capsule. Status row icons sit in 52 pt circles. Strokes are 1 pt on chips, 1.5 pt on the alert, 2 pt for the focus rim.

## Components

### Glass Pane
The dashboard's container and its focus target.
- **Shape:** 40 pt continuous corners; insets 30 pt by 40 pt.
- **Rest:** Liquid Glass tinted with Glass Shade at the scene's percentage; white ink.
- **Focus:** scales to 1.04, gains a 16% white sheen under the content, a 2 pt white rim at 75%, and the focus lift shadow. Spring animation, 0.35 s response, 0.82 damping.
- **Pressed:** scales to 0.98 while the clickpad is held.
- **Action:** the weather pane opens radar; the Home pane opens the scene buttons; Back returns.

### Pane Heading
Uppercase Label type at Ink 72% with an optional SF Symbol: "NEXT 6 HOURS", "HOME", "GITHUB". It is the pane's heading, never a kicker above another heading.

### Status Row
A 52 pt icon well (Well 14%), a Body Medium title, an optional Caption detail at Ink 80%, and an optional trailing view (a nudge chip, avatars). The title never truncates before the trailing view shrinks.

### Nudge Chip
- **Nudge:** Label type in Nudge Ink on the amber fill with a 1 pt amber stroke, 20 pt corners, optional symbol in Nudge Amber.
- **Warning:** the same shape in coral, for a lost connection or a failed setup test.

### Alert Banner
A weather alert, coral fill and stroke, title at Title size with a filled warning triangle, issuer and end time ("until 8:15 PM") at Caption. WeatherKit gives an alert's summary, issuer, region, severity and end time, not its full text, so the title is the summary exactly as issued and wraps; it is never shortened, and the full text lives on Apple's alert details page. A QR code (132 pt, 104 pt when stacked) links to that page. Clicking a banner opens the alert detail: every active alert with a large QR code. In the bottom strip only the first alert fits, and its caption says how many more there are.

### Scene Button
Native `.buttonStyle(.glass)` with a label and SF Symbol ("Goodnight", "Movie", "Morning"). Focus is the platform's: a white platter with dark text. Disabled buttons dim and are skipped by focus.

### Settings Rows and Setup Fields
Native tvOS `List` rows (`LabeledContent` values, `Toggle`) and native `TextField` and `SecureField`, so the iPhone keyboard prompt works. Focus is the platform's white platter. Setup actions are 400 pt native glass buttons, stacked.

### Daylight Arc
A dashed quadratic arc (white 45%, 2 pt, 2 on 8 off) over a 30% baseline, with the sun dot (Sunlight, 18 pt core, 44 pt glow at 25%) at the day's fraction. Captions: sunrise time with the sunrise symbol, a middle caption ("Sunset in 33 min"), sunset time with the sunset symbol. At night the dot hides.

### Contribution Grid
26 weeks by 7 days of 12 pt cells with 3 pt gaps and 3 pt corners. Empty days use Faint 10%; activity steps through the scene accent at 28, 48, 72 and 96 percent.

### Weather Glyphs
SF Symbols, monochrome, Light weight, sized to their slot (104 pt hero, 44 pt hourly, 40 pt daily, 64 pt in storm conditions).

### Radar Timeline
A floating glass capsule: play symbol, the current frame's time, twelve capsule ticks (current wider and solid white, past at 80%, future at 20%), and "Now".

### The Sky (signature)
A mesh gradient built from the scene's five colors, drifting slowly, with a soft vignette. Particles add the condition: rain streaks slanted about 14° at 10 to 22 percent white, snow as soft dots, fog as wide blurred bands, stars at night, and rare lightning in storms. Every render feature sits behind a quality knob (particle count, gradient resolution, glass pane count) so the A15 check can trade effects for frames. With Reduce Motion on, the sky stops drifting, stars stop twinkling, fog stops sliding and lightning never flashes; rain and snow keep falling at half density, because falling precipitation is the weather itself. Night dim fades the particles out with the dim over 3 seconds.

## Do's and Don'ts

### Do:
- **Do** take every large color field from the scene palette, and raise Glass Shade as the sky brightens (10% at night up to 36% on snow).
- **Do** keep text at 24 pt or larger and at Regular weight or heavier below 64 pt.
- **Do** use native tvOS controls for lists, toggles, fields and scene buttons, and let the platform draw their focus.
- **Do** show focus on custom panes with the 1.04 lift, 16% sheen, 75% rim and the outside-only shadow.
- **Do** show weather alert summaries exactly as issued, wrapped, with the QR code to Apple's alert page for the full text.
- **Do** keep the Apple Weather mark on screen whenever weather data is shown.
- **Do** stack setup actions vertically under their fields.

### Don't:
- **Don't** give a pane, heading or button a brand color; the sky is the only color field.
- **Don't** use amber, coral, rain blue or sunlight for anything but their one job.
- **Don't** use Thin or Light weights below 64 pt.
- **Don't** put a resting shadow on a pane, or a text shadow on text inside a pane.
- **Don't** shorten, rephrase or truncate weather alert text.
- **Don't** animate anything faster than the weather on the resting screen; fast motion is reserved for focus, storm takeover and lightning.
- **Don't** force a foreground color on native controls; it breaks their focus platter (white text on white).
