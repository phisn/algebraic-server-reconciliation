use std::net::{Ipv4Addr, Ipv6Addr};

use avian2d::{
    interpolation,
    math::PI,
    prelude::{
        Collider, Gravity, LinearVelocity, PhysicsInterpolationPlugin, RigidBody,
        TransformInterpolation,
    },
    sync::SyncPlugin,
    PhysicsPlugins,
};
use bevy::{prelude::*, render::camera::CameraProjection, ui::update};
use bevy_defer::{AsyncAccess, AsyncCommandsExtension, AsyncPlugin, AsyncWorld};
use bevy_quinnet::{
    client::{
        certificate::CertificateVerificationMode,
        client_just_connected,
        connection::{ClientEndpointConfiguration, ConnectionEvent, ConnectionFailedEvent},
        QuinnetClient,
    },
    server::{certificate::CertificateRetrievalMode, QuinnetServer, ServerEndpointConfiguration},
    shared::channels::ChannelsConfiguration,
};
use bevy_replicon::{
    client::ClientPlugin,
    prelude::{
        AppRuleExt, Channel, ClientEventAppExt, ClientEventPlugin, ClientTriggerAppExt,
        ClientTriggerExt, ConnectedClient, FromClient, Replicated, RepliconChannels,
        ServerEventPlugin, ServerTriggerAppExt,
    },
    server::{
        server_tick::ServerTick, ReplicatedClient, ServerPlugin, TickPolicy, VisibilityPolicy,
    },
    shared::{
        backend::{connected_client::NetworkId, replicon_client},
        replication::replication_rules::ReplicationRule,
        RepliconSharedPlugin,
    },
    RepliconPlugins,
};
use bevy_replicon_quinnet::{
    client::RepliconQuinnetClientPlugin, server::RepliconQuinnetServerPlugin,
    ChannelsConfigurationExt, RepliconQuinnetPlugins,
};
use bevy_transform_interpolation::prelude::TransformInterpolationPlugin;
use movement::{Movement, MovementConfig, MovementController, MovementInput, MovementPlugin};
use serde::{Deserialize, Serialize};

mod movement;

pub struct PocPlugin {
    pub typ: PocType,
}

pub enum PocType {
    Client,
    Server,
}

const PORT: u16 = 24325;

impl Plugin for PocPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins((AsyncPlugin::default_settings(), RepliconSharedPlugin));

        match self.typ {
            PocType::Client => {
                app.add_plugins((
                    ClientPlugin,
                    ClientEventPlugin,
                    RepliconQuinnetClientPlugin,
                    TransformInterpolationPlugin::default(),
                ))
                .add_observer(observer_client_init_player)
                .add_observer(observer_client_init_terrain)
                .add_systems(
                    Update,
                    (
                        system_client_connection_failed,
                        system_client_connection_handler,
                    ),
                )
                .add_systems(Startup, system_client_init)
                .add_systems(FixedUpdate, system_client_input);
            }
            PocType::Server => {
                app.add_plugins((
                    PhysicsPlugins::default(),
                    RepliconQuinnetServerPlugin,
                    ServerPlugin {
                        tick_policy: TickPolicy::Manual,
                        // visibility_policy: VisibilityPolicy::Whitelist,
                        replicate_after_connect: false,
                        ..default()
                    },
                    ServerEventPlugin,
                ))
                .add_observer(observer_client_init_player)
                .add_observer(observer_client_init_terrain)
                .add_observer(observer_server_client_connected)
                .add_systems(Startup, system_server_init)
                .add_systems(
                    FixedUpdate,
                    (
                        system_server_login,
                        system_server_movement,
                        system_server_tick,
                    ),
                )
                .insert_resource(Gravity(Vec2::new(0.0, -1000.0)));
            }
        }

        app.add_plugins(MovementPlugin)
            .replicate::<Player>()
            .replicate::<Terrain>()
            .replicate::<Transform>()
            .add_event::<Login>()
            .add_client_event::<Login>(Channel::Ordered);
    }
}

fn system_server_tick(mut tick: ResMut<ServerTick>) {
    tick.increment();
}

fn system_server_init(
    mut commands: Commands,
    mut server: ResMut<QuinnetServer>,
    channels: Res<RepliconChannels>,
) {
    commands.spawn((
        Camera2d,
        Projection::Orthographic(OrthographicProjection {
            scale: 1.0,
            ..OrthographicProjection::default_2d()
        }),
    ));

    commands.spawn((
        Terrain {
            width: 500.0,
            height: 20.0,
        },
        Transform::from_xyz(100.0, -100.0, 0.0),
        Replicated,
        RigidBody::Kinematic,
        Collider::rectangle(500.0, 20.0),
    ));

    server
        .start_endpoint(
            ServerEndpointConfiguration::from_ip(Ipv4Addr::LOCALHOST, PORT),
            CertificateRetrievalMode::GenerateSelfSigned {
                server_hostname: Ipv6Addr::LOCALHOST.to_string(),
            },
            channels.client_configs(),
        )
        .unwrap();
}

fn observer_server_client_connected(trigger: Trigger<OnAdd, NetworkId>, mut commands: Commands) {
    let client_entity = trigger.target();

    commands.spawn_task(async move || {
        AsyncWorld.sleep(5).await;

        let connected = AsyncWorld
            .entity(client_entity)
            .query::<Option<&ClientInfo>>()
            .get(|x| x.is_some())
            .unwrap_or(false);

        if !connected {
            println!("Client timed out");
        }

        Ok(())
    });
}

fn system_server_login(mut reader_login: EventReader<FromClient<Login>>, mut commands: Commands) {
    for login in reader_login.read() {
        let player_id = login.player_id;

        println!("Got login by {}", player_id);

        let collider = Collider::capsule(10.0, 30.0);

        let player = commands
            .spawn((
                MovementController::new(
                    collider,
                    MovementConfig {
                        acceleration: 1250.0,
                        damping: 0.92,
                        jump_impulse: 300.0,
                        max_slope_angle: Some(30.0f32.to_radians()),
                    },
                ),
                Player { player_id },
                Transform::from_translation(Vec3 {
                    x: 0.0,
                    y: 100.0,
                    z: 0.0,
                }),
                Replicated,
            ))
            .id();

        commands
            .entity(login.client_entity)
            .insert((ClientInfo { player, player_id }, ReplicatedClient));
    }
}

fn system_server_movement(
    mut read_movement: EventReader<FromClient<MovementInput>>,
    query_client_info: Query<&ClientInfo>,
    mut query_player: Query<&mut Movement>,
) {
    for movement in read_movement.read() {
        let Ok(client_info) = query_client_info.get(movement.client_entity) else {
            println!("Client tried to move but was not initialized");
            continue;
        };

        let Ok(mut player) = query_player.get_mut(client_info.player) else {
            println!("Client tried to move but was not initialized'");
            continue;
        };

        println!("Moving {:?}", player.input);

        player.input = Some(movement.event.clone());
        player.uses = 0;
    }
}

fn system_client_init(
    mut commands: Commands,
    mut client: ResMut<QuinnetClient>,
    channels: Res<RepliconChannels>,
) {
    commands.spawn((
        Camera2d,
        Projection::Orthographic(OrthographicProjection {
            scale: 1.0,
            ..OrthographicProjection::default_2d()
        }),
    ));

    client
        .open_connection(
            ClientEndpointConfiguration::from_ips(
                Ipv4Addr::LOCALHOST,
                PORT,
                Ipv6Addr::UNSPECIFIED,
                0,
            ),
            CertificateVerificationMode::SkipVerification,
            channels.client_configs(),
        )
        .unwrap();
}

fn system_client_connection_handler(
    mut reader_connected: EventReader<ConnectionEvent>,
    mut writer_login: EventWriter<Login>,
) {
    let player_id = rand::random::<u64>();

    for _ in reader_connected.read() {
        writer_login.write(Login { player_id });
        println!("Logging in {}", player_id)
    }
}

fn system_client_connection_failed(
    mut reader_connection_failed: EventReader<ConnectionFailedEvent>,
) {
    for connection_failed in reader_connection_failed.read() {
        println!("Failed to connecto to server {}", connection_failed.err);
    }
}

fn observer_client_init_player(
    trigger: Trigger<OnAdd, Player>,
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<ColorMaterial>>,
) {
    commands.entity(trigger.target()).insert((
        Mesh2d(meshes.add(Capsule2d::new(10.0, 30.0))),
        MeshMaterial2d(materials.add(Color::srgb(1.0, 0.0, 0.0))),
    ));
}

fn observer_client_init_terrain(
    trigger: Trigger<OnAdd, Terrain>,
    query_terrain: Query<&Terrain>,
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<ColorMaterial>>,
) {
    let terrain = query_terrain.get(trigger.target()).unwrap();

    commands.entity(trigger.target()).insert((
        Mesh2d(meshes.add(Rectangle::new(terrain.width, terrain.height))),
        MeshMaterial2d(materials.add(Color::srgb(0.75, 0.75, 0.75))),
    ));
}

fn system_client_input(
    mut writer_movement: EventWriter<MovementInput>,
    keyboard: ResMut<ButtonInput<KeyCode>>,
) {
    let mut input = MovementInput::default();

    if keyboard.pressed(KeyCode::KeyA) {
        input.direction -= 1.0;
    }

    if keyboard.pressed(KeyCode::KeyD) {
        input.direction += 1.0;
    }

    if keyboard.pressed(KeyCode::KeyW) {
        input.jump = true;
    }

    writer_movement.write(input);
}

#[derive(Component)]
struct ClientInfo {
    player: Entity,
    player_id: u64,
}

#[derive(Event, Serialize, Deserialize)]
struct Login {
    player_id: u64,
}

#[derive(Component, Serialize, Deserialize)]
struct Player {
    player_id: u64,
}

#[derive(Component, Serialize, Deserialize)]
struct Terrain {
    width: f32,
    height: f32,
}
