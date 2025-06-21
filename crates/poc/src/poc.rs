use std::{
    collections::VecDeque,
    net::{Ipv4Addr, Ipv6Addr},
    ops::{DerefMut, Sub},
    time::{Duration, Instant},
};

use avian2d::{
    math::PI,
    prelude::{
        AngularVelocity, Collider, Friction, Gravity, LinearDamping, LinearVelocity, Physics,
        PhysicsInterpolationPlugin, PhysicsSchedule, PhysicsSchedulePlugin, RigidBody,
        TransformInterpolation,
    },
    sync::SyncPlugin,
    PhysicsPlugins,
};
use bevy::{
    core_pipeline::core_2d::graph::input,
    ecs::{component::Mutable, schedule::ScheduleLabel},
    math::ops::sin,
    prelude::*,
    render::camera::CameraProjection,
    ui::update,
};
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
use bevy_quinnet::client::client_connected;
use bevy_replicon::{
    client::{confirm_history::ConfirmHistory, ClientPlugin, ClientSet},
    prelude::{
        server_running, AppMarkerExt, AppRuleExt, Channel, ClientEventAppExt, ClientEventPlugin,
        ClientTriggerAppExt, ClientTriggerExt, ClientVisibility, ConnectedClient, FromClient,
        Replicated, RepliconChannels, RepliconClient, ServerEventPlugin, ServerTriggerAppExt,
        SyncRelatedAppExt,
    },
    server::{
        server_tick::ServerTick, ReplicatedClient, ServerPlugin, TickPolicy, VisibilityPolicy,
    },
    shared::{
        backend::{connected_client::NetworkId, replicon_client},
        replication::{
            command_markers::MarkerConfig, replication_registry::rule_fns::RuleFns,
            replication_rules::ReplicationRule,
        },
        replicon_tick::RepliconTick,
        RepliconSharedPlugin,
    },
    RepliconPlugins,
};
use bevy_replicon_quinnet::{
    client::RepliconQuinnetClientPlugin, server::RepliconQuinnetServerPlugin,
    ChannelsConfigurationExt, RepliconQuinnetPlugins,
};
use interpolation::{client_received_replication, Interpolation, InterpolationPlugin};
use movement::{Movement, MovementConfig, MovementController, MovementInput, MovementPlugin};
use serde::{de::DeserializeOwned, Deserialize, Serialize};

use crate::poc::movement::Grounded;

mod interpolation;
mod movement;

pub struct PocPlugin {
    pub typ: PocType,
}

pub enum PocType {
    Client(bool),
    Server,
}

const PORT: u16 = 24325;
const SERVER_CONFIG_HZ: f32 = 30.0;

#[derive(ScheduleLabel, Hash, Debug, Eq, PartialEq, Clone)]
pub struct Simulate;

impl Plugin for PocPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins((AsyncPlugin::default_settings(), RepliconSharedPlugin));

        match self.typ {
            PocType::Client(automatic) => {
                app.add_plugins((
                    PhysicsPlugins::new(Simulate),
                    ClientPlugin,
                    ClientEventPlugin,
                    InterpolationPlugin,
                    RepliconQuinnetClientPlugin,
                ))
                    .add_observer(observe_client_added_owned)
                    .add_observer(observer_client_init_player)
                    .add_observer(observer_client_init_terrain)
                    // .add_observer(observer_client_sync_time)
                    .add_observer(observer_client_new_config)
                    .add_systems(
                        FixedPreUpdate,
                        (system_predict).run_if(predicted_tick_changed).in_set(PredictSystemSet),
                    )
                    .add_systems(
                        Update,
                        (
                            system_client_connection_failed,
                            system_client_connection_handler,
                        ),
                    )
                    .add_systems(Startup, system_client_init)
                    .insert_resource(Gravity(Vec2::new(0.0, -1000.0)))
                    .init_resource::<ClientContext>()
                    .init_resource::<InputMemory>();

                app.add_systems(
                    FixedPostUpdate,
                    |query: Query<(&Predicted, &Transform, &LinearVelocity)>| {
                        if let Ok((_, t, lv)) = query.single() {
                            println!("after fu = y: {}, yt: {}", t.translation.y, lv.0.y);
                        }
                    },
                );

                if automatic {
                    app.add_systems(
                        FixedUpdate,
                        (
                            system_client_input_automatic,
                            system_capture_input,
                            system_simulate,
                        )
                            .chain(),
                    );
                } else {
                    app.add_systems(
                        FixedUpdate,
                        (system_client_input, system_capture_input, system_simulate).chain(),
                    );
                }
            }
            PocType::Server => {
                app.add_plugins((
                    PhysicsPlugins::new(Simulate),
                    RepliconQuinnetServerPlugin,
                    ServerPlugin {
                        tick_policy: TickPolicy::Manual,
                        replicate_after_connect: false,
                        visibility_policy: VisibilityPolicy::Whitelist,
                        ..default()
                    },
                    ServerEventPlugin,
                ))
                    //.add_observer(observer_client_init_player)
                    .add_observer(observer_client_init_terrain)
                    .add_observer(observer_server_client_connected)
                    .add_observer(observer_client_spawn)
                    .add_systems(Startup, system_server_init)
                    .add_systems(
                        FixedUpdate,
                        (
                            system_server_login,
                            system_server_movement,
                            system_server_tick,
                            system_simulate,
                            system_progress_input,
                            system_ack_movment::<LinearVelocity>,
                            system_ack_movment::<AngularVelocity>,
                            system_ack_movment::<Transform>,
                            system_ack_movment::<Grounded>,
                        )
                            .chain(),
                    )
                    .sync_related_entities::<Owned>()
                    .insert_resource(Gravity(Vec2::new(0.0, -1000.0)))
                    .init_resource::<ClientContext>();
            }
        }

        app.add_plugins(MovementPlugin)
            .replicate::<Collider>()
            .replicate::<IndividualServerConfig>()
            .replicate::<Owned>()
            .replicate::<Player>()
            .replicate::<Terrain>()
            .replicate::<LinearVelocity>()
            .replicate::<AngularVelocity>()
            .replicate::<Transform>()
            .replicate::<Grounded>()
            .add_event::<Login>()
            .insert_resource(Time::<Fixed>::from_hz(SERVER_CONFIG_HZ as f64))
            .add_client_event::<Login>(Channel::Ordered);

        app.register_marker_with::<Predicted>(MarkerConfig {
            need_history: false,
            ..Default::default()
        }).replicate_predicted::<LinearVelocity>()
            .replicate_predicted::<AngularVelocity>()
            .replicate_predicted::<Transform>()
            .replicate_predicted::<Grounded>();
    }
}

#[derive(SystemSet, Clone, Copy, Debug, Hash, PartialEq, Eq)]
struct PredictSystemSet;

trait AppExt {
    fn replicate_predicted<C: Clone + Component + Serialize + DeserializeOwned>(
        &mut self,
    ) -> &mut Self;
}

impl AppExt for App {
    fn replicate_predicted<C: Clone + Component + Serialize + DeserializeOwned>(
        &mut self,
    ) -> &mut Self {
        self.add_systems(FixedUpdate, system_ack_movment::<C>.run_if(server_running))
            .add_systems(
                FixedPreUpdate,
                (
                    system_find_new_min_ack::<C>,
                    system_predict_prune_components::<C>.run_if(predicted_tick_changed),
                ).before(PredictSystemSet).run_if(client_connected),
            )
            .set_marker_fns::<Predicted, AckComponent<C>>(
                |ctx, rules, entity, data| {
                    let component = rules.deserialize(ctx, data)?;

                    if let None = entity.get::<C>() {
                        ctx.commands
                            .entity(entity.id())
                            .insert(component.value.clone());
                    }

                    if let Some(mut memory) = entity.get_mut::<PredictedMemory<C>>() {
                        if memory
                            .values
                            .back()
                            .map(|x| x.1.get() < component.ack_tick.get())
                            .unwrap_or(true)
                        {
                            memory
                                .values
                                .push_back((component.value.clone(), component.ack_tick));
                        }
                    } else {
                        let mut values = VecDeque::new();
                        values.push_back((component.value, component.ack_tick));
                        ctx.commands
                            .entity(entity.id())
                            .insert(PredictedMemory { values });
                    }

                    Ok(())
                },
                |ctx, entity| {
                    ctx.commands.entity(entity.id()).remove::<C>();
                    ctx.commands
                        .entity(entity.id())
                        .remove::<PredictedMemory<C>>();
                },
            );

        self
    }
}

#[derive(Resource, Default)]
pub struct ClientContext {
    pub individual_config: Option<Entity>,
    pub player_entity: Option<Entity>,
    pub player_id: Option<u64>,
    pub tick: RepliconTick,
}

fn system_server_tick(mut res_tick: ResMut<ServerTick>) {
    res_tick.increment();
}

fn system_simulate(world: &mut World) {
    world.run_schedule(Simulate);
}

fn system_progress_input(movement_query: Query<&mut Movement>) {
    for mut movement in movement_query {
        let Some(input) = &mut movement.input else {
            continue;
        };

        input.tick = RepliconTick::new(input.tick.get() + 1);
    }
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

fn observer_client_spawn(
    trigger: Trigger<OnAdd, ClientVisibility>,
    mut query_client_visibility: Query<&mut ClientVisibility>,
    query_players: Query<Entity, With<Player>>,
    query_terrain: Query<Entity, With<Terrain>>,
    query_info: Query<&ClientInfo>,
) {
    let mut client_visibility = query_client_visibility.get_mut(trigger.target()).unwrap();

    for entity in query_players.iter().chain(query_terrain) {
        client_visibility.set_visibility(entity, true);
    }

    let info = query_info.get(trigger.target()).unwrap();
    client_visibility.set_visibility(info.individual_config, true);
    println!(
        "Setting {} = {}",
        info.player_id,
        info.individual_config.to_bits()
    );
}

fn system_server_login(
    mut reader_login: EventReader<FromClient<Login>>,
    mut commands: Commands,
    mut query_client_visibility: Query<&mut ClientVisibility>,
) {
    for login in reader_login.read() {
        let player_id = login.player_id;

        println!("Got login by {}", player_id);

        let collider = Collider::capsule(10.0, 30.0);

        let player = commands
            .spawn((
                MovementController::new(
                    collider,
                    MovementConfig {
                        acceleration: 2250.0,
                        damping: 0.92,
                        jump_impulse: 300.0,
                        max_slope_angle: Some(30.0f32.to_radians()),
                        max_velocity: 250.0,
                    },
                ),
                Player { player_id },
                Transform::from_translation(Vec3 {
                    x: 0.0,
                    y: 100.0,
                    z: 0.0,
                }),
                Replicated,
                Owned {
                    owner: login.client_entity,
                    owner_player_id: player_id,
                },
                InputAck {
                    ack_tick: RepliconTick::new(0),
                },
            ))
            .id();

        for mut client_visibility in &mut query_client_visibility {
            client_visibility.set_visibility(player, true);
        }

        let config = commands
            .spawn((
                Replicated,
                IndividualServerConfig {
                    player_id: player_id,
                    hz: SERVER_CONFIG_HZ,
                    owns: vec![],
                },
            ))
            .id();

        commands.entity(login.client_entity).insert((
            ClientInfo {
                individual_config: config,
                player,
                player_id,
            },
            ReplicatedClient,
        ));
    }
}

fn system_server_movement(
    mut commands: Commands,
    mut read_movement: EventReader<FromClient<MovementInput>>,
    query_client_info: Query<&ClientInfo>,
    mut query_player: Query<&mut Movement>,
) {
    for movement in read_movement.read() {
        let client_entity = movement.client_entity;

        let Ok(client_info) = query_client_info.get(client_entity).cloned() else {
            println!("Client tried to move but was not initialized");
            continue;
        };

        let movement = movement.event.clone();

        commands.spawn_task(async move || {
            AsyncWorld.sleep(0.25).await;

            AsyncWorld.query::<&mut Movement>().get_mut(|mut x| {
                let mut player = x.get_mut(client_info.player).unwrap();
                player.input = Some(movement.clone());
                player.uses = 0;
            })?;

            Ok(())
        });
    }
}

fn system_ack_movment<C: Component + Clone>(
    input_ack_query: Query<(&C, &mut AckComponent<C>, &Movement)>,
) {
    for (component, mut to_ack, movement) in input_ack_query {
        let Some(input) = &movement.input else {
            continue;
        };

        to_ack.ack_tick = RepliconTick::new(to_ack.ack_tick.get().max(input.tick.get()));
        to_ack.value = component.clone();
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
    mut commands: Commands,
    mut reader_connected: EventReader<ConnectionEvent>,
    mut writer_login: EventWriter<Login>,
    mut res_client_context: ResMut<ClientContext>,
) {
    for _ in reader_connected.read() {
        let player_id = rand::random::<u64>();

        println!("spawning with {}", player_id);

        res_client_context.player_id = Some(player_id);
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
    trigger: Trigger<OnAdd, (Player, Collider)>,
    mut commands: Commands,
    query_player: Query<(&Player, &Collider)>,
    mut res_client_context: ResMut<ClientContext>,
    mut res_meshes: ResMut<Assets<Mesh>>,
    mut res_materials: ResMut<Assets<ColorMaterial>>,
) {
    let mut player_entity = commands.entity(trigger.target());

    let Ok((player, collider)) = query_player.get(trigger.target()) else {
        return;
    };

    player_entity.insert((
        Mesh2d(res_meshes.add(Capsule2d::new(10.0, 30.0))),
        MeshMaterial2d(res_materials.add(Color::srgb(1.0, 0.0, 0.0))),
    ));

    if res_client_context
        .player_id
        .map(|x| x == player.player_id)
        .unwrap_or(false)
    {
        player_entity.insert(MovementController::new(
            collider.clone(),
            MovementConfig {
                acceleration: 2250.0,
                damping: 0.92,
                jump_impulse: 300.0,
                max_slope_angle: Some(30.0f32.to_radians()),
                max_velocity: 250.0,
            },
        ));

        res_client_context.player_entity = Some(trigger.target());
    } else {
        player_entity.insert((RigidBody::Static, Interpolation::default()));
    }
}

/*
fn observer_client_sync_time(
    trigger: Trigger<OnAdd, IndividualServerConfig>,
    query_server_config: Query<&IndividualServerConfig>,
    mut client_context: ResMut<ClientContext>,
) {
    let server_config = query_server_config.get(trigger.target()).unwrap();

    if server_config.player_id == client_context.player_id.unwrap() {
        client_context.tick = server_config.ack_tick;
    }
}
     */

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
        RigidBody::Static,
    ));
}

fn system_client_input(
    mut writer_movement: EventWriter<MovementInput>,
    mut query_movment: Query<(&Transform, &mut Movement)>,
    mut res_client_context: ResMut<ClientContext>,
    res_keyboard: ResMut<ButtonInput<KeyCode>>,
) {
    let mut input = MovementInput::default();

    if res_keyboard.pressed(KeyCode::KeyA) {
        input.direction -= 1.0;
    }

    if res_keyboard.pressed(KeyCode::KeyD) {
        input.direction += 1.0;
    }

    if res_keyboard.pressed(KeyCode::KeyW) {
        input.jump = true;
    }

    res_client_context.tick += 1;
    input.tick = res_client_context.tick;

    writer_movement.write(input.clone());

    if let Some(player_entity) = res_client_context.player_entity {
        let (transform, mut movement) = query_movment.get_mut(player_entity).unwrap();

        movement.input = Some(input.clone());
        movement.uses = 0;

        println!("Input y={}, {}", transform.translation.y, input.jump);
    }
}

fn system_client_input_automatic(time: Res<Time>, mut writer_movement: EventWriter<MovementInput>) {
    let mut input = MovementInput::default();

    input.direction = sin(5.0 * time.elapsed_secs());
    writer_movement.write(input);
}

fn system_capture_input(
    mut input_event_reader: EventReader<MovementInput>,
    mut input_memory: ResMut<InputMemory>,
    client_context: Res<ClientContext>,
) {
    for input_event in input_event_reader.read() {
        input_memory
            .inputs
            .push_back((client_context.tick, input_event.clone()));
    }
}
fn system_find_new_min_ack<C: Component>(
    mut input_memory: ResMut<InputMemory>,
    memory_query: Query<&PredictedMemory<C>>,
) {
    for memory in memory_query {
        let predicted_tick = input_memory
            .new_min_ack
            .map(|x| x.get())
            .unwrap_or(u32::MAX);

        let Some(memory_tick) = memory.values.back().map(|x| x.1.get()) else {
            continue;
        };

        println!("memorytick: {:?}, predictedtick: {:?}", memory_tick, predicted_tick);

        if predicted_tick > memory_tick {
            input_memory.new_min_ack = Some(RepliconTick::new(memory_tick));
        }
    }
}

fn predicted_tick_changed(input_memory: Res<InputMemory>) -> bool {
    input_memory.new_min_ack.map(|x| x.get() > input_memory.current_min_ack.get()).unwrap_or(false)
}

fn system_predict_prune_components<C: Component>(
    input_memory: Res<InputMemory>,
    memory_query: Query<&mut PredictedMemory<C>>,
) {
    let predicted_tick = &input_memory.new_min_ack.unwrap();

    for mut memory in memory_query {
        let Some(index) = memory
            .values
            .iter()
            .position(|(_, x)| x >= predicted_tick)
        else {
            continue;
        };

        memory.values.drain(0..index);
    }
}

fn system_predict(world: &mut World) {
    world.resource_scope(|world, client_context: Mut<ClientContext>| {
        let Some(player_entity) = client_context.player_entity else {
            return;
        };

        world.resource_scope(|world, mut input_memory: Mut<InputMemory>| {
            let Some(config_entity) = client_context.individual_config else {
                return;
            };

            let config = world
                .query::<&IndividualServerConfig>()
                .get(world, config_entity)
                .unwrap();

            let current_tick = input_memory.new_min_ack.unwrap();
            let dt = Duration::from_secs_f32(1.0 / config.hz);

            if let Some(remove_to) = input_memory
                .inputs
                .iter()
                .position(|(tick, _)| tick > &current_tick)
            {
                input_memory.inputs.drain(0..remove_to);
            } else {
                input_memory.inputs.clear();
            }

            let mut movement_query = world.query::<&mut Movement>();
            // let mut transform_query = world.query::<&mut Transform>();
            // let mut lin_vel_query = world.query::<&LinearVelocity>();

            // let transform = transform_query.get(world, player_entity).unwrap();
            // let linvel = lin_vel_query.get(world, player_entity).unwrap();

            world.schedule_scope(Simulate, |world, schedule| {
                let current_time = world.resource::<Time>().as_generic();
                *world.resource_mut::<Time>() = Time::new_with(());

                for (_, input) in &input_memory.inputs {
                    let mut movement = movement_query.get_mut(world, player_entity).unwrap();
                    movement.input = Some(input.clone());
                    movement.uses = 0;

                    world.resource_mut::<Time>().advance_by(dt);

                    schedule.run(world);
                }

                *world.resource_mut::<Time>() = current_time;
            });

            let mut transform_query = world.query::<&mut Transform>();
            let transform = transform_query.get(world, player_entity).unwrap();
            if input_memory.inputs.len() > 0 {
                println!("After y={}\n", transform.translation.y);
            }

            input_memory.current_min_ack = current_tick;
            input_memory.new_min_ack = None;
        });
    })
}

fn observer_client_new_config(
    trigger: Trigger<OnAdd, IndividualServerConfig>,
    query_server_config: Query<&IndividualServerConfig>,
    mut client_context: ResMut<ClientContext>,
) {
    let server_config = query_server_config.get(trigger.target()).unwrap();

    if server_config.player_id == client_context.player_id.unwrap() {
        client_context.individual_config = Some(trigger.target());
    }
}

fn observe_client_added_owned(
    trigger: Trigger<OnAdd, Owned>,
    mut commands: Commands,
    client_context: Res<ClientContext>,
    owned_query: Query<(Entity, &Owned)>,
) {
    let (owned_entity, owned) = owned_query.get(trigger.target()).unwrap();

    if client_context
        .player_id
        .map(|player_id| owned.owner_player_id == player_id)
        .unwrap_or(false)
    {
        commands.entity(owned_entity).insert(Predicted);
    }
}

#[derive(Resource, Default)]
struct InputMemory {
    pub current_min_ack: RepliconTick,
    pub new_min_ack: Option<RepliconTick>,
    pub inputs: VecDeque<(RepliconTick, MovementInput)>,
}

#[derive(Component, Serialize, Deserialize)]
#[relationship_target(relationship = Owned)]
pub struct IndividualServerConfig {
    pub hz: f32,
    pub player_id: u64,

    #[relationship]
    owns: Vec<Entity>,
}

#[derive(Component, Serialize, Deserialize)]
#[relationship(relationship_target = IndividualServerConfig)]
pub struct Owned {
    #[relationship]
    pub owner: Entity,
    pub owner_player_id: u64,
}

#[derive(Component, Serialize, Deserialize)]
pub struct InputAck {
    pub ack_tick: RepliconTick,
}

#[derive(Component)]
pub struct Predicted;

#[derive(Component, Serialize, Deserialize)]
pub struct AckComponent<C: Component> {
    pub ack_tick: RepliconTick,
    pub value: C,
}

#[derive(Component)]
pub struct PredictedMemory<C: Component> {
    pub values: VecDeque<(C, RepliconTick)>,
}

#[derive(Component, Clone)]
struct ClientInfo {
    individual_config: Entity,
    player: Entity,
    player_id: u64,
}

#[derive(Event, Serialize, Deserialize)]
struct Login {
    player_id: u64,
}

#[derive(Component, Serialize, Deserialize)]
struct Player {
    pub player_id: u64,
}

#[derive(Component, Serialize, Deserialize)]
struct Terrain {
    width: f32,
    height: f32,
}
