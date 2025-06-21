use avian2d::{math::*, prelude::*};
use bevy::{ecs::query::Has, prelude::*};
use bevy_replicon::{
    prelude::{server_running, Channel, ClientEventAppExt, ClientTriggerAppExt, ServerEventAppExt},
    shared::replicon_tick::RepliconTick,
};
use serde::{Deserialize, Serialize};

use super::Simulate;

pub struct MovementPlugin;

impl Plugin for MovementPlugin {
    fn build(&self, app: &mut App) {
        app.add_event::<MovementInput>()
            .add_client_event::<MovementInput>(Channel::Unreliable)
            .add_systems(Simulate, (movement, apply_movement_damping))
            .add_systems(Simulate, update_grounded.after(PhysicsSet::Sync));
    }
}

#[derive(Event, Serialize, Deserialize, Clone, Default, Debug)]
pub struct MovementInput {
    pub direction: f32,
    pub jump: bool,
    pub tick: RepliconTick,
}

#[derive(Component, Default)]
pub struct Movement {
    pub input: Option<MovementInput>,
    pub uses: u32,
}

#[derive(Component, Serialize, Deserialize, Clone)]
#[component(storage = "SparseSet")]
pub struct Grounded(bool);

#[derive(Component)]
pub struct MovementConfig {
    pub acceleration: f32,
    pub damping: f32,
    pub jump_impulse: f32,
    pub max_slope_angle: Option<f32>,
    pub max_velocity: f32,
}

#[derive(Bundle)]
pub struct MovementController {
    body: RigidBody,
    collider: Collider,
    friction: Friction,
    ground_caster: ShapeCaster,
    locked_axes: LockedAxes,
    grounded: Grounded,

    movement_config: MovementConfig,
    movement: Movement,
}

impl MovementController {
    pub fn new(collider: Collider, movement_config: MovementConfig) -> Self {
        let mut caster_shape = collider.clone();
        caster_shape.set_scale(Vector::ONE * 0.99, 10);

        Self {
            body: RigidBody::Dynamic,
            collider,
            friction: Friction {
                combine_rule: avian2d::prelude::CoefficientCombine::Average,
                dynamic_coefficient: 0.0,
                static_coefficient: 0.0,
            },
            ground_caster: ShapeCaster::new(caster_shape, Vector::ZERO, 0.0, Dir2::NEG_Y)
                .with_max_distance(10.0),
            locked_axes: LockedAxes::ROTATION_LOCKED,
            grounded: Grounded(false),

            movement_config,
            movement: Movement::default(),
        }
    }
}

fn update_grounded(
    mut query: Query<
        (
            Entity,
            &ShapeHits,
            &Rotation,
            &MovementConfig,
            &mut Grounded,
        ),
        With<Movement>,
    >,
) {
    for (entity, hits, rotation, movement_config, mut grounded) in &mut query {
        // The character is grounded if the shape caster has a hit with a normal
        // that isn't too steep.
        let is_grounded = hits.iter().any(|hit| {
            if let Some(angle) = movement_config.max_slope_angle {
                (rotation * -hit.normal2).angle_to(Vector::Y).abs() <= angle
            } else {
                true
            }
        });

        grounded.0 = is_grounded;
    }
}

fn movement(
    time: Res<Time>,
    mut controllers: Query<(
        &mut Movement,
        &Transform,
        &MovementConfig,
        &mut LinearVelocity,
        &Grounded,
    )>,
) {
    let delta_time = time.delta_secs_f64().adjust_precision();

    for (mut movement, transform, movement_config, mut linear_velocity, grounded) in
        &mut controllers
    {
        let Some(input) = &movement.input else {
            continue;
        };

        println!(
            "Step jump={} y={} yt={} dt={} floor={}",
            input.jump, transform.translation.y, linear_velocity.y, delta_time, grounded.0
        );

        let movement_factor = if grounded.0 { 1.0 } else { 0.5 };

        linear_velocity.x += input.direction.clamp(-1.0, 1.0)
            * movement_factor
            * movement_config.acceleration
            * delta_time;

        linear_velocity.x = linear_velocity
            .x
            .clamp(-movement_config.max_velocity, movement_config.max_velocity);

        if grounded.0 && input.jump {
            linear_velocity.y = movement_config.jump_impulse;
        }

        movement.uses += 1;

        if movement.uses > 3 {
            movement.input = None;
        }
    }
}

/// Slows down movement in the X direction.
fn apply_movement_damping(mut query: Query<(Has<Grounded>, &MovementConfig, &mut LinearVelocity)>) {
    for (is_grounded, movement_config, mut linear_velocity) in &mut query {
        linear_velocity.x *= 0.995;

        if is_grounded {
            linear_velocity.x *= movement_config.damping;
        };
    }
}
