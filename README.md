# Hiello (test build)

Family photo and video "commercials" for grandparents. Family members make a Hiello (photo or short video, a sticker note, a look). Grandpa sees it on his home screen and between rounds of a simple mahjong game.

This is the **one-phone demo**: everything is saved on the phone itself. Use the switch at the bottom of the screen to flip between the **Family side** and **Grandpa's phone**.

## What's in it
- `www/index.html`: the whole app (layout, styles and code in one file). Fonts are the iPhone's own Baskerville and Helvetica Neue.
- `resources/`: app icon and launch screen.
- `capacitor.config.json`: app name and ID (`com.hiello.app`).
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
1. In **App Store Connect**: Apps → **+** → New App. Platform iOS, name **Hiello**, bundle ID **com.hiello.app** (if it's not in the list, add it under Certificates, Identifiers & Profiles → Identifiers first), SKU `hiello`.
2. In **Codemagic**: Add application → connect GitHub → pick the `hiello` repo → it finds `codemagic.yaml`.
3. Start the **Hiello for iPhone** workflow. It uses the same App Store Connect key as your Paper Meadow games ("PaperMeadow").
4. When the build finishes (about 15–20 min) it uploads to TestFlight. Open the TestFlight app on your iPhone and install Hiello.

## Not in this test build yet
Sending between two phones (needs a server such as Supabase), the real iPhone home screen widget (needs a small Swift add-on), notifications, accounts, subscriptions, moderation/reporting, and account deletion. Those come next, in that order.

## Test hook
`window.__hi` in the browser console: `S()` state, `findPair()`, `G` board, `go(name)`.

## Brand colors (Heritage forest)
| Use | Color |
|---|---|
| Icon background, Grandpa's home, mahjong table | Forest `#23463A` |
| Main buttons on light screens, headings | Navy `#1B2A4A` |
| "hi" in the logo, buttons on dark screens, highlights | Khaki `#E3D5B8` |
| Heart fill | Pink `#F2B8C6` |
| Heart outline | Deep red `#A51D2A` |
| Backgrounds | Warm white `#F7F5F0` |

Rules: buttons on dark screens are khaki with navy text. Never put pink or red text on navy or forest.
