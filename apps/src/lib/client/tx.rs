use std::convert::TryFrom;

use anoma::proto::Tx;
use anoma::types::key::ed25519::Keypair;
use anoma::types::token;
use anoma::types::transaction::UpdateVp;
use borsh::BorshSerialize;
use tendermint_rpc::query::{EventType, Query};
use tendermint_rpc::Client;

use super::rpc;
use crate::cli::args;
use crate::client::tendermint_rpc_client::{
    hash_tx, Error, TendermintRpcClient, WebSocketAddress,
};
use crate::wallet;

const TX_UPDATE_VP_WASM: &str = "wasm/tx_update_vp.wasm";
const TX_TRANSFER_WASM: &str = "wasm/tx_transfer.wasm";

pub async fn submit_custom(args: args::TxCustom) {
    let tx_code = std::fs::read(args.code_path)
        .expect("Expected a file at given code path");
    let data = args.data_path.map(|data_path| {
        std::fs::read(data_path).expect("Expected a file at given data path")
    });
    let tx = Tx::new(tx_code, data);

    submit_tx(args.tx, tx).await
}

pub async fn submit_update_vp(args: args::TxUpdateVp) {
    let addr = args.addr;
    let source_key: Keypair = wallet::key_of(addr.encode());
    let vp_code = std::fs::read(args.vp_code_path)
        .expect("Expected a file at given code path");
    let tx_code = std::fs::read(TX_UPDATE_VP_WASM)
        .expect("Expected a file at given code path");

    let update_vp = UpdateVp { addr, vp_code };
    let data = update_vp.try_to_vec().expect(
        "Encoding transfer data to update a validity predicate shouldn't  fail",
    );
    let tx = Tx::new(tx_code, Some(data)).sign(&source_key);

    submit_tx(args.tx, tx).await
}

pub async fn submit_transfer(args: args::TxTransfer) {
    let source_key: Keypair = wallet::key_of(args.source.encode());
    let tx_code = std::fs::read(TX_TRANSFER_WASM).unwrap();

    let transfer = token::Transfer {
        source: args.source,
        target: args.target,
        token: args.token,
        amount: args.amount,
    };
    tracing::debug!("Transfer data {:?}", transfer);
    let data = transfer
        .try_to_vec()
        .expect("Encoding unsigned transfer shouldn't fail");
    let tx = Tx::new(tx_code, Some(data)).sign(&source_key);

    submit_tx(args.tx, tx).await
}

async fn submit_tx(args: args::Tx, tx: Tx) {
    let tx_bytes = tx.to_bytes();

    // NOTE: use this to print the request JSON body:

    // let request =
    // tendermint_rpc::endpoint::broadcast::tx_commit::Request::new(
    //     tx_bytes.clone().into(),
    // );
    // use tendermint_rpc::Request;
    // let request_body = request.into_json();
    // println!("HTTP request body: {}", request_body);

    if args.dry_run {
        rpc::dry_run_tx(&args.ledger_address, tx_bytes).await
    } else if let Err(err) = broadcast_tx(args.ledger_address, tx_bytes).await {
        eprintln!("Encountered error while broadcasting transaction: {}", err);
    }
}

async fn broadcast_tx(
    address: tendermint::net::Address,
    tx_bytes: Vec<u8>,
) -> Result<(), Error> {
    let mut client =
        TendermintRpcClient::open(WebSocketAddress::try_from(address)?)?;
    // It is better to subscribe to the transaction before it is broadcast
    let query = Query::from(EventType::Tx)
        .and_eq("tx.hash", hash_tx(&tx_bytes).to_string());
    client.subscribe(query)?;
    println!(
        "{:?}",
        client
            .broadcast_tx_sync(tx_bytes.into())
            .await
            .map_err(|err| Error::Response(format!("{:?}", err)))?
    );
    println!("{}", client.receive_response()?);
    client.unsubscribe()?;
    client.close();
    Ok(())
}
