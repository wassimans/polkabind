# PolkaBind: Cross-Language Polkadot SDK via UniFFI

**Tagline:**  
One Rust source, native SDKs for Swift, Kotlin, Python & JavaScript.

---

## 1. Project Overview

PolkaBind is a Rust-first Polkadot/​Substrate binding library that uses Mozilla’s UniFFI toolchain to generate and publish native language SDKs automatically. Version 0.1.0 will deliver:

- A core Rust crate (`polkabind-core`) exposing essential wallet operations via UniFFI annotations.
- A Swift Package (`polkabind.swift`) published to the Swift Package Registry.
- A minimal iOS demo app (“PolkaBindWallet”) showcasing `importWallet`, `getBalance`, and `sendTransfer`.

---

## 2. Motivation & Ecosystem Fit

- **Current Gap:**  
  - JavaScript (`@polkadot/api`), Python and Go have mature Polkadot SDKs.  
  - Native Swift/Kotlin devs today rely on WebViews or ad-hoc FFI layers.  

- **Ecosystem Demand:**  
  - Frequent requests in Polkadot forums and Discord for mobile-native bindings.  
  - Mobile wallets (Nova, Speem) are constrained by suboptimal bridging.  

- **Alignment with Polkadot Treasury Goals:**  
  - Broadens the developer on-ramp.  
  - Fosters mobile and desktop adoption.  
  - Enhances cross-platform consistency by keeping all cryptography and SCALE encoding in Rust.

---

## 3. Technical Approach

1. **Core Rust Crate (`polkabind-core`):**  
   - Define UniFFI annotations for a minimal wallet API:  
     - `import_wallet(seed: String) -> WalletHandle`  
     - `get_balance(handle: WalletHandle) -> u128`  
     - `transfer(handle: WalletHandle, dest: String, amount: u128) -> TxHash`  
     - Simple storage query support.  

2. **UniFFI Generation & Packaging:**  
   - Use `build.rs` to invoke `uniffi-bindgen` on our Rust code and produce:  
     - `polkabind.swift` + module map → Swift Package.  
     - (stub) `polkabind.kt` → Maven artifact.  

3. **Swift PoC & CI:**  
   - Scaffold iOS demo (“PolkaBindWallet”) that:  
     - Imports `PolkaBind` Swift Package.  
     - Displays an account balance and sends a DOT transfer.  
   - GitHub Actions: on tag → publish to SwiftPM registry.  

4. **Kotlin Starter:**  
   - Provide a minimal `polkabind.kt` package and a “Hello, PolkaBind” Android Gradle sample.

---

## 4. Deliverables & Timeline

| Month | Milestone & Deliverables                                          |
|-------|-------------------------------------------------------------------|
| **M1**| • Design UniFFI UDL & annotate Rust APIs for core wallet v0.1<br>• Scaffold Swift Package + iOS demo (import & balance) |
| **M2**| • Generate & publish Swift Package (pre-release)<br>• Implement `transfer` + update demo app |
| **M3**| • Stub Kotlin bindings & publish to Maven Central<br>• Finalize docs, examples & cut v0.1.0 release |

---

## 5. Budget & Resources

| Role       | Effort       | Rate      | Total     |
|------------|--------------|-----------|-----------|
| Lead Dev   | 480 hours    | \$62.50/h | **\$30,000** |

---

## 6. Team & Expertise

- **Wassim Mansouri**  
  - 5+ years Rust & Polkadot/Substrate experience.  
  - Creator of SPEEM mobile wallet (Swift/Kotlin + Rust).  
  - Maintainer of PolkaBind prototype.

---

## 7. Risks & Mitigations

| Risk                              | Mitigation                                     |
|-----------------------------------|------------------------------------------------|
| UniFFI limitations on complex types | Start with primitive types & simple structs; extend in v0.2 |
| Publishing pipelines complexity   | Leverage existing GitHub Actions templates; iterate on one registry first |
| Scope creep                       | Lock v0.1 to core wallet API; defer event subscriptions to v0.2 |

---

*PolkaBind will unlock truly native Polkadot integration across all major languages—one Rust crate at a time.*  
