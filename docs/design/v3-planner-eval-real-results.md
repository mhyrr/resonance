# v3 Planner Eval Real-Provider Results

Started: 2026-05-13T19:54:36Z
Finished: 2026-05-13T19:56:34Z
Provider: `anthropic`
Model: `claude-sonnet-4-5`
Prompts: 12

## Summary

| Metric | Result |
| --- | ---: |
| Total prompts | 12 |
| Valid plans | 12 |
| Compiled workspaces | 12 |
| Invalid plans | 0 |
| Compile failures | 0 |
| Retried | 1 |
| Recovered | 1 |
| Invented capability failures | 0 |
| Invented pattern failures | 0 |
| Invented primitive failures | 0 |
| Valid plan rate | 100.0% |
| Compile rate | 100.0% |

Note: this artifact was generated before retry-error reporting was added to the
real-provider eval task. It records that `largest_deals` recovered on the second
attempt, but not the first-attempt validation errors. Future runs include retry
error messages and retry validation error codes in the markdown and JSON
reports.

## Prompt Results

| Prompt | Status | Attempts | Sections | Primitives | Errors |
| --- | --- | ---: | ---: | --- | --- |
| Show me pipeline health by stage and owner. | `compiled` | 1 | 4 | segment_population, rank_entities |  |
| Which deals are stuck in negotiation? | `compiled` | 1 | 3 | summarize_findings, rank_entities |  |
| Compare this quarter's pipeline to last quarter. | `compiled` | 1 | 3 | summarize_findings, compare_over_time |  |
| Give me an account review for top enterprise deals. | `compiled` | 1 | 4 | summarize_findings, rank_entities, segment_population |  |
| What should Alice focus on this week? | `compiled` | 1 | 4 | summarize_findings, rank_entities, segment_population, compare_over_time |  |
| Show open pipeline by owner. | `compiled` | 1 | 2 | rank_entities, segment_population |  |
| What does the contact funnel look like? | `compiled` | 1 | 2 | segment_population, rank_entities |  |
| Where are sales activities getting no response? | `compiled` | 1 | 2 | summarize_findings, rank_entities |  |
| Rank the largest deals in the pipeline. | `compiled` | 2 | 1 | rank_entities |  |
| Summarize proposal-stage pipeline. | `compiled` | 1 | 3 | summarize_findings, rank_entities |  |
| Which opportunities are the forecast vampires: technically alive, still draining attention, and most likely to embarrass us on Friday? | `compiled` | 1 | 4 | summarize_findings, rank_entities, segment_population |  |
| Board packet is tomorrow. I need a compact CRM operating dashboard that tells me whether the pipeline is healthy, where revenue is stuck, whether the quarter is getting better or worse, and which accounts or owners need attention.  Keep it read-only and executive-friendly: show the big pipeline picture first, then give me the specific account/deal focus areas I should ask the team about. | `compiled` | 1 | 5 | summarize_findings, segment_population, compare_over_time, rank_entities |  |
