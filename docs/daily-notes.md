# Daily cards (the Notes tab)

Each day the Notes tab shows one card. It starts as a **blurred photo**; tap it to **reveal** the
photo, tap again to **flip** it and read the message on the back, and tap again to flip it back.
Opened cards go into **Collected** below. Clicking one opens it over the app (everything else is
blurred out), already showing the photo, and a click flips it.

- Cards come in a **random order per person**, with no repeats until every card has been seen, and
  never the same card two days running. When all have been seen, a new shuffle starts.
- When signed in, a person gets the **same card on their phone and computer**.
- A new card arrives at **midnight** (the page counts down to it).

## Adding a card

1. Put the photo in `app/assets/daily_notes/`.
2. Add an entry to `app/assets/daily_notes/notes.yaml`:

```yaml
- id: bamboo-forest          # unique, lowercase letters, numbers and dashes
  photo: bamboo-forest.jpg   # the file you added in step 1
  title: A walk in the bamboo   # optional, shown on the back above the message
  text: |
    Pandas spend up to 14 hours a day eating.
    Take a proper lunch break today.
```

3. Commit, push, and make a release (see the README). New cards reach people with the next release.

The order of entries in the file doesn't matter. You can edit `notes.yaml` and upload photos straight
from GitHub's website (**Add file → Upload files** in the folder, and the pencil icon to edit).

## Rules (checked automatically)

The tests read the real folder on every push, so CI goes red instead of the app breaking if:

| Rule | Why |
|---|---|
| Every `id` is unique, lowercase-with-dashes, and **never changed** once released | The id is how the app remembers which cards someone has seen |
| `photo` names a file in the same folder | Otherwise there'd be nothing to show |
| `text` is present and at most **400 characters** | It has to fit on the back of the card on a phone |
| Every photo is under **1 MB** | The web version downloads them; aim for under 500 KB |
| Every photo in the folder is used by a card | Catches typos in `photo:` and forgotten files |

## Photos

- **Portrait 4:5** fits the card exactly (other shapes are cropped to fill it, from the middle).
- About **1080 × 1350 px**, saved as **JPG** (quality ~80) or WebP.
- Keep the subject away from the very edges, and avoid text in the photo: the card is small on phones.

## Good to know

- Removing a card from `notes.yaml` also removes it from everyone's Collected gallery.
- Adding cards changes how many are in a cycle, so the order is reshuffled from then on (a card may
  come round again a little sooner than expected around a release).
- What has been opened is remembered on each device. Today's card is the same everywhere, but the
  Collected gallery is per device.
