uniffi::setup_scaffolding!();

use uniffi_macros::export;
use tokio::runtime::Runtime;
use subxt::{OnlineClient, dynamic::Value, tx::dynamic as dynamic_call, PolkadotConfig, ext::scale_value::Composite};
use subxt_signer::sr25519::dev;
use thiserror::Error;
use std::sync::OnceLock;

static RT: OnceLock<Runtime> = OnceLock::new();
fn rt() -> &'static Runtime {
    RT.get_or_init(|| Runtime::new().unwrap())
}

#[derive(Error, Debug)]
pub enum TransferError {
    #[error("hex decode failed")]
    Decode(#[from] hex::FromHexError),
    #[error("subxt error: {0}")]
    Subxt(#[from] subxt::Error),
}

#[uniffi::export]
pub fn do_transfer(dest_hex: &str, amount: u64) -> Result<(), TransferError> {
    let s = dest_hex.strip_prefix("0x").unwrap_or(dest_hex);
    let raw = hex::decode(s)?;
    let arr: [u8;32] = raw.as_slice().try_into().unwrap();
    let dst = Value::variant(
        "Id",
        Composite::unnamed(vec![ Value::from_bytes(arr.to_vec()) ]),
    );
    let client = rt().block_on(async {
        OnlineClient::<PolkadotConfig>::from_url("ws://127.0.0.1:9944").await.unwrap()
    });
    let signer = dev::alice();
    let tx = dynamic_call(
        "Balances",
        "transfer_allow_death",
        vec![ dst, Value::u128(amount as u128) ],
    );
    rt().block_on(async {
        let progress = client.tx().sign_and_submit_then_watch_default(&tx, &signer).await?;
        progress.wait_for_finalized_success().await?;
        Ok(())
    })
}
