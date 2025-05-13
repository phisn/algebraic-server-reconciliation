use avian2d::{math::*, prelude::*};
use bevy::{ecs::query::Has, prelude::*};
use bevy_replicon::prelude::{
    server_running, Channel, ClientEventAppExt, ClientTriggerAppExt, ServerEventAppExt,
};
use serde::{Deserialize, Serialize};

pub struct MovementPlugin;

impl Plugin for MovementPlugin {
    fn build(&self, app: &mut App) {
        app.add_event::<MovementInput>()
            .add_client_event::<MovementInput>(Channel::Unreliable)
            .add_systems(
                FixedUpdate,
                (update_grounded, movement, apply_movement_damping).run_if(server_running),
            );
    }
}

#[derive(Event, Serialize, Deserialize, Clone, Default, Debug)]
pub struct MovementInput {
    pub direction: f32,
    pub jump: bool,
}

#[derive(Component, Default)]
pub struct Movement {
    pub input: Option<MovementInput>,
    pub uses: u32,
}

#[derive(Component)]
#[component(storage = "SparseSet")]
pub struct Grounded;

#[derive(Component)]
pub struct MovementConfig {
    pub acceleration: f32,
    pub damping: f32,
    pub jump_impulse: f32,
    pub max_slope_angle: Option<f32>,
}

#[derive(Bundle)]
pub struct MovementController {
    body: RigidBody,
    collider: Collider,
    ground_caster: ShapeCaster,
    locked_axes: LockedAxes,

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
            ground_caster: ShapeCaster::new(caster_shape, Vector::ZERO, 0.0, Dir2::NEG_Y)
                .with_max_distance(10.0),
            locked_axes: LockedAxes::ROTATION_LOCKED,

            movement_config,
            movement: Movement::default(),
        }
    }
}

fn update_grounded(
    mut commands: Commands,
    mut query: Query<(Entity, &ShapeHits, &Rotation, &MovementConfig), With<Movement>>,
) {
    for (entity, hits, rotation, movement_config) in &mut query {
        // The character is grounded if the shape caster has a hit with a normal
        // that isn't too steep.
        let is_grounded = hits.iter().any(|hit| {
            if let Some(angle) = movement_config.max_slope_angle {
                (rotation * -hit.normal2).angle_to(Vector::Y).abs() <= angle
            } else {
                true
            }
        });

        if is_grounded {
            commands.entity(entity).insert(Grounded);
        } else {
            commands.entity(entity).remove::<Grounded>();
        }
    }
}

fn movement(
    time: Res<Time>,
    mut controllers: Query<(
        &mut Movement,
        &MovementConfig,
        &mut LinearVelocity,
        Has<Grounded>,
    )>,
) {
    let delta_time = time.delta_secs_f64().adjust_precision();

    for (mut movement, movement_config, mut linear_velocity, is_grounded) in &mut controllers {
        let Some(input) = &movement.input else {
            continue;
        };

        println!("Movement: {:?}", linear_velocity);

        let movement_factor = if is_grounded { 1.0 } else { 0.2 };

        linear_velocity.x += input.direction.clamp(-1.0, 1.0)
            * movement_factor
            * movement_config.acceleration
            * delta_time;

        if is_grounded && input.jump {
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
        let damping = if is_grounded { 0.98 } else { 0.96 };

        linear_velocity.x *= damping;
    }
}
