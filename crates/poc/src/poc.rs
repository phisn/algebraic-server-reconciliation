mod network;

use std::net::Ipv4Addr;

use avian2d::{
    prelude::{Collider, RigidBody},
    PhysicsPlugins,
};
use bevy::{prelude::*, ui::update};
use network::{NetworkClientPlugin, NetworkServerPlugin};
use serde::{Deserialize, Serialize};

pub struct PocPlugin {
    pub typ: PocType,
}

pub enum PocType {
    Client,
    Server,
}

impl Plugin for PocPlugin {
    fn build(&self, app: &mut App) {
        const PORT: u16 = 24325;

        match self.typ {
            PocType::Client => {
                app.add_plugins(NetworkClientPlugin {
                    ip: Ipv4Addr::LOCALHOST,
                    port: PORT,
                });
            }
            PocType::Server => {
                app.add_plugins(NetworkServerPlugin { port: PORT });
            }
        }

        app.add_plugins(PhysicsPlugins::default())
            .add_systems(Startup, startup_init)
            .add_observer(observer_add_visuals);
    }
}

#[derive(Serialize, Deserialize)]
struct PlayerInput {
    direction: Vec2,
    jump: bool,
}

#[derive(Component)]
struct Player;

fn startup_init(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<ColorMaterial>>,
) {
    commands.spawn((Player, Transform::default()));
    commands.spawn((
        Camera2d::default(),
        Projection::from(OrthographicProjection {
            scale: 0.05,
            ..OrthographicProjection::default_2d()
        }),
    ));
    commands.spawn((
        RigidBody::Static,
        Transform::from_translation(Vec3 {
            x: 0.0,
            y: -8.0,
            z: 0.0,
        }),
        Collider::rectangle(50.0, 1.0),
        Mesh2d(meshes.add(Rectangle::new(50.0, 1.0))),
        MeshMaterial2d(materials.add(Color::srgb(0.75, 0.75, 0.75))),
    ));
}

fn observer_add_visuals(
    trigger: Trigger<OnAdd, Player>,
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<ColorMaterial>>,
) {
    commands.entity(trigger.entity()).insert((
        RigidBody::Dynamic,
        Collider::capsule(1.0, 3.0),
        Mesh2d(meshes.add(Capsule2d::new(1.0, 3.0))),
        MeshMaterial2d(materials.add(Color::srgb(1.0, 0.0, 0.0))),
    ));
}
