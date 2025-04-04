import { Canvas } from "@react-three/fiber"

interface GameState {}

const GameState = {
    step(state: GameState): GameState {
        throw new Error()
    },

    add(stateLeft: GameState, stateRight: GameState): GameState {
        throw new Error()
    },
    negative(state: GameState): GameState {
        throw new Error()
    },
    zero(): GameState {
        throw new Error()
    },
}

export function PocServer() {
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
