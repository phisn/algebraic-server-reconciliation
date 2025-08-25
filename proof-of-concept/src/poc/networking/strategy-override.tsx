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
    state: GenericState
}

interface ClientMessage extends GenericMessage {
    type: typeof MessageSymbol
    action: GenericAction
}

export class OverrideNetworking implements NetworkingStrategy {
    wrapServer(game: Game, sockets: Socket[]): ServerStrategy {
        return new OverrideServerStrategy(game, sockets)
    }

    wrapClient(game: Game, socket: Socket): ClientStrategy {
        return new OverrideClientStrategy(game, socket)
    }
}

export class OverrideServerStrategy implements ServerStrategy {
    constructor(
        private _game: Game,
        private _sockets: Socket[],
    ) {
        for (const socket of this._sockets) {
            console.log("spawning player", socket.id())
            this._game.spawnPlayer(socket.id())
        }
    }

    render(): JSX.Element {
        return this._game.render()
    }

    update(): void {
        const actions: GenericCompoundAction = {
            actions: {},
        }

        for (const socket of this._sockets) {
            const clientId = socket.id()
            const message = socket.receive() as ClientMessage | undefined

            if (message) {
                actions.actions[clientId] = message.action
            }
        }

        this._game.update(actions)

        const message: ServerMessage = {
            type: MessageSymbol,
            state: this._game.getState(),
        }

        for (const socket of this._sockets) {
            socket.send(message)
        }
    }
}

export class OverrideClientStrategy implements ClientStrategy {
    constructor(
        private _game: Game,
        private _socket: Socket,
    ) {}

    getInput(): GenericAction {
        return this._game.getInput()
    }

    render(): JSX.Element {
        return this._game.render()
    }

    update(): void {
        const message: ClientMessage = {
            type: MessageSymbol,
            action: this._game.getInput(),
        }

        this._socket.send(message)

        const serverMessage = this._socket.receiveLatest() as ServerMessage | undefined

        if (serverMessage) {
            this._game.setState(serverMessage.state)
        }
    }
}
