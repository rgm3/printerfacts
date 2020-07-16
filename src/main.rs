use crate::templates::RenderRucte;
use lazy_static::lazy_static;
use pfacts::Facts;
use prometheus::{opts, register_int_counter_vec, IntCounterVec};
use rand::prelude::*;
use std::convert::Infallible;
use warp::{http::Response, Filter, Rejection, Reply};

include!(concat!(env!("OUT_DIR"), "/templates.rs"));

const APPLICATION_NAME: &str = concat!(env!("CARGO_PKG_NAME"), "/", env!("CARGO_PKG_VERSION"));

lazy_static! {
    static ref HIT_COUNTER: IntCounterVec =
        register_int_counter_vec!(opts!("hits", "Number of hits to various pages"), &["page"])
            .unwrap();
}

async fn give_fact(facts: Facts) -> Result<String, Infallible> {
    HIT_COUNTER.with_label_values(&["fact"]).inc();
    Ok(facts.choose(&mut thread_rng()).unwrap().clone())
}

async fn index(facts: Facts) -> Result<impl Reply, Rejection> {
    HIT_COUNTER.with_label_values(&["index"]).inc();
    Response::builder()
        .html(|o| templates::index_html(o, facts.choose(&mut thread_rng()).unwrap().clone()))
}

async fn not_found() -> Result<impl Reply, Rejection> {
    HIT_COUNTER.with_label_values(&["not_found"]).inc();
    Response::builder()
        .status(404)
        .html(|o| templates::not_found_html(o))
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    pretty_env_logger::init();
    let facts = pfacts::make();

    let fact = {
        let facts = facts.clone();
        warp::any().map(move || facts.clone())
    };

    let files = warp::path("static").and(warp::fs::dir("./static"));

    let fact_handler = warp::get()
        .and(warp::path("fact"))
        .and(fact.clone())
        .and_then(give_fact);

    let index_handler = warp::get()
        .and(warp::path::end())
        .and(fact.clone())
        .and_then(index);

    let not_found_handler = warp::any().and_then(not_found);

    log::info!("listening on port 5000");
    warp::serve(
        fact_handler
            .or(index_handler)
            .or(files)
            .or(not_found_handler)
            .with(warp::log(APPLICATION_NAME)),
    )
    .run(([0, 0, 0, 0], 5000))
    .await;
    Ok(())
}
