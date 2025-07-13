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

export interface MemorySocketModifiers {
    // Delay in number of packets
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
    ) {
        const sockets = [MemorySocket.pair({ delay: 30 }), MemorySocket.pair({ delay: 30 })]

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
            clients: this._clients.map(client => () => client.render()),
        }
    }
}

export function Sandbox() {
    const [scenario, setScenario] = useState<Scenario | null>(null)

    useEffect(() => {
        const scenario = new Scenario(
            () => new TopDown({ static_entities_in_prediction: true }),
            new AlgebraicNetworking(),
        )
        setScenario(scenario)

        const interval = setInterval(() => {
            scenario?.update()
        }, 1000 / 60)

        return () => clearInterval(interval)
    }, [])

    if (scenario === null) {
        return
    }

    const { Server, clients } = scenario.views()

    return (
        <div className="max-h-screen bg-white p-2">
            <div className="flex flex-col">
                <div className="">
                    <ServerViewport>
                        <Server />
                    </ServerViewport>
                </div>
                <div className="flex w-[30rem] space-x-4">
                    {clients.map(Client => (
                        <ClientViewport>
                            <Client />
                        </ClientViewport>
                    ))}
                </div>
            </div>
        </div>
    )
}

function ClientViewport(props: { children: JSX.Element }) {
    const [focus, setFocus] = useState(false)

    return (
        <div className="relative w-[30rem]">
            <div className="absolute right-0 top-0 z-50 p-4">
                <InputViewer focused={focus} />
            </div>
            <FocusContext.Provider value={focus}>
                <Viewport className="flex aspect-[1/1] flex-grow">
                    <Canvas
                        onFocus={() => setFocus(true)}
                        onBlur={() => setFocus(false)}
                        tabIndex={0}
                        orthographic
                    >
                        <OrthographicCamera makeDefault far={1000} near={-1000} scale={1.2} />
                        {props.children}
                    </Canvas>
                </Viewport>
            </FocusContext.Provider>
        </div>
    )
}

function ServerViewport(props: { children: JSX.Element }) {
    return (
        <div className="w-[30rem]">
            <Viewport className="flex aspect-[1/1] flex-grow">
                <Canvas>
                    <OrthographicCamera makeDefault far={1000} near={-1000} scale={2} />
                    {props.children}
                </Canvas>
            </Viewport>
        </div>
    )
}

function Viewport(props: { children: JSX.Element; className?: string }) {
    return (
        <div className={`relative border border-black ${props.className}`}>
            <div className="absolute inset-0">{props.children}</div>
        </div>
    )
}

function InputViewer(props: { focused: boolean }) {
    const [left, setLeft] = useState(false)
    const [up, setUp] = useState(false)
    const [right, setRight] = useState(false)
    const [down, setDown] = useState(false)

    useEffect(() => {
        if (props.focused === false) {
            return
        }

        const handleKeyDown = (event: KeyboardEvent) => {
            if (event.key === "ArrowLeft") {
                setLeft(true)
            }

            if (event.key === "ArrowRight") {
                setRight(true)
            }

            if (event.key === "ArrowUp") {
                setUp(true)
            }

            if (event.key === "ArrowDown") {
                setDown(true)
            }
        }

        const handleKeyUp = (event: KeyboardEvent) => {
            if (event.key === "ArrowLeft") {
                setLeft(false)
            }

            if (event.key === "ArrowRight") {
                setRight(false)
            }

            if (event.key === "ArrowUp") {
                setUp(false)
            }

            if (event.key === "ArrowDown") {
                setDown(false)
            }
        }

        window.addEventListener("keydown", handleKeyDown)
        window.addEventListener("keyup", handleKeyUp)

        return () => {
            window.removeEventListener("keydown", handleKeyDown)
            window.removeEventListener("keyup", handleKeyUp)

            setLeft(false)
            setRight(false)
            setUp(false)
            setDown(false)
        }
    }, [props.focused])

    return (
        <div className={"space-y-2 " + (props.focused ? "" : "opacity-50")}>
            <div className="flex w-full justify-center">
                <div className={"kbd kbd-xl " + (up ? "bg-red-400" : "")}>▲</div>
            </div>
            <div className="space-x-2">
                <kbd className={"kbd kbd-xl " + (left ? "bg-red-400" : "")}>◀︎</kbd>
                <kbd className={"kbd kbd-xl " + (down ? "bg-red-400" : "")}>▼</kbd>
                <kbd className={"kbd kbd-xl " + (right ? "bg-red-400" : "")}>▶︎</kbd>
            </div>
        </div>
    )
}
