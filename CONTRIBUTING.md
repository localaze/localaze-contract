# Contributing

Thanks for helping with Localaze for the contract. Bug reports, fixes and documentation are all welcome.

## Before you start

- **A bug:** open an issue with what you expected and what happened, the SDK version, and any `onDiagnostic` output. That output is usually the fastest route to the cause.
- **A change in behaviour, or a new option:** open an issue first, so we can agree on it before you write it.
- **A security problem:** do not open an issue. See [`SECURITY.md`](SECURITY.md).

## Building and testing

You need Python 3 and Dart.

```sh
git clone https://github.com/localaze/localaze-contract.git
cd localaze-contract
python3 scripts/check-contract.py
dart run stub-server/serve.dart    # the stub read API on :8787
```

A pull request here runs every SDK's suite against your change. That run is the real check: it shows which SDKs a contract change would break before it merges.

CI runs the same steps on every pull request, and a pull request merges only when they pass.

## The rules

The rules every Localaze SDK follows are in [`contract/CLAUDE.md`](https://github.com/localaze/localaze-contract/blob/main/CLAUDE.md). The ones that matter most for a contribution:

- **No public API throws.** A failure leaves the app on the text it already had, and calls `onDiagnostic` saying what failed and why.
- **No MF2 parsing and no CLDR data on the device.** Catalogs arrive parsed; plural rules arrive compiled into generated code.
- **Generated output is deterministic,** and a change to it is a change to the golden files, reviewed like any other API change.
- **No new runtime dependency** without discussing it first. Every dependency here is one every app using the SDK carries.

## Pull requests

- One change per pull request, with a description of what it changes and why.
- Tests for the change. A fix comes with the test that would have caught it.
- Update `CHANGELOG.md` under `Unreleased`.
- README code is checked by CI against compiled code (`contract/scripts/check-snippets.py`). To change an example, change the file it comes from, and copy the region into the README.

By contributing you agree that your contribution is licensed under the MIT License, like the rest of this repository.
