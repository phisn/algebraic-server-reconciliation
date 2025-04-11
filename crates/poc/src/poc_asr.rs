use std::{any::TypeId, collections::HashMap, net::Ipv4Addr, sync::Arc};

use bevy::{ecs::component::ComponentId, prelude::*};
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
    shared::channels::{
        ChannelId, ChannelKind, ChannelsConfiguration, DEFAULT_MAX_RELIABLE_FRAME_LEN,
    },
};
use serde::{Deserialize, Serialize};

pub struct PocAsrClientPlugin {
    pub ip: Ipv4Addr,
    pub port: u16,
}

impl Plugin for PocAsrClientPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(PocAsrGamePlugin)
            .add_plugins(QuinnetClientPlugin::default());

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
                        ClientChannel::channels_configuration(),
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
            .add_plugins(PocAsrGamePlugin)
            .add_plugins(QuinnetServerPlugin::default())
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
                        ServerChannel::channels_configuration(),
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
    commands.spawn(Camera2d).despawn();
}

#[derive(Component)]
pub struct PlayerComponent {
    player_id: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct AsrState {
    last_entity_id: u32,
    entities: HashMap<u32, AsrEntity>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct AsrEntity {
    cardinality: i8,
    components: HashMap<u32, AsrComponent>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct AsrComponent {
    cardinality: i8,
    data: Vec<u8>,
}

trait DynamicComponent {}

#[derive(Debug, Clone, Serialize, Deserialize)]
enum ClientMessage {
    Action { message: ClientMessageAction },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ClientMessageAction {
    movement: Vec2,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
enum ServerMessage {
    State { message: ServerMessageStateDelta },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ServerMessageStateDelta {}

#[repr(u8)]
pub enum ClientChannel {
    Action,
}

impl Into<ChannelId> for ClientChannel {
    fn into(self) -> ChannelId {
        self as ChannelId
    }
}

impl ClientChannel {
    pub fn channels_configuration() -> ChannelsConfiguration {
        ChannelsConfiguration::from_types(vec![ChannelKind::OrderedReliable {
            max_frame_size: DEFAULT_MAX_RELIABLE_FRAME_LEN,
        }])
        .unwrap()
    }
}

#[repr(u8)]
pub enum ServerChannel {
    State,
}

impl Into<ChannelId> for ServerChannel {
    fn into(self) -> ChannelId {
        self as ChannelId
    }
}

impl ServerChannel {
    pub fn channels_configuration() -> ChannelsConfiguration {
        ChannelsConfiguration::from_types(vec![ChannelKind::UnorderedReliable {
            max_frame_size: DEFAULT_MAX_RELIABLE_FRAME_LEN,
        }])
        .unwrap()
    }
}
