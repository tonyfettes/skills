# MoonBit Async (`moonbitlang/async`)

Runtime setup, structured concurrency, async tests, cancellation-safe cleanup,
and pipeline backpressure. Language-level basics live elsewhere: the `async`
prefix / no-`await` rule and implicit raising in `language.md` and `errors.md`;
`defer` itself in `control-flow.md`.

## Runtime and setup

Asynchronous programming uses compiler support plus the `moonbitlang/async`
runtime. Prefer the native backend for async IO; WebAssembly support is not
available for async IO-oriented packages.

Discover the API before coding: after `moon add moonbitlang/async@<version>`,
explore it with `moon ide doc "@async"` (and subpackages like
`moon ide doc "@async/stdio"`). For exact signatures, read the pinned version's
`pkg.generated.mbti` under `${MOON_HOME}/registry/cache/moonbitlang/async/<version>.zip`
(see the "API Lookup Rule" in `SKILL.md`). Subpackages — `@async` (tasks,
timers, cancellation), `@async/aqueue`, `@async/fs`, `@async/stdio`,
`@async/websocket`, … — must each be imported separately in `moon.pkg`.

1. Add the dependency and pin the native target in `moon.mod`:
   ```
   import {
     "moonbitlang/async@0.18.1",
   }

   options(
     "preferred-target": "native",
   )
   ```
2. In the executable's `moon.pkg`, set `is-main`, restrict to native, and import
   what you need:
   ```
   import {
     "moonbitlang/async",
     "moonbitlang/async/stdio",
   }
   supported_targets = "native"
   options(
     "is-main": true,
   )
   ```
3. Define `async fn main` and call async functions normally. There is no
   `await` keyword. Spawn concurrent tasks via `with_task_group` for structured
   concurrency:
   ```mbt nocheck
   ///|
   async fn main {
     @async.with_task_group(group => {
       group.spawn_bg(() => {
         @async.sleep(50)
         @stdio.stdout.write("A\n")
       })
       group.spawn_bg(() => {
         @async.sleep(20)
         @stdio.stdout.write("B\n")
       })
     })
   }
   ```

`with_task_group` guarantees every spawned task has terminated when it returns.
If a spawned task fails without `allow_failure=true`, peer tasks are cancelled
and the error propagates. Cancelled tasks do not trigger peer cancellation by
themselves.

For `spawn_bg` / `spawn` closures, use `() => { ... }` or `async fn() { ... }`.
Avoid `fn() { ... }` because it triggers deprecated async syntax warnings.
Forms like `async () => ...`, `fn() async { ... }`, and `fn(args) async { ... }`
are parse errors.

## Async tests

Use `async test` for tests that call async functions. The package containing
the test must import `moonbitlang/async` for the relevant test mode:

```
import {
  "moonbitlang/async",
  "moonbitlang/async/stdio",
} for "test"
```

Async tests run in parallel by default. Avoid shared ports, files, environment
variables, and global mutable state unless each test isolates its resources.
Run with `moon test --target native` unless `moon.mod` sets
`"preferred-target": "native"`.

## Don't swallow all async errors

In async code, never write a catch-all branch like `catch { _ => () }`. If a
catch-all is genuinely needed for a user-visible best-effort operation, first
preserve cancellation with
`error if @async.is_being_cancelled() => raise error`. If cancellation itself
should be swallowed, discuss that behavior with the user before doing it.

## Cancellation-safe cleanup

Cancellation is delivered as a raised error at suspension points, so
`defer`/`catch` blocks do run on cancellation — but any **async operation
inside the cleanup** is itself cancelled immediately while the task is being
cancelled. Must-complete async cleanup (terminal-state restore,
external-resource release) needs `@async.protect_from_cancel` or
`TaskGroup::add_defer` with the same protection inside. Refinements from
production review:

- In practice, protect only the cancelled path and leave the normal path
  cancellable — otherwise `with_timeout` over the whole operation can no
  longer abort it. **Know that this is a compromise, not the ideal**: if
  cancellation arrives while the normal-path cleanup is already running, that
  cleanup still gets cancelled. The ideal semantics for best-effort cleanup
  would protect the cleanup on both paths, with (1) no hard timeout when the
  task is not cancelled, (2) on cancellation mid-cleanup, the cleanup keeps
  running but its already-elapsed time counts against the hard-timeout
  budget, and (3) cleanup errors propagating directly. That cannot be
  implemented correctly in user space today (it needs runtime support), which
  is why the cancelled-path-only compromise stands.
- Bound the protected (cancelled-path) section with its own hard timeout.
- If the cleanup's timeout fires during error propagation, catch **only** the
  cleanup timeout and re-raise the original body error — otherwise the cleanup
  `TimeoutError` masks the real failure.

(`defer` semantics and syntax: `control-flow.md`.)

## Spawning subprocesses (`@process`)

Default to `@process.run(...)` (runs to completion) or
`@process.spawn(group, ...)` (returns a `Process` bound to a task group — the
group waits on / reaps / can cancel it). These keep the child's lifetime tied to
a scope you control.

**Never reach for `@process.spawn_orphan` on your own.** It detaches the child
from every task group: the parent does not wait or reap it, and it outlives the
scope — exactly the "orphaned child keeps running after the host exits" failure
mode. Use it only when the user has **explicitly asked for or confirmed** a
detached/daemon process; otherwise use `spawn` with a task group so shutdown and
cancellation stay well-defined.

## Pipeline backpressure and shutdown

Between reader/writer tasks use **bounded** queues — an `Unbounded` inbound
queue silently removes socket backpressure and can OOM the process. Forced
shutdown must clear both queues (stale frames leak across reconnects), and
verify loop tasks actually park/exit after their channel closes — don't assume
`exit` alone stops a busy loop.
