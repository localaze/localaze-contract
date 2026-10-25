# Rules for the Localaze SDKs

Applies to every SDK repository in [github.com/localaze](https://github.com/localaze): `localaze-dart`, `localaze-swift` and `localaze-kotlin`. Each one includes this repository as a submodule at `contract/`, so these rules are at `contract/CLAUDE.md` in every checkout. Anything specific to one platform lives in that repository's own `CLAUDE.md`.

## Session behavior

- Present a plan and wait for approval when a change touches more than one file. Apply single-file fixes directly.
- After applying changes, list the files you touched and any point where you deviated from the plan. Nothing else.
- Do not scan the codebase looking for files. If you need a file that is not in context, ask for it. Opening a file at a path you already know, or listing a package's sources to see what exists, is not scanning.

## What these packages are

Three runtime libraries that consuming apps depend on, one per platform, each in a repository of its own. Each also ships the generator that produces an app's typed source from a published release.

| Repository | Platform | Published as |
|---|---|---|
| `localaze-dart` | Dart / Flutter | `localaze` and `localaze_flutter` |
| `localaze-swift` | Swift / iOS | the `Localaze` library and the `localaze-generate` executable |
| `localaze-kotlin` | Kotlin / Android | `dev.sharpy.localaze:localaze`, `localaze-generator` and `localaze-android` |

`localaze-contract`, this repository, is not a package. It holds the two written specifications all three implement — `runtime-contract.md` and `generator-contract.md` — the conformance cases, the fixture project they are all tested against, and the stub read API the example apps use.

They are **libraries, not applications**. Nothing here has a UI or a container. The only `main` is each package's generator, a command a developer or CI runs at build time, kept in its own entry point so the runtime core never sees it. A library ships to a package registry, not as an image.

## The division of labour

This is the whole design, and every rule below follows from it. Read `contract/runtime-contract.md` before writing runtime code.

Each package's generator produces **two** things per app, from the release it is pointed at, and they change on different clocks:

| | Contents | Changes when |
|---|---|---|
| **Generated source** | Typed accessors, compiled CLDR plural rules, the typed signature, the version generated from | The **contract** changes — a key added or removed, a parameter retyped |
| **Catalogs**, one per language | The text, in the resolved shape the read API serves | The **wording** changes |

The packages in this folder are the third thing, and they change on a clock of their own: they are hand-written, versioned and tested, and a consuming app upgrades them like any other dependency.

That separation is the point of the work. Wording is what changes most often, so it must be the thing that ships without regenerating or rebuilding. Fold the runtime back into the generated file and a fix to the fetch logic becomes a regeneration for every app that ever integrated.

**Never inline generated content into a package.** These packages contain no translations, no key names, and no project identifiers. They are generic. If a package needs to know a key, the generated code passes it in.

## Never throws

**No public API in these packages throws, returns a failed future, or propagates an error.** Not on network failure, not on a malformed payload, not on an unreadable cache, not on a missing asset, not on a refused signature. Each one leaves the app on the content it already had.

The reason is proportion. A translation outage is a stale screen; an SDK that throws turns it into a crash, which is far worse than yesterday's strings.

The cost is that silence hides genuine misconfiguration — a wrong API key looks exactly like a quiet network. So the diagnostic callback is not optional polish, it is how anyone finds out the integration never worked:

- Every swallowed failure calls `onDiagnostic` with a message naming what failed and why.
- A throwing `onDiagnostic` is caught too. A broken diagnostic must not take the app with it.
- `onDiagnostic` defaults to nothing, so silence is the default and not the only option.

Internal functions may throw. The rule is about the boundary.

## Identical across platforms

The three SDKs are promised to behave identically. That guarantee is only worth something if it is tested, so:

- Every behaviour goes in `contract/runtime-contract.md` **first**, then into three implementations.
- Every implementation is tested against the same fixture project in `contract/fixtures/`.
- A behaviour that exists in one package and not the others is a defect, even when the odd one out is better.

If a platform genuinely cannot do something the contract requires, change the contract for all three. Do not let one package drift and record it as a quirk — that is how a string renders differently on iOS than on Android, which is the failure the conformance suite exists to prevent.

Naming follows each platform's convention (`fetchIfAccepted` in Dart and Kotlin, `fetchIfAccepted()` in Swift; snake_case files in Dart, PascalCase in Swift and Kotlin). Shape is identical, spelling is native.

## No MF2 on the device

Catalogs arrive already parsed, as parts and variants. A device walks them and concatenates. **No package here parses MF2, and none carries CLDR data.** Plural rules arrive compiled into the generated source.

This is what keeps an MF2 runtime off the device — there is no maintained MF2 implementation for Dart or Swift, and this design means none is needed. A runtime MF2 parser anywhere in these packages reintroduces the exact problem codegen was built to remove.

## Platform abstraction

Transport and storage are **interfaces, injected**, never called directly from core logic.

- No `dart:io` in `localaze-dart`'s core. It breaks Flutter Web, and it is what made the old inlined runtime impossible to unit test.
- No `URLSession` reached for directly in Swift core logic, no `OkHttp` in Kotlin core logic.
- Each package ships a default implementation for its platform, and tests substitute a fake.

A runtime that can only be tested against a live server is a runtime that is not tested.

The generators are the exception. They run on a developer machine or in CI, never on a device, so they call the network and the filesystem directly. They still never sit in a runtime's core: each is a separate entry point, and each is tested offline from `contract/fixtures/`.

## Signature compatibility

The hard gate on every update. A fetched catalog is applied only when:

- every key in the generated signature is present, **and**
- every present key's parameter **names and types** match the signature.

Names alone is not enough, and it was the bug in the backend's former Dart generator. A retype — `{$count}` becoming `{$count :number}` — leaves the key and its parameter name intact while breaking every call site the compiler already checked. It is also the likelier edit in practice.

Keys **added** since generation are ignored, not refused. The app has no accessor for them, and a newer platform release is not a client failure.

A refused catalog is refused **whole**. Half an update means some screens render content the compiler never checked.

## Update policy

Policy is about intent — "we do not want minor updates in this build". The signature check is about possibility. Policy is consulted first because it is cheaper; the signature is checked before anything is written.

| Policy | Accepts |
|---|---|
| `none` | Nothing. The app ships with what it was built with |
| `patchOnly` | Wording fixes |
| `minorAndPatch` | **Default.** Wording fixes and added keys — exactly the set that leaves every existing call site valid |
| explicit range | For teams who want one |

**A major is refused under every policy, including an explicit range.** The platform defines a major release as signature-breaking by construction, so applying one would leave call sites passing parameters the messages no longer take. That is not a stale screen, it is a wrong one.

A refused update leaves the previous catalog in place.

## Configuration

Every option has a working default except the API key. An app constructed with only a key behaves sensibly.

`apiKey`, `baseUrl`, `assetPath`, `cacheDirectory`, `policy`, `timeout`, `applyImmediately`, `onDiagnostic`.

The key carries the project and the environment, so neither is a separate parameter and a staging build cannot read production.

## Package CLAUDE.md

Each package's `CLAUDE.md` declares its Baselines: language and toolchain versions, minimum OS, and distribution target.

**Never guess a baseline.** Leave it `_to be confirmed_` and say so. The same rule the backend applies to Java and Spring Boot versions applies here, for the same reason: a minimum iOS version or an Android `minSdk` chosen by an assistant is a number an app team then has to unwind, and unwinding it means every consuming app moves too.

A package manifest — `pubspec.yaml`, `Package.swift`, `build.gradle.kts` — is not written until its baselines are filled in.

## Code quality

- One public entry point per package. Everything else is internal until something needs it.
- No public API takes an untyped map or a loose string key. That defeats type safety, which is the reason these packages exist.
- Every failure path has a test, and the test asserts it returned rather than threw.
- No commented-out code in a commit.
- Documentation comments where the name does not already say it, and on every rule that looks arbitrary without its reason.

## Generators

Read `contract/generator-contract.md` before writing generator code. The runtime rules above govern the runtime; these govern the generator.

- **A generator may fail, and should fail loudly.** It runs at build time, where a refusal is cheap and a wrong file is expensive. It exits non-zero and prints every problem at once.
- **It checks everything before writing anything.** A failed run leaves the previous output untouched.
- **Its output is deterministic.** No timestamps, no paths, no machine names, so the generated file can be checked in and diffed.
- **Its output is golden-tested** against the fixture project, in every package.
- **It never compiles CLDR or parses MF2.** Plural rules arrive compiled in the manifest; text arrives resolved in the catalogs.

## Never do

- Never throw from a public API
- Never swallow a failure without calling `onDiagnostic`
- Never inline translations, key names, or a project identifier into a package
- Never parse MF2 or ship CLDR data
- Never call the network or the filesystem directly from core logic
- Never check parameter names without also checking types
- Never apply part of a catalog
- Never accept a major update, whatever the policy says
- Never let one platform's behaviour drift from the contract
- Never guess a language version, a minimum OS, or an `minSdk`
- Never expose a dynamic key lookup API


## Changing the contract

**The contract comes first.** A new behaviour, or a changed one, is a pull request to `localaze-contract`: the specification, the conformance case, and the fixture if it needs one. Its CI runs every SDK against the proposed contract and shows which would fail. Once it merges, each SDK repository gets a pull request that moves its `contract/` submodule forward, and the implementation lands there.

The contract and a package that implements it are separate units of work. So are two packages.

## Commits

One unit of work per commit, as soon as it is complete and the build passes: one feature, one fix, or one refactor. A commit spanning three packages cannot be reviewed, cannot be reverted without losing the other two, and hides which change broke the build. If a unit is not finished, leave it uncommitted rather than committing a half-built feature.

The message says what changed and why, in a sentence a reader of `git log` understands without the diff. Maintainers prefix it with the ticket key (`L10N-123: …`); a contribution does not need one.

Releases follow `RELEASING.md`: one version for all three platforms.

## The server side

The Localaze read API. These packages consume it and do not change it.

| Endpoint | Returns |
|---|---|
| `GET /api/v1/read/manifest?version=x.y.z` | The typed manifest a generator reads: keys, parameter types, compiled plural rules. Refuses an incomplete release unless `strict=false` |
| `GET /api/v1/read/version` | Current semver, bump, published date, available versions. Cheap enough for every launch — no translations |
| `GET /api/v1/read/translations/{lang}?format=resolved` | One language's catalog in the resolved shape |
| `GET /api/v1/read/translations/{lang}?version=x.y.z` | Pinned to a release, so it cannot move underneath a build |

Authenticated with the `X-Localaze-Key` header. Both support `If-None-Match`, and the ETag is version-scoped so a pinned version's tag never changes and a rollback returns the earlier tag rather than inventing a new one. **Send `If-None-Match`.** A 304 is the cheap path the server was built to serve, and the current Dart runtime never asks for it.


The server generates no source. Generation is each SDK's job, from the manifest and the catalogs.
