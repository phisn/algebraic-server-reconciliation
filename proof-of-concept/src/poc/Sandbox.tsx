import { OrthographicCamera } from "@react-three/drei"
import { Canvas } from "@react-three/fiber"
import deepcopy from "deepcopy"
import { JSX, useEffect, useState } from "react"
import { FocusContext, Game } from "./game/game"
import { TopDown } from "./game/TopDown"
import {
    ClientStrategy,
    GenericMessage,
    NetworkingStrategy,
    ServerStrategy,
    Socket,
} from "./networking/networking"
import { AlgebraicNetworking } from "./networking/strategy-algebraic"
import { OverrideNetworking } from "./networking/strategy-override"
import { RollbackNetworking } from "./networking/strategy-rollback"

export interface MemorySocketModifiers {
    delay: number
}

export class MemorySocket implements Socket {
    private _buffer: GenericMessage[]

    constructor(
        private _id: string,
        private _receive: GenericMessage[],
        private _send: GenericMessage[],
        private _modifiers: MemorySocketModifiers,
    ) {
        this._buffer = []
    }

    static pair(modifiers: MemorySocketModifiers): [Socket, Socket] {
        const id = Math.random().toString(36).substring(2, 15)
        const l: GenericMessage[] = []
        const r: GenericMessage[] = []
        return [new MemorySocket(id, l, r, modifiers), new MemorySocket(id, r, l, modifiers)]
    }

    public id(): string {
        return this._id
    }

    public send(message: GenericMessage) {
        this._buffer.push(deepcopy(message))
        if (this._buffer.length > this._modifiers.delay) {
            this._send.push(this._buffer.shift()!)
        }
    }

    public receive(): GenericMessage | undefined {
        return this._receive.shift()
    }

    public receiveLatest(): GenericMessage | undefined {
        if (this._receive.length > 0) {
            const result = this._receive[this._receive.length - 1]
            this._receive.length = 0
            return result
        }
        return undefined
    }
}

export class Scenario {
    private _clients: ClientStrategy[]
    private _server: ServerStrategy

    constructor(
        private _gameFactory: () => Game,
        private _networkingStrategy: NetworkingStrategy,
        clientCount: number = 2,
        delay: number = 30,
    ) {
        const sockets = Array.from({ length: clientCount }, () => MemorySocket.pair({ delay }))

        this._clients = sockets.map(([, socket]) =>
            this._networkingStrategy.wrapClient(this._gameFactory(), socket),
        )

        this._server = this._networkingStrategy.wrapServer(
            this._gameFactory(),
            sockets.map(([socket]) => socket),
        )
    }

    public update() {
        this._server.update()
        this._clients.forEach(client => client.update())
    }

    public views() {
        return {
            Server: () => this._server.render(),
            clients: this._clients.map((client, index) => () => client.render()),
        }
    }
}

const NETWORKING_STRATEGIES = {
    algebraic: {
        name: "Algebraic",
        description: "Algebraic using abelian groups",
        factory: () => new AlgebraicNetworking(),
    },
    rollback: {
        name: "Rollback",
        description: "Client-side prediction with rollback",
        factory: () => new RollbackNetworking(),
    },
    override: {
        name: "Override",
        description: "Simple server authoritative",
        factory: () => new OverrideNetworking(),
    },
} as const

type StrategyKey = keyof typeof NETWORKING_STRATEGIES

export function Sandbox() {
    const [scenario, setScenario] = useState<Scenario | null>(null)
    const [isPaused, setIsPaused] = useState(false)
    const [networkDelay, setNetworkDelay] = useState(30)
    const [clientCount, setClientCount] = useState(2)
    const [tickRate, setTickRate] = useState(60)
    const [showStats, setShowStats] = useState(true)
    const [networkingStrategy, setNetworkingStrategy] = useState<StrategyKey>("algebraic")

    useEffect(() => {
        const strategy = NETWORKING_STRATEGIES[networkingStrategy].factory()
        const newScenario = new Scenario(
            () => new TopDown({ static_entities_in_prediction: false }),
            strategy,
            clientCount,
            networkDelay,
        )
        setScenario(newScenario)
    }, [clientCount, networkDelay, networkingStrategy])

    useEffect(() => {
        if (!scenario || isPaused) return

        const interval = setInterval(() => {
            scenario.update()
        }, 1000 / tickRate)

        return () => clearInterval(interval)
    }, [scenario, isPaused, tickRate])

    if (scenario === null) {
        return (
            <div className="bg-base-200 flex h-screen items-center justify-center">
                <span className="loading loading-spinner loading-lg"></span>
            </div>
        )
    }

    const { Server, clients } = scenario.views()

    return (
        <div className="bg-base-200 flex h-screen">
            {/* Main Content Area */}
            <div className="flex-1 overflow-auto p-4">
                <div className="mx-auto max-w-7xl">
                    {/* Header */}
                    <div className="navbar bg-base-100 rounded-box mb-4 shadow-sm">
                        <div className="navbar-start">
                            <h1 className="px-4 text-xl font-bold">Network Sandbox</h1>
                        </div>
                        <div className="navbar-center">
                            <div className="badge badge-primary badge-lg">
                                {NETWORKING_STRATEGIES[networkingStrategy].name}
                            </div>
                        </div>
                        <div className="navbar-end px-4">
                            <button
                                className={`btn ${isPaused ? "btn-success" : "btn-error"} btn-sm`}
                                onClick={() => setIsPaused(!isPaused)}
                            >
                                {isPaused ? <>▶ Play</> : <>⏸ Pause</>}
                            </button>
                        </div>
                    </div>

                    {/* Server View */}
                    <div className="card bg-base-100 mb-4 shadow-sm">
                        <div className="card-body p-3">
                            <h2 className="card-title text-base">Server View</h2>
                            <ServerViewport>
                                <Server />
                            </ServerViewport>
                        </div>
                    </div>

                    {/* Clients Grid */}
                    <div
                        className={`grid gap-3 ${clientCount <= 2 ? "grid-cols-2" : "grid-cols-2 lg:grid-cols-3"}`}
                    >
                        {clients.map((Client, index) => (
                            <div key={index} className="card bg-base-100 shadow-sm">
                                <div className="card-body p-3">
                                    <h3 className="text-base font-semibold">Client {index + 1}</h3>
                                    <ClientViewport showStats={showStats}>
                                        <Client />
                                    </ClientViewport>
                                </div>
                            </div>
                        ))}
                    </div>
                </div>
            </div>

            {/* Configuration Sidebar */}
            <div className="bg-base-100 w-80 overflow-y-auto p-4 shadow-lg">
                <h2 className="mb-4 text-lg font-bold">Configuration</h2>

                <div className="space-y-4">
                    {/* Networking Strategy */}
                    <div className="card bg-base-200">
                        <div className="card-body p-4">
                            <h3 className="mb-3 font-semibold">Networking Strategy</h3>

                            <div className="form-control">
                                <select
                                    className="select select-primary select-sm w-full"
                                    value={networkingStrategy}
                                    onChange={e =>
                                        setNetworkingStrategy(e.target.value as StrategyKey)
                                    }
                                >
                                    {Object.entries(NETWORKING_STRATEGIES).map(
                                        ([key, strategy]) => (
                                            <option key={key} value={key}>
                                                {strategy.name}
                                            </option>
                                        ),
                                    )}
                                </select>
                                <label className="label p-2">
                                    <span className="label-text-alt">
                                        {NETWORKING_STRATEGIES[networkingStrategy].description}
                                    </span>
                                </label>
                            </div>
                        </div>
                    </div>

                    {/* Network Settings */}
                    <div className="card bg-base-200">
                        <div className="card-body p-4">
                            <h3 className="mb-3 font-semibold">Network Settings</h3>

                            <div className="form-control">
                                <label className="label">
                                    <span className="label-text">Network Delay</span>
                                    <span className="label-text-alt">{networkDelay} packets</span>
                                </label>
                                <input
                                    type="range"
                                    min="0"
                                    max="100"
                                    value={networkDelay}
                                    onChange={e => setNetworkDelay(Number(e.target.value))}
                                    className="range range-primary range-sm"
                                />
                            </div>

                            <div className="form-control">
                                <label className="label">
                                    <span className="label-text">Client Count</span>
                                    <span className="label-text-alt">{clientCount}</span>
                                </label>
                                <input
                                    type="range"
                                    min="1"
                                    max="4"
                                    value={clientCount}
                                    onChange={e => setClientCount(Number(e.target.value))}
                                    className="range range-primary range-sm"
                                />
                            </div>

                            <div className="form-control">
                                <label className="label">
                                    <span className="label-text">Tick Rate</span>
                                    <span className="label-text-alt">{tickRate} Hz</span>
                                </label>
                                <input
                                    type="range"
                                    min="10"
                                    max="144"
                                    step="10"
                                    value={tickRate}
                                    onChange={e => setTickRate(Number(e.target.value))}
                                    className="range range-primary range-sm"
                                />
                            </div>
                        </div>
                    </div>

                    {/* Display Settings */}
                    <div className="card bg-base-200">
                        <div className="card-body p-4">
                            <h3 className="mb-3 font-semibold">Display Settings</h3>

                            <div className="form-control">
                                <label className="label cursor-pointer">
                                    <span className="label-text">Show Input Stats</span>
                                    <input
                                        type="checkbox"
                                        className="toggle toggle-primary toggle-sm"
                                        checked={showStats}
                                        onChange={e => setShowStats(e.target.checked)}
                                    />
                                </label>
                            </div>
                        </div>
                    </div>

                    {/* Statistics */}
                    <div className="card bg-base-200">
                        <div className="card-body p-4">
                            <h3 className="mb-3 font-semibold">Statistics</h3>
                            <div className="stats stats-vertical shadow">
                                <div className="stat p-2">
                                    <div className="stat-title text-xs">Status</div>
                                    <div className="stat-value text-base">
                                        {isPaused ? "Paused" : "Running"}
                                    </div>
                                </div>
                                <div className="stat p-2">
                                    <div className="stat-title text-xs">Strategy</div>
                                    <div className="stat-value text-base">
                                        {NETWORKING_STRATEGIES[networkingStrategy].name}
                                    </div>
                                </div>
                                <div className="stat p-2">
                                    <div className="stat-title text-xs">Clients</div>
                                    <div className="stat-value text-base">{clientCount}</div>
                                </div>
                                <div className="stat p-2">
                                    <div className="stat-title text-xs">Latency</div>
                                    <div className="stat-value text-base">
                                        {Math.round((networkDelay * 1000) / tickRate)}ms
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>

                    {/* Actions */}
                    <div className="card bg-base-200">
                        <div className="card-body p-4">
                            <h3 className="mb-3 font-semibold">Actions</h3>
                            <button
                                className="btn btn-primary btn-sm btn-block"
                                onClick={() => {
                                    const strategy =
                                        NETWORKING_STRATEGIES[networkingStrategy].factory()
                                    setScenario(
                                        new Scenario(
                                            () =>
                                                new TopDown({
                                                    static_entities_in_prediction: true,
                                                }),
                                            strategy,
                                            clientCount,
                                            networkDelay,
                                        ),
                                    )
                                }}
                            >
                                Reset Simulation
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    )
}

function ClientViewport({
    children,
    showStats = true,
}: {
    children: JSX.Element
    showStats?: boolean
}) {
    const [focus, setFocus] = useState(false)

    return (
        <div className="relative flex justify-center">
            {showStats && (
                <div className="absolute top-1 right-1 z-50">
                    <InputViewer focused={focus} />
                </div>
            )}
            <FocusContext.Provider value={focus}>
                <div
                    className={`border-base-300 aspect-square w-[25rem] overflow-hidden rounded border ${focus ? "ring-primary ring-2 ring-offset-1" : ""}`}
                >
                    <Canvas
                        onFocus={() => setFocus(true)}
                        onBlur={() => setFocus(false)}
                        tabIndex={0}
                        orthographic
                    >
                        <OrthographicCamera makeDefault far={1000} near={-1000} scale={1.5} />
                        {children}
                    </Canvas>
                </div>
            </FocusContext.Provider>
        </div>
    )
}

function ServerViewport({ children }: { children: JSX.Element }) {
    return (
        <div className="flex w-full justify-center">
            <div className="border-base-300 aspect-video w-[30rem] overflow-hidden rounded border">
                <Canvas orthographic>
                    <OrthographicCamera makeDefault far={1000} near={-1000} scale={2.5} />
                    {children}
                </Canvas>
            </div>
        </div>
    )
}

function InputViewer({ focused }: { focused: boolean }) {
    const [left, setLeft] = useState(false)
    const [up, setUp] = useState(false)
    const [right, setRight] = useState(false)
    const [down, setDown] = useState(false)

    useEffect(() => {
        if (!focused) {
            setLeft(false)
            setRight(false)
            setUp(false)
            setDown(false)
            return
        }

        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.key === "ArrowLeft") setLeft(true)
            if (e.key === "ArrowRight") setRight(true)
            if (e.key === "ArrowUp") setUp(true)
            if (e.key === "ArrowDown") setDown(true)
        }

        const handleKeyUp = (e: KeyboardEvent) => {
            if (e.key === "ArrowLeft") setLeft(false)
            if (e.key === "ArrowRight") setRight(false)
            if (e.key === "ArrowUp") setUp(false)
            if (e.key === "ArrowDown") setDown(false)
        }

        window.addEventListener("keydown", handleKeyDown)
        window.addEventListener("keyup", handleKeyUp)

        return () => {
            window.removeEventListener("keydown", handleKeyDown)
            window.removeEventListener("keyup", handleKeyUp)
        }
    }, [focused])

    return (
        <div
            className={`bg-base-100 rounded p-1 shadow-md transition-opacity ${focused ? "opacity-100" : "opacity-40"}`}
        >
            <div className="space-y-0.5">
                <div className="flex justify-center">
                    <kbd className={`kbd kbd-xs ${up ? "bg-primary text-primary-content" : ""}`}>
                        ▲
                    </kbd>
                </div>
                <div className="flex justify-center gap-0.5">
                    <kbd className={`kbd kbd-xs ${left ? "bg-primary text-primary-content" : ""}`}>
                        ◀
                    </kbd>
                    <kbd className={`kbd kbd-xs ${down ? "bg-primary text-primary-content" : ""}`}>
                        ▼
                    </kbd>
                    <kbd className={`kbd kbd-xs ${right ? "bg-primary text-primary-content" : ""}`}>
                        ▶
                    </kbd>
                </div>
            </div>
        </div>
    )
}
