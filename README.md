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

## Look (November 2026): warm slate + pink
Chosen with the "Jobs Treatment" plus a readability check for older eyes (WCAG contrast):
- **Warm slate `#4A4541`**: Hiello's main background (Grandpa's home, games menu, trivia). Text `#FFF9F3` scores 9.1, pink scores 5.6.
- **Warm graphite `#34302D`**: wherever a photo fills the screen (camera, stories, Photos) and the widget background.
- **Warm cream `#F6F2ED`**: setup and settings screens, with warm graphite buttons.
- **Ballet pink `#F2B8C6` + heart red `#9B1B1F`**: the only highlight color, used sparingly.
- Ruled out: pewter `#6B655F` (pink 3.4, small text 4.6) and brushed aluminum `#BFB9B2` (pink 1.2, disappears).
- 2000s Apple touches: a faint brushed finish on slate screens and a soft gloss on round buttons. The navy charm logo stays as the signature mark.

## Photo notifications

When someone sends a Hiello, everyone else in the family gets a notification with the photo inside it.
When Grandpa sees it, hearts it, writes a note or RSVPs, the person who sent it gets one too. These replace
each other, so each photo only ever has one notification on screen.

How it fits together:
- `backend/push.sql`: database triggers. When something happens, they quietly call the Edge Function, passing a private secret.
- `backend/functions/hiello-push/index.ts`: the Supabase Edge Function. It signs in to Apple with your push key and sends the alerts, attaching a one-day link to the small photo.
- `native/ios/HielloNotify/`: a Notification Service Extension. It downloads that photo and puts it inside the notification.
- `scripts/add_notify.rb`: adds that extension to the Xcode project. It also adds the AppDelegate token hand-off. This runs in the "Hiello for iPhone + Widget" workflow.
- When the app asks: Grandpa sees "Ding me for new photos" on the You're connected screen. Parents are asked right after their first send.

Setup (one time):
1. In Apple Developer, create an APNs key and turn on Push Notifications for `com.hiello.family`. Then register a new App ID, `com.hiello.family.notify`, with no capabilities.
2. In Supabase, run `backend/push.sql`. Then deploy the `hiello-push` function with "Verify JWT" turned off; the database calls it with its own secret instead. Finally, add the secrets `APNS_KEY`, `APNS_KEY_ID` and `APNS_TEAM_ID`.
