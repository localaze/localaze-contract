# The SDK runtime contract

One specification, three implementations. Dart, Swift and Kotlin implement exactly what is written here, and `LZ-54` guarantees they behave identically. A behaviour that exists in one package and not the others is a defect, even when the odd one out is better.

Everything here is exercised by `fixtures/` and enumerated in `conformance.json`.

Sources: `LZ-58` (fetch, cache, offline), `LZ-59` (the resolved payload), `LZ-62` (what major, minor and patch mean), `LZ-65` (catalogs, updates, policy).

---

## 1. The three artifacts

An integrated app holds three things, and they change on different clocks. Keeping them separate is the whole design.

| Artifact | Contents | Written by | Changes when |
|---|---|---|---|
| **The package** | Config, store, updater, policy, signature check, renderer | Hand, in this folder | The runtime changes |
| **Generated source** | Typed accessors, compiled plural rules, the signature, the version generated from | The platform, per app | The **contract** changes |
| **Catalogs** | The text, one file per language | The platform, per app | The **wording** changes |

Wording changes most often, so wording must be the thing that ships without regenerating or rebuilding. That is the property the whole contract protects.

---

## 2. Catalog format

A catalog is one language's messages in the resolved shape of `LZ-59`. **It contains no MF2 syntax.** A device walks parts and concatenates; it never parses.

A catalog file is **byte-identical in shape to the read API's response body**, so a bundled asset and a fetched payload go through one parser and one code path. Do not invent a second envelope for bundled files.

```json
{
  "environment": "production",
  "version": "1.0.0",
  "pinned": false,
  "language": "ru",
  "count": 3,
  "messages": { "<key>": { /* resolved message */ } }
}
```

Only `version` and `messages` are required by the runtime. The rest is context, and an unknown field is ignored rather than rejected — a newer server must not break an older SDK.

### A resolved message

```json
{
  "selectors": ["count"],
  "params": [{ "name": "count", "type": "NUMBER" }],
  "variants": {
    "one":  [{"text": "У вас "}, {"var": "count", "type": "NUMBER"}, {"text": " сообщение"}],
    "few":  [{"text": "У вас "}, {"var": "count", "type": "NUMBER"}, {"text": " сообщения"}],
    "many": [{"text": "У вас "}, {"var": "count", "type": "NUMBER"}, {"text": " сообщений"}],
    "*":    [{"text": "У вас "}, {"var": "count", "type": "NUMBER"}, {"text": " сообщения"}]
  }
}
```

- `selectors` — parameters the message selects on. **Empty for a simple message**, never absent.
- `params` — every parameter, with its type. `STRING`, `NUMBER` or `DATETIME`. The set is deliberately small and is not to be widened per platform.
- `variants` — variant category to an ordered list of parts. A message with no selection has the single key `*`.
- A part is **either** `{"text": ...}` **or** `{"var": ..., "type": ...}`. Never both. Null fields are omitted by the server, so absence is meaningful and a part with neither field is malformed.

`*` is guaranteed present on every message by `LZ-07`. The runtime relies on that: a variant category missing from a fetched message **falls back to `*`** rather than failing.

---

## 3. Rendering

To render a key with arguments:

1. If `selectors` is empty, take `variants["*"]`.
2. Otherwise resolve the selector's value to a plural category using the **generated** rules — compiled into the source at build time, never shipped in the payload and never derived from CLDR data on device.
3. Look up that category in `variants`. **If absent, fall back to `*`.**
4. Walk the parts in order. Emit `text` as-is; for `var`, substitute the argument by name.
5. Concatenate.

That is the entire algorithm. If an implementation needs more than this, the payload is wrong, not the implementation.

### Substituting each type

| Type | Rendered as |
|---|---|
| `STRING` | The value, unchanged |
| `NUMBER` | The platform's default integer or decimal rendering |
| `DATETIME` | **ISO-8601, UTC**, unless the app supplies a formatter |

**The default date rendering is deliberate and worth arguing with.** Locale-aware date formatting is what an app usually wants, but Dart, Swift and Kotlin do not agree on the output for a given locale — Foundation's rules are its own — so making it the default would break the one guarantee these SDKs exist to make. ISO-8601 in UTC is identical on all three and therefore testable. An app that wants a local format supplies `dateFormatter` in config, and accepts that it now owns the difference.

A missing argument is a compile error, because the accessor requires it. There is no runtime path for one.

---

## 4. The signature

What the generated code promises its call sites. Emitted into the generated source, never fetched.

```json
{
  "auth.sign_out": [],
  "auth.welcome":  [{ "name": "name",  "type": "STRING" }],
  "inbox.unread":  [{ "name": "count", "type": "NUMBER" }]
}
```

**Names and types, not names alone.** Checking names only is the bug in the current implementation, and it misses the likelier edit: `{$count}` becoming `{$count :number}` leaves the key and the parameter name intact while changing what every call site passes. The compiler already promised `itemCount(count: Int)`; a catalog that retyped it would make that promise false.

### The compatibility check

A catalog is compatible when, for every key in the signature:

- the key is **present** in the catalog, and
- for every parameter in the signature, the catalog's message declares a parameter with the **same name and the same type**.

Otherwise it is incompatible, and:

- **A catalog is refused whole, never merged.** Half an update means some screens render content the compiler never checked.
- **Keys added since generation are ignored, not refused.** The app has no accessor for them, and a newer platform release is not a client failure.
- **Extra parameters on a present key are ignored.** The signature is a floor, not an equality.
- The refusal is reported through `onDiagnostic`, naming every key and reason.

---

## 5. The update policy

Policy is about **intent** — "we do not want minor updates in this build". The signature check is about **possibility**. Policy is consulted first because it is cheaper; the signature is checked before anything is written to disk.

| Policy | Accepts |
|---|---|
| `none` | Nothing |
| `patchOnly` | Same major, same minor, greater patch |
| `minorAndPatch` | **Default.** Same major, greater version |
| range | Same major, and within the app's stated bounds |

Rules that hold under every policy, including a range:

- **A different major is refused.** `LZ-62` defines major as signature-breaking by construction, so its messages no longer take the parameters generated call sites pass. That is not a stale screen, it is a wrong one.
- A version **older** than the one held is refused. Downgrade is not an update.
- A refused update leaves the previous catalog in place.

**The version the app already holds is `upToDate`, not a refusal.** Nothing was refused; the server and the app agree. Reporting it as `refusedByPolicy` reads, in a log and in a UI, as though the policy blocked something — which sends whoever is debugging to the wrong setting. This case is by far the most common outcome in production, so it is the one whose wording matters most.

Versions compare numerically field by field, not as strings: `1.10.0` is greater than `1.9.0`. A malformed version compares as refused.

`LZ-62` guarantees a release marked minor or patch can never be signature-incompatible. The runtime checks anyway. That is belt and braces, and the diagnostic distinguishes them — a signature failure on a minor release is a platform bug worth hearing about.

---

## 6. Fetching

| Call | Endpoint | Purpose |
|---|---|---|
| `currentVersion()` | `GET /api/v1/read/version` | What the key serves now. No translations, cheap enough for every launch. **A non-200 here is reported with its status**, exactly as on the translations path — a 401 is a wrong key, and without the status it is indistinguishable from a quiet network |
| `fetchIfAccepted(language)` | `GET /api/v1/read/translations/{lang}?format=resolved` | One catalog |
| pinned | `…&version=x.y.z` | A release that cannot move underneath a build |

- Authenticated with `X-Localaze-Key`. The key carries the project and the environment, so neither is a parameter and a staging build cannot read production.
- **`If-None-Match` is sent** with the ETag held from the previous fetch. A `304` means keep what we have, and is a success, not a failure. The server's ETag is version-scoped, so a pinned version's tag never changes and a rollback returns the earlier tag rather than inventing a new one.
- The order is: policy, then version check, then download, then signature check, then persist. Nothing is written before the signature passes.
- **Fetching never blocks a screen.** The app renders from what it has; a new catalog applies when told to, or on next launch, per `applyImmediately`.

---

## 7. Where content comes from

Resolution order per key, highest first:

1. The **applied** catalog, if one was fetched and accepted this session.
2. The **cached** catalog from a previous run, if readable.
3. The **bundled** asset shipped with the app.
4. The **compiled-in** copy in the generated source.

**Per key, not per catalog.** A partial or stale catalog degrades key by key rather than wholly, so one missing key does not cost an app every string it has.

Level 4 is duplication and it earns its place. Without it, the first launch of a fresh install with no network has no text at all, and a mistyped `assetPath` is a blank screen rather than a stale one. It is the floor, and it is why the asset path can safely be configurable.

A cached catalog persists across launches and survives app upgrade. On upgrade the signature check runs again, because the generated code may now promise something the cached catalog does not have.

---

## 8. Failure

**No public API throws, returns a failed future, or propagates an error.** Every failure leaves the app on the content it already had, and returns a value saying so.

| Failure | Result |
|---|---|
| Network unreachable, timeout, non-200 | Keep current content |
| Malformed JSON, missing `messages` | Keep current content |
| Unreadable or corrupt cache | Ignore the cache, fall through to bundled |
| Missing or unreadable asset | Fall through to the compiled-in copy |
| Refused by policy | Keep current content |
| Refused by signature | Keep current content, nothing written |
| A part with neither `text` nor `var` | Skip the part, render the rest |
| A variant category absent | Fall back to `*` |

The reason is proportion: a translation outage is a stale screen, while an SDK that throws turns it into a crash.

The cost is that silence hides genuine misconfiguration — a wrong API key looks exactly like a quiet network. So:

- Every swallowed failure calls `onDiagnostic` with a message naming what failed and why.
- **A throwing `onDiagnostic` is caught too.** A broken diagnostic must not take the app with it.
- `onDiagnostic` defaults to nothing. Silence is the default and not the only option.
- Last-fetch status is readable, so an app can report it rather than guess.

---

## 9. Configuration

Every option has a working default except the key. An app constructed with only a key behaves sensibly.

| Option | Default |
|---|---|
| `apiKey` | **Required** |
| `baseUrl` | `https://localize.sharpy.dev` |
| `assetPath` | Platform default, documented per package |
| `cacheDirectory` | Platform default; when unset, updates last for the session only |
| `policy` | `minorAndPatch` |
| `timeout` | 10 seconds |
| `applyImmediately` | `false` — a new catalog takes effect on next launch |
| `dateFormatter` | ISO-8601 UTC (§3) |
| `onDiagnostic` | Nothing |

`applyImmediately` defaults to off because text changing under a user mid-session is worse than text being a launch out of date.

---

## 10. Platform abstraction

Transport and storage are interfaces, injected, never reached for from core logic.

- No `dart:io` in the Dart core. It breaks Flutter Web, and it is why the current runtime cannot be unit tested.
- Each package ships a default implementation for its platform; tests substitute a fake.

A runtime testable only against a live server is a runtime that is not tested. Every row in the failure table above is reachable with a fake and unreachable without one.

---

## 11. Naming

Shape is identical; spelling is native. The same key produces the same accessor name on all three platforms, or a developer moving between them has to relearn the API.

| Concept | Dart | Swift | Kotlin |
|---|---|---|---|
| Accessor for `inbox.unread` | `inboxUnread(count: 3)` | `inboxUnread(count: 3)` | `inboxUnread(count = 3)` |
| Config | `LocalazeConfig` | `LocalazeConfig` | `LocalazeConfig` |
| Policy value | `LocalazeUpdatePolicy.minorAndPatch` | `.minorAndPatch` | `LocalazeUpdatePolicy.MINOR_AND_PATCH` |
| Files | `snake_case.dart` | `PascalCase.swift` | `PascalCase.kt` |

Key to accessor: split on `.` and `_`, lower-camel the result. `auth.sign_out` becomes `authSignOut`.

---

## 12. Fixtures

`fixtures/` holds one fixture project — `Postbox`, source `az`, languages `az` and `ru` — and is the single input all three packages are tested against. `conformance.json` enumerates the cases.

The fixture is currently duplicated in Java, in `GeneratorConformanceTest.java`. **Phase 4 points that test at these files**, so there is one fixture rather than two that drift. Until then, a change here must be mirrored there.

The Azerbaijani plural variants `one` and `*` carry identical text. That is correct, not an oversight — Azerbaijani does not inflect the noun after a numeral — and it is why the Russian message carries the selection assertions.
