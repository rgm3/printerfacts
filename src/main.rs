use std::convert::Infallible;
use pfacts::Facts;
use rand::prelude::*;
use warp::Filter;

async fn give_fact(facts: Facts) -> Result<String, Infallible> {
    Ok(facts.choose(&mut thread_rng()).unwrap().clone())
}

#[tokio::main]
async fn main() {
    pretty_env_logger::init();
    let facts = pfacts::make();

    let mw = warp::any().map(move || facts.clone());

    let fact_handler = warp::any()
        .and(mw)
        .and_then(give_fact);

    log::info!("listening on port 5000");
    warp::serve(fact_handler)
        .run(([0, 0, 0, 0], 5000))
        .await;
}
