use std::{any::TypeId, collections::HashMap, marker::PhantomData, net::Ipv4Addr, sync::Arc};

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
use serde::{de::DeserializeOwned, Deserialize, Serialize};

pub struct NetworkClientPlugin {
    pub ip: Ipv4Addr,
    pub port: u16,
}

impl Plugin for NetworkClientPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins((
            AsyncPlugin::default_settings(),
            QuinnetClientPlugin::default(),
        ))
        .add_systems(FixedUpdate, fixed_update_client);

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

fn fixed_update_client() {}

pub struct NetworkServerPlugin {
    pub port: u16,
}

impl Plugin for NetworkServerPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(AsyncPlugin::default_settings())
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

fn server_on_connect(
    trigger: Trigger<ConnectionEvent>,
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<ColorMaterial>>,
) {
}

fn update_server(
    mut commands: Commands,
    mut server: ResMut<QuinnetServer>,
    mut clients: Query<(&mut Transform, &mut ClientConntected)>,
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

trait AppExt {
    fn replicate_input<I: Resource + Serialize + DeserializeOwned>(&mut self);
    fn replicate_component<E: Component + Serialize + DeserializeOwned>(&mut self);
    fn replicate_component_asr<E: Component + Serialize + DeserializeOwned>(&mut self);
    fn replicate_component_rsr<E: Component, Serialize, DeserializeOwned>(&mut self);
}

trait AbelianGroup {
    fn add_mut(&mut self, other: &Self) -> Self;
    fn neg_mut(&mut self) -> Self;
}

impl AppExt for App {
    fn replicate_input<I: Resource + Serialize + DeserializeOwned>(&mut self) {}
    fn replicate_component<E: Component + Serialize + DeserializeOwned>(&mut self) {}
    fn replicate_component_asr<E: Component + Serialize + DeserializeOwned>(&mut self) {}
    fn replicate_component_rsr<E: Component, Serialize, DeserializeOwned>(&mut self) {}
}

fn update_client<T>(mut world: World) {}

#[derive(Component)]
pub struct ClientConntected {
    player_id: u64,
}

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
