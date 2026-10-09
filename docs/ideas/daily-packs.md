# Idea: daily card packs, a binder and the Panda Exchange

Status: **idea, not built.** Saved for a later milestone. It would replace the current one-card-a-day
Notes tab (see [../daily-notes.md](../daily-notes.md)).

Interactive mockup: https://claude.ai/artifact/R529YMPH3Aq898XZU8tocB (private to the project owner
until shared). It shows pack opening, the binder, every finish and the exchange, with sample cards.

## The loop

1. **A free pack every day** (the Bamboo Booster) with **7 cards**.
2. Tear it open; 7 cards appear face down. Their backs **glow in their rarity colour** before you
   flip them (blue Rare, purple Epic, orange Legendary). Tap each to flip, or "Reveal all".
3. Every card goes into the **binder**. Duplicates add to a copy count.
4. Spare copies can be traded at the **Panda Exchange** for bamboo shoots, which buy **better packs**.
5. Idea: finishing every task on a day earns a second free pack (ties the game to the planner).

## Rarity (set per card in notes.yaml)

| Rarity | Gem | Cards 1–5 | Cards 6–7 |
|---|---|---|---|
| Common | white | 80% | 0% |
| Rare | blue | 17% | 60% |
| Epic | purple | 3% | 30% |
| Legendary | orange | 0% | 10% |

- **Pity timer:** a Legendary is guaranteed within 10 packs.
- Suggested set mix: 50% common, 30% rare, 15% epic, 5% legendary; 60–100 cards before duplicates dominate.

## Finishes (rolled per card on every pull, independent of rarity)

One photo becomes many collectibles. Card 7 gets double finish odds.

| Finish | Inspired by | Look | Odds | Value ×| Build |
|---|---|---|---|---|---|
| No finish | | Plain card | 70% | 1 | – |
| Ink wash | Chinese brush painting (panda original) | Greyscale on rice-paper grain | 5% | 2 | colour filter |
| Bamboo | panda original | Green tint, bamboo-stalk frame | 4.5% | 2 | filter + frame |
| Moonlight | panda original | Night-blue tones, moon in the corner | 4.5% | 2 | filter |
| Vintage | old photographs | Sepia, darkened edges | 4% | 2 | filter |
| Full art | Pokémon full art, MTG borderless | Photo fills the card | 3% | 3 | layout |
| Signed | Hearthstone Signature | Artist signature on the art | 3% | 3 | layout |
| Reverse holo | Pokémon reverse holo | Rainbow sheen on the frame only | 3% | 3 | moving sheen |
| Holo | Pokémon holofoil, MTG foil | Rainbow sheen across the photo | 1.5% | 3 | moving sheen |
| Gold | Hearthstone Golden, gold secret rare | Gold frame and glint | 0.4% | 5 | sheen + frame |
| Cosmos | Pokémon cosmos holo, MTG galaxy foil | Glittering stars | 0.3% | 5 | pattern + sheen |
| Ghost | Yu-Gi-Oh! Ghost Rare | Pale, see-through, silver sheen | 0.3% | 5 | filter + sheen |
| Rainbow | Pokémon Rainbow Rare | Pastel rainbow over everything | 0.4% | 8 | overlay + sheen |
| Misprint | real printing errors | Off-centre art, doubled colours | 0.1% | 12 | layout |
| Sakura | panda original | Pink tint, drifting petals | seasonal packs | 3 | animated overlay |
| Pixel | retro games | 8-bit version of the photo | event packs | 3 | downscale |
| Sketch | pencil art cards | Hand-drawn look | later | – | shader |
| Diamond | Hearthstone Diamond, Yu-Gi-Oh! Prismatic | Cut-glass facets | later | – | shader |
| Numbered | MTG serialized | "007 / 100" | later | – | server counter |

Shiny finishes follow the mouse on desktop and the phone's tilt on mobile; with "reduced motion"
on they show a still sheen. A flipped card with a finish (or a Legendary) gets a short sparkle.

## Binder

- Every card in card-number order; owned cards show **×copies** and a coloured dot per finish owned;
  missing cards are greyed silhouettes with "?".
- Progress per rarity ("Rare 3 / 3") and for card + finish pairs.
- Filters: All, Owned, Missing, by rarity.
- Clicking a card opens it large in the blurred viewer, Hearthstone-style: the card on one side, a
  parchment panel with the **flavour text**, set name, rarity gem, card number and artist, plus the
  finishes you own (tap one to see it).

## Panda Exchange: buy packs with duplicates

You always keep one copy of each card + finish; spares can be traded for **bamboo shoots**.

- Card value: Common 1 · Rare 3 · Epic 8 · Legendary 20, multiplied by the finish value above.
- **The rarer the cards you trade, the better the pack you can afford:**

| Pack | Cost | What's better |
|---|---|---|
| Bamboo Booster | free daily | standard odds |
| Jade Booster | 25 shoots | ~2× Legendary chance (1% / 18%), double finish odds, card 7 triple |
| Golden Booster | 70 shoots | a Legendary and a shiny finish (Holo or better) guaranteed, triple finish odds |

## Card format (extends notes.yaml)

```yaml
- id: story-of-amara           # never change once released
  name: Story of Amara
  rarity: epic                 # common | rare | epic | legendary
  photo: story-of-amara.jpg
  text: Take a full lunch break today.
  flavour: "Once upon a time... ok how about we just skip to the end?"
  set: Bamboo Grove            # optional
  artist: Ms Tan               # optional
  finishes: [no-misprint]      # optional: rule out finishes for this card
```

## Build notes for later

- Packs can be deterministic per person and day (like today's card), so phone and computer agree.
- Copy counts and shoots should **sync through Supabase** (a new table per user), otherwise trading
  on one device and opening on another goes wrong.
- Colour finishes are `ColorFiltered` matrices; sheens are animated gradients with blend modes driven
  by pointer position or `sensors_plus` tilt; Sketch and Diamond need `FragmentProgram` shaders.
- Keep it purely fun: no purchases, no streak penalties.

## Open questions

- Confirm rarity odds, pack size (7) and the pity timer.
- Bonus pack for finishing all of a day's tasks?
- Should the daily card stay as a separate small feature, or be fully replaced?
