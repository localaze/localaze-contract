# The SDK generator contract

One specification, three generators. Each SDK package ships a command that turns a published release into the **generated source** and the **catalogs** of `runtime-contract.md` §1. Dart, Swift and Kotlin implement exactly what is written here, and `LZ-54` guarantees the generated code behaves identically on all three.

Generation runs on a developer machine or in CI, never on a device. It is the only place in this folder that touches the network and the filesystem directly, which is why each generator is a separate entry point from its package's core.

Sources: `LZ-53` (the manifest), `LZ-54` (type safety and required translations), `LZ-55`–`LZ-57` (per platform), `LZ-65` (catalogs).

---

## 1. Why the generators live in the SDKs

The server serves data, not source. It publishes a typed manifest and resolved catalogs; each package turns them into code for its own platform.

- A generated file and the runtime it calls are versioned together. A generator change ships as a package upgrade, not as a server deploy that silently changes every app's next build.
- The backend stays free of three code templates in three languages it does not compile.
- The cost is three generators instead of one, which drift unless tested. §9 is how they are kept identical.

---

## 2. The command

The same options on every platform. Spelling is native — Dart `dart run localaze:generate`, Swift `swift run localaze-generate`, Kotlin `java -jar localaze-generator.jar` — and the options are identical.

| Option | Meaning |
|---|---|
| `--key` | Integration key. Carries the project and the environment, so neither is an option |
| `--version` | Release to generate from. **A build should pin it.** Omitted means the environment's live release |
| `--base-url` | Default `https://localize.sharpy.dev` |
| `--out` | The generated source file to write |
| `--assets` | Directory the catalogs are written into, one `<language>.json` each |
| `--allow-gaps` | Generate even when a translation is missing. For early development only |
| `--manifest`, `--catalogs` | Read a manifest file and a directory of catalogs instead of the server. For tests and offline builds. Replaces `--key`, `--version` and `--base-url` |
| `--package` | Kotlin only: the package of the generated file |

Exit code `0` on success. On failure, exit `1` and print **every** problem, not the first — a team fixes them in one pass rather than one build at a time. A generator never leaves a half-written output: everything is checked before anything is written.

---

## 3. Inputs

### Online

1. `GET /api/v1/read/manifest?version=…&strict=…` with `X-Localaze-Key`. `strict` is `false` only under `--allow-gaps`.
2. For each language in the manifest, `GET /api/v1/read/translations/{language}?format=resolved&version={manifest.version}`.

Step 2 always pins to the version the manifest returned, **even when the caller did not pin**. A release published between the two requests would otherwise give a manifest from one version and catalogs from another.

A non-200 is a failure, printed with its status and the server's problem `detail`. A `422` from the manifest prints each entry of `gaps`.

### Offline

`--manifest <file>` and `--catalogs <dir>`, where the directory holds `<language>.json` for every language the manifest names. The files are in exactly the shapes the two endpoints return, so a build can save a server response and replay it.

---

## 4. Checks

Generation fails, naming each problem, when:

| Check | Why |
|---|---|
| A language in the manifest has no catalog | Required translations (`LZ-54`) |
| A catalog lacks a key the manifest names | Required translations. Waived by `--allow-gaps` |
| A catalog's `version` differs from the manifest's | The code and the text would describe different releases |
| A plural rule uses an operand other than `n`, `i` or `v` | §7 declares only those three. Failing is better than generating code that does not compile |
| A plural rule contains anything but those operands, integers, whitespace, parentheses and the operators of §7 | The condition is pasted into source. Anything else is either a server bug or an injection, and neither should compile |
| A message selects on a parameter that is not `NUMBER` | The runtime resolves plural categories only. A selection on a string would silently render the catch-all every time |
| Two keys produce the same accessor name | One would silently shadow the other |
| An accessor name collides with a generated member (§5) | The same |
| A key or parameter produces an empty identifier, one starting with a digit, or one with a character outside ASCII letters and digits | It cannot be compiled on every platform |
| Two parameters of one message produce the same identifier | The accessor could not declare both |

The server's strict manifest has already checked parameter types across languages. The generator does not repeat that check.

---

## 5. The generated source

One file, in this order. Every platform emits the same sections with the same contents.

1. **Header.** `GENERATED BY LOCALAZE — DO NOT EDIT`, the environment, the version, the content hash and the source language. **No timestamp**, so regenerating unchanged input produces a byte-identical file and a clean diff.
2. **The type**, named `Localaze`, holding the runtime and these members:
   - `supportedLocales` — the manifest's languages, in its order
   - `sourceLocale`
   - `generatedFrom` — the manifest version, which the update policy compares against
   - `contentHash`
   - `forLocale(locale, config)` — builds the runtime with the signature, the plural resolver and the compiled-in catalog for `locale`, falling back to the source language's
   - `runtime` — exposed so the app can reach the update machinery

   Those names are reserved, and so are `hashCode`, `toString`, `equals`, `runtimeType` and `noSuchMethod`, which a base type already has on at least one platform. A key whose accessor would take one fails generation on **every** platform, so a key set that generates for Dart also generates for Swift and Kotlin.
3. **One accessor per key**, in manifest order (§6).
4. **The signature** — every key with its parameter names and types, from the manifest.
5. **Plural rules** (§7).
6. **Compiled-in catalogs** — each language's catalog, embedded as an escaped string literal, byte-for-byte what was written to `--assets`. This is resolution level 4 of `runtime-contract.md` §7.

Every accessor gets a documentation comment previewing the source-language text: the `*` variant, text parts verbatim and variables as `{$name}`, with newlines turned into spaces and cut at 80 characters.

### Catalogs

`--assets/<language>.json`, byte-identical to the translations response body. A bundled asset and a fetched update therefore go through one parser, as `runtime-contract.md` §2 requires.

---

## 6. Accessors

**Name.** Split the key on `.`, `_` and `-`, drop empty segments, lower-camel the rest: `auth.sign_out` → `authSignOut`. The same rule names parameters: `user_name` → `userName`. The argument map passes the **original** name to the runtime, so the catalog is never affected by the spelling.

A name reserved by the target language is escaped the way that language escapes it: backticks in Swift and Kotlin. Dart has no escape, so the name takes a trailing underscore: `in` → `in_`. That is the one place call sites differ, and only for a name no team would choose.

**Shape.** A key with no parameters is a property, not a call. A key with parameters is a function taking each one, named and required, in manifest order. A key that selects passes its selector's value to the runtime as the plural selector. The selector is the first entry of `selectors` in the source language's catalog message, since the manifest says only that a message selects.

The accessor reaches the runtime through `this` or `self` explicitly, so a parameter named `runtime` cannot shadow it.

**Types.**

| Manifest | Dart | Swift | Kotlin |
|---|---|---|---|
| `STRING` | `String` | `String` | `String` |
| `NUMBER` | `num` | `some LocalazeNumber` | `Number` |
| `DATETIME` | `DateTime` | `Date` | `java.time.Instant` |

`NUMBER` takes integers and decimals on every platform, because a manifest cannot say which a message expects. Swift has no common numeric supertype, so the runtime package declares `LocalazeNumber`, adopted by the standard integer and floating-point types.

---

## 7. Plural rules

The manifest's `pluralRules` carries each language's categories as conditions over three CLDR operands, already compiled by the server. The generator does not compile CLDR. It declares the operands, translates the condition's syntax where a platform needs it, and emits one resolver per language.

**Operands**, from the selector value `x`:

| Operand | Meaning | Declared as |
|---|---|---|
| `n` | `|x|` | the floating-point absolute value |
| `i` | the integer part of `n` | an integer |
| `v` | `0` when `x` is integral, otherwise `1` | an integer |

`v` is an approximation. CLDR's `v` counts visible fraction digits, which a number type does not carry — `1.0` and `1` are the same `Double`. It is the same approximation on all three platforms, which is the property that matters.

**Guard.** A non-finite value, or one with `n ≥ 10^15`, resolves to no category, and the runtime renders the catch-all. That keeps every platform's integer conversion in range and keeps the result identical.

**Declare only what is used.** An operand the conditions do not mention is not declared, so a generated file reports no warnings. A file that reports warnings is one a team excludes from analysis.

**Translation per platform.** The server's syntax — `==`, `!=`, `>=`, `<=`, `%`, `&&`, `||`, `!` and parentheses — is valid as written in Dart. Two platforms need one rewrite each:

| Platform | Rewrite | Why |
|---|---|---|
| Swift | `(n % k)` → `n.truncatingRemainder(dividingBy: k)` | Swift has no `%` on floating-point values |
| Kotlin | every integer literal `k` → `k.0`, with `i` and `v` declared as `Double` | Kotlin will not compare a `Double` or a `Long` with an `Int` literal |

**Resolver.** `plural(locale, value)` dispatches to one function per language. Each returns the first category whose condition holds, and no category otherwise. Categories are tested in the manifest's order. CLDR categories are mutually exclusive, so the order does not change the result.

---

## 8. Determinism

The same manifest and catalogs produce byte-identical output on every run and every machine. Keys follow the manifest's order, languages follow the manifest's order, and plural categories follow the manifest's order. No timestamp, no absolute path, no machine name.

That is what lets the generated file be checked in and reviewed, and what makes the golden-file tests in §9 possible.

---

## 9. Conformance

Every generator is tested against `fixtures/manifest.json` and `fixtures/catalogs/`:

- **Golden.** The output for the fixtures is checked in to each package. A test regenerates it and asserts the result is byte-identical. A change to generator output is therefore a reviewed diff, never an accident.
- **Behaviour.** The checked-in output is compiled against the package and renders every row of `fixtures/expected-renders.json`. That is the `LZ-54` guarantee: the three generators agree because their output renders the same strings, not because their source looks alike.
- **Failure.** Each row of §4 has a test asserting the generator exits non-zero, names the problem, and writes nothing.

The cases are enumerated in `conformance.json` under the group `generator`.
