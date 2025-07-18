# Polkabind

**Seamless interaction with any Polkadot SDK based chain for Kotlin**

## Overview

`Polkabind` is a library that opens the Polkadot ecosystem to programming languages other than Rust. It exposes mainly standard wallet-level functionality (key management, balance queries, extrinsic building, signing, RPC, event subscriptions and more) to other languages (Swift, Kotlin, Python, Javascript and more) by exposing the **[Subxt](https://github.com/paritytech/subxt)** library through FFI (foreign language interface). This is the Polkabind Kotlin package, for Kotlin developers.

## High-Level Workflow

This is a high level workflow showcasing the production a Kotlin Polkabind package.

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

# Show me the code

Here's what it looks like to use `Polkabind` in Swift:

## Classic Subxt (Rust)

``` rust
// build the address, compose the dynamic call,
// sign, submit, watch for finality …
let dst = Value::variant(
    "Id",
    Composite::unnamed(vec![Value::from_bytes(arr)]),
);
let client = OnlineClient::<PolkadotConfig>::from_url(url).await?;
let tx = dynamic_call(
    "Balances",
    "transfer_allow_death",
    vec![dst, Value::u128(amount)],
);
client
    .tx()
    .sign_and_submit_then_watch_default(&tx, &signer)
    .await?
    .wait_for_finalized_success()
    .await?;
```

## Polkabind (Swift)
```swift
// one blocking FFI call – done 🎉
try Polkabind.doTransfer(destHex: destHex, amount: amt)
```

Behind the scenes **Polkabind** executes that same Rust (left column) but
exposes a single, ergonomic Swift API.

## Status

This is a *work-in-progress*, please visit [polkabind.dev](https://polkabind.dev) for a summary of the expected roadmap.

## License

Polkabind is licensed under the Apache License, Version 2.0 (see LICENSE).

### Third-Party Licenses and Attributions

Polkabind uses Subxt, which is dual-licensed under either:
    • Apache License, Version 2.0, or
    • GNU General Public License v3.0 (or later)

Polkabind explicitly elects to use Subxt under the terms of the Apache License, Version 2.0.
