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
A symbol, not a word: two heart-topped "i" figures, one tall and one small (a grandparent and a grandkid), hearts leaning toward each other.
One-color style with a soft drop shadow: tile deep teal `#1E7F7A`, figures light teal `#5FBDB5`, shadow `#08403C`. File: `resources/icon-only.png`.

## Brand colors (final)
| Color | Hex | Job |
|---|---|---|
| Deep teal | `#1E7F7A` | App icon tile |
| Button teal | `#1A7470` | Main buttons (white text) |
| Teal ink | `#12403D` | Text and headings |
| Dark teal | `#134F4C` | Dark screens: Grandpa's home, mahjong, Family Break, Big One card |
| Pale teal | `#A9D3CE` | Soft surfaces and labels on dark screens |
| Mint white | `#F2F7F6` | Page backgrounds |
| Ballet pink | `#F2B8C6` | Hearts, NEW tags, buttons on dark screens (teal-ink text) |
| Heart red | `#9B1B1F` | Heart outline only |

Rules: pink always carries teal-ink text or a red outline; heart red is only for hearts; no navy, orange, yellow or purple in the brand.
