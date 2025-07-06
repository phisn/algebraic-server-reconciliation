import { JSX } from "react"
import { Game, GenericAction, GenericCompoundAction, GenericState } from "../game/game"
import {
    ClientStrategy,
    GenericMessage,
    MessageSymbol,
    NetworkingStrategy,
    ServerStrategy,
    Socket,
} from "./networking"

interface ServerMessage extends GenericMessage {
    type: typeof MessageSymbol
    variant: "set"

    clientTick: number
    state: GenericState
}

interface ClientMessage extends GenericMessage {
    type: typeof MessageSymbol

    action: GenericAction
    tick: number
}

export class RollbackNetworking implements NetworkingStrategy {
    wrapServer(game: Game, sockets: Socket[]): ServerStrategy {
        return new RollbackServerStrategy(game, sockets)
    }

    wrapClient(game: Game, socket: Socket): ClientStrategy {
        return new RollbackClientStrategy(game, socket)
    }
}

export class RollbackServerStrategy implements ServerStrategy {
    private _clientTicks: Map<string, number>
    private _tick: number

    constructor(
        private _game: Game,
        private _sockets: Socket[],
    ) {
        this._clientTicks = new Map()
        this._tick = 0

        for (const socket of this._sockets) {
            this._game.spawnPlayer(socket.id())
            this._clientTicks.set(socket.id(), 0)
        }
    }

    render(): JSX.Element {
        return this._game.render()
    }

    update(): void {
        this._tick++

        const actions: GenericCompoundAction = {
            actions: {},
        }

        for (const socket of this._sockets) {
            const clientId = socket.id()

            const message = socket.receiveLatest() as ClientMessage | undefined

            if (message) {
                actions.actions[clientId] = message.action
                this._clientTicks.set(socket.id(), this._clientTicks.get(socket.id())! + 1)
            }
        }

        this._game.update(actions)
        const state = this._game.getState()

        for (const socket of this._sockets) {
            const message: ServerMessage = {
                type: MessageSymbol,
                variant: "set",

                clientTick: this._clientTicks.get(socket.id())!,
                state,
            }

            socket.send(message)
        }
    }
}

export class RollbackClientStrategy implements ClientStrategy {
    private _actions: [number, GenericAction][]
    private _tick: number

    constructor(
        private _game: Game,
        private _socket: Socket,
    ) {
        this._actions = []
        this._tick = 0
    }

    getInput(): GenericAction {
        return this._game.getInput()
    }

    render(): JSX.Element {
        return this._game.render()
    }

    update(): void {
        this._tick++

        const message: ClientMessage = {
            type: MessageSymbol,
            action: this._game.getInput(),
            tick: this._tick,
        }
        this._socket.send(message)

        const serverMessage = this._socket.receiveLatest() as ServerMessage | undefined
        if (serverMessage) {
            const removeUntil = this._actions.findIndex(([x]) => x <= serverMessage.clientTick)
            this._actions.splice(0, removeUntil + 1)

            this._game.setState(serverMessage.state)

            for (const [, action] of this._actions) {
                this._game.predict(this._socket.id(), action)
            }
        }

        this._game.predict(this._socket.id(), this._game.getInput())
        this._actions.push([this._tick, this._game.getInput()])
    }
}
