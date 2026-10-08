# "Do next" priority scoring

The welcome page ranks incomplete tasks by a score that combines how soon each task is **due** with the **priority** the user gave it. The welcome page shows the top 5 tasks, with a "See all" link for the rest.

## Formula
```
P        = priority weight: Low 1, Medium 2, High 3, Urgent 4
daysLeft = (dueAt − now) in days (fractional)
U        = urgency
           overdue (daysLeft < 0) → 1.25
           otherwise              → 1 / (1 + daysLeft / 2)

score = 0.55 · U + 0.45 · (P / 4)
```
Ties are broken by the earlier due date, then by the shorter estimated time.

## Urgency at a glance
| Due in | U |
|---|---|
| overdue | 1.25 |
| now | 1.00 |
| 1 day | 0.67 |
| 2 days | 0.50 |
| 1 week | 0.22 |
| 2 weeks | 0.13 |

## Worked example
| Task | Due | Priority | U | P/4 | Score | Rank |
|---|---|---|---|---|---|---|
| Submit report | overdue | Medium | 1.25 | 0.50 | **0.91** | 1 |
| Mark 3A essays | tomorrow | High | 0.67 | 0.75 | **0.70** | 2 |
| Reply to parents | today (in 4h) | Low | 0.92 | 0.25 | **0.62** | 3 |
| Plan CCA trip | in 7 days | Urgent | 0.22 | 1.00 | **0.57** | 4 |

An urgent task that is a week away still ranks below a low-priority task due today, because a deadline only hours away outweighs priority. Once the CCA trip is 2 days away (score 0.73), it moves up to second place.

## Explaining the ranking
Each card in "Do next" shows a short reason built from its two inputs, e.g. *"Due tomorrow · High priority"* or *"Overdue by 2 days"*. This lets users see why a task is ranked where it is.

## Tuning
The weights (0.55 for urgency, 0.45 for priority) and the half-life (2 days) are constants in `priority_scorer.dart`. They can be exposed later in Settings as a single slider, *"Deadlines matter more ↔ Priority matters more"*.
