use std::{
    cell::RefCell,
    env,
    io::{stdin, stdout},
    net::Ipv4Addr,
    process::{self, Command},
    rc::Rc,
    str::FromStr,
    sync::{mpsc::Sender, Arc, Mutex},
    thread,
};

use anyhow::Result;
use bevy::{app::PluginsState, prelude::*, tasks::tick_global_task_pools_on_main_thread};
use bevy_quinnet::{
    client::connection::ClientEndpointConfiguration, server::ServerEndpointConfiguration,
};
use poc_asr::{PocAsrClientPlugin, PocAsrServerPlugin};
use std::sync::mpsc;

mod poc_asr;
mod poc_baseline;

fn main() -> anyhow::Result<()> {
    if let Some(argument) = env::args().nth(1) {
        match argument.as_str() {
            "client" => run_client(),
            "server" => run_server(),
            _ => panic!("Unknown arguments: {}", argument),
        }
    } else {
        let filename = env::current_exe()?;
        Command::new(&filename)
            .arg("client")
            .stdout(stdout())
            .spawn()?;
        Command::new(&filename)
            .arg("server")
            .stdout(stdout())
            .spawn()?;

        Ok(())
    }
}

fn run_client() -> Result<()> {
    let mut app = App::new();

    app.add_plugins(DefaultPlugins.set(WindowPlugin {
        primary_window: Some(Window {
            title: "Client".to_string(),
            ..Default::default()
        }),
        ..default()
    }))
    .add_plugins(PocAsrClientPlugin {
        ip: Ipv4Addr::LOCALHOST,
        port: 23454,
    })
    .run();

    Ok(())
}

fn run_server() -> Result<()> {
    let mut app = App::new();

    app.add_plugins(DefaultPlugins.set(WindowPlugin {
        primary_window: Some(Window {
            title: "Server".to_string(),
            ..Default::default()
        }),
        ..default()
    }))
    .add_plugins(PocAsrServerPlugin { port: 23454 })
    .run();

    Ok(())
}
