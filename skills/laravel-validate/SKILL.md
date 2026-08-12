---
name: laravel-validate
description: "The inner loop's Validate step for Laravel — detecting the project's runner and toolchain (Sail vs host, Pest vs PHPUnit, Pint, Larastan), the exact commands to run and in which order, how to read a failure into a next action, and the self-check every slice passes before it is returned. Use before returning any code change, when a test fails and the next move is unclear, or when setting up validation on an unfamiliar Laravel codebase."
---

# Laravel Validate

Step 4 of the inner loop. An agent that skips this returns claims instead of evidence.

## Detect first — one pass, then cache it in your head

Never assume the toolchain. Wrong assumptions here waste a whole refine pass on an error that was never about the code.

| Question | How to answer |
|---|---|
| Sail or host? | `vendor/bin/sail` **and** a `docker-compose.yml`/`compose.yaml` both present → Sail. The sail dependency alone (Herd/Valet shape) → host. |
| Pest or PHPUnit? | `pestphp/pest` in `composer.json` → Pest. Otherwise PHPUnit. |
| Static analysis? | `phpstan.neon` / `larastan` present → run it. Absent → skip, and say so in FLAGS rather than inventing a config. |
| Style? | `laravel/pint` → Pint. A `.php-cs-fixer.php` → that instead. |
| Frontend? | `package.json` scripts — run its lint/test only when the slice touched frontend files. |

Sail project → **every** command below is prefixed `./vendor/bin/sail`. A bare `php artisan` on a Sail project runs against the wrong PHP and the wrong database, and the resulting failure will look like a code bug.

## Order matters

Run cheapest-and-most-likely-to-be-noise first, so a formatting nit never masquerades as a logic failure.

```bash
# 1. Style — fix, never check. Seconds.
vendor/bin/pint --dirty --format agent

# 2. Static analysis — catches type and null errors before a test has to.
vendor/bin/phpstan analyse --memory-limit=2G

# 3. The slice's own test — filtered, not the whole suite.
php artisan test --compact --filter=<Name>

# 4. Full suite — ONCE, at the end of the unit of work, not per slice.
php artisan test --compact
```

`--test` on Pint is for CI, not for you. You have write access; use it and move on.

Filtered tests per slice, full suite once at integration. A full-suite rerun after every slice is the largest avoidable wall-clock cost in a multi-slice unit of work.

## Reading a failure into a next action

The point of validation is deciding what to do next, not producing a log.

| Failure | What it usually means | Next action |
|---|---|---|
| `Class not found` after `make:*` | Autoload stale | `composer dump-autoload`, retry once |
| `Target class does not exist` | Binding or namespace typo | Read the provider/route, do not regenerate |
| SQLSTATE, table missing | Test DB not migrated, or `RefreshDatabase` absent | Check the base TestCase trait, not the migration |
| Assertion on a null relation | Missing eager load, or factory did not create it | Fix the **factory or the test setup** — not the assertion |
| 403 in a feature test | Policy working as designed | Assert the denial too; do not remove the Policy |
| 419 | CSRF / session in test context | Check the test's HTTP helper, not the middleware |
| Passes alone, fails in suite | Shared state — order dependence, leaked fake, frozen time | Fix the leak; **never** mark the test skipped |
| PHPStan "always true/false" | Redundant check, or a wrong type hint | Read it — this one finds real bugs |

**"Passes alone, fails in suite" is never a reason to skip a test.** It is a leak, and a leak that survives will fail something else later at a worse moment.

## The self-check before returning

Every slice. All of it, not the parts that are convenient.

- [ ] Pint run and clean
- [ ] Static analysis clean, or genuinely absent from the project (said so in FLAGS)
- [ ] The slice's named test exists, runs, and **passes**
- [ ] That test **fails** against the pre-change code — a test that passes either way proves nothing. Verify by reasoning about it, or by stashing the change if cheap.
- [ ] Failure modes from the spec are covered, not only the happy path
- [ ] Authorization tested **both** ways — allowed and denied
- [ ] Nothing on the slice's `Do NOT` list was touched
- [ ] `VERIFIED` carries real command output counts, not the word "passing"

## Evidence format

```
VERIFIED: pint --dirty → 3 files fixed
          phpstan → no errors (level 8)
          test --filter=InvoiceTotals → 6 passed, 0 failed
```

Not: "all tests pass". That is the sentence an agent writes when it did not run them.

## What validation does not cover

Say so in FLAGS rather than implying coverage you do not have: performance under real data volume, behaviour against the production dataset's shape, anything needing a browser you did not run, and third-party integrations you faked. `Http::fake()` proves you call the API correctly — never that the API behaves as you assumed.
