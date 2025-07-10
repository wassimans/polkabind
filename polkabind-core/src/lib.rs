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
    let s = dest_hex.strip_prefix("0x").unwrap_or(dest_hex);
    let raw = hex::decode(s).map_err(|e| TransferError::Decode(e.to_string()))?;

    let arr: [u8; 32] = raw
      .as_slice()
      .try_into()
      .map_err(|_| TransferError::Decode("invalid 32-byte address".into()))?;

    let dst = Value::variant(
        "Id",
        Composite::unnamed(vec![Value::from_bytes(arr.to_vec())]),
    );

    // ✅ Force the async Result out with `?`
    let client = rt().block_on(async {
        OnlineClient::<PolkadotConfig>::from_url("ws://127.0.0.1:8000")
            .await
            .map_err(|e| TransferError::Subxt(e.to_string()))
    })?;

    let signer = dev::alice();
    let tx = dynamic_call(
        "Balances",
        "transfer_allow_death",
        vec![dst, Value::u128(amount as u128)],
    );

    // ✅ And again propagate errors
    rt().block_on(async {
        client
            .tx()
            .sign_and_submit_then_watch_default(&tx, &signer)
            .await
            .map_err(|e| TransferError::Subxt(e.to_string()))?
            .wait_for_finalized_success()
            .await
            .map_err(|e| TransferError::Subxt(e.to_string()))?;
        Ok(())
    })
}
