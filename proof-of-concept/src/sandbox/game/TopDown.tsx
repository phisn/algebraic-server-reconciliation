import "@react-three/fiber"
import deepcopy from "deepcopy"
import { Bodies, Body, Composite, Engine, Runner } from "matter-js"
import { JSX, useContext, useEffect, useRef, useSyncExternalStore } from "react"
import {
    AbelianGroup,
    ActionSymbol,
    FocusContext,
    Game,
    GenericAction,
    GenericCompoundAction,
    StateSymbol,
} from "./game"

export interface Action {
    type: typeof ActionSymbol

    move?: "left" | "right" | "up" | "down"
}

export interface State {
    type: typeof StateSymbol

    players: Record<string, Player>
    walls: Record<string, Wall>
}

export interface Player {
    x: number
    y: number
    vx: number
    vy: number
    radius: number
}

export interface Wall {
    x: number
    y: number
    width: number
    height: number
}

export function TopDownRenderer(props: { onAction: (action: Action) => void; state: State }) {
    const state = props.state
    const inputRef = useRef<Action>({ type: ActionSymbol })

    const actionRef = useRef(props.onAction)
    actionRef.current = props.onAction

    const hasFocus = useContext(FocusContext)

    useEffect(() => {
        if (hasFocus === false) {
            return
        }

        let left = false
        let right = false
        let up = false
        let down = false

        const updateMove = () => {
            let move: Action["move"]
            if (up && !down) {
                move = "up"
            } else if (down && !up) {
                move = "down"
            } else if (left && !right) {
                move = "left"
            } else if (right && !left) {
                move = "right"
            }
            inputRef.current.move = move
            actionRef.current(inputRef.current)
        }

        const handleKeyDown = (event: KeyboardEvent) => {
            if (event.key === "ArrowLeft") {
                left = true
            }
            if (event.key === "ArrowRight") {
                right = true
            }
            if (event.key === "ArrowUp") {
                up = true
            }
            if (event.key === "ArrowDown") {
                down = true
            }
            updateMove()
        }

        const handleKeyUp = (event: KeyboardEvent) => {
            if (event.key === "ArrowLeft") {
                left = false
            }
            if (event.key === "ArrowRight") {
                right = false
            }
            if (event.key === "ArrowUp") {
                up = false
            }
            if (event.key === "ArrowDown") {
                down = false
            }
            updateMove()
        }

        window.addEventListener("keydown", handleKeyDown)
        window.addEventListener("keyup", handleKeyUp)

        return () => {
            window.removeEventListener("keydown", handleKeyDown)
            window.removeEventListener("keyup", handleKeyUp)

            actionRef.current({
                type: ActionSymbol,
            })
        }
    }, [actionRef, inputRef, hasFocus])

    return (
        <>
            {Object.entries(state.players).map(([id, player]) => (
                <mesh key={id} position={[player.x, player.y, 1]}>
                    <circleGeometry args={[player.radius, player.radius]} />
                    <meshBasicMaterial color="red" />
                </mesh>
            ))}
            {Object.entries(state.walls).map(([id, wall]) => (
                <mesh key={id} position={[wall.x, wall.y, 0]}>
                    <boxGeometry args={[wall.width, wall.height, 1]} />
                    <meshBasicMaterial color="blue" />
                </mesh>
            ))}
        </>
    )
}

export class TopDown implements Game {
    private _bodies: Record<string, Body>
    private _engine: Engine
    private _input: Action
    private _runner: Runner
    private _state: State
    private _subscribers: Set<() => void>
    private _tick: number

    public constructor(
        private props: {
            static_entities_in_prediction: boolean
        },
    ) {
        this._bodies = {}
        this._engine = Engine.create({
            gravity: { x: 0, y: 0 },
        })
        this._input = { type: ActionSymbol }
        this._runner = Runner.create()
        this._state = {
            type: StateSymbol,
            players: {},
            walls: {},
        }
        this._subscribers = new Set()
        this._tick = 0
        this._state.walls["wall-1"] = {
            x: 0,
            y: -300,
            width: 550,
            height: 50,
        }
        this._state.walls["wall-2"] = {
            x: 0,
            y: 300,
            width: 550,
            height: 50,
        }
        this._state.walls["wall-3"] = {
            x: -250,
            y: 0,
            width: 50,
            height: 600,
        }
        this._state.walls["wall-4"] = {
            x: 250,
            y: 0,
            width: 50,
            height: 600,
        }
    }

    public spawnPlayer(playerId: string) {
        if (this._state.players[playerId]) {
            throw new Error(`Player ${playerId} already exists`)
        }

        this._state.players[playerId] = {
            x: 0,
            y: 0,
            vx: 0,
            vy: 0,
            radius: 25,
        }
    }

    public getInput(): GenericAction {
        return deepcopy(this._input)
    }

    public render(): JSX.Element {
        // eslint-disable-next-line react-hooks/rules-of-hooks
        useSyncExternalStore(
            onStoreChange => this.subscribe(onStoreChange),
            () => this._tick,
        )

        return (
            <TopDownRenderer
                onAction={action => {
                    this._input = action
                }}
                state={this._state}
            />
        )
    }

    public getState(): State {
        return deepcopy(this._state)
    }

    public setState(state: State) {
        this._state = deepcopy(state as State)
        this.handleSyncToEngine()

        this._tick++
        this.notifySubscribers()
    }

    public update(action: GenericCompoundAction) {
        this.handleCompoundAction(action)
        this.handleSyncToEngine()
        Runner.tick(this._runner, this._engine, 1000 / 60)
        this.handleSyncToState()

        this._tick++
        this.notifySubscribers()
    }

    public predict(action: GenericCompoundAction) {
        if (this.props.static_entities_in_prediction) {
            for (const playerId in this._state.players) {
                const body = this._bodies[playerId]

                if (body) {
                    Body.setStatic(body, !action.actions[playerId])
                }
            }
        }

        this.update(action)

        if (this.props.static_entities_in_prediction) {
            for (const playerId in this._state.players) {
                const body = this._bodies[playerId]

                if (body) {
                    Body.setStatic(body, false)
                }
            }
        }
    }

    public abelianGroup(): AbelianGroup {
        return {
            add(_left, _right) {
                const left = _left as State
                const right = _right as State
                const result: State = {
                    type: StateSymbol,
                    walls: deepcopy({
                        ...left.walls,
                        ...right.walls,
                    }),
                    players: deepcopy(left.players),
                }

                for (const id in right.players) {
                    const player = right.players[id]

                    if (result.players[id] === undefined) {
                        result.players[id] = deepcopy(player)
                        continue
                    }

                    result.players[id].radius += player.radius
                    result.players[id].x += player.x
                    result.players[id].y += player.y
                    result.players[id].vx += player.vx
                    result.players[id].vy += player.vy
                }

                return result
            },
            neg(_state) {
                const state = _state as State
                const result: State = deepcopy(state)

                for (const id in state.players) {
                    result.players[id].radius *= -1
                    result.players[id].x *= -1
                    result.players[id].y *= -1
                    result.players[id].vx *= -1
                    result.players[id].vy *= -1
                }

                return result
            },
        }
    }

    private handleCompoundAction(action: GenericCompoundAction) {
        for (const playerId in action.actions) {
            this.handleAction(playerId, action.actions[playerId])
        }
    }

    private handleAction(playerId: string, _action: GenericAction) {
        const action = _action as Action
        const player = this._state.players[playerId]
        const speed = 5

        let vx = 0
        let vy = 0

        if (action.move === "left") {
            vx = -speed
        } else if (action.move === "right") {
            vx = speed
        } else if (action.move === "up") {
            vy = speed
        } else if (action.move === "down") {
            vy = -speed
        }

        player.vx = vx
        player.vy = vy
    }

    private handleSyncToEngine() {
        const removed = new Set(Object.keys(this._bodies))

        for (const playerId in this._state.players) {
            const player = this._state.players[playerId]
            let body = this._bodies[playerId]

            if (!body) {
                body = Bodies.circle(player.x, player.y, player.radius, {
                    inertia: Infinity,
                })
                this._bodies[playerId] = body
                Composite.add(this._engine.world, body)
            }

            removed.delete(playerId)

            Body.setPosition(body, { x: player.x, y: player.y })
            Body.setVelocity(body, { x: player.vx, y: player.vy })
        }

        for (const wallId in this._state.walls) {
            const wall = this._state.walls[wallId]
            let body = this._bodies[wallId]

            if (!body) {
                body = Bodies.rectangle(wall.x, wall.y, wall.width, wall.height, {
                    isStatic: true,
                })
                this._bodies[wallId] = body
                Composite.add(this._engine.world, body)
            }

            removed.delete(wallId)

            Body.setPosition(body, { x: wall.x, y: wall.y })
        }

        for (const bodyId of removed) {
            const body = this._bodies[bodyId]
            Composite.remove(this._engine.world, body)
            delete this._bodies[bodyId]
        }
    }

    private handleSyncToState() {
        for (const playerId in this._state.players) {
            const player = this._state.players[playerId]
            const body = this._bodies[playerId]

            player.x = body.position.x
            player.y = body.position.y
            player.vx = body.velocity.x
            player.vy = body.velocity.y
        }

        for (const wallId in this._state.walls) {
            const wall = this._state.walls[wallId]
            const body = this._bodies[wallId]

            wall.x = body.position.x
            wall.y = body.position.y
        }
    }

    private subscribe(onStoreChange: () => void) {
        this._subscribers.add(onStoreChange)
        return () => {
            this._subscribers.delete(onStoreChange)
        }
    }

    private notifySubscribers() {
        for (const subscriber of this._subscribers) {
            subscriber()
        }
    }
}
