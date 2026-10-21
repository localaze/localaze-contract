# contract

Not a package. The one written specification the three SDKs implement, and the one fixture project they are all tested against.

| File | Contents |
|---|---|
| `runtime-contract.md` | **The runtime specification.** Catalog format, rendering, signature, update policy, fetching, resolution order, failure, configuration |
| `generator-contract.md` | **The generator specification.** The command, its inputs and checks, and the generated source every platform emits |
| `conformance.json` | Every case all three packages must pass, with the rule each one enforces |
| `fixtures/manifest.json` | The typed manifest for the fixture project, as `LZ-53` defines it |
| `fixtures/signature.json` | What the generated code promises — names **and** types |
| `fixtures/catalogs/` | The good catalogs, `az` and `ru`, at version `1.0.0` |
| `fixtures/expected-renders.json` | Exact output every package must produce |
| `fixtures/updates/` | Catalogs that exercise policy and signature refusal |
| `fixtures/bundled/` | A partial asset, for per-key fallback |

## The fixture project

`Postbox`, source language `az`, languages `az` and `ru`, held version `1.0.0`. Four keys, chosen to cover each parameter type and the one plural rule with a real exception in it:

| Key | Exercises |
|---|---|
| `auth.sign_out` | No parameters. A property, not a format call |
| `auth.welcome` | A `STRING` parameter |
| `billing.due` | A `DATETIME` parameter, and the ISO-8601 default |
| `inbox.unread` | A `NUMBER` selector, and plural selection in two languages |

Azerbaijani's `one` and `*` variants carry identical text. That is correct — Azerbaijani does not inflect the noun after a numeral — which is why Russian carries the selection assertions. Russian is also the reason the plural rule matters at all: `11` and `111` select `many` despite ending in `1`, and a rule that special-cases only a literal `11` gets `111` wrong.

## The update fixtures

Each one is a specific refusal or acceptance, not a variation for its own sake.

| File | Version | What it proves |
|---|---|---|
| `patch-1.0.1-ru.json` | `1.0.1` | Wording changed, signature identical. Accepted under `patchOnly` and above |
| `minor-1.1.0-ru.json` | `1.1.0` | Adds `settings.title`. An added key is ignored, not refused |
| `major-2.0.0-ru.json` | `2.0.0` | Drops `auth.sign_out`. Refused under **every** policy |
| `retyped-1.0.2-ru.json` | `1.0.2` | **The important one.** See below |
| `malformed-shape-ru.json` | `1.0.4` | Valid JSON, no `messages` |
| `malformed-syntax-ru.txt` | — | Not JSON at all |

### Why `retyped-1.0.2-ru.json` matters most

It is a **patch**, so the policy accepts it. Every key is present, so a key-set check accepts it. And `inbox.unread` still declares a parameter named `count`, so a name-only signature check accepts it too.

But the type changed from `NUMBER` to `STRING`, and the message stopped selecting. Generated code has already promised every call site `inboxUnread(count: Int)`. Applying this catalog makes that promise false.

The backend's Dart generator, since removed, emitted a signature of parameter names only, so the runtime it generated accepted this catalog. That was the defect. This fixture is the regression test for it.

## Keeping it single

These files are the only copy. The backend generators, and the Java copy of this fixture their tests carried, were removed when generation moved into the SDKs.

`manifest.json` was produced by the server's own plural rule compiler and hashing. The catalogs are hand-written to the shape `Mf2Resolver.resolve` produces. Nothing yet asserts that the checked-in files equal the server's output, so a change to either side of that boundary must be mirrored by hand.

## Adding a case

1. Write the rule in `runtime-contract.md` or `generator-contract.md` first.
2. Add the fixture it needs.
3. Add the case to `conformance.json`.
4. Implement it in **all three** packages.

A behaviour in one package and not the others is a defect, even when the odd one out is better. That is what `LZ-54` guarantees and what the suite is here to enforce.
