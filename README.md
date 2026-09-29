# LarzFlow

A DAG/workflow orchestration engine for [Larzscript](https://github.com/larz-scripter/larzscript): define steps with dependencies, run them in topological order, gate specific steps on a money budget using Larzscript's own money-native type, and inspect a run after the fact from a persisted JSON state file.

`larz-scripter/larzscript-packages` already has excellent, independent packages for a job queue (`task`), a cron scheduler (`cron`), retry/circuit-breaking (`retry`), an FSM (`fsm`), pub/sub (`bus`) and category-based spend tracking (`budget`). LarzFlow doesn't reimplement any of that - it composes `cron`, `retry` and `budget`, and fills the one piece none of them cover: tying individual steps into a **graph** with dependencies, running that graph, and persisting the result.

## Install

You need the [Larzscript](https://github.com/larz-scripter/larzscript) interpreter and the `cron`, `retry`, `budget`, `fs`, `json`, `uuid` and `random` packages:

```
curl -fsSL https://raw.githubusercontent.com/larz-scripter/larzscript/main/install.sh | sh
mkdir -p ~/.larzscript/lib
for pkg in cron retry budget fs json uuid random; do
  curl -fsSL "https://raw.githubusercontent.com/larz-scripter/larzscript-packages/master/packages/$pkg/main.lz" -o ~/.larzscript/lib/"$pkg".lz
done
```

## Quickstart

A workflow is a plain `.lz` file that builds a dag and exports it as a top-level `let workflow = ...` - the CLI loads it the same way any Larzscript module import works, just with the file path taken from the command line instead of a literal:

```larzscript
# examples/linear.lz
import "../lib/dag" as dag

let workflow = dag.new("etl-linear")

dag.step(workflow, "fetch", fn() {
  print("fetching source data...")
  return "raw-data(42 rows)"
})

dag.step(workflow, "transform", fn() {
  print("transforming...")
  return "clean-data(42 rows)"
}, {"depends_on": ["fetch"]})

dag.step(workflow, "load", fn() {
  print("loading into warehouse...")
  return "loaded 42 rows"
}, {"depends_on": ["transform"]})
```

```
$ larzscript bin/larzflow.lz validate examples/linear.lz
ok: 3 step(s), run order: fetch -> transform -> load

$ larzscript bin/larzflow.lz run examples/linear.lz readme-demo /tmp/readme-runs
fetching source data...
transforming...
loading into warehouse...
run readme-demo (etl-linear)
  [ok]   fetch (0s)
  [ok]   transform (0s)
  [ok]   load (0s)

$ larzscript bin/larzflow.lz status readme-demo /tmp/readme-runs
run readme-demo (etl-linear)
  [ok]   fetch (0s)
  [ok]   transform (0s)
  [ok]   load (0s)
```

`status` re-reads the JSON state file `run` wrote after every single step - not just at the end - so a crash mid-run still leaves a readable partial record.

## A failing branch doesn't take down the whole run

`examples/failing.lz` makes `transform` throw (with a retry configured, so it's retried once before giving up). `report`, which depends on `transform`, is correctly marked `skipped` rather than silently running on bad data - but `notify`, which has no dependency on that branch, still runs:

```
$ larzscript bin/larzflow.lz run examples/failing.lz readme-fail /tmp/readme-runs
fetching source data...
notifying on-call (unrelated to the fetch/transform/report branch)...
run readme-fail (etl-with-failure)
  [ok]   fetch (0s)
  [fail] transform: LarzValueError: malformed row 17: missing 'id' field (line 18) (line 25)
  [skip] report (dependency 'transform' did not complete)
  [ok]   notify (0s)
```

## Budget-gated steps (the money-native part)

A step can be gated on a spending category from the `budget` package. The gate is checked *before* the step runs; if it would push the category over its limit, the step fails with a clear `BudgetExceededError` instead of running (and instead of the native `paywall`/`subscribe`/`has` keywords - see [Limitations](#limitations) for why):

```larzscript
# examples/budget_gate.lz
import "../lib/dag" as dag
import "budget" as budget

let b = budget.new()
budget.set_limit(b, "api_calls", $1.00)

let workflow = dag.new("budget-gated")

dag.step(workflow, "cheap_call", fn() { ... },
  {"budget_gate": {"budget": b, "category": "api_calls", "cost": $0.60}})

dag.step(workflow, "pricey_call", fn() { ... },
  {"depends_on": ["cheap_call"],
   "budget_gate": {"budget": b, "category": "api_calls", "cost": $0.70}})
```

```
$ larzscript bin/larzflow.lz run examples/budget_gate.lz readme-budget /tmp/readme-runs
calling the cheap endpoint...
run readme-budget (budget-gated)
  [ok]   cheap_call (0s)
  [fail] pricey_call: BudgetExceededError: budget gate blocked step: category 'api_calls' has $0.40 remaining of a $1.00 limit, step costs $0.70 (line 40)
```

`cheap_call` spent `$0.60` of the `$1.00` limit; `pricey_call`'s `$0.70` would have pushed the category to `$1.30`, so it's blocked before it ever runs, and the recorded spend stays at `$0.60`.

## A bad graph is rejected before anything runs

```
$ larzscript bin/larzflow.lz validate tests/data/cyclic.lz
LarzValueError: cycle detected: x -> y -> x (line 60)

$ larzscript bin/larzflow.lz validate tests/data/undefined_dep.lz
LarzValueError: step 'a' depends on undefined step 'nope' (line 50)
```

## Modules

| Module | What it does |
| --- | --- |
| `lib/dag.lz` | Define steps with `depends_on`/`retry`/`budget_gate` options; `validate()` does cycle detection + undefined-dependency checking via a 3-color DFS topological sort. |
| `lib/executor.lz` | Runs a validated dag in topological order; skips a step's transitive dependents once it fails for good; persists JSON state after every step. |
| `lib/budgetgate.lz` | Thin `check()`/`record()` wrapper around the `budget` package - the money-native differentiator. |
| `lib/schedule.lz` | Trigger a dag on a cron expression, composing the `cron` package's scheduler with `executor.run()`. |
| `lib/report.lz` | Render a dag's graph or a run's state as text or JSON. |
| `bin/larzflow.lz` | CLI: `validate`, `run`, `status`. |

## Limitations

- **No true concurrency.** Larzscript is a single-threaded interpreter, so "parallel" branches of a DAG still execute sequentially - the real thing this project gives you is that one branch's failure doesn't block unrelated branches from still running, not that they run at the same time.
- **No daemon.** `lib/schedule.lz` is a foreground loop (`schedule.run_forever()`) that calls `cron.tick()` and sleeps between passes - the same honest framing the `cron` package's own docs use. Run it under systemd/cron/a process supervisor if you need it to survive a restart.
- **State persistence is JSON files, not a database.** `.larzflow/runs/<run_id>.json` by default. Fine for inspecting a run after the fact; not a query engine.
- **The budget gate deliberately does not use the native `paywall`/`subscribe`/`has` keywords.** Those track subscription state by a wallet's *declared variable name* rather than its runtime identity, so two wallets created by the same factory function collide - a bug we filed as [larzscript#37](https://github.com/larz-scripter/larzscript/issues/37) after hitting it while designing this. `budgetgate.lz` builds on the `budget` package's plain dict-based spend tracking instead, which has no such issue.
- **A workflow file's own name can't collide with a package it imports.** We hit a real interpreter segfault (filed as [larzscript#38](https://github.com/larz-scripter/larzscript/issues/38)) from naming an example file `budget.lz` while it also did `import "budget"` - self-import recursion with no cycle guard. Our own `examples/budget_gate.lz` is named to avoid this; keep the same rule in mind for your own workflow files.
- Step results are stored in run state via `str(result)` - fine for inspecting what happened, not a typed return-value channel between steps (a step reads whatever it needs itself, e.g. from a shared closure variable, same as any other Larzscript function composition).

## Tests

```
sh tests/run_tests.sh
```

Covers: a fully successful run, a failing branch with correct skip propagation, the budget gate blocking and correctly *not* recording an over-limit spend, cycle/undefined-dependency rejection, and that a persisted run's state file is real, valid JSON, re-readable by `status` after the process that wrote it has exited.

## License

MIT, see [LICENSE](LICENSE).
