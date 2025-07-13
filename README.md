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

```mermaid
flowchart TD
  %% -----------------------------------------------------------
  %%  Repositories
  %% -----------------------------------------------------------
  subgraph CoreRepo["**polkabind** (Rust · Subxt façade)"]
    A1[Push / Tag] --> CI[ GitHub Actions CI ]
  end

  subgraph SwiftRepo["**polkabind-swift-pkg**"]
    P1[Release&nbsp;zip<br/>+ SPM manifest]:::asset
  end

  classDef asset fill:#fff5dd,stroke:#e6ba42,color:#000;

  %% -----------------------------------------------------------
  %%  Core CI stages
  %% -----------------------------------------------------------
  subgraph CorePipeline["CI Pipeline (in Core repo)"]
    direction LR
    CI --> B1[Build Rust dylib<br/> + aarch64 & sim]:::ci
    B1 --> B2[UniFFI → Swift stubs]:::ci
    B2 --> B3[Bundle xcframework<br/>+ Package.swift]:::ci
    B3 --> B4[Publish files<br/>to Swift repo<br/>+ version tag]:::ci
  end

  classDef ci fill:#eef3ff,stroke:#97b3ff,color:#000;

  %% -----------------------------------------------------------
  %%  Swift Repo CI
  %% -----------------------------------------------------------
  subgraph SwiftPipeline["CI in Swift repo"]
    direction LR
    PR1[Tag pushed<br/>from Core CI] --> SR1[Zip package]:::ci2
    SR1 --> SR2[Create GitHub<br/>Release]:::ci2
  end

  classDef ci2 fill:#e8fce8,stroke:#84cc84,color:#000;

  %% -----------------------------------------------------------
  %%  Consumers
  %% -----------------------------------------------------------
  subgraph Consumers
    IOS[iOS / macOS<br/>SwiftUI app] -->|SPM fetches Release| P1
    AND[Android app<br/> future Kotlin] -.->|Maven Central| D2
    PY[Python script] -.->|PyPI wheel| D3
    JS[Node / Web] -.->|npm package| D4
  end

  %% grey boxes for future lanes
  D2[Maven artefact]:::future
  D3[Python wheel]:::future
  D4[npm package]:::future
  classDef future fill:#f4f4f4,stroke:#ccc,color:#666,font-style:italic;
  ```

## Status

This is a *work-in-progress*, please visit [polkabind.dev](https://polkabind.dev) for a summary of the expected roadmap.
