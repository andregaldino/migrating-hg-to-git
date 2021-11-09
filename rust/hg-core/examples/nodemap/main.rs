// Copyright 2019-2020 Georges Racinet <georges.racinet@octobus.net>
//
// This software may be used and distributed according to the terms of the
// GNU General Public License version 2 or any later version.

use clap::*;
use hg::revlog::node::*;
use hg::revlog::nodemap::*;
use hg::revlog::*;
use memmap2::MmapOptions;
use rand::Rng;
use std::fs::File;
use std::io;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::time::Instant;

mod index;
use index::Index;

fn mmap_index(repo_path: &Path) -> Index {
    let mut path = PathBuf::from(repo_path);
    path.extend([".hg", "store", "00changelog.i"].iter());
    Index::load_mmap(path)
}

fn mmap_nodemap(path: &Path) -> NodeTree {
    let file = File::open(path).unwrap();
    let mmap = unsafe { MmapOptions::new().map(&file).unwrap() };
    let len = mmap.len();
    NodeTree::load_bytes(Box::new(mmap), len)
}

/// Scan the whole index and create the corresponding nodemap file at `path`
fn create(index: &Index, path: &Path) -> io::Result<()> {
    let mut file = File::create(path)?;
    let start = Instant::now();
    let mut nm = NodeTree::default();
    for rev in 0..index.len() {
        let rev = rev as Revision;
        nm.insert(index, index.node(rev).unwrap(), rev).unwrap();
    }
    eprintln!("Nodemap constructed in RAM in {:?}", start.elapsed());
    file.write(&nm.into_readonly_and_added_bytes().1)?;
    eprintln!("Nodemap written to disk");
    Ok(())
}

fn query(index: &Index, nm: &NodeTree, prefix: &str) {
    let start = Instant::now();
    let res = NodePrefix::from_hex(prefix).map(|p| nm.find_bin(index, p));
    println!("Result found in {:?}: {:?}", start.elapsed(), res);
}

fn bench(index: &Index, nm: &NodeTree, queries: usize) {
    let len = index.len() as u32;
    let mut rng = rand::thread_rng();
    let nodes: Vec<Node> = (0..queries)
        .map(|_| {
            index
                .node((rng.gen::<u32>() % len) as Revision)
                .unwrap()
                .clone()
        })
        .collect();
    if queries < 10 {
        let nodes_hex: Vec<String> =
            nodes.iter().map(|n| format!("{:x}", n)).collect();
        println!("Nodes: {:?}", nodes_hex);
    }
    let mut last: Option<Revision> = None;
    let start = Instant::now();
    for node in nodes.iter() {
        last = nm.find_bin(index, node.into()).unwrap();
    }
    let elapsed = start.elapsed();
    println!(
        "Did {} queries in {:?} (mean {:?}), last was {:x} with result {:?}",
        queries,
        elapsed,
        elapsed / (queries as u32),
        nodes.last().unwrap(),
        last
    );
}

fn main() {
    let matches = App::new("Nodemap pure Rust example")
        .arg(
            Arg::with_name("REPOSITORY")
                .help("Path to the repository, always necessary for its index")
                .required(true),
        )
        .arg(
            Arg::with_name("NODEMAP_FILE")
                .help("Path to the nodemap file, independent of REPOSITORY")
                .required(true),
        )
        .subcommand(
            SubCommand::with_name("create")
                .about("Create NODEMAP_FILE by scanning repository index"),
        )
        .subcommand(
            SubCommand::with_name("query")
                .about("Query NODEMAP_FILE for PREFIX")
                .arg(Arg::with_name("PREFIX").required(true)),
        )
        .subcommand(
            SubCommand::with_name("bench")
                .about(
                    "Perform #QUERIES random successful queries on NODEMAP_FILE")
                .arg(Arg::with_name("QUERIES").required(true)),
        )
        .get_matches();

    let repo = matches.value_of("REPOSITORY").unwrap();
    let nm_path = matches.value_of("NODEMAP_FILE").unwrap();

    let index = mmap_index(&Path::new(repo));

    if let Some(_) = matches.subcommand_matches("create") {
        println!("Creating nodemap file {} for repository {}", nm_path, repo);
        create(&index, &Path::new(nm_path)).unwrap();
        return;
    }

    let nm = mmap_nodemap(&Path::new(nm_path));
    if let Some(matches) = matches.subcommand_matches("query") {
        let prefix = matches.value_of("PREFIX").unwrap();
        println!(
            "Querying {} in nodemap file {} of repository {}",
            prefix, nm_path, repo
        );
        query(&index, &nm, prefix);
    }
    if let Some(matches) = matches.subcommand_matches("bench") {
        let queries =
            usize::from_str(matches.value_of("QUERIES").unwrap()).unwrap();
        println!(
            "Doing {} random queries in nodemap file {} of repository {}",
            queries, nm_path, repo
        );
        bench(&index, &nm, queries);
    }
}
