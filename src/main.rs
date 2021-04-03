use crate::templates::RenderRucte;
use hyper::{header::CONTENT_TYPE, Body, Response};
use lazy_static::lazy_static;
use pfacts::Facts;
use prometheus::{opts, register_int_counter_vec, Encoder, IntCounterVec, TextEncoder};
use rand::prelude::*;
use std::{convert::Infallible, str::FromStr};
use tokio::net::UnixListener;
use tokio_stream::wrappers::UnixListenerStream;
use warp::{Filter, Rejection, Reply};

include!(concat!(env!("OUT_DIR"), "/templates.rs"));

const APPLICATION_NAME: &str = concat!(env!("CARGO_PKG_NAME"), "/", env!("CARGO_PKG_VERSION"));

lazy_static! {
    static ref HIT_COUNTER: IntCounterVec = register_int_counter_vec!(
        opts!("printerfacts_hits", "Number of hits to various pages"),
        &["page"]
    )
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
    tracing_subscriber::fmt::init();
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

    let metrics_endpoint = warp::path("metrics").and(warp::path::end()).map(move || {
        let encoder = TextEncoder::new();
        let metric_families = prometheus::gather();
        let mut buffer = vec![];
        encoder.encode(&metric_families, &mut buffer).unwrap();
        Response::builder()
            .status(200)
            .header(CONTENT_TYPE, encoder.format_type())
            .body(Body::from(buffer))
            .unwrap()
    });

    let server = warp::serve(
        fact_handler
            .or(index_handler)
            .or(files)
            .or(metrics_endpoint)
            .or(not_found_handler)
            .with(warp::log(APPLICATION_NAME)),
    );

    if let Ok(sockpath) = std::env::var("SOCKPATH") {
        let _ = std::fs::remove_file(&sockpath);
        let listener = UnixListener::bind(sockpath).unwrap();
        let incoming = UnixListenerStream::new(listener);
        server.run_incoming(incoming).await;

        Ok(())
    } else {
        let port = std::env::var("PORT")
            .unwrap_or("5000".into())
            .parse::<u16>()
            .expect("PORT to be a string-encoded u16");
        tracing::info!("listening on port {}", port);
        server
            .run((std::net::IpAddr::from_str("::").unwrap(), port))
            .await;

        Ok(())
    }
}
