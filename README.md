# Hiello (test build)

Family photo and video "commercials" for grandparents. Family members make a Hiello (photo or short video, a sticker note, a look). Grandpa sees it on his home screen and between rounds of a simple mahjong game.

This is the **one-phone demo**: everything is saved on the phone itself. Use the switch at the bottom of the screen to flip between the **Family side** and **Grandpa's phone**.

## What's in it
- `www/index.html`: the whole app (layout, styles and code in one file). Fonts are the iPhone's own Baskerville and Helvetica Neue.
- `resources/`: app icon and launch screen.
- `capacitor.config.json`: app name and ID (`com.hiello.family`).
- `codemagic.yaml`: builds the iPhone app on Codemagic's Macs and sends it to TestFlight.

## Screens
- **Welcome**: names for Grandpa, you, and a grandkid (used for the sample updates).
- **Family side**: Make a Hiello, plus a "Sent" list showing watched ✓, hearts sent back, and RSVPs for big moments.
- **Make a Hiello**: pick a photo or video, drag the sticker note, choose Polaroid / Comic / Retro TV / Postcard, mark it Everyday or Big moment ★.
- **Grandpa's home**: widget preview (newest Hiello), Play Mahjong, This week in the family.
- **Mahjong**: 6×6 board, 18 pairs; a tile can move if its left or right side is open. The bottom banner rotates family updates. After each round, a full-screen Family Break plays the oldest unwatched Hiello, or an encore when nothing is new.
- **This week**: "You're all caught up," a one-minute recap, and the gold "The big one · worth the trip" card with I'll be there / Send me the recap.
- **Settings → Demo tools**: send a surprise Hiello in 10 seconds (to show live arrival while playing), add samples, erase everything.

## Putting it on your iPhone (TestFlight)
1. In **App Store Connect**: Apps → **+** → New App. Platform iOS, name **Hiello**, bundle ID **com.hiello.family** (if it's not in the list, add it under Certificates, Identifiers & Profiles → Identifiers first), SKU `hiello`.
2. In **Codemagic**: Add application → connect GitHub → pick the `hiello` repo → it finds `codemagic.yaml`.
3. Start the **Hiello for iPhone** workflow. It uses the same App Store Connect key as your Paper Meadow games ("PaperMeadow").
4. When the build finishes (about 15–20 min) it uploads to TestFlight. Open the TestFlight app on your iPhone and install Hiello.

## Not in this test build yet
Sending between two phones (needs a server such as Supabase), the real iPhone home screen widget (needs a small Swift add-on), notifications, accounts, subscriptions, moderation/reporting, and account deletion. Those come next, in that order.

## Test hook
`window.__hi` in the browser console: `S()` state, `findPair()`, `G` board, `go(name)`.

## Logo (locked)
An Italian charm-bracelet link: a brushed-steel frame with two small pins (top and bottom), a navy enamel face (`#14285A`), and a white serif "hi" whose i is dotted with a ballet-pink heart (`#F2B8C6`) outlined in heart red (`#9B1B1F`). File: `resources/icon-only.png`.
Chosen over the teal two-figure symbol because teal with a pink heart is the look of teen couples widget apps (noteit, Loveit); navy reads as family. The teal figures are kept for a future alternate icon or in-app mascot.

## Brand colors (final)
| Color | Hex | Job |
|---|---|---|
| Navy | `#14285A` | Icon enamel, text, main buttons |
| Steel / silver | `#C8CACE` | Icon frame, soft surfaces, labels on dark screens |
| Ballet pink | `#F2B8C6` | Hearts, NEW tags, buttons on dark screens (navy text) |
| Heart red | `#9B1B1F` | Heart outline only |
| White | `#FFFFFF` | Cards, widget, photo frames |
| Off-white | `#F5F5F7` | Page backgrounds |
| Slate | `#4B5263` | Secondary text |
| Midnight | `#0B1733` | Dark screens: Grandpa's home, mahjong, Family Break, Big One card |

Rules: pink always carries navy text or a red outline; heart red only for hearts; no teal, orange, yellow or purple in the brand.

## Family sharing (Supabase) and the home screen widget

**Backend:** `backend/schema.sql` sets up everything in a Supabase project (paste it into SQL Editor and run). There are no passwords: each family has a long random secret, and a phone only gets it by typing a 6-digit family code (good for 7 days, 10 wrong tries locks that connection out for 15 minutes). Tables are locked; all reads and writes go through `hi_*` functions that check the secret. Photos are in a private storage bucket. To switch it on, put the Project URL and publishable (anon) key into `HIELLO_CLOUD` at the top of the cloud section in `www/index.html`. Without them the app runs as the one-phone demo.

**Widget:** `native/ios/HielloWidget/` (SwiftUI WidgetKit extension, iOS 17+) plus the app-side bridge in `native/ios/App/`. The Codemagic workflow **Hiello for iPhone + Widget** copies them in and runs `scripts/add_widget.rb` to add the extension target. The widget fetches new Hiellos by itself (so it updates with the app closed), and also uses the newest pictures the app leaves in the shared App Group.

What it does beyond Locket: heart a photo straight from the home screen, a "3 NEW" count, Aura-style rotation through recent photos when nothing's new, one widget per grandkid (Edit Widget > Show photos from), Lock Screen widgets, StandBy nightstand photo frame, and a parent version that shows "Grandpa watched ✓ ♥2" and Grandpa's replies.

**Apple setup the widget needs:** App Group `group.com.hiello.family` on App ID `com.hiello.family`, a new App ID `com.hiello.family.widget` with the same App Group, and App Store profiles for both fetched into Codemagic.
