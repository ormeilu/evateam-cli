# Open-issue batch acceptance ledger

Snapshot: November 7, 2026, issues #36–#80. One PR carries the whole batch;
“implemented” below means the documented command contract is exercised against
loopback fixtures, not that every live-server version has been mutation-tested.
No live tracker writes were used to validate this batch.

Three issues remain partial and must not receive closing keywords: #38 (the
conditional archive wrapper), #44 (Gantt propagation), and #68 (subscription
writes). Read-only API discovery confirmed the underlying models used for wiki,
project roles, EvaTest, queues/SLA and saved JSON filters. Unverified behavior is
not replaced with a guessed API or a successful-looking empty answer.

| Issue | State | Delivered contract / remaining limit | Regression evidence |
|---|---|---|---|
| #36 | implemented | Wiki drafts, explicit publish, published-text readback | `test_document_draft_and_explicit_publish` |
| #37 | implemented | Document comments use the task reader/writer and thread rules | `test_document_comments_and_attachments` |
| #38 | partial | Document attachment list/upload, shared collision and cleanup checks; archive layout/extraction not verified, no download-all wrapper | `test_document_comments_and_attachments` |
| #39 | implemented | Typed directional links, unlink, duplicate/absent no-ops | `test_links_types_and_noops` |
| #40 | implemented | Sprint discovery/cards and additive task membership | `test_sprints_releases_and_membership` |
| #41 | implemented | Release discovery/cards and additive membership; no shipping action | `test_sprints_releases_and_membership` |
| #42 | implemented | Person spectators, self/login resolution and repeated watch/unwatch | `test_watch_unwatch_idempotent` |
| #43 | implemented | Priority captions, points, dates, alarm and existing raw fields | `test_task_planning_participants_and_tags` |
| #44 | partial | Validated typed task-field writes and readback; no claim that these create/reschedule a Gantt object | `test_task_planning_participants_and_tags` |
| #45 | implemented | Checklist progress, ordered items, DONE/OPEN tick/undo | `test_checklists_and_template` |
| #46 | implemented | Template creation, prevalidated overrides and post-create update | `test_checklists_and_template` |
| #47 | implemented | Status-only history, descending dates, bounded page | `test_read_history_time_dev_notifications` |
| #48 | implemented | Comment-owned attachments; upload refusal keeps the comment and identifies the failed file | `test_comment_upload_failure_and_duplicate_batch_names` |
| #49 | implemented | Same-parent replies, comment editing, server-owned edit markers | `test_comment_reply_edit_and_files` |
| #50 | implemented | Own unread notification feed; --all does not mark read | `test_read_history_time_dev_notifications` |
| #51 | implemented | Bounded task/document name-or-text ILIKE search and fenced snippets; not a global attachment index | `test_search_bounded_text_and_fenced` |
| #52 | implemented | Tag discovery/display, exact-name filtering and explicit replacement | `test_task_planning_participants_and_tags` |
| #53 | implemented | Confirmed attachment removal, refusal without --yes, absent repeat | `test_attachment_delete_confirmation_and_repeat` |
| #54 | implemented | Task work-log page, actual/plan distinction and page-only totals | `test_read_history_time_dev_notifications` |
| #55 | implemented | Confirmed document children and bounded recursive depth; not a complete mixed-node tree | `test_wiki_children_history_and_versions` |
| #56 | implemented | History and exact opaque revision selection; no invented ordinal versions | `test_wiki_children_history_and_versions` |
| #57 | implemented | Project owner, polymorphic direct role assignments and lists; not an effective-human-member total | `test_project_testcases_and_sla` |
| #58 | implemented | Author, watcher, waiting-for, archive and me selectors combined with other filters | `test_task_desk_filters` |
| #59 | implemented | Co-assignees/waiting-for display, replacement/clear and person resolution | `test_task_planning_participants_and_tags` |
| #60 | implemented | Linked git artifacts and repository reads, retaining provider state/IDs | `test_read_history_time_dev_notifications` |
| #61 | implemented | Confirmed testcase/step/testplan/membership models; no guessed run/cycle commands | `test_project_testcases_and_sla` |
| #62 | implemented | Native SLA cycles and paged computed-JSON queue matches; unsupported definitions are unknown, durations stay server-native | `test_project_testcases_and_sla` |
| #63 | implemented | Deleted-task view, confirmed restore and already-restored no-op; no invented deletion timestamp/retention | `test_trash_restore_and_safe_bulk` |
| #64 | implemented | Complete bounded selection before writes, default preview, --yes, partial failure reporting | `test_complete_selection_pages_and_bulk_cap`, `test_write_readback_and_partial_bulk_failure` |
| #65 | implemented | Component display/list/filter and shared multi-select name/ID resolution | `test_components_saved_filters_and_subscriptions` |
| #66 | implemented | Own saved JSON BQL with model/name validation; null/malformed/UBQL-only definitions fail closed | `test_components_saved_filters_and_subscriptions` |
| #67 | implemented | Complete visible period aggregation by project/day; fact/plan/other kept separate | `test_time_report_grouped_visible_minutes`, `test_complete_selection_pages_and_bulk_cap` |
| #68 | partial | Explicit followers are readable; CmfFollower create/delete and permission contracts remain unverified | `test_components_saved_filters_and_subscriptions` |
| #69 | implemented | Shared private principal-scoped metadata cache, local schema filtering and tested offline class catalog | `test_schema_filters_locally_refreshes_and_keeps_only_metadata`, `test_schema_catalog_covers_literal_model_call_sites` |
| #70 | implemented | Six task write previews with resolved methods/kwargs and no mutation; not validate-only | `test_write_previews_never_mutate` |
| #71 | implemented | Ordered deduplicated text-card sections reusing readers; not a single-RPC optimization | `test_json_projection_columns_and_comment_windows` |
| #72 | implemented | Bounded read-only context, batched project tallies, explicit unavailable/lower-bound sections | `test_context_is_bounded_read_only_and_has_no_project_n_plus_one` |
| #73 | implemented | Separate actionable stderr hint without changing server text/exit failure | `test_integrated_main_help_raw_reply_and_error_exit` |
| #74 | implemented | Dotted column projection, escaped TSV without footer and format-conflict validation | `test_json_projection_columns_and_comment_windows` |
| #75 | implemented | Bounded raw pipe output and unique private full-result files; --full/terminal keep full JSON | `test_raw_64k_boundary_and_unicode_single_line`, `test_large_raw_pipe_is_private_unique_and_bounded` |
| #76 | implemented | Local nested JSON projection, implicit-field omission, null/missing/array handling | `test_projection_nested_arrays_and_missing_fields`, `test_projection_empty_and_repeated_paths` |
| #77 | implemented | Newest window, chronological inside each page, earlier-page hint and explicit bounded --all | `test_json_projection_columns_and_comment_windows` |
| #78 | implemented | Offline canonical recipes tested against dispatch/help | `test_cheatsheet_is_offline_and_recipes_match_dispatcher` |
| #79 | implemented | Command monolith split into domain modules and dependency-free shared plumbing; existing e2e expectations retained except explained deltas below | `test_help_readmes_and_permissions_cover_dispatch` |
| #80 | implemented | Update builder/apply orchestration/derived-change reporting separated, shared template overrides, same note wording | `test_readback_normalized_relations_numbers_and_missing_null`; legacy e2e “update notes side change” and “update no false note” |

## Architecture and intentional compatibility deltas

- `main.mojo` dispatches; `common.mojo` owns generic lookup/input/paging helpers.
  Task, workflow, collaboration, documents, attachments and resource modules own
  their command behavior rather than depending on a command monolith.
- `dates.mojo` centralizes validation/time helpers; projection/readback/selection
  modules share pure operations and fail-closed collection behavior.
- `fields.mojo` and schema discovery share private cached metadata; `state.mojo`
  owns cache/spill filesystem policy. Client/transport remain below commands.
- Existing CLI defaults and derived-change note text are preserved except the
  requested comment window, bounded large raw replies, additional task-card
  fields and separate error hints. The legacy hostname test now expects the
  name written by its earlier update instead of the stale original fixture name.
- A move to the existing status is now an explicit no-op. Transition-only
  fields/comments/resolution are refused in that case instead of silently lost.
- Duplicate filenames within an upload batch are rejected before creation;
  collision discovery is paginated rather than silently stopping at 2,000.

## Verification entrypoints

`pixi run test` enforces zero compiler warnings. `pixi run e2e` retains the
legacy shell checks and runs all Python integration tests against `EVA_BIN`.
`pixi run asan` repeats unit/e2e coverage with the instrumented main binary.
Both READMEs, binary help, agent permissions, schema class catalog, cheatsheet
recipes and this ledger have drift checks. Hosted Linux/macOS CI is the
cross-platform authority; local execution is macOS arm64.
