import { useEffect, useState } from "react"
import {
    CartesianGrid,
    Legend,
    Line,
    LineChart,
    ResponsiveContainer,
    Tooltip,
    XAxis,
    YAxis,
} from "recharts"
import { ButtonGame, State } from "./game/ButtonGame"
import { MemorySocket } from "./networking/memory-socket"
import { ClientStrategy, NetworkingStrategy, ServerStrategy } from "./networking/networking"
import { AlgebraicNetworking } from "./networking/strategy-algebraic"
import { OverrideNetworking } from "./networking/strategy-override"
import { RollbackNetworking } from "./networking/strategy-rollback"

export class Scenario {
    private _clients: ClientStrategy[]
    private _server: ServerStrategy
    private _clientGames: ButtonGame[]
    private _serverGame: ButtonGame

    constructor(
        private _networkingStrategy: NetworkingStrategy,
        stepValue: number,
        maxSumValue: number,
        delay: number = 5,
    ) {
        const sockets = [MemorySocket.pair({ delay }), MemorySocket.pair({ delay })]

        this._clientGames = []
        this._clients = sockets.map(([, socket]) => {
            const buttonGame = new ButtonGame({
                stepValue,
                maxSumValue,
            })
            this._clientGames.push(buttonGame)
            return this._networkingStrategy.wrapClient(buttonGame, socket)
        })

        this._serverGame = new ButtonGame({
            stepValue,
            maxSumValue,
        })
        this._server = this._networkingStrategy.wrapServer(
            this._serverGame,
            sockets.map(([socket]) => socket),
        )
    }

    public update() {
        this._server.update()
        this._clients.forEach(client => client.update())
    }

    public clientStates() {
        return this._clientGames.map(x => x.getState()) as State[]
    }

    public serverState() {
        return this._serverGame.getState() as State
    }
}

interface DataPoint {
    tick: number
    serverValue: number
    client1Value: number
    client2Value: number
}

interface ExperimentData {
    name: string
    data: DataPoint[]
    color: string
}

export function Experiments() {
    const [experiments, setExperiments] = useState<ExperimentData[]>([])
    const [isRunning, setIsRunning] = useState(false)
    const [config, setConfig] = useState({
        stepValue: 1,
        maxSumValue: 10,
        networkDelay: 5,
        totalTicks: 50,
    })

    const runExperiments = () => {
        setIsRunning(true)

        const strategies = [
            {
                name: "Algebraic",
                factory: () => new AlgebraicNetworking(),
                color: "#3b82f6", // blue
            },
            {
                name: "Rollback",
                factory: () => new RollbackNetworking(),
                color: "#10b981", // green
            },
            {
                name: "Override",
                factory: () => new OverrideNetworking(),
                color: "#f59e0b", // amber
            },
        ]

        const newExperiments: ExperimentData[] = []

        strategies.forEach(strategy => {
            const scenario = new Scenario(
                strategy.factory(),
                config.stepValue,
                config.maxSumValue,
                config.networkDelay,
            )

            const data: DataPoint[] = []

            for (let tick = 0; tick < config.totalTicks; tick++) {
                scenario.update()

                const serverState = scenario.serverState()
                const clientStates = scenario.clientStates()

                // Get the first player's value (since all players have same behavior)
                const serverPlayerId = Object.keys(serverState.players)[0]
                const serverValue = serverPlayerId ? serverState.players[serverPlayerId].value : 0

                const client1Value =
                    clientStates[0] && Object.keys(clientStates[0].players)[0]
                        ? clientStates[0].players[Object.keys(clientStates[0].players)[0]].value
                        : 0

                const client2Value =
                    clientStates[1] && Object.keys(clientStates[1].players)[0]
                        ? clientStates[1].players[Object.keys(clientStates[1].players)[0]].value
                        : 0

                data.push({
                    tick,
                    serverValue,
                    client1Value,
                    client2Value,
                })
            }

            newExperiments.push({
                name: strategy.name,
                data,
                color: strategy.color,
            })
        })

        setExperiments(newExperiments)
        setIsRunning(false)
    }

    useEffect(() => {
        runExperiments()
    }, [])

    return (
        <div className="bg-base-200 min-h-screen p-4">
            <div className="mx-auto max-w-7xl">
                {/* Header */}
                <div className="navbar bg-base-100 rounded-box mb-4 shadow-sm">
                    <div className="navbar-start">
                        <h1 className="px-4 text-xl font-bold">Network Strategy Experiments</h1>
                    </div>
                    <div className="navbar-end px-4">
                        <button
                            className="btn btn-primary btn-sm"
                            onClick={runExperiments}
                            disabled={isRunning}
                        >
                            {isRunning ? (
                                <>
                                    <span className="loading loading-spinner loading-xs"></span>
                                    Running...
                                </>
                            ) : (
                                "Run Experiments"
                            )}
                        </button>
                    </div>
                </div>

                {/* Configuration */}
                <div className="card bg-base-100 mb-4 shadow-sm">
                    <div className="card-body p-4">
                        <h2 className="card-title mb-3 text-lg">Configuration</h2>
                        <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
                            <div className="form-control">
                                <label className="label">
                                    <span className="label-text text-xs">Step Value</span>
                                </label>
                                <input
                                    type="number"
                                    className="input input-bordered input-sm"
                                    value={config.stepValue}
                                    onChange={e =>
                                        setConfig({ ...config, stepValue: Number(e.target.value) })
                                    }
                                />
                            </div>
                            <div className="form-control">
                                <label className="label">
                                    <span className="label-text text-xs">Max Sum Value</span>
                                </label>
                                <input
                                    type="number"
                                    className="input input-bordered input-sm"
                                    value={config.maxSumValue}
                                    onChange={e =>
                                        setConfig({
                                            ...config,
                                            maxSumValue: Number(e.target.value),
                                        })
                                    }
                                />
                            </div>
                            <div className="form-control">
                                <label className="label">
                                    <span className="label-text text-xs">Network Delay</span>
                                </label>
                                <input
                                    type="number"
                                    className="input input-bordered input-sm"
                                    value={config.networkDelay}
                                    onChange={e =>
                                        setConfig({
                                            ...config,
                                            networkDelay: Number(e.target.value),
                                        })
                                    }
                                />
                            </div>
                            <div className="form-control">
                                <label className="label">
                                    <span className="label-text text-xs">Total Ticks</span>
                                </label>
                                <input
                                    type="number"
                                    className="input input-bordered input-sm"
                                    value={config.totalTicks}
                                    onChange={e =>
                                        setConfig({ ...config, totalTicks: Number(e.target.value) })
                                    }
                                />
                            </div>
                        </div>
                    </div>
                </div>

                {/* Charts */}
                <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
                    {experiments.map(experiment => (
                        <div key={experiment.name} className="card bg-base-100 shadow-sm">
                            <div className="card-body p-4">
                                <h3 className="mb-2 text-base font-semibold">
                                    {experiment.name} Strategy
                                </h3>
                                <ResponsiveContainer width="100%" height={250}>
                                    <LineChart data={experiment.data}>
                                        <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                                        <XAxis
                                            dataKey="tick"
                                            tick={{ fontSize: 10 }}
                                            stroke="#6b7280"
                                        />
                                        <YAxis
                                            tick={{ fontSize: 10 }}
                                            stroke="#6b7280"
                                            domain={[0, config.maxSumValue]}
                                        />
                                        <Tooltip
                                            contentStyle={{
                                                backgroundColor: "#fff",
                                                border: "1px solid #e5e7eb",
                                                borderRadius: "4px",
                                                fontSize: "12px",
                                            }}
                                        />
                                        <Legend wrapperStyle={{ fontSize: "10px" }} iconSize={8} />
                                        <Line
                                            type="monotone"
                                            dataKey="serverValue"
                                            stroke={experiment.color}
                                            strokeWidth={2}
                                            dot={false}
                                            name="Server"
                                        />
                                        <Line
                                            type="monotone"
                                            dataKey="client1Value"
                                            stroke={experiment.color}
                                            strokeOpacity={0.5}
                                            strokeWidth={1.5}
                                            strokeDasharray="5 5"
                                            dot={false}
                                            name="Client"
                                        />
                                    </LineChart>
                                </ResponsiveContainer>

                                {/* Summary Stats */}
                                <div className="stats mt-2 shadow">
                                    <div className="stat p-2">
                                        <div className="stat-title text-xs">Final Server Value</div>
                                        <div className="stat-value text-sm">
                                            {experiment.data[experiment.data.length - 1]
                                                ?.serverValue || 0}
                                        </div>
                                    </div>
                                    <div className="stat p-2">
                                        <div className="stat-title text-xs">Final Client Value</div>
                                        <div className="stat-value text-sm">
                                            {experiment.data[experiment.data.length - 1]
                                                ?.client1Value || 0}
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    ))}
                </div>

                {/* Comparison Chart */}
                <div className="card bg-base-100 mt-4 shadow-sm">
                    <div className="card-body p-4">
                        <h3 className="mb-2 text-base font-semibold">
                            Strategy Comparison - Client Values
                        </h3>
                        <ResponsiveContainer width="100%" height={300}>
                            <LineChart>
                                <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                                <XAxis
                                    dataKey="tick"
                                    tick={{ fontSize: 10 }}
                                    stroke="#6b7280"
                                    type="number"
                                    domain={[0, config.totalTicks - 1]}
                                />
                                <YAxis
                                    tick={{ fontSize: 10 }}
                                    stroke="#6b7280"
                                    domain={[0, config.maxSumValue]}
                                />
                                <Tooltip
                                    contentStyle={{
                                        backgroundColor: "#fff",
                                        border: "1px solid #e5e7eb",
                                        borderRadius: "4px",
                                        fontSize: "12px",
                                    }}
                                />
                                <Legend wrapperStyle={{ fontSize: "12px" }} />
                                {experiments.map(experiment => (
                                    <Line
                                        key={experiment.name}
                                        type="monotone"
                                        data={experiment.data}
                                        dataKey="client1Value"
                                        stroke={experiment.color}
                                        strokeWidth={2}
                                        dot={false}
                                        name={experiment.name}
                                    />
                                ))}
                            </LineChart>
                        </ResponsiveContainer>
                    </div>
                </div>
            </div>
        </div>
    )
}
