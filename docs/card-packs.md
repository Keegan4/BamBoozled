# Daily packs (the Notes tab)

Every day the Notes tab has a free **Bamboo Booster** with **7 cards**.

1. **Tear it open** by sliding a finger or the mouse across the top of the pack. A glowing cut
   follows you; let go past about 70% (or flick quickly) and the top tears off. Let go earlier and
   it stays sealed. With a keyboard, focus the pack and press **Enter** or **Space**; screen
   readers get an "Open pack" action.
2. The cards come out **face up in a stack**, over the rest of the app (which is blurred). **Tap**
   the top card or **swipe** it left or right to slide it away and see the next. The arrow keys,
   Enter and Space do the same. Rare, Epic and Legendary cards glow in their rarity colour.
3. After the last card comes an **overview** of all 7, with **New** on cards you didn't have and
   **New finish** on a card you had, but not in this finish. Tap one for a closer look, or go to the
   binder.

Once opened, the page shows today's cards (tap to see the overview again) and counts down to the
next pack at **midnight**.

The **binder** (Notes → Binder) lists every card in the set by number: the ones you have in their
showiest finish, with a ×count for duplicates and a dot per finish owned, and the rest as numbered
gaps. Filters show All, Collected or Missing. Tap a card to see it large with its story (flavour
text, photographer, set) and switch between the finishes you own. Moving the mouse or a finger over
a large card tilts it and moves the shine of shiny finishes (not when the device asks for reduced
motion).

## Odds

Each card is rolled for a **rarity**, then separately for a **finish**, so the same photo can be
collected many ways.

| Rarity | Gem | Cards 1–5 | Cards 6–7 |
|---|---|---|---|
| Common | white | 80% | 0% |
| Rare | blue | 17% | 60% |
| Epic | purple | 3% | 30% |
| Legendary | orange | 0% | 10% |

**Pity timer:** if 9 packs in a row have had no Legendary, the 10th has one in its last slot.

About **30%** of cards get a finish; the 7th card's chances are doubled.

| Finish | Chance per card | What it looks like |
|---|---|---|
| Ink wash | 5% | Black-and-white brush-painting look |
| Bamboo | 4.5% | Green-tinted photo in a bamboo-striped frame |
| Moonlight | 4.5% | Blue night tint with a moon |
| Vintage | 4% | Sepia with darkened corners |
| Full art | 3% | The photo fills the whole card |
| Signed | 3% | The photographer's signature across the photo |
| Reverse holo | 3% | A rainbow frame that shifts as the card tilts |
| Holo | 1.5% | A rainbow sheen over the photo |
| Gold | 0.4% | Gold frame and a golden photo |
| Rainbow | 0.4% | Pastel rainbow over the whole card |
| Cosmos | 0.3% | A starry night frame and sparkles |
| Ghost | 0.3% | Pale, silvery and see-through |
| Misprint | 0.1% | Shifted colours and a crooked banner, like a printing error |

Packs are **the same for the same person on every device** for a given day (they're shuffled from
the signed-in account, or from an id made for the device when not signed in). The collection itself
is kept on each device.

## Adding a card

1. Put the photo in `app/assets/cards/`.
2. Add an entry at the **end** of `app/assets/cards/cards.yaml` (cards are numbered in file order):

```yaml
- id: tea-break              # unique, lowercase letters, numbers and dashes; never change it
  name: Tea Break            # on the card's banner (up to 24 characters)
  rarity: common             # common, rare, epic or legendary
  photo: tea-break.jpg       # the file you added in step 1
  text: Step away for five minutes.   # the card's text box (up to 90 characters)
  flavour: '"I''ll just reply to one email first," said the tea, now cold.'   # optional, up to 300
  artist: Mr Lim             # optional: credited in the binder, signed on Signed cards
  exclude: [misprint]        # optional: finishes this card never gets
```

3. Commit, push, and make a release (see the README). New cards reach people with the next release.

You can edit `cards.yaml` and upload photos straight from GitHub's website (**Add file → Upload
files** in the folder, and the pencil icon to edit).

Keep a mix of rarities: roughly 6 commons for every 3 rares, 2 epics and 1 legendary. If a rarity
has no cards yet, packs use the nearest one instead.

## Rules (checked automatically)

The tests read the real folder on every push, so CI goes red instead of the app breaking if:

| Rule | Why |
|---|---|
| Every `id` is unique, lowercase-with-dashes, and **never changed** once released | Collections are saved by id |
| `name`, `photo` and `text` are present and short enough | They have to fit on a small card on a phone |
| `rarity` and `exclude` use known names | Typos would otherwise be silently ignored |
| `photo` names a file in the same folder | Otherwise there'd be nothing to show |
| Every photo is under **1 MB** and used by a card | The web version downloads them; catches typos and forgotten files |
| There is at least one card of each rarity, and at least 7 cards | So packs have something to roll |

## Photos

- **Portrait 4:5** suits the card's photo window (other shapes are cropped from the middle).
- About **1080 × 1350 px**, saved as **JPG** (quality ~80) or WebP, under 500 KB.
- Keep the subject in the middle: the top corners are rounded off by the arch, and the banner covers
  the bottom.

## Good to know

- Removing a card from `cards.yaml` removes it from everyone's binder (copies are kept, so it comes
  back if the card is restored with the same id).
- Opening packs is per device for now: the same person can open today's pack on their phone and on
  their computer, and gets the same 7 cards on both.
