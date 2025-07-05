import { Canvas } from "@react-three/fiber"
import { JSX, useEffect, useState } from "react"
import { Game } from "./game/game"
import { SideScroller } from "./game/SideScroller"
import {
    ClientStrategy,
    GenericMessage,
    NetworkingStrategy,
    ServerStrategy,
    Socket,
} from "./networking/networking"
import { OverrideNetworking } from "./networking/Override"

export interface MemorySocketModifiers {
    // Delay in number of packets
    receiveDelay: number
    sendDelay: number
}

export class MemorySocket implements Socket {
    private _buffer: GenericMessage[]

    constructor(
        private _id: string,
        private _modifiers: MemorySocketModifiers,
        private _receive: GenericMessage[],
        private _send: GenericMessage[],
    ) {
        this._buffer = []
    }

    static pair(modifiers: MemorySocketModifiers): [Socket, Socket] {
        const id = Math.random().toString(36).substring(2, 15)

        const l: GenericMessage[] = []
        const r: GenericMessage[] = []

        return [new MemorySocket(id, modifiers, l, r), new MemorySocket(id, modifiers, r, l)]
    }

    public id(): string {
        return this._id
    }

    public send(message: GenericMessage) {
        this._send.push(message)
    }

    public receive(): GenericMessage | undefined {
        return this._receive.shift()
    }

    public receiveLatest(): GenericMessage | undefined {
        if (this._receive.length > 0) {
            const result = this._receive[this.receive.length - 1]
            this._receive = []
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
        const sockets = MemorySocket.pair({ sendDelay: 10 })

        this._clients = [this._networkingStrategy.wrapClient(this._gameFactory(), sockets[1])]
        this._server = this._networkingStrategy.wrapServer(this._gameFactory(), [sockets[0]])
    }

    public update() {
        this._server.update()
        this._clients.forEach(client => client.update())
    }

    public views(): (() => JSX.Element)[] {
        return [() => this._server.render(), ...this._clients.map(client => () => client.render())]
    }
}

export function Sandbox() {
    const [scenario, setScenario] = useState<Scenario | null>(null)

    useEffect(() => {
        const scenario = new Scenario(() => new SideScroller(), new OverrideNetworking())
        setScenario(scenario)

        const interval = setInterval(() => {
            scenario?.update()
        }, 1000 / 60)

        return () => clearInterval(interval)
    }, [])

    return (
        <div className="flex max-h-screen justify-stretch space-x-2 p-2">
            {scenario?.views().map((View, index) => (
                <Viewport key={index} className="flex aspect-[1/1] flex-grow">
                    <Canvas orthographic>
                        <View />
                    </Canvas>
                </Viewport>
            ))}
        </div>
    )
}

export function Viewport(props: { children: JSX.Element; className?: string }) {
    return (
        <div className={`relative border ${props.className}`}>
            <div className="absolute inset-0">{props.children}</div>
        </div>
    )
}
