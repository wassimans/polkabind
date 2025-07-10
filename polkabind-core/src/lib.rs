uniffi::setup_scaffolding!();

use thiserror::Error as ThisError;
use uniffi_macros::Error;

use std::sync::OnceLock;
use subxt::{
    OnlineClient, PolkadotConfig, dynamic::Value, ext::scale_value::Composite,
    tx::dynamic as dynamic_call,
};
use subxt_signer::sr25519::dev;
use tokio::runtime::Runtime;

static RT: OnceLock<Runtime> = OnceLock::new();
fn rt() -> &'static Runtime {
    RT.get_or_init(|| Runtime::new().unwrap())
}

#[derive(ThisError, Error, Debug)]
pub enum TransferError {
    #[error("hex decode failed: {0}")]
    Decode(String),

    #[error("subxt error: {0}")]
    Subxt(String),
}

#[uniffi::export]
pub fn do_transfer(dest_hex: &str, amount: u64) -> Result<(), TransferError> {
    eprintln!("🦀 [Rust] do_transfer() start; dest={} amount={}", dest_hex, amount);
    let s = dest_hex.strip_prefix("0x").unwrap_or(dest_hex);
    let raw = hex::decode(s).map_err(|e| {
        eprintln!("🦀 [Rust] hex decode err: {}", e);
        TransferError::Decode(e.to_string())
    })?;

    eprintln!("🦀 [Rust] hex decoded → {} bytes", raw.len());
    let arr: [u8; 32] = raw.as_slice().try_into().map_err(|_| {
        eprintln!("🦀 [Rust] invalid length for address");
        TransferError::Decode("invalid 32-byte address".into())
    })?;

    let dst = Value::variant(
        "Id",
        Composite::unnamed(vec![Value::from_bytes(arr.to_vec())]),
    );
    eprintln!("🦀 [Rust] built Destination Value");

    let client = rt().block_on(async {
        eprintln!("🦀 [Rust] connecting to ws://127.0.0.1:8000 …");
        OnlineClient::<PolkadotConfig>::from_url("ws://127.0.0.1:8000")
            .await
            .map_err(|e| {
                eprintln!("🦀 [Rust] connection error: {}", e);
                TransferError::Subxt(e.to_string())
            })
    })?;

    eprintln!("🦀 [Rust] connected; submitting tx");
    let signer = dev::alice();
    let tx = dynamic_call(
        "Balances",
        "transfer_allow_death",
        vec![dst, Value::u128(amount as u128)],
    );

    rt().block_on(async {
        let watch = client
            .tx()
            .sign_and_submit_then_watch_default(&tx, &signer)
            .await
            .map_err(|e| {
                eprintln!("🦀 [Rust] submit error: {}", e);
                TransferError::Subxt(e.to_string())
            })?;
        eprintln!("🦀 [Rust] watching for finalized…");
        watch
            .wait_for_finalized_success()
            .await
            .map_err(|e| {
                eprintln!("🦀 [Rust] finalize error: {}", e);
                TransferError::Subxt(e.to_string())
            })?;
        eprintln!("🦀 [Rust] tx finalized!");
        Ok(())
    })
}
