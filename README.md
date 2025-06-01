# uniffi-polkadot-lib

> **Work in Progress**: A Rust → UniFFI bridge for Polkadot, automatically publishing native bindings for Swift, Kotlin, Python, JavaScript, and more.

---

## Overview

`uniffi-polkadot-lib` is a Rust-based SDK that exposes Polkadot functionality (key management, balance queries, extrinsic building, signing, RPC, event subscriptions) via UniFFI. When the library updates, a CI pipeline automatically generates and publishes native language packages—so iOS, Android, Python, JavaScript, and other clients can consume the same Rust logic without writing custom FFI.

---

## High-Level Workflow

```mermaid
flowchart LR
  subgraph Repo
    A[uniffi-polkadot-lib (Rust + UDL)] 
    A -->|CI Trigger on Push| B[CI Pipeline]
  end

  subgraph CI_Pipeline
    B --> C1[uniFFI Bindgen → Swift Stubs]
    B --> C2[uniFFI Bindgen → Kotlin Stubs]
    B --> C3[uniFFI Bindgen → Python Bindings]
    B --> C4[uniFFI Bindgen → JavaScript/TS Bindings]
    C1 --> D1[Publish Swift Package to GitHub / CocoaPods]
    C2 --> D2[Publish Kotlin Artifact to Maven Central]
    C3 --> D3[Publish Python Wheel to PyPI]
    C4 --> D4[Publish JS Package to npm]
  end

  subgraph Consumers
    D1 --> E1[iOS App (SwiftUI) imports Swift Package]
    D2 --> E2[Android App (Compose) imports Maven Artifact]
    D3 --> E3[Python Script imports via PyPI]
    D4 --> E4[Node/Browser App imports via npm]
  end

  style Repo fill:#f9f9f9,stroke:#ccc
  style CI_Pipeline fill:#f0f0f0,stroke:#bbb
  style Consumers fill:#f9f9f9,stroke:#ccc
