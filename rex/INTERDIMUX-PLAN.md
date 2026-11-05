# Shared interdimux support for tmux and Rex

The initial proof of concept is implemented. The next implementation now shares
the persistent Rust controller, measured three-column tree, raw search/scopes,
previews, confirmation/input dialogs, project directory browsing, find-or-create,
and in-place rename/close/swap/send/split/refresh actions. Rex supplies only its
native data and operations through one coordinator connection. Its program
status reports feed the existing agent formatter, with foreground owner checks.

The controller keeps fzf alive and uses never-reused opaque target tokens.
Small action/preview helpers connect through a private framed Unix socket;
the Rex adapter sends versioned atomic mailbox requests to the coordinator.
Ordinary typing does not invoke helpers or recollect data. Native actions publish
one updated snapshot; reloads reuse it. Preview and directory scans are lazy
and bounded. Single-pane rows navigate to the exact pane but use window actions.

Rex zoom closes the picker before changing focus/zoom. Window swaps reorder
tabs; pane swaps move panes, within one session. Cross-session Rex swaps and
tmux-style client detach are unavailable. The legacy tmux frontend still owns
its scheduling/jobs facilities; those are not part of the shared controller.

The design and alternatives below record the original extraction plan and the
performance reasons for keeping the backend shared.

Extend interdimux itself to support both tmux and Rex, using its existing
Rust implementation for the expensive work. Start by extracting a shared
Rust data and rendering pipeline, then add backend adapters and a shared Rust
fzf navigator. The first Rex feature remains a floating fuzzy picker on
`Ctrl+b` then `f`, switching existing sessions, windows, and panes.

The design priorities are:

- Preserve the performance improvement that motivated the Rust backend.
- Keep implementation and ownership in interdimux, with dotfiles providing
  the Rex binding and installation path.
- Share the data model, grouping, formatting, width calculation, row
  generation, fzf process control, selection, cancellation, and activation
  dispatch between both backends.
- Limit the first Rex UI to search, Enter to switch, and Escape/Ctrl+C to
  cancel. A small feature set should still use the intended shared core.

## Feasibility and performance

Substantial sharing is feasible. `rust/src/main.rs` currently mixes tmux
parsing with measuring, ordering, grouping, and emission inside `gather()`.
The surrounding `text`, `widths`, `palette`, and rendering modules already
provide reusable building blocks. Separate the input and target semantics
from those operations rather than replacing the renderer.

The project's recorded A/B measurements show why Rust belongs in the first
Rex implementation:

| List size | Bash total | Rust total | Recorded speedup |
| --- | --- | --- | --- |
| 12 rows | 37 ms | 22 ms | 1.7 times |
| 147 rows | 172 ms | 34 ms | 5.1 times |
| 497 rows | 535 ms | 69 ms | 7.8 times |

At 497 rows, first-row time was 124 ms with Bash and 49 ms with Rust. These
are the repository's existing measurements, not new Rex benchmarks. Collection,
process startup, and terminal first paint remain separate costs. Reusing Rust
must be paired with avoiding repeated CLI startups and per-row subprocesses.
See [recorded measurements](/opt/tools/interdimux/rust/README.md) and the
[performance history](/opt/tools/interdimux/docs/PERFORMANCE.md).

Most of the switching pipeline can be common. Acquisition, popup creation,
native target activation, and some metadata semantics remain backend-specific.
The shared command is `imux pick --backend tmux|rex`, initially limited to
switching. The existing full tmux navigator remains the TPM default while its
advanced actions migrate behind backend capabilities in later work.

## Shared architecture

Both adapters should feed one in-process Rust pipeline. Keep the current
tmux collector and `gather3` entry point compatible while introducing Rex
JSON input.

| Layer | Shared implementation | Backend-specific work |
| --- | --- | --- |
| Collection | Snapshot contract and collection error handling | Tmux's batched format query; Rex's server snapshot calls |
| Model | Sessions, windows, panes, origin context, optional metadata, typed targets | Conversion from native fields and identifiers |
| Rendering | Native palette presentation, Unicode handling, colors, grouping, parent context, full searchable labels, current markers, four-field output | Native metadata normalized by the adapter |
| Picker | Rust controller owns fzf, base options, searchable columns, tie ordering, accepted-row parsing, cancellation, and errors | Supported actions and native integration |
| Activation | Typed dispatch and common stale-target/error behavior | Exact tmux switching; Rex server focus and client session selection |
| Hosting | Invocation contract and initiating context | Tmux popup; Rex floating terminal and Lua binding |

The shared Rust model must distinguish **grouping keys**, **display names and
indices**, and **navigation targets**. Two equally named sessions or panes
must remain different objects. Window numbering displayed in Rex can be a
derived ordinal without becoming the identifier used to switch.

Keep the legacy renderer protocol compatible while the shared picker uses
native identity for both backends:

```text
Target::TmuxLegacy { original S:/W:/P: spec }
Target::TmuxNative { session_id, optional window_id, optional pane_id }
Target::Rex { session_id, optional window_id, optional block_id }
```

The current `gather3` protocol supplies session names and window/pane indices;
only its pane records also include native pane IDs. It does not already
provide full native session/window IDs. Requiring those everywhere would force
an unnecessary tmux protocol change. A later `gather4` can add them separately.
The new tmux picker collector captures native IDs in its own batched query,
without changing `gather3`. Accepted rows therefore retain their identity even
after windows or panes are renumbered. The server/socket and initiating client
belong to the invocation context.

`imux gather3` should continue emitting its existing hidden target specs and
visible rows byte for byte. The common internal renderer can produce row
objects containing identity, context, command/title, and a typed target;
legacy and new callers choose the final-field encoding. The Rust navigator
owns the complete invocation and can retain native targets in an in-memory
table, putting only an opaque token in the hidden field. Display labels and
ordinals never determine the target to activate.

The shared controller keeps collection, target lookup, and selection dispatch
in one process. Backend transport subprocesses receive explicit IDs as separate
arguments or structured data; target records are never evaluated as shell code.

The modern native navigator uses `presentation.rs` for both tmux and Rex.
It shows a compact indented tree, combines single-pane windows into one row,
and keeps full names searchable beyond the viewport. The legacy `gather3` formatter retains
its existing byte-compatible output. Both presentations stay in Rust; the
legacy contract does not constrain the new native UI.

### Existing Rust code to reuse

| Code | Plan |
| --- | --- |
| `text.rs`, `widths.rs`, `palette.rs` | Reuse directly; keep the existing width/squeeze rules and theme defaults. |
| `render.rs` and emission in `main.rs` | Extract a shared render pipeline; keep the tmux output unchanged. Make optional facts available without requiring tmux-shaped metadata. |
| `format.rs` | Reuse command formatting when a backend provides suitable command data. |
| `git.rs`, `proc.rs`, `macproc.rs`, `mounts.rs` | Preserve the current tmux path. Enable enrichment for Rex only when host/path/process provenance makes it valid. |
| `agent.rs`, `titles.rs` | Formatting can share normalized facts later. Claude registry parsing tied to `%pane` IDs and tmux plugin options stays in the tmux adapter. |

Some rendering currently performs enrichment: `render::ctx_field` accepts a
`GitCache`. Keep that behavior intact for tmux during extraction. Rex's first
snapshot can omit command lines, paths, git, agent state, and MRU timestamps.
Do not invent PIDs or use this Mac's process/filesystem APIs for data belonging
to another server. Sanitize Rex labels before measuring and rendering them;
existing name rendering partly relies on tmux's restrictions on control bytes.

## Implementation approaches

| Approach | Pros | Cons |
| --- | --- | --- |
| **Shared Rust pipeline and Rust navigator — selected** | One process owns targets, starts fzf, interprets selection, and dispatches activation. Both tmux and Rex exercise the same switching code immediately. Reuses the fast renderer and avoids a second shell/Python implementation. | Requires extracting a controller and backend adapters. Advanced tmux callbacks, reload behavior, and actions still need staged migration; the initial shared command remains opt-in for tmux. |
| **Shared Rust pipeline plus shell fzf support** | Reuses the fast renderer with less initial movement of the Bash frontend; useful if preserving every current shell callback is the immediate priority. | Leaves orchestration split across implementations and requires a later Rust-controller migration. Offers less sharing for the new switching path. |
| **Translate Rex JSON into gather3** | Quickly exercises the current compiled renderer with little initial extraction. | Introduces synthetic tmux fields and reverse mappings, preserves name/index assumptions, and couples Rex to an internal protocol. Useful for a throwaway feasibility experiment, weaker as the maintained dual-backend architecture. |

The selected approach makes the small PoC the first version of the intended
shared navigator. Rust owns the controller, data pipeline, common fzf options,
selection, cancellation, and backend dispatch. Thin adapters collect snapshots
and perform native activation. Keep tmux's richer action callbacks in their
existing loop until their shared-controller equivalents are implemented. Do
not build a general plugin framework or replace fzf's fuzzy matcher.

## Efficient Rex collection

The normal binding starts one detached `rex do` coordinator when opening the
picker. That coordinator collects through native Lua APIs, writes a versioned
snapshot into a private temporary directory, and opens the floating terminal
with `--snapshot FILE --result FILE`. The Rust picker reads the snapshot and
publishes an atomic completion record. It starts no Rex CLI process on Enter
or Escape. The collector:

1. Calls `session.attach_all` with `event_scope="session"` to obtain the list
   and establish the observer subscription needed by subsequent view calls.
2. Requests `session.view` for each listed session over that same connection.
3. Fetches process metadata for placed terminal blocks to provide available
   foreground command and working-directory context.
4. Returns a versioned object containing sessions, views keyed by session ID,
   metadata, and any per-session errors. The coordinator's connection remains
   available to complete the selection directly.

This uses **one coordinator startup and one attach call, one view call per
session, and one process-metadata call per terminal block**. The loops are
sequential; remote latency can grow with session and terminal count. A session
closed during collection should be skipped or reported without discarding every
candidate. Handle nullable lists and Lua's empty-table JSON representation
explicitly.

Calling `session.list` and then `session.view` without attaching the connection
failed on the installed version. `attach_all` installs a temporary observation
subscription; it does not switch the app, own panes, or change layout. Its
response contains the session list, not their views.

Store the coordinator and collector in interdimux, so deployment does not
depend on copied helpers beside the dotfiles. Standalone Rust invocations also
support the embedded collector through one `rex do -` process. Rust decodes JSON
through `serde_json`; keep its dependency versions compatible with Rust 1.74.

Avoid a Python/jq data pipeline or one CLI executable per session/pane. Keep
native Rust Rex transport as a later performance option: it could remove CLI
startup and pipeline requests, but introduces connection discovery, protocol,
authentication, subscription, and compatibility responsibilities. Measure the
single-CLI approach before taking on that scope.

## Minimal Rex behavior

### Launch and ownership

Interdimux owns the Rust adapter, collector, common picker code, and Rex host
integration at `integrations/rex.lua`. Dotfiles loads that integration with a
guarded `dofile(...).setup { root = interdimux_root }`. The integration binds:

```lua
rex.bind("ctrl+b>f", "interdimux")
```

The dotfiles checkout selects the interdimux root through `INTERDIMUX_ROOT`,
defaulting to `/opt/tools/interdimux`. The integration chooses `INTERDIMUX_BIN`
or `<root>/rust/target/release/imux`; it needs no copied helper or additional
dotfiles manifest entry. Build the release binary before using the binding.

Capture the initiating client/session/block IDs before opening the float, and
find the origin window through `session.view`. Create a centered terminal
directly with `session.new_layer` and `focus=true`. Its command runs the
interdimux Rex entry point with
those IDs as separate arguments. Specify the backend explicitly, since tmux
can run inside Rex and environment-based detection would be ambiguous.

The shared navigator's invocation is:

```sh
imux pick --backend rex \
  --client CLIENT_ID --session SESSION_ID --window WINDOW_ID --block BLOCK_ID
```

`--block` is the origin. The temporary terminal is identified separately by
`--picker-block`, defaulting to `REX_BLOCK`. An optional `--server ENDPOINT`
selects the server explicitly. `imux list` accepts the same options and emits
candidate rows without opening fzf or activating a target.

The tmux counterpart is `imux pick --backend tmux`, with optional
`--client CLIENT_TTY`, `--block %PANE`, and `--socket SOCKET_PATH`. Its
environment defaults are `INTERDIMUX_CLIENT`, `TMUX_PANE`, and the socket in
`TMUX`. TPM continues to bind the existing full navigator by default.

The Rex entry point runs `imux pick --backend rex` directly and bypasses tmux
dependency checks, option probes, and autobuild logic. Reuse defaults/environment
settings without querying a tmux server. Build the Rust binary before binding
activation; Rex can report a missing binary clearly while tmux keeps its
existing Bash fallback.

The Lua action starts the detached coordinator and returns immediately. Its
30-second limit should not bound the user's search. The coordinator outlives
the floating terminal and can close its layer before applying navigation;
completion does not depend on the picker surviving its own close. Disable
login for the temporary terminal and retain fzf's last frame until the float
closes. Use the official CLI to start the coordinator, including a bundled-app
path fallback on this Mac.
See [custom actions](https://www.superlogical.com/rex/docs/customize/actions)
and [floating layers](https://www.superlogical.com/rex/docs/reference/api#sessionnewlayer).

### Search and switch

Use the shared Rust pipeline to build session, window, and placed-pane rows
from the snapshot. Include existing floating panes, exclude the picker itself,
and keep detached blocks out of the PoC. Use the captured origin for current
markers because the newly opened picker now holds focus. Missing enrichment
remains absent. Preserve deterministic ordering without inventing Rex MRU data.

Use the shared fzf base behavior: the same four-field row layout, all three
visible fields searchable, `--tiebreak=index`, and one accepted result. The
modern navigator requires fzf 0.74+. It uses one line per tree entry, without
type badges, blank spacer rows, or wrapping.
No synchronous callback or subprocess should run when the query or cursor
changes.

| Accepted type | Rex activation |
| --- | --- |
| Session | Revalidate it and invoke `session.select` on the originating client. |
| Window | Focus the window, then show its session/window on that client. |
| Pane | `session.focus_block` activates its window; then show that session/window on the client. |

`session.select` has no block argument, so pane focus and client selection are
separate operations. The hosted coordinator performs these calls over its
existing connection when it observes terminal completion. Standalone commands
retain a bounded activation CLI fallback, scoped or attached to the target
session. Always use the captured full client ID and full Rex target IDs; a stale
target must not redirect to another similarly named object.

Normalize Escape/Ctrl+C and no-selection outcomes to successful completion,
then allow the terminal to close. Rex preserves quick program failures, so a
raw fzf cancellation status could otherwise leave a dead float. On cancellation,
restore the origin if it exists. On successful selection, avoid restoring the
origin afterward. Verify automatic layer cleanup and zoom behavior in the first
live spike; closing the helper's own layer too early kills its process.

Rex floating layers and server focus are session state, not client-private UI.
Another client viewing the window may see the float. Explicit client selection
ensures the intended app switches sessions; it does not make the layer private.

## Migration and validation

Before changing code, capture the current tmux output, process counts, and
latency with fixed fixtures and build settings as the comparison baseline.

1. **Extract the common Rust model and pipeline.** Move parsing out of
   `gather()` and route `gather3` through the extracted pipeline. Preserve input,
   output, defaults, the Bash fallback, and early list delivery. No Rex queries
   or generic JSON conversion should enter the tmux hot path.
2. **Prove legacy parity.** Run existing Rust golden, protocol, truncated-input,
   and session-directory tests; Bash/Rust and corpus parity; process-budget and
   early-list checks. Preserve the goldens and budgets rather than changing
   them to accommodate an unexplained regression.
3. **Add Rex fixtures and the Rust adapter.** Exercise both adapters through
   the same renderer. Cover duplicate/missing labels, Unicode, control bytes,
   absent metadata, mixed floating/tiled panes, empty lists, and closed targets.
4. **Add the shared Rust navigator.** `imux pick --backend tmux|rex` owns fzf,
   accepted-target lookup, cancellation, and activation dispatch. Connect both
   collectors and activation adapters. Test switching through the same
   controller for both backends; preserve the existing tmux advanced UI as the
   default integration.
5. **Prove the Rex float lifecycle.** Test immediate cancellation, keeping the
   picker open beyond 30 seconds, origin focus/zoom, selected target focus, and
   removal of the temporary block/layer. Use disposable fixtures for another
   pane, window, session, and existing floating pane.
6. **Measure latency before handoff.** Separate collection, Rust parsing/rendering,
   and keypress-to-first-fzf-paint. Use small and large fixtures and vary session
   count independently of row count. Interleave baseline and candidate runs;
   report medians and tail latency on the same machine and build profile.
7. **Hand over the switching PoC.** Enable `Ctrl+b` then `f`, let the user test
   it, and refine from that feedback.

Performance acceptance includes preserving tmux's current process budget and
latency within measured baseline noise, avoiding per-row subprocesses and
per-keystroke work, and keeping Rex collection at one CLI startup per snapshot.
The old Rust speedup is evidence for reuse, not a prediction of Rex end-to-end
latency. If sequential RPCs dominate, optimize the collector before adding UI
features or a persistent cache/daemon.

Useful existing checks include
[Rust parity](/opt/tools/interdimux/tests/test_rust_parity.sh),
[process budgets](/opt/tools/interdimux/tests/test_exec_budget.sh:183),
[early-list delivery](/opt/tools/interdimux/tests/test_early_list.sh), and the
[real-fzf benchmark harness](/opt/tools/interdimux/dev/perf/bench.sh).
The source baseline is interdimux commit `b3ceddd`.

The first Rex release stops at switching existing targets. Advanced tmux modes
keep working through their current integration; shared support for preview,
creation, rename, kill, swap, send keys, agents, directory discovery, MRU, and
cross-server navigation can be added behind backend capabilities afterward.
