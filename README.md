# Agent Island

Agent Island is a local-first native macOS companion for monitoring and
interacting with concurrent AI coding work without leaving the application
you are currently using.

It brings Agent Sessions from tools such as Claude Code, Codex, and Cursor
into a non-modal top-edge overlay, while keeping canonical state and sensitive
interaction data on the Mac. Product integrations and Host navigation are
implemented behind capability-scoped boundaries so the UI does not take
ownership of external conversations.

## Requirements

- macOS 14 or later on Apple silicon
- Swift 6 toolchain (full Xcode is required to run the test suites)
- [SQLCipher](https://www.zetetic.net/sqlcipher/) available through
  Homebrew/pkg-config

```sh
brew install sqlcipher
```

## Build and run

The production Swift package lives in [`src`](src/).

```sh
cd src
swift build
swift run AgentIslandApp
```

Run the automated tests from the same directory on a machine with full Xcode:

```sh
swift test
```

For the headless integration evidence check:

```sh
Scripts/self-check.sh
```

## Repository guide

- [`CONTEXT.md`](CONTEXT.md) defines the system-wide domain language.
- [`src/README.md`](src/README.md) documents the production architecture,
  module boundaries, current capabilities, and evidence workflows.
- [`docs/adr`](docs/adr/) contains the architecture decision records.
- [`docs/evidence`](docs/evidence/) and [`src/Evidence`](src/Evidence/) contain
  implementation evidence and report templates.
- [`spikes`](spikes/) contains accepted technical explorations that informed
  the production implementation.

Issues are maintained as local Markdown records under `.scratch/`; see
[`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md) for the workflow.

## Project status

Agent Island is under active development. The current implementation includes
the native Island Overlay and Settings shell, protected local persistence,
typed Agent Product adapter boundaries, Host navigation adapters, and
headless self-check executables. See the production source documentation for
the exact supported capability and known limitations.
