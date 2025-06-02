uniffi::setup_scaffolding!();

/// We only annotate our own wrapper functions (init_client, get_balance, build_signed_transfer)
/// with #[export].
/// SubXT’s code lives as an ordinary dependency, so no annotations needed on SubXT itself.
/// Return types must be Result<…, ErrorCode>
///     (so UniFFI knows to map it to a T | ErrorCode in target languages).
/// Custom record types (like AccountData) must implement Serialize + Deserialize and
///     be used in an #[export] function.

use once_cell::sync::OnceCell;
use std::sync::Mutex;
use uniffi::export; // Macro for marking exports
use subxt::{OnlineClient, PolkadotConfig, ext::sp_core::Pair, ext::sp_core::sr25519};
use subxt::ext::sp_runtime::AccountInfo;
use serde::{Serialize, Deserialize};

// A global, thread-safe handle to the SubXT client
static CLIENT: OnceCell<Mutex<OnlineClient<PolkadotConfig>>> = OnceCell::new();

// An enum for error codes returned to foreign languages
#[derive(Debug)]
#[repr(C)]
pub enum ErrorCode {
    Ok = 0,
    RpcError = 1,
    DecodeError = 2,
    SigningError = 3,
}

// A record type to send balance info (free vs. reserved)
#[derive(Serialize, Deserialize)]
pub struct AccountData {
    pub free: u128,
    pub reserved: u128,
}

#[uniffi::export]
// Initialize the SubXT client with a WebSocket URL (e.g. "wss://rpc.polkadot.io")
// Returns ErrorCode::Ok on success, or RpcError on failure.
pub fn init_client(url: String) -> Result<(), ErrorCode> {
    // Build a synchronous Tokio runtime for this example
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|_| ErrorCode::RpcError)?;

    // Attempt to connect
    let client = rt.block_on(async {
        OnlineClient::<PolkadotConfig>::from_url(url).await
    }).map_err(|_| ErrorCode::RpcError)?;

    CLIENT.set(Mutex::new(client)).unwrap();
    Ok(())
}

#[uniffi::export]
// Fetch the on-chain balance (free, reserved) for an SS58-encoded address.
// Returns (free, reserved) on success; otherwise ErrorCode.
pub fn get_balance(address: String) -> Result<AccountData, ErrorCode> {
    let client_lock = CLIENT.get().ok_or(ErrorCode::RpcError)?;
    let client = client_lock.lock().unwrap();

    // Convert SS58 string to AccountId32
    let account_id = subxt::utils::AccountId32::from_ss58check(&address)
        .map_err(|_| ErrorCode::DecodeError)?;

    // Build a minimal runtime
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|_| ErrorCode::RpcError)?;

    // Query the System Account storage
    let info: AccountInfo<u128, subxt::ext::sp_runtime::AccountData> = rt.block_on(async {
        client
            .storage()
            .at(None)
            .await
            .map_err(|_| ErrorCode::RpcError)?
            .fetch(&subxt::dynamic::storage("System", "Account", vec![account_id.into()]))
            .await
            .map_err(|_| ErrorCode::RpcError)
    })?;

    Ok(AccountData {
        free: info.data.free,
        reserved: info.data.reserved,
    })
}

#[uniffi::export]
// Build and sign a transfer extrinsic. Returns SCALE-encoded bytes on success, or an ErrorCode.
// Parameters:
//   to: SS58 address string of the recipient
//   amount: number of Planck (u128) to transfer
//   seed: BIP-39 seed phrase (String)
// Returns Vec<u8> of SCALE-encoded signed extrinsic.
pub fn build_signed_transfer(
    to: String,
    amount: u128,
    seed: String,
) -> Result<Vec<u8>, ErrorCode> {
    let client_lock = CLIENT.get().ok_or(ErrorCode::RpcError)?;
    let client = client_lock.lock().unwrap();

    // Derive the sr25519 keypair from seed phrase
    let pair = sr25519::Pair::from_string(&seed, None)
        .map_err(|_| ErrorCode::SigningError)?;
    let signer = subxt::tx::PairSigner::new(pair.clone());

    // Convert recipient address
    let dest = subxt::utils::AccountId32::from_ss58check(&to)
        .map_err(|_| ErrorCode::DecodeError)?;

    // Build the transfer payload
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|_| ErrorCode::RpcError)?;
    let tx_payload = client.tx().balances().transfer(dest.into(), amount);

    // Sign & encode (but do NOT submit)
    let encoded = rt.block_on(async {
        tx_payload.sign(&signer).map_err(|_| ErrorCode::SigningError)
    })?;

    Ok(encoded.to_vec())
}

//TODO: re-export more functions

// uniffi::setup_scaffolding!();

// /// Everything inside this `mod` is now part of your FFI interface.
// /// A tiny example function we’ll call from Swift/Kotlin.
// #[uniffi::export]
// pub fn greet(name: String) -> String {
//     format!("Hello, {}!", name)
// }

// /// Another example: add two integers.
// #[uniffi::export]
// pub fn add(a: i32, b: i32) -> i32 {
//     a + b
// }

// /// You can also export custom structs, enums, etc.
// #[derive(uniffi::Object)]
// pub struct Point {
//     pub x: f64,
//     pub y: f64,
// }
