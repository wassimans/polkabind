# Polkabind

**Seamless interaction with any Polkadot SDK based chain for Swift, Kotlin, Python and more!**

<p align="center">
  ⚠️ **Work in Progress** ⚠️
</p>

## Overview

`Polkabind` is a library that opens the Polkadot ecosystem to programming languages other than Rust. It exposes mainly standard wallet-level functionality (key management, balance queries, extrinsic building, signing, RPC, event subscriptions and more) to other languages (Swift, Kotlin, Python, Javascript and more) by exposing the **[Subxt](https://github.com/paritytech/subxt)** library through FFI (foreign language interface). 

## Why?

As of today, the **main** and **supported** languages that can be used to interact with a chain built on the Polkadot SDK are:

- *Rust*: primary and official through **Subxt**, **Polkadot SDK** and **FRAME**.
- *Javascript/Typescript*: widely used and community supported through tools like: **PAPI** and **PolkadotJS** and more.

Some projects tried to expose the same rich functionality for other languages, but many are way behind in terms of API exposure compared to Subxt. And still, it's really difficult to produce safe code in other languages compared to Rust, and especially compared to the established Rust cryptographic libraries used under the hood by Subxt and FRAME.

Subxt itself is the primary Rust/Webassembly based tool used to interact with Polkadot SDK based chains, and many community developer tools use it internally. But for a developer, other than the Rust language learning curve, Subxt adds to it its own learning curve because of it's rich API coverage and the complexity of the blockchain based interactions in general.

`Polkabind` tries to open the Polkadot ecosystem to other languages in a smart way by: 

- creating a façade/abstraction on top of Subxt itself: we use Subxt, we don't replace it. Subxt is our source of truth. The façade exposes mainly standard wallet-level functionality, no fancy interactions, at least for now.
- simplifying the developer experience: instead of crafting a big block of code using Subxt to do a simple transfer, Polkabind abstracts it to be a simple function exposed to other langugaes.
- the façade is translated to other languages through FFI (C ABI), the standard bridge between Rust and most runtimes.
- Polkabind will produce small ready-to-import libraries for major languages: Swift, Kotlin, Nodejs, Python and more. And later, those libraries will be published to each language package manager's repository: for Nodejs, it will be as simple as *npm install @polkabind/latest*. 
- If Subxt gains a new feature, a single Rust change in Polkabind automatically propagates to every supported language.


## High-Level Workflow

This is a high level workflow showcasing the production a Swift Polkabind package.

```mermaid
flowchart TD
  %% ──────────────────────────────────────────────
  %%  Repositories (left-to-right data flow)
  %% ──────────────────────────────────────────────
  subgraph CORE["**polkabind**  (Rust + Subxt façade)"]
    A[Push / Tag vX.Y.Z]
  end

  subgraph CORE_CI["Core repo CI  ( GitHub Actions )"]
    direction LR
    B1[Build<br/>⚙️ Rust dylib<br/> device + sim] --> B2[Generate Swift stubs<br/>🔧 UniFFI]
    B2 --> B3[Bundle xcframework<br/>+ Package.swift]
    B3 -->|git push files & tag| B4[Mirror into<br/>**polkabind-swift-pkg**]
  end

  subgraph SWIFT_REPO["**polkabind-swift-pkg**  (repo)"]
    C[New commit<br/>+ tag vX.Y.Z]
  end

  subgraph SWIFT_CI["Swift repo CI  ( GitHub Actions )"]
    D1[Zip package] --> D2[Create GitHub Release<br/>📦 polkabind-swift-pkg.zip]
  end

  subgraph CONSUMER["Developer / CI using SwiftPM"]
    E[Swift / iOS App<br/>adds SPM dependency<br/>→ fetches Release]
  end

  %% ──────────────────────────────────────────────
  %%  Link everything
  %% ──────────────────────────────────────────────
  A --> CORE_CI
  B4 --> C
  C --> SWIFT_CI
  D2 --> E

  %% ──────────────────────────────────────────────
  %%  Styling helpers
  %% ──────────────────────────────────────────────
  classDef repo      fill:#f9f9f9,stroke:#bbb;
  classDef pipeline  fill:#eef3ff,stroke:#87a9ff;
  classDef release   fill:#e8fce8,stroke:#78c878;

  class CORE,SWIFT_REPO repo
  class CORE_CI,SWIFT_CI pipeline
  class D2 release
  ```

## Status

This is a *work-in-progress*, please visit [polkabind.dev](https://polkabind.dev) for a summary of the expected roadmap.
