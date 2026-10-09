# Bamboo Trivia (Play tab)

One run a day. Everyone gets the same questions in the same order, with the answers in the same order, without anything being synced.

## Rules

All of these are in `TriviaRules` (`app/lib/domain/trivia/daily_trivia.dart`), so they're easy to tune.

| Rule | Value |
|---|---|
| Lives | start with 2, never more than 2 |
| Reading time (question shown alone) | 1.2 s + 0.03 s per character, between 1.5 s and 3.5 s |
| Time to answer question *n* | 15 s − 0.8 s × (*n* − 1), never under 5 s |
| Difficulty | questions 1–5 easy, 6–12 medium, 13 onwards hard |
| Wrong answer or out of time | lose a life; the right answer is shown |
| Right answer | +1 score |
| Right answer within 1 s of the answers appearing | +1 score and +1 life (up to 2) |
| After each answer | the result shows for 1.2 s (or tap **Next**) |

The score is the number of questions answered correctly.

**Fairness:**
- Each answer is saved straight away, so a run can be left and continued later the same day.
- If you leave while the answers are showing, that question counts as missed when you come back, so leaving can't be used to skip a question.
- A finished run can't be replayed until the next day.
- Runs are kept on the device, in the settings table under `trivia_runs`, for 400 days.

## Choosing the day's questions

Implemented as `DailyTrivia` in `app/lib/domain/trivia/daily_trivia.dart`.

- The day number counts days since 1 January 2026 (local date).
- Each difficulty is a separate pool, sorted, then shuffled with `StableRandom`. That is the same small generator the Notes cards use, and it gives identical results on phones, computers and in the browser.
- Day *d* reads its easy questions from position *d* × 5 of the easy pool, medium from *d* × 7, and hard from *d* × 8. That's roughly a full run's worth a day, so the questions people actually reach change daily, and a pool is reshuffled only once all its questions have been used.
- If a difficulty has no questions, the nearest easier pool is used, then the nearest harder one.
- The four answers are shuffled with a seed made from the day and the question number.

## The question bank

`app/assets/trivia/questions.json` is a list of objects:

```json
{"q": "What is the capital of Australia?", "a": "Canberra", "wrong": ["Sydney", "Melbourne", "Perth"], "cat": "Geography", "diff": "easy"}
```

It is made from [Open Trivia DB](https://opentdb.com), whose questions are licensed **CC BY-SA 4.0**. The game shows the credit "Questions from Open Trivia DB (opentdb.com), CC BY-SA 4.0" on its start and result screens. Keep it there.

To build or refresh it (takes about 10 minutes, because the site allows one request every 5 seconds):

```bash
cd app
dart run tool/fetch_trivia.dart
```

The script:
- downloads every verified multiple-choice question;
- leaves out:
  - categories that are mostly one country's pop culture;
  - questions about US sports and politics, or ones likely to go out of date ("current", "this year");
  - questions over 140 characters;
  - answers like "All of the above";
- keeps the questions already in the file, so running it again only adds.

Look over the new questions in the diff before committing. You can also add or fix questions by hand in the same format.

Adding questions changes the pool sizes, so the daily order changes from then on. That's fine. Only today's run being in progress at the moment of an update could see a different next question.
