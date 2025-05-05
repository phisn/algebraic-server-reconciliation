import { Canvas } from "@react-three/fiber"
import { create } from "mutative"

type Delta<T> = T extends object
    ? {
          [P in keyof T]?: Delta<T[P]>
      }
    : T

export interface Point {
    x: number
    y: number
}

export interface Size {
    width: number
    height: number
}

export interface GameState extends Record<GameStatePlayerType, GameStatePlayer> {
    playerOffset: number
    size: Size

    ball: GameStateBall
}

export interface GameStateBall {
    point: Point
    velocity: Point
}

export interface GameStatePlayer {
    paddle: number
}

export type GameInput = Record<GameStatePlayerType, GameInputPlayer>

export type GameStatePlayerType = "playerTop" | "playerBot"

export interface GameInputPlayer {
    paddle: number
}

export function deltaProgress(state: GameState, input: GameInput): Delta<GameState> {
    const delta: Partial<GameState> = {}

    for (const keyInput in input) {
        const player = keyInput as GameStatePlayerType
        progressInPlaceInput(state, delta, input[player], player)
    }

    return delta
}

export function predictDeltaProgress(
    state: GameState,
    input: GameInputPlayer,
    player: GameStatePlayerType,
): Delta<GameState> {
    const delta: Delta<GameState> = {}

    progressInPlaceInput(state, delta, input, player)

    return delta
}

function progressInPlaceInput(
    state: GameState,
    delta: Delta<GameState>,
    input: GameInputPlayer,
    player: GameStatePlayerType,
) {
    const right = -state[player].paddle + state.size.width
    const left = -state[player].paddle + 0

    delta[player] = {
        paddle: Math.min(Math.max(input.paddle, right), left),
    }
}

function progressInPlaceBall(state: GameState, delta: Delta<GameState>) {
    const point = {
        x: state.ball.point.x + state.ball.velocity.x,
        y: state.ball.point.y + state.ball.velocity.y,
    }

    if (point.x < 0) {
        point.x = -point.x % state.size.width
    } else if (point.x > state.size.width) {
        point.x = state.size.width - (point.x % state.size.width)
    }

    delta.ball = {
        ...delta.ball,
        point,
    }
}

const AbelianGroup = {
    toPlus<T extends object>(left: T, right: T): T {
        return create(left, left => {
            this.plus(left as T, right)
        })
    },
    plus<T extends object>(left: T, right: Partial<T>) {
        for (const key in right) {
            const sourceValue = right[key]
            const sourceValueType = typeof sourceValue

            if (sourceValueType === "number") {
                left[key] = sourceValue + ((left[key] as any) ?? 0)
            } else if (sourceValueType === "object") {
                const targetValue = left[key]

                if (targetValue) {
                    this.plus(targetValue, sourceValue!)
                } else {
                    left[key] = sourceValue!
                }
            }
        }
    },
    toNegative<T extends object>(value: T): T {
        return create(value, value => {
            this.negative(value)
        })
    },
    negative<T extends object>(value: T) {
        for (const key in value) {
            const sourceValue = value[key]
            const sourceValueType = typeof sourceValue

            if (sourceValueType === "number") {
                value[key] = -sourceValue as any
            } else if (sourceValueType === "object") {
                this.negative(sourceValue!)
            }
        }
    },
}

const a: GameState = null!
const b: Partial<GameState> = null!

AbelianGroup.plus(a, b)

interface Network {}

interface Reconciliation {}

export function PocServer() {
    const gameState: GameState = {
        playerOffset: 0,
        size: {
            width: 0,
            height: 0,
        },
        ball: {
            point: {
                x: 5,
                y: 2,
            },
            velocity: {
                x: 0,
                y: 0,
            },
        },
        playerBot: {
            paddle: 2,
        },
        playerTop: {
            paddle: 3,
        },
    }

    console.log(gameState)
    console.log(AbelianGroup.toNegative(gameState))
    console.log(AbelianGroup.toPlus(gameState, gameState))
    console.log(AbelianGroup.toPlus(gameState, AbelianGroup.toNegative(gameState)))

    return (
        <Canvas orthographic>
            <mesh>
                <boxGeometry args={[20, 20, 1]} />
                <meshBasicMaterial color="blue" />
            </mesh>
        </Canvas>
    )
}

export function PocClient() {
    return (
        <Canvas orthographic>
            <mesh>
                <boxGeometry args={[20, 20, 1]} />
                <meshBasicMaterial color="red" />
            </mesh>
        </Canvas>
    )
}
