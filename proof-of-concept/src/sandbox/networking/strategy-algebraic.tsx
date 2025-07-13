import { JSX } from "react"
import {
    AbelianGroup,
    Game,
    GenericAction,
    GenericCompoundAction,
    GenericState,
} from "../game/game"
import { State } from "../game/SideScroller"
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
    deltaState: GenericState
}

interface ClientMessage extends GenericMessage {
    type: typeof MessageSymbol

    action: GenericAction
    tick: number
}

export class AlgebraicNetworking implements NetworkingStrategy {
    wrapServer(game: Game, sockets: Socket[]): ServerStrategy {
        return new AlgebraicServerStrategy(game, sockets)
    }

    wrapClient(game: Game, socket: Socket): ClientStrategy {
        return new AlgebraicClientStrategy(game, socket)
    }
}

export class AlgebraicServerStrategy implements ServerStrategy {
    private _abelian: AbelianGroup
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

        const deltaState = this._game.getState()

        for (const socket of this._sockets) {
            const message: ServerMessage = {
                type: MessageSymbol,
                variant: "set",

                clientTick: 0,
                deltaState,
            }

            socket.send(message)
        }

        this._abelian = this._game.abelianGroup()
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
                this._clientTicks.set(socket.id(), message.tick)
            }
        }

        const state = this._game.getState()
        this._game.update(actions)
        const deltaState = this._abelian.add(this._game.getState(), this._abelian.neg(state))

        for (const socket of this._sockets) {
            const message: ServerMessage = {
                type: MessageSymbol,
                variant: "set",

                clientTick: this._clientTicks.get(socket.id())!,
                deltaState,
            }

            socket.send(message)
        }
    }
}

export class AlgebraicClientStrategy implements ClientStrategy {
    private _states: { [id: number]: GenericState }
    private _abelian: AbelianGroup
    private _tick: number

    constructor(
        private _game: Game,
        private _socket: Socket,
    ) {
        this._states = {}
        this._abelian = _game.abelianGroup()
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

        let state = this._game.getState()
        while (true) {
            const serverMessage = this._socket.receive() as ServerMessage | undefined
            if (serverMessage === undefined) {
                break
            }

            const previousState = this._states[serverMessage.clientTick]
            const epsilon =
                previousState === undefined
                    ? serverMessage.deltaState
                    : this._abelian.add(serverMessage.deltaState, this._abelian.neg(previousState))

            if (previousState && (previousState as State).players[this._socket.id()]) {
                console.log(
                    "expected ",
                    (serverMessage.deltaState as State).players[this._socket.id()].y,
                    (serverMessage.deltaState as State).players[this._socket.id()].vy,
                    " got ",
                    (previousState as State).players[this._socket.id()].y,
                    (previousState as State).players[this._socket.id()].vy,
                )
            }

            state = this._abelian.add(state, epsilon)
        }

        this._game.setState(state)
        this._game.predict({ actions: { [this._socket.id()]: this._game.getInput() } })
        this._states[this._tick] = this._abelian.add(
            this._game.getState(),
            this._abelian.neg(state),
        )
    }
}
