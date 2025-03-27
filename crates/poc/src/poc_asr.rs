use std::net::Ipv4Addr;

use bevy::prelude::*;
use bevy_defer::{AsyncCommandsExtension, AsyncPlugin, AsyncWorld};
use bevy_quinnet::{
    client::{
        certificate::CertificateVerificationMode, connection::ClientEndpointConfiguration,
        QuinnetClient, QuinnetClientPlugin,
    },
    server::{
        self, certificate::CertificateRetrievalMode, ConnectionEvent, QuinnetServer,
        QuinnetServerPlugin, ServerEndpointConfiguration,
    },
    shared::channels::ChannelsConfiguration,
};
use serde::{Deserialize, Serialize};

pub struct PocAsrClientPlugin {
    pub ip: Ipv4Addr,
    pub port: u16,
}

impl Plugin for PocAsrClientPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(QuinnetClientPlugin::default())
            .add_plugins(PocAsrGamePlugin);

        app.world_mut()
            .resource_scope(|_, mut client: Mut<QuinnetClient>| {
                client
                    .open_connection(
                        ClientEndpointConfiguration::from_ips(
                            self.ip,
                            self.port,
                            Ipv4Addr::UNSPECIFIED,
                            0,
                        ),
                        CertificateVerificationMode::SkipVerification,
                        ChannelsConfiguration::default(),
                    )
                    .expect("Failed to connect");
            })
    }
}

pub struct PocAsrServerPlugin {
    pub port: u16,
}

impl Plugin for PocAsrServerPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(AsyncPlugin::default_settings())
            .add_plugins(QuinnetServerPlugin::default())
            .add_plugins(PocAsrGamePlugin)
            .add_systems(FixedUpdate, update_server)
            .add_observer(server_on_connect);

        app.world_mut()
            .resource_scope(|_, mut server: Mut<QuinnetServer>| {
                server
                    .start_endpoint(
                        ServerEndpointConfiguration::from_ip(Ipv4Addr::UNSPECIFIED, self.port),
                        CertificateRetrievalMode::GenerateSelfSigned {
                            server_hostname: Ipv4Addr::LOCALHOST.to_string(),
                        },
                        ChannelsConfiguration::default(),
                    )
                    .expect("Failed to serve")
            });
    }
}

pub struct PocAsrGamePlugin;

impl Plugin for PocAsrGamePlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, startup_game);
    }
}

#[derive(Serialize, Deserialize)]
enum ServerMessage {
    State(ServerStateChanges),
}

#[derive(Serialize, Deserialize)]
struct ServerStateChanges {
    changes: Vec<ServerStateChangesPlayer>,
}

struct Change {}

impl Change {}

#[derive(Serialize, Deserialize)]
enum ClientMessage {
    Move { dir: Vec2 },
}

fn server_on_connect(
    trigger: Trigger<ConnectionEvent>,
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<ColorMaterial>>,
) {
    commands.spawn((
        Mesh2d(meshes.add(Circle::new(5.0))),
        MeshMaterial2d(materials.add(Color::linear_rgba(1.0, 1.0, 1.0, 1.0))),
        PlayerComponent {
            player_id: trigger.id,
        },
        Transform::from_xyz(0.0, 0.0, 0.0),
    ));
}

fn update_server(
    mut commands: Commands,
    mut server: ResMut<QuinnetServer>,
    mut players: Query<(&mut Transform, &mut PlayerComponent)>,
) {
    let endpoint = server.endpoint_mut();

    for client_id in endpoint.clients() {
        while let Some((_channel_id, message)) =
            endpoint.try_receive_message_from::<ClientMessage>(client_id)
        {
            commands.spawn_task(async move || {
                match message {
                    _ => {}
                }

                Ok(())
            });
        }
    }
}

fn startup_game(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<ColorMaterial>>,
) {
    commands.spawn(Camera2d);
}

#[derive(Component)]
pub struct PlayerComponent {
    player_id: u64,
}
