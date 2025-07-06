import "@react-three/fiber"
import deepcopy from "deepcopy"
import { Bodies, Body, Composite, Engine, Query, Runner } from "matter-js"
import { JSX, useEffect, useRef, useSyncExternalStore } from "react"
import { ActionSymbol, Game, GenericAction, GenericCompoundAction, StateSymbol } from "./game"

export interface Action {
    type: typeof ActionSymbol

    move?: "left" | "right"
    jump?: boolean
}

export interface State {
    type: typeof StateSymbol

    players: Record<string, Player>
    platforms: Record<string, Platform>
}

export interface Player {
    onGround: boolean
    x: number
    y: number
    vx: number
    vy: number
    width: number
    height: number
}

export interface Platform {
    x: number
    y: number
    width: number
    height: number
}

export function SideScrollerRenderer(props: { onAction: (action: Action) => void; state: State }) {
    const state = props.state
    const inputRef = useRef<Action>({ type: ActionSymbol })

    const actionRef = useRef(props.onAction)
    actionRef.current = props.onAction

    useEffect(() => {
        console.log("effect")
        let left = false
        let right = false

        const handleKeyDown = (event: KeyboardEvent) => {
            console.log(event.key, "kd", left, right)
            if (event.key === "ArrowLeft") {
                left = true
                inputRef.current.move = right ? undefined : "left"

                actionRef.current(inputRef.current)
            }
            if (event.key === "ArrowRight") {
                right = true
                inputRef.current.move = left ? undefined : "right"

                actionRef.current(inputRef.current)
            }
            if (event.key === "ArrowUp") {
                inputRef.current.jump = true
                actionRef.current(inputRef.current)
            }

            console.log("kd_", left, right)
        }

        const handleKeyUp = (event: KeyboardEvent) => {
            console.log("keyup", event.key)
            if (event.key === "ArrowLeft") {
                left = false
                inputRef.current.move = right ? "right" : undefined

                actionRef.current(inputRef.current)
            }
            if (event.key === "ArrowRight") {
                right = false
                inputRef.current.move = left ? "left" : undefined

                actionRef.current(inputRef.current)
            }
            if (event.key === "ArrowUp") {
                inputRef.current.jump = undefined
                actionRef.current(inputRef.current)
            }
        }

        window.addEventListener("keydown", handleKeyDown)
        window.addEventListener("keyup", handleKeyUp)

        return () => {
            window.removeEventListener("keydown", handleKeyDown)
            window.removeEventListener("keyup", handleKeyUp)
        }
    }, [actionRef, inputRef])

    return (
        <>
            {Object.entries(state.players).map(([id, player]) => (
                <mesh key={id} position={[player.x, player.y, 1]}>
                    <boxGeometry args={[player.width, player.height, 1]} />
                    <meshBasicMaterial color="red" />
                </mesh>
            ))}
            {Object.entries(state.platforms).map(([id, platform]) => (
                <mesh key={id} position={[platform.x, platform.y, 0]}>
                    <boxGeometry args={[platform.width, platform.height, 1]} />
                    <meshBasicMaterial color="blue" />
                </mesh>
            ))}
        </>
    )
}

export class SideScroller implements Game {
    private _bodies: Record<string, Body>
    private _engine: Engine
    private _input: Action
    private _runner: Runner
    private _state: State
    private _subscribers: Set<() => void>
    private _tick: number

    public constructor(private _playerName: boolean) {
        this._bodies = {}
        this._engine = Engine.create({
            gravity: { x: 0, y: -1 },
        })
        this._input = { type: ActionSymbol }
        this._runner = Runner.create()
        this._state = {
            type: StateSymbol,
            players: {},
            platforms: {},
        }
        this._subscribers = new Set()
        this._tick = 0
        this._state.platforms["platform-1"] = {
            x: 0,
            y: -100,
            width: 500,
            height: 50,
        }
    }

    public spawnPlayer(playerId: string) {
        if (this._state.players[playerId]) {
            throw new Error(`Player ${playerId} already exists`)
        }

        this._state.players[playerId] = {
            onGround: false,
            x: 0,
            y: 0,
            vx: 0,
            vy: 0,
            width: 50,
            height: 50,
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
            <SideScrollerRenderer
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

    public predict(clientId: string, action: GenericAction) {
        for (const playerId in this._state.players) {
            const body = this._bodies[playerId]

            if (body) {
                Body.setStatic(body, playerId !== clientId)
            }
        }

        this.handleAction(clientId, action)
        this.handleSyncToEngine()
        Runner.tick(this._runner, this._engine, 1000 / 60)
        this.handleSyncToState()

        this._tick++
        this.notifySubscribers()

        for (const playerId in this._state.players) {
            const body = this._bodies[playerId]

            if (body) {
                Body.setStatic(body, false)
            }
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

        if (action.move) {
            const dvx = action.move === "left" ? -5 : 5

            if (player.onGround) {
                player.vx = dvx
            } else {
                player.vx = player.vx * 0.9 + dvx * 0.1
            }
        }

        if (action.jump && player.onGround) {
            player.vy = 8
            player.onGround = false
        }
    }

    private handleSyncToEngine() {
        const removed = new Set(Object.keys(this._bodies))

        for (const playerId in this._state.players) {
            const player = this._state.players[playerId]
            let body = this._bodies[playerId]

            if (!body) {
                body = Bodies.rectangle(player.x, player.y, player.width, player.height, {
                    inertia: Infinity,
                })
                this._bodies[playerId] = body
                Composite.add(this._engine.world, body)
            }

            removed.delete(playerId)

            Body.setPosition(body, { x: player.x, y: player.y })
            Body.setVelocity(body, { x: player.vx, y: player.vy })
            // console.log(`Expected vy: ${player.vy}, actual vy: ${body.velocity.y}`)
        }

        for (const platformId in this._state.platforms) {
            const platform = this._state.platforms[platformId]
            let body = this._bodies[platformId]

            if (!body) {
                body = Bodies.rectangle(platform.x, platform.y, platform.width, platform.height, {
                    isStatic: true,
                })
                this._bodies[platformId] = body
                Composite.add(this._engine.world, body)
            }

            removed.delete(platformId)

            Body.setPosition(body, { x: platform.x, y: platform.y })
        }

        for (const bodyId of removed) {
            const body = this._bodies[bodyId]
            Composite.remove(this._engine.world, body)
            delete this._bodies[bodyId]
        }
    }

    private checkPlayerOnGround(playerId: string): boolean {
        const body = this._bodies[playerId]

        if (!body) {
            return false
        }

        const rayStart = {
            x: body.bounds.max.x,
            y: body.bounds.min.y - 1,
        }

        const rayEnd = {
            x: body.bounds.min.x,
            y: body.bounds.min.y - 1,
        }

        const bodies = this._engine.world.bodies.filter(b => b !== body)
        const collisions = Query.ray(bodies, rayStart, rayEnd)

        return collisions.length > 0
    }

    private handleSyncToState() {
        for (const playerId in this._state.players) {
            const player = this._state.players[playerId]
            const body = this._bodies[playerId]

            player.x = body.position.x
            player.y = body.position.y
            player.vx = body.velocity.x
            player.vy = body.velocity.y

            player.onGround = this.checkPlayerOnGround(playerId)
        }

        for (const platformId in this._state.platforms) {
            const platform = this._state.platforms[platformId]
            const body = this._bodies[platformId]

            platform.x = body.position.x
            platform.y = body.position.y
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
