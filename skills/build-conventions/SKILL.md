---
name: build-conventions
description: "The inner loop's Generate step — which Laravel primitive a slice's requirement maps to, and which shortcut to refuse. Covers validation, authorization, response shape, mass assignment, config, transactions, and queue dispatch, each with the antipattern it replaces and the one-line reason. Use before writing the first line of a slice, when choosing between two ways to express a requirement, when a slice adds a route, model, or job, or when the codebase already does the opposite of the convention."
---

# Build Conventions

Step 3 of the inner loop. `laravel-validate` checks the work afterwards; this decides what to write in the first place.

**One rule outranks every table below: match the codebase.** A file that already does it the other way is a convention decision someone made, and a slice is the wrong place to relitigate it. Follow the local pattern and put one line in `FLAGS` saying you did. Consistency inside a file beats correctness imported from a cookbook — and a diff that half-converts a file is worse than either.

## Requirement → primitive

The mapping most slices need. Left column is what the slice asks for; right is what to reach for before considering anything else.

| The slice needs | Reach for | Refuse |
|---|---|---|
| Input checked before it is used | Form Request | `$request->validate()` inline in a controller |
| A rule about *who* may do this | Policy + `authorize()` | An `if ($user->id === $model->user_id)` in the action |
| Data returned to a client | API Resource | Returning a model or `->toArray()` directly |
| A field the client may set | Explicit `$fillable` | `Model::create($request->all())` |
| A value that varies by environment | `config('x.y')` + a config file | `env()` anywhere outside `config/` |
| Two or more rows written together | `DB::transaction()` | Sequential writes and hope |
| Work that can happen later | Queued job | Doing it in the request cycle |
| A job dispatched inside a transaction | `->afterCommit()` | Bare `dispatch()` — the worker can beat the commit |
| Domain logic more than a few lines | Action class, single `handle()` | A controller method that grew |
| A URL, anywhere | `route()` / typed route helper | A hardcoded string |
| A new file of any kind | `php artisan make:* --no-interaction` | Hand-writing the skeleton |

Every "refuse" column entry is something `loop-verify` looks for. Shipping one costs a FAIL and a re-brief, which is more expensive than the thirty seconds the shortcut saved.

## The reasons that change behaviour

Skip the ones you already believe; these three are the ones people get wrong under time pressure.

**`env()` outside `config/` is not a style preference.** Once `config:cache` runs — and it runs on every production deploy — `env()` returns `null`. The bug does not appear in local, in CI, or in staging if staging skips the cache step. It appears in production, as a null, in whatever code path was least tested.

**Mass assignment is an authorization hole, not a tidiness issue.** `Model::create($request->all())` lets a caller set any fillable column, including the ones your Policy is guarding. A Form Request narrows the input *before* the model sees it; `$fillable` is the second line, not the first.

**`->afterCommit()` matters more than it looks.** A job dispatched inside `DB::transaction()` can be picked up by a worker before the transaction commits, and then it reads rows that do not exist yet. It fails intermittently, under load, in a way that never reproduces locally.

## Per-slice checklist

Before the first edit, answer these four. Each has a wrong answer that produces a predictable `loop-verify` finding:

1. **Does this slice add or change a route?** → It needs a Policy or an explicit, stated reason it does not.
2. **Does it accept input?** → Form Request, and the failure modes from the spec are validation rules, not afterthoughts.
3. **Does it return data to a client?** → API Resource, with the field list decided rather than inherited from the model.
4. **Does it write more than one row?** → Transaction, and any job dispatched inside it is `afterCommit`.

## New files

`php artisan make:*` with `--no-interaction`, always. Not because hand-writing is forbidden, but because generated scaffolding matches the framework version actually installed — namespaces, base classes, and stubs drift between majors, and your recollection of Laravel 11's stub is not evidence about Laravel 13's.

`make:model` on a new model creates the factory and seeder too. A model with no factory makes the slice's test harder to write, which is how a slice ends up with a weaker test than it named at G1.

## Consult the docs before writing

Version-specific documentation first — Laravel Boost's `search-docs` when the project has it, the installed version's docs otherwise. Training data is stale on anything that moves, and a confidently wrong API call costs a full refine pass to discover.

Worth a lookup every time: anything in the first-party packages (Fortify, Sanctum, Cashier, Scout, Horizon), anything added or renamed in the last two majors, and any signature you are recalling rather than reading.

## Style

`declare(strict_types=1)` in every new PHP file. Explicit param and return types on every method. Constructor property promotion. Curly braces always, including single-line bodies. Typed exceptions extending a framework or project base — a bare `\Exception` is a `loop-verify` finding. Structured logging: `Log::info('event.name', [...])`, lowercase dot notation, no string interpolation.

Run `vendor/bin/pint --dirty --format agent` before returning. Never `--test` — you have write access, so fix it and move on.

## When the convention and the slice disagree

The envelope wins on scope; the codebase wins on style; the spec wins on behaviour.

If following a convention here would require touching a file on the slice's `Do NOT` list, that is a **slice defect** — return `blocked` and say which convention and which file. Do not quietly widen the slice to do it properly, and do not quietly do it badly to stay inside the lines. Both hide a decision that belongs to a human at G1.
