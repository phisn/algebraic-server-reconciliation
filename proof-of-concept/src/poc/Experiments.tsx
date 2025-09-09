import { OrthographicCamera } from "@react-three/drei"
import { Canvas } from "@react-three/fiber"
import { JSX, useEffect, useMemo, useState } from "react"
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

// Import game types
import { Experiment, Game, GenericCompoundAction, GenericState } from "./game/game"

// Import games and their experiments
import { SideScroller, experiments as sideScrollerExperiments } from "./game/SideScroller"
import { TopDown, experiments as topDownExperiments } from "./game/TopDown"

// Import networking types and strategies
import { MemorySocket } from "./networking/memory-socket"
import { ClientStrategy, NetworkingStrategy, ServerStrategy } from "./networking/networking"
import { AlgebraicNetworking } from "./networking/strategy-algebraic"
import { OverrideNetworking } from "./networking/strategy-override"
import { RollbackNetworking } from "./networking/strategy-rollback"

interface StrategyConfig {
    name: string
    color: string
    factory: () => NetworkingStrategy
}

interface GameConfig {
    name: string
    factory: () => Game
    experiments: Experiment[]
}

interface ObservedDataPoint {
    tick: number
    [key: string]: number | undefined
}

interface ExperimentResults {
    divergence: ObservedDataPoint[]
    observed: ObservedDataPoint[]
    observedComparison: ObservedDataPoint[]
}

const NETWORKING_STRATEGIES: Record<string, StrategyConfig> = {
    algebraic: {
        name: "Algebraic",
        color: "#8b5cf6",
        factory: () => new AlgebraicNetworking(),
    },
    rollback: {
        name: "Rollback",
        color: "#3b82f6",
        factory: () => new RollbackNetworking(),
    },
    override: {
        name: "Override",
        color: "#ef4444",
        factory: () => new OverrideNetworking(),
    },
}

const GAMES: Record<string, GameConfig> = {
    TopDown: {
        name: "Top Down",
        factory: () => new TopDown({ static_entities_in_prediction: false }),
        experiments: topDownExperiments || [],
    },
    SideScroller: {
        name: "Side Scroller",
        factory: () => new SideScroller({ static_entities_in_prediction: false }),
        experiments: sideScrollerExperiments || [],
    },
}

// Helper function to extract value from nested object using dot notation
function getNestedValue(obj: any, path: string): number | undefined {
    if (!path) return undefined

    const keys = path.split(".")
    let value = obj

    for (const key of keys) {
        if (value === null || value === undefined) return undefined
        value = value[key]
    }

    // Convert to number if possible
    if (typeof value === "number") return value
    if (typeof value === "string" && !isNaN(Number(value))) return Number(value)
    if (typeof value === "boolean") return value ? 1 : 0

    return undefined
}

/**
 * Calculate divergence for each client individually (no averaging)
 */
function calculateDivergence(serverState: GenericState, clientGames: Game[]): number[] {
    try {
        const serverStr = JSON.stringify(serverState)
        return clientGames.map(g => {
            const clientStr = JSON.stringify(g.getState())
            let diff = 0
            const maxLen = Math.max(serverStr.length, clientStr.length)
            for (let i = 0; i < maxLen; i++) {
                if (serverStr[i] !== clientStr[i]) diff++
            }
            return diff / Math.max(maxLen, 1)
        })
    } catch {
        return clientGames.map(() => 0)
    }
}

function runExperiment(
    gameFactory: () => Game,
    experiment: Experiment,
    strategy: NetworkingStrategy,
    strategyKey: string,
    delay: number = 30,
): ExperimentResults {
    const results: ExperimentResults = {
        divergence: [],
        observed: [],
        observedComparison: [],
    }

    const clientIds = Object.keys(experiment.inputs)
    const clientCount = clientIds.length

    if (clientCount === 0) {
        return results
    }

    const maxInputLength = Math.max(...clientIds.map(id => experiment.inputs[id]?.length || 0))

    if (maxInputLength === 0) {
        return results
    }

    // Create server game
    const serverGame = gameFactory()

    // Create client games
    const clientGames: Game[] = clientIds.map(() => {
        const game = gameFactory()
        return game
    })

    // Create sockets
    const socketPairs = Array.from({ length: clientCount }, (_, i) =>
        MemorySocket.pair({
            delay,
            id: clientIds[i],
        }),
    )

    // Create wrapped clients
    const clients: ClientStrategy[] = socketPairs.map((pair, i) => {
        const wrappedClient = strategy.wrapClient(clientGames[i], pair[1])

        const clientId = clientIds[i]
        const inputSequence = experiment.inputs[clientId]

        let currentTick = 0
        const originalGetInput = wrappedClient.getInput.bind(wrappedClient)

        wrappedClient.getInput = () => {
            if (inputSequence && currentTick < inputSequence.length) {
                const input = inputSequence[currentTick]
                currentTick++
                return input
            }
            return originalGetInput()
        }

        return wrappedClient
    })

    // Wrap server
    const server: ServerStrategy = strategy.wrapServer(
        serverGame,
        socketPairs.map(pair => pair[0]),
    )

    serverGame.setState(experiment.state)
    clientGames.forEach(clientGame => clientGame.setState(experiment.state))

    // Run simulation
    const sampleRate = Math.max(1, Math.floor(experiment.length / 40))

    for (let tick = 0; tick < experiment.length; tick++) {
        const compoundAction: GenericCompoundAction = {
            actions: {},
        }

        clientIds.forEach((clientId, i) => {
            const inputSequence = experiment.inputs[clientId]
            if (inputSequence && tick < inputSequence.length) {
                compoundAction.actions[clientId] = inputSequence[tick]
            }
        })

        server.update()
        clients.forEach(client => client.update(compoundAction.actions[client.getId()]))

        // Sample metrics
        if (tick % sampleRate === 0 || tick === experiment.length - 1) {
            const serverState = serverGame.getState()

            // --- Divergence: one series per client ---
            const divergences = calculateDivergence(serverState, clientGames)
            let divPoint = results.divergence.find(p => p.tick === tick)
            if (!divPoint) {
                divPoint = { tick }
                results.divergence.push(divPoint)
            }
            divergences.forEach((div, i) => {
                const clientId = clientIds[i]
                divPoint[`${strategyKey}_client_${clientId}`] = div
            })

            // --- Observed values: server + each client separately ---
            if (experiment.observe) {
                const serverValue = getNestedValue(serverState, experiment.observe)

                let obsPoint = results.observed.find(p => p.tick === tick)
                if (!obsPoint) {
                    obsPoint = { tick }
                    results.observed.push(obsPoint)
                }
                // Keep a server line (per strategy, solid)
                obsPoint[`${strategyKey}_server`] = serverValue

                // Per-client observed lines (no averaging)
                const clientValues = clientGames.map(g =>
                    getNestedValue(g.getState(), experiment.observe),
                )

                // Comparison (|client - server|)
                let compPoint = results.observedComparison.find(p => p.tick === tick)
                if (!compPoint) {
                    compPoint = { tick }
                    results.observedComparison.push(compPoint)
                }

                clientValues.forEach((cv, i) => {
                    const clientId = clientIds[i]
                    if (cv !== undefined) {
                        obsPoint[`${strategyKey}_client_${clientId}`] = cv
                        if (serverValue !== undefined) {
                            compPoint[`${strategyKey}_client_${clientId}`] = Math.abs(
                                cv - serverValue,
                            )
                        }
                    }
                })
            }
        }
    }

    return results
}

interface ChartProps {
    gameName: string
    gameFactory: () => Game
    experiment: Experiment
    experimentIndex: number
}

/**
 * Utilities to build a real-time simulation for the chosen experiment + strategy,
 * rendering the actual Server and Client views (inspired by the Sandbox).
 */
function useSimScenario(
    gameFactory: () => Game,
    experiment: Experiment,
    strategyKey: string,
    delay = 30,
) {
    return useMemo(() => {
        const strategy = NETWORKING_STRATEGIES[strategyKey].factory()
        const clientIds = Object.keys(experiment.inputs)

        // Create games
        const serverGame = gameFactory()
        const clientGames: Game[] = clientIds.map(() => {
            const g = gameFactory()
            return g
        })

        // Sockets
        const socketPairs = clientIds.map((id: string) =>
            MemorySocket.pair({
                delay,
                id,
            }),
        )

        // Wrap
        const clients: ClientStrategy[] = socketPairs.map((pair, i) =>
            strategy.wrapClient(clientGames[i], pair[1]),
        )
        const server: ServerStrategy = strategy.wrapServer(
            serverGame,
            socketPairs.map(p => p[0]),
        )

        // One tick step driven by experiment inputs
        const step = (tick: number) => {
            const compoundAction: GenericCompoundAction = { actions: {} }
            clientIds.forEach(clientId => {
                const seq = experiment.inputs[clientId]
                if (seq && tick < seq.length) {
                    compoundAction.actions[clientId] = seq[tick]
                }
            })

            server.update()
            clients.forEach(c => c.update(compoundAction.actions[c.getId()]))
        }

        // Small wrappers to render current state
        const Views = {
            Server: () => server.render(),
            clients: clients.map(c => () => c.render()),
        }

        // A function to reset all games to initial state (used by external re-init)
        const resetState = () => {
            serverGame.setState(experiment.state)
            clientGames.forEach(g => g.setState(experiment.state))
        }

        serverGame.setState(experiment.state)
        // clientGames.forEach(clientGame => clientGame.setState(experiment.state))

        return { step, Views, resetState, clientCount: clientIds.length }
        // Rebuild scenario whenever these change
    }, [gameFactory, experiment, strategyKey, delay])
}

function ExperimentChart({ gameName, gameFactory, experiment, experimentIndex }: ChartProps) {
    const [viewMode, setViewMode] = useState<"divergence" | "observed" | "comparison">("divergence")
    const [showSim, setShowSim] = useState(false)

    // NEW: track which series (by dataKey) are hidden
    const [hiddenKeys, setHiddenKeys] = useState<Set<string>>(new Set())

    const { divergenceData, observedData, comparisonData } = useMemo(() => {
        const allDivergence: ObservedDataPoint[] = []
        const allObserved: ObservedDataPoint[] = []
        const allComparison: ObservedDataPoint[] = []

        Object.entries(NETWORKING_STRATEGIES).forEach(([strategyKey, strategyConfig]) => {
            const strategy = strategyConfig.factory()
            const results = runExperiment(gameFactory, experiment, strategy, strategyKey)

            results.divergence.forEach(point => {
                let existing = allDivergence.find(p => p.tick === point.tick)
                if (!existing) {
                    existing = { tick: point.tick }
                    allDivergence.push(existing)
                }
                Object.assign(existing, point)
            })

            results.observed.forEach(point => {
                let existing = allObserved.find(p => p.tick === point.tick)
                if (!existing) {
                    existing = { tick: point.tick }
                    allObserved.push(existing)
                }
                Object.assign(existing, point)
            })

            results.observedComparison.forEach(point => {
                let existing = allComparison.find(p => p.tick === point.tick)
                if (!existing) {
                    existing = { tick: point.tick }
                    allComparison.push(existing)
                }
                Object.assign(existing, point)
            })
        })

        return {
            divergenceData: allDivergence.sort((a, b) => a.tick - b.tick),
            observedData: allObserved.sort((a, b) => a.tick - b.tick),
            comparisonData: allComparison.sort((a, b) => a.tick - b.tick),
        }
    }, [gameFactory, experiment])

    // Reset hidden state when switching view/experiment/game
    useEffect(() => {
        setHiddenKeys(new Set())
    }, [viewMode, experimentIndex, gameName])

    const handleExport = (format: "svg" | "json") => {
        if (format === "svg") {
            const chartId = `chart-${gameName}-${experimentIndex}`
            const svgElement = document.querySelector(`#${chartId} svg`) as SVGElement
            if (svgElement) {
                // Clone the SVG to avoid modifying the original
                const svgClone = svgElement.cloneNode(true) as SVGElement

                // Get all text elements (including axis labels)
                const textElements = svgClone.querySelectorAll("text")

                // Apply computed styles inline to ensure they're preserved
                textElements.forEach(textEl => {
                    const computedStyle = window.getComputedStyle(textEl)
                    // Copy important text styles
                    textEl.style.fontFamily = computedStyle.fontFamily || "sans-serif"
                    textEl.style.fontSize = computedStyle.fontSize || "12px"
                    textEl.style.fill = computedStyle.fill || "#9ca3af"
                    textEl.style.fontWeight = computedStyle.fontWeight || "normal"
                })

                // Add a title and description for accessibility
                const title = document.createElementNS("http://www.w3.org/2000/svg", "title")
                title.textContent = `${gameName} - ${experiment.name} - ${viewMode}`
                svgClone.insertBefore(title, svgClone.firstChild)

                // Set proper SVG attributes for standalone viewing
                svgClone.setAttribute("xmlns", "http://www.w3.org/2000/svg")
                svgClone.setAttribute("xmlns:xlink", "http://www.w3.org/1999/xlink")

                // Add a white background for better visibility
                const background = document.createElementNS("http://www.w3.org/2000/svg", "rect")
                background.setAttribute("width", "100%")
                background.setAttribute("height", "100%")
                background.setAttribute("fill", "white")
                svgClone.insertBefore(background, svgClone.firstChild)

                const svgData = new XMLSerializer().serializeToString(svgClone)
                const blob = new Blob([svgData], { type: "image/svg+xml;charset=utf-8" })
                const url = URL.createObjectURL(blob)
                const link = document.createElement("a")
                link.href = url
                link.download = `${gameName}-${experiment.name.replace(/\s+/g, "-")}-${viewMode}.svg`
                link.click()
                URL.revokeObjectURL(url)
            }
        } else {
            const exportData = {
                game: gameName,
                experiment: experiment.name,
                viewMode,
                observe: experiment.observe,
                clients: Object.keys(experiment.inputs),
                duration: experiment.length,
                divergence: divergenceData,
                observed: observedData,
                comparison: comparisonData,
                timestamp: new Date().toISOString(),
            }
            const blob = new Blob([JSON.stringify(exportData, null, 2)], {
                type: "application/json",
            })
            const url = URL.createObjectURL(blob)
            const link = document.createElement("a")
            link.href = url
            link.download = `${gameName}-${experiment.name.replace(/\s+/g, "-")}-${viewMode}.json`
            link.click()
            URL.revokeObjectURL(url)
        }
    }

    const clientIds = Object.keys(experiment.inputs)
    const clientCount = clientIds.length
    const hasObservedData = experiment.observe && observedData.length > 0

    const dashPatterns = ["5 5", "3 3", "8 4", "2 6", "7 3 3 3"]

    let chartData = divergenceData
    let chartLines: Array<{ key: string; name: string; color: string; dash?: string }> = []
    let yAxisLabel = "State Divergence"

    if (viewMode === "divergence") {
        chartData = divergenceData
        chartLines = Object.entries(NETWORKING_STRATEGIES).flatMap(([key, strategy]) =>
            clientIds.map((clientId, idx) => ({
                key: `${key}_client_${clientId}`,
                name: `${strategy.name} (Client ${clientId})`,
                color: strategy.color,
                dash: dashPatterns[idx % dashPatterns.length],
            })),
        )
        yAxisLabel = "State Divergence"
    } else if (viewMode === "observed" && hasObservedData) {
        chartData = observedData
        chartLines = Object.entries(NETWORKING_STRATEGIES).flatMap(([key, strategy]) => {
            const serverLine = {
                key: `${key}_server`,
                name: `${strategy.name} (Server)`,
                color: strategy.color,
            }
            const clientLines = clientIds.map((clientId, idx) => ({
                key: `${key}_client_${clientId}`,
                name: `${strategy.name} (Client ${clientId})`,
                color: strategy.color,
                dash: dashPatterns[idx % dashPatterns.length],
            }))
            return [serverLine, ...clientLines]
        })
        yAxisLabel = `Observed value`
    } else if (viewMode === "comparison" && hasObservedData) {
        chartData = comparisonData
        chartLines = Object.entries(NETWORKING_STRATEGIES).flatMap(([key, strategy]) =>
            clientIds.map((clientId, idx) => ({
                key: `${key}_client_${clientId}`,
                name: `${strategy.name} Δ (Client ${clientId})`,
                color: strategy.color,
                dash: dashPatterns[idx % dashPatterns.length],
            })),
        )
        yAxisLabel = `Difference from Server Truth`
    }

    // Legend interactions
    const toggleKey = (key: string) =>
        setHiddenKeys(prev => {
            const next = new Set(prev)
            next.has(key) ? next.delete(key) : next.add(key)
            return next
        })
    const showAll = () => setHiddenKeys(new Set())
    const hideAll = () => setHiddenKeys(new Set(chartLines.map(l => l.key)))

    // Custom legend so we can show "hidden" state
    const renderLegend = (props: any) => {
        // Recharts supplies payload that mirrors our <Line> children
        const payload: Array<{ value: string; color: string; dataKey: string }> =
            props?.payload || []
        return (
            <div className="mt-3 flex flex-wrap items-center gap-2">
                {payload.map(item => {
                    const off = hiddenKeys.has(item.dataKey)
                    return (
                        <button
                            key={item.dataKey}
                            onClick={() => toggleKey(item.dataKey)}
                            aria-pressed={!off}
                            className={`btn btn-xs ${off ? "btn-ghost opacity-50" : "btn-ghost"}`}
                            title={`Toggle ${item.value}`}
                        >
                            <span
                                className="mr-2 inline-block h-3 w-3 rounded"
                                style={{ background: item.color }}
                            />
                            {item.value}
                        </button>
                    )
                })}
                <span className="ml-2" />
                <button className="btn btn-ghost btn-xs" onClick={showAll}>
                    Show all
                </button>
                <button className="btn btn-ghost btn-xs" onClick={hideAll}>
                    Hide all
                </button>
            </div>
        )
    }

    // ---- NEW: Compute Y-axis domain as ±10% padding around visible series ----
    const yDomain: [number, number] = useMemo(() => {
        const visibleKeys = chartLines.map(l => l.key).filter(k => !hiddenKeys.has(k))

        let min = Infinity
        let max = -Infinity

        for (const point of chartData) {
            for (const key of visibleKeys) {
                const val = point[key]
                if (typeof val === "number" && !Number.isNaN(val)) {
                    if (val < min) min = val
                    if (val > max) max = val
                }
            }
        }

        // Fallback if nothing visible
        if (min === Infinity || max === -Infinity) {
            return [0, 1]
        }

        // If flat line, add reasonable padding
        if (min === max) {
            const pad = Math.max(Math.abs(max) * 0.1, 1e-6)
            let lower = min - pad
            let upper = max + pad
            // For non-negative metrics, avoid showing negative floor if unnecessary
            if (viewMode !== "observed") lower = Math.max(0, lower)
            return [lower, upper]
        }

        const range = max - min
        const pad = range * 0.1 // ±10%

        let lower = min - pad
        let upper = max + pad

        // Divergence & Comparison are non-negative; don't dip below 0 unless observed
        if (viewMode !== "observed") lower = Math.max(0, lower)

        return [lower, upper]
    }, [chartData, chartLines, hiddenKeys, viewMode])

    return (
        <div className="card bg-base-100 shadow-xl">
            <div className="card-body">
                <div className="flex items-start justify-between">
                    <div>
                        <h3 className="card-title text-lg">{experiment.name}</h3>
                        <p className="text-base-content/60 text-sm">
                            {clientCount} {clientCount === 1 ? "client" : "clients"} •{" "}
                            {experiment.length} ticks
                            {experiment.observe && (
                                <>
                                    <br />
                                    Observing:{" "}
                                    <code className="bg-base-200 rounded px-1 text-xs">
                                        {experiment.observe}
                                    </code>
                                </>
                            )}
                        </p>
                    </div>
                    <div className="flex items-center gap-2">
                        <button
                            className={`btn btn-sm ${showSim ? "btn-warning" : "btn-primary"}`}
                            onClick={() => setShowSim(s => !s)}
                            title="Open live simulation to render server/clients"
                        >
                            {showSim ? "Close Simulation" : "Simulate ▶"}
                        </button>
                        {hasObservedData && (
                            <select
                                className="select select-sm select-bordered"
                                value={viewMode}
                                onChange={e => setViewMode(e.target.value as any)}
                            >
                                <option value="divergence">Divergence</option>
                                <option value="observed">Observed Values</option>
                                <option value="comparison">Server Comparison</option>
                            </select>
                        )}
                        <button
                            className="btn btn-sm btn-ghost"
                            onClick={() => handleExport("json")}
                        >
                            JSON
                        </button>
                        <button
                            className="btn btn-sm btn-ghost"
                            onClick={() => handleExport("svg")}
                        >
                            SVG
                        </button>
                    </div>
                </div>

                <div id={`chart-${gameName}-${experimentIndex}`} className="mt-4 w-full">
                    <ResponsiveContainer width="100%" height={280}>
                        <LineChart
                            data={chartData}
                            margin={{ top: 5, right: 15, left: 15, bottom: 25 }}
                        >
                            <CartesianGrid strokeDasharray="3 3" stroke="#374151" opacity={0.3} />
                            <XAxis
                                dataKey="tick"
                                label={{
                                    value: "Simulation Ticks",
                                    position: "insideBottom",
                                    offset: -10,
                                }}
                                stroke="#9ca3af"
                                style={{ fontSize: 12 }}
                            />
                            <YAxis
                                label={{
                                    value: yAxisLabel,
                                    angle: -90,
                                    style: { textAnchor: "middle" },
                                    position: "left",
                                }}
                                stroke="#9ca3af"
                                domain={yDomain}
                                style={{ fontSize: 12 }}
                                tickFormatter={value =>
                                    typeof value === "number" ? value.toFixed(2) : value
                                }
                            />
                            <Tooltip
                                contentStyle={{
                                    backgroundColor: "#1f2937",
                                    border: "1px solid #374151",
                                    borderRadius: "0.5rem",
                                }}
                                labelStyle={{ color: "#f3f4f6" }}
                                formatter={(value: number) =>
                                    value?.toFixed ? value.toFixed(4) : value
                                }
                            />

                            {/* Custom legend with toggles */}
                            <Legend verticalAlign="bottom" align="left" content={renderLegend} />

                            {chartLines.map(line => (
                                <Line
                                    key={line.key}
                                    type="monotone"
                                    dataKey={line.key}
                                    stroke={line.color}
                                    strokeWidth={2}
                                    strokeDasharray={line.dash}
                                    name={line.name}
                                    dot={false}
                                    activeDot={{ r: 4 }}
                                    hide={hiddenKeys.has(line.key)} // <-- toggle visibility
                                />
                            ))}
                        </LineChart>
                    </ResponsiveContainer>
                </div>

                {showSim && <SimulatePanel experiment={experiment} gameFactory={gameFactory} />}
            </div>
        </div>
    )
}

/** Live simulation (render server + all client views, driven by the experiment's input). */
function SimulatePanel({
    experiment,
    gameFactory,
}: {
    experiment: Experiment
    gameFactory: () => Game
}) {
    const [strategyKey, setStrategyKey] = useState<keyof typeof NETWORKING_STRATEGIES>("algebraic")
    const [tick, setTick] = useState(0)
    const [isPlaying, setIsPlaying] = useState(false)
    const [tickRate, setTickRate] = useState(60)
    const [delay, setDelay] = useState(30)

    const maxTicks = experiment.length

    const { step, Views, resetState, clientCount } = useSimScenario(
        gameFactory,
        experiment,
        strategyKey,
        delay,
    )

    // Drive the simulation
    useEffect(() => {
        if (!isPlaying) return
        const id = setInterval(() => {
            setTick(prev => {
                if (prev >= maxTicks - 1) {
                    return prev // stop at the end; will pause below
                }
                // advance one tick and step scenario
                step(prev)
                return prev + 1
            })
        }, 1000 / tickRate)
        return () => clearInterval(id)
    }, [isPlaying, step, tickRate, maxTicks])

    // Auto-pause when reaching end
    useEffect(() => {
        if (tick >= maxTicks - 1 && isPlaying) {
            setIsPlaying(false)
        }
    }, [tick, maxTicks, isPlaying])

    // When strategy or delay changes, reset everything
    useEffect(() => {
        setIsPlaying(false)
        setTick(0)
        resetState()
    }, [strategyKey, delay, resetState])

    const doStep = () => {
        if (tick < maxTicks - 1) {
            step(tick)
            setTick(tick + 1)
        }
    }

    const doReset = () => {
        setIsPlaying(false)
        setTick(0)
        resetState()
    }

    return (
        <div className="border-base-300 bg-base-200 mt-6 rounded-lg border p-3">
            {/* Controls */}
            <div className="mb-3 flex flex-wrap items-center gap-2">
                <select
                    className="select select-sm select-bordered"
                    value={strategyKey}
                    onChange={e =>
                        setStrategyKey(e.target.value as keyof typeof NETWORKING_STRATEGIES)
                    }
                    title="Select networking strategy to simulate"
                >
                    {Object.entries(NETWORKING_STRATEGIES).map(([key, s]) => (
                        <option key={key} value={key}>
                            {s.name}
                        </option>
                    ))}
                </select>

                <label className="flex items-center gap-2 text-sm">
                    <span>Delay</span>
                    <input
                        type="range"
                        min={0}
                        max={100}
                        value={delay}
                        onChange={e => setDelay(Number(e.target.value))}
                        className="range range-xs"
                        style={{ width: 160 }}
                    />
                    <span className="badge">{delay} packets</span>
                </label>

                <label className="flex items-center gap-2 text-sm">
                    <span>Tick Rate</span>
                    <input
                        type="range"
                        min={10}
                        max={144}
                        step={10}
                        value={tickRate}
                        onChange={e => setTickRate(Number(e.target.value))}
                        className="range range-xs"
                        style={{ width: 160 }}
                    />
                    <span className="badge">{tickRate} Hz</span>
                </label>

                <div className="ml-auto flex items-center gap-2">
                    <button
                        className={`btn btn-sm ${isPlaying ? "btn-error" : "btn-success"}`}
                        onClick={() => setIsPlaying(p => !p)}
                    >
                        {isPlaying ? "⏸ Pause" : "▶ Play"}
                    </button>
                    <button className="btn btn-sm btn-ghost" onClick={doStep} disabled={isPlaying}>
                        Step
                    </button>
                    <button className="btn btn-sm btn-ghost" onClick={doReset}>
                        Reset
                    </button>
                    <span className="badge badge-outline">
                        {tick} / {maxTicks - 1}
                    </span>
                </div>
            </div>

            {/* Progress */}
            <div className="mb-3">
                <progress
                    className="progress progress-primary w-full"
                    value={tick}
                    max={maxTicks - 1}
                />
            </div>

            {/* Views */}
            <div className="grid gap-3 lg:grid-cols-2">
                <div className="card bg-base-100 shadow-sm">
                    <div className="card-body p-3">
                        <h4 className="mb-2 font-semibold">Server View</h4>
                        <ServerViewport>
                            <Views.Server />
                        </ServerViewport>
                    </div>
                </div>

                <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
                    {Array.from({ length: clientCount }).map((_, i) => {
                        const Client = Views.clients[i]
                        return (
                            <div key={i} className="card bg-base-100 shadow-sm">
                                <div className="card-body p-3">
                                    <h4 className="mb-2 font-semibold">Client {i + 1}</h4>
                                    <ClientViewport>
                                        <Client />
                                    </ClientViewport>
                                </div>
                            </div>
                        )
                    })}
                </div>
            </div>

            <p className="mt-3 text-xs opacity-70">
                This live view replays the experiment's recorded inputs on each client while the
                selected networking strategy processes them in real time. Use Play, Step, and Reset
                for precise debugging.
            </p>
        </div>
    )
}

function ClientViewport({ children }: { children: JSX.Element }) {
    return (
        <div className="flex justify-center">
            <div className="border-base-300 aspect-square w-[22rem] max-w-full overflow-hidden rounded border">
                <Canvas orthographic>
                    <OrthographicCamera makeDefault far={1000} near={-1000} scale={5} />
                    {children}
                </Canvas>
            </div>
        </div>
    )
}

function ServerViewport({ children }: { children: JSX.Element }) {
    return (
        <div className="flex w-full justify-center">
            <div className="border-base-300 aspect-video w-[30rem] max-w-full overflow-hidden rounded border">
                <Canvas orthographic>
                    <OrthographicCamera makeDefault far={1000} near={-1000} scale={5} />
                    {children}
                </Canvas>
            </div>
        </div>
    )
}

export function Experiments() {
    const [selectedGame, setSelectedGame] = useState<string>("TopDown")
    const [loading, setLoading] = useState(true)

    const currentGame = GAMES[selectedGame]
    const experiments = currentGame?.experiments || []

    useEffect(() => {
        setLoading(true)
        const timer = setTimeout(() => setLoading(false), 300)
        return () => clearTimeout(timer)
    }, [selectedGame])

    if (loading) {
        return (
            <div className="bg-base-200 flex min-h-screen items-center justify-center">
                <div className="text-center">
                    <div className="loading loading-spinner loading-lg"></div>
                    <p className="mt-4 text-lg">Computing experiments...</p>
                </div>
            </div>
        )
    }

    return (
        <div className="bg-base-200 min-h-screen p-4">
            <div className="mx-auto max-w-7xl space-y-6">
                {/* Header */}
                <div className="navbar bg-base-100 rounded-box shadow-lg">
                    <div className="navbar-start">
                        <h1 className="px-4 text-2xl font-bold">Network Experiments</h1>
                    </div>
                    <div className="navbar-center">
                        <div className="tabs tabs-boxed">
                            {Object.entries(GAMES).map(([key, config]) => (
                                <button
                                    key={key}
                                    className={`tab ${selectedGame === key ? "tab-active" : ""}`}
                                    onClick={() => setSelectedGame(key)}
                                >
                                    {config.name}
                                </button>
                            ))}
                        </div>
                    </div>
                    <div className="navbar-end px-4">
                        <div className="badge badge-lg badge-outline">
                            {experiments.length}{" "}
                            {experiments.length === 1 ? "Experiment" : "Experiments"}
                        </div>
                    </div>
                </div>

                {/* Strategy Legend */}
                <div className="card bg-base-100 shadow">
                    <div className="card-body py-4">
                        <div className="flex flex-wrap items-center justify-center gap-6">
                            {Object.entries(NETWORKING_STRATEGIES).map(([key, strategy]) => (
                                <div key={key} className="flex items-center gap-2">
                                    <div
                                        className="h-3 w-3 rounded-full"
                                        style={{ backgroundColor: strategy.color }}
                                    />
                                    <span className="text-sm font-medium">{strategy.name}</span>
                                </div>
                            ))}
                        </div>
                    </div>
                </div>

                {/* Experiments Grid */}
                {experiments.length > 0 ? (
                    <div className="grid gap-6 lg:grid-cols-2">
                        {experiments.map((experiment, index) => (
                            <ExperimentChart
                                key={`${selectedGame}-${index}`}
                                gameName={selectedGame}
                                gameFactory={currentGame.factory}
                                experiment={experiment}
                                experimentIndex={index}
                            />
                        ))}
                    </div>
                ) : (
                    <div className="card bg-base-100 shadow">
                        <div className="card-body py-16 text-center">
                            <p className="text-base-content/60 text-lg">
                                No experiments defined for {currentGame.name}
                            </p>
                            <p className="text-base-content/40 mt-2 text-sm">
                                Export an{" "}
                                <code className="bg-base-200 rounded px-2 py-1">Experiment[]</code>{" "}
                                from {selectedGame}.tsx
                            </p>
                        </div>
                    </div>
                )}

                {/* Summary */}
                {experiments.length > 0 && (
                    <div className="card bg-base-100 shadow">
                        <div className="card-body">
                            <h2 className="card-title mb-4">Summary</h2>
                            <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
                                <div className="stat bg-base-200 rounded-lg p-4">
                                    <div className="stat-title text-xs">Game</div>
                                    <div className="stat-value text-lg">{currentGame.name}</div>
                                </div>
                                <div className="stat bg-base-200 rounded-lg p-4">
                                    <div className="stat-title text-xs">Experiments</div>
                                    <div className="stat-value text-lg">{experiments.length}</div>
                                </div>
                                <div className="stat bg-base-200 rounded-lg p-4">
                                    <div className="stat-title text-xs">Strategies</div>
                                    <div className="stat-value text-lg">
                                        {Object.keys(NETWORKING_STRATEGIES).length}
                                    </div>
                                </div>
                                <div className="stat bg-base-200 rounded-lg p-4">
                                    <div className="stat-title text-xs">Network Delay</div>
                                    <div className="stat-value text-lg">30 packets</div>
                                </div>
                            </div>
                        </div>
                    </div>
                )}
            </div>
        </div>
    )
}
