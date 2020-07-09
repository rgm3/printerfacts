use handlebars::Handlebars;
use pfacts::Facts;
use rand::prelude::*;
use serde::Serialize;
use std::{convert::Infallible, sync::Arc};
use warp::Filter;

async fn give_fact(facts: Facts) -> Result<String, Infallible> {
    Ok(facts.choose(&mut thread_rng()).unwrap().clone())
}

#[derive(Serialize)]
struct TemplateContext {
    title: &'static str,
    fact: Option<String>,
    // This key tells handlebars which template is the parent.
    parent: &'static str,
}

struct WithTemplate<T: Serialize> {
    name: &'static str,
    value: T,
}

fn render<T>(template: WithTemplate<T>, hbs: Arc<Handlebars>) -> impl warp::Reply
where
    T: Serialize,
{
    let render = hbs
        .render(template.name, &template.value)
        .unwrap_or_else(|err| err.to_string());
    warp::reply::html(render)
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    pretty_env_logger::init();
    let facts = pfacts::make();
    let mut hb = Handlebars::new();

    hb.register_template_file("layout", "./templates/layout.hbs")?;
    hb.register_template_file("footer", "./templates/footer.hbs")?;
    hb.register_template_file("index", "./templates/index.hbs")?;
    hb.register_template_file("error/404", "./templates/error/404.hbs")?;

    let fact = {
        let facts = facts.clone();
        warp::any().map(move || facts.clone())
    };
    let hb = Arc::new(hb);
    let handlebars = move |with_template| render(with_template, hb.clone());

    let files = warp::path("static").and(warp::fs::dir("./static"));

    let fact_handler = warp::get()
        .and(warp::path("fact"))
        .and(fact)
        .and_then(give_fact);

    let index_handler = warp::get()
        .and(warp::path::end())
        .map(move || WithTemplate {
            name: "index",
            value: TemplateContext {
                title: "Printer Facts",
                fact: {
                    let ref facts = facts.clone();
                    Some(facts.choose(&mut thread_rng()).unwrap().clone())
                },
                parent: "layout",
            },
        })
        .map(handlebars.clone());

    let not_found_handler = warp::any()
        .map(move || WithTemplate {
            name: "error/404",
            value: TemplateContext {
                title: "Not Found",
                fact: None,
                parent: "layout",
            },
        })
        .map(handlebars.clone());

    log::info!("listening on port 5000");
    warp::serve(
        fact_handler
            .or(index_handler)
            .or(files)
            .or(not_found_handler),
    )
    .run(([0, 0, 0, 0], 5000))
    .await;
    Ok(())
}
