use std::{
    cell::RefCell,
    env,
    io::{stdin, stdout, Read, Write},
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
use crossterm::{
    event::{self, Event, KeyCode, KeyEvent},
    terminal::{disable_raw_mode, enable_raw_mode},
};
use poc::PocPlugin;
use std::io;
use std::sync::mpsc;
use std::time::Duration;

mod poc;

fn main() -> anyhow::Result<()> {
    if let Some(argument) = env::args().nth(1) {
        match argument.as_str() {
            "client" => run_client(),
            "server" => run_server(),
            _ => panic!("Unknown arguments: {}", argument),
        }
    } else {
        // enable_raw_mode()?;

        let filename = env::current_exe()?;

        let mut client = Command::new(&filename)
            .arg("client")
            .stdout(stdout())
            .spawn()?;

        let mut server = Command::new(&filename)
            .arg("server")
            .stdout(stdout())
            .spawn()?;

        loop {
            if event::poll(Duration::from_millis(100))? {
                match event::read()? {
                    event::Event::Key(event::KeyEvent { code, kind, .. }) => {
                        if kind != event::KeyEventKind::Press {
                            continue;
                        }

                        if code == KeyCode::Enter {
                            println!("Closing: Polled enter");
                            break;
                        }
                    }
                    _ => {}
                }
            } else {
                if client.try_wait().map(|x| x.is_some()).unwrap_or(true) {
                    println!("Closing: Client dead");
                    break;
                }

                if server.try_wait().map(|x| x.is_some()).unwrap_or(true) {
                    println!("Closing: Server dead");
                    break;
                }
            }
        }

        let _ = client.kill();
        let _ = server.kill();

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
    .add_plugins(PocPlugin {
        typ: poc::PocType::Client,
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
    .add_plugins(PocPlugin {
        typ: poc::PocType::Server,
    })
    .run();

    Ok(())
}
