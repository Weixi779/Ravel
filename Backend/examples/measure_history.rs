//
//  measure_history.rs
//  Ravel
//
//  Created by weixi on 2026/09/17.
//  Copyright © 2026 Ravel. All rights reserved.
//

// Read-only diagnostic: cargo run --release --example measure_history -- <workspace> [page-size]
use ravel_backend::{BackendCancellation, BackendRepository};
use std::{sync::Arc, time::Instant};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    pollster::block_on(measure())
}

async fn measure() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args().nth(1).ok_or("Expected a workspace path")?;
    let page_size = std::env::args()
        .nth(2)
        .unwrap_or_else(|| "200".into())
        .parse()?;
    let started = Instant::now();
    let repository = BackendRepository::open(path).await?;
    let query = repository
        .history(page_size, Arc::new(BackendCancellation::new()))
        .await?;
    println!("open: {:.3}s", started.elapsed().as_secs_f64());
    let mut cursor = 0;
    let mut count = 0;
    loop {
        let page = query
            .page(cursor, Arc::new(BackendCancellation::new()))
            .await?;
        count += page.revisions.len();
        if cursor == 0 {
            println!(
                "first page: {:.3}s ({} rows)",
                started.elapsed().as_secs_f64(),
                count
            );
        }
        match page.next_cursor {
            Some(next) => cursor = next,
            None => break,
        }
    }
    println!(
        "all: {:.3}s ({} rows, native metadata only)",
        started.elapsed().as_secs_f64(),
        count
    );
    repository.close().await;
    Ok(())
}
