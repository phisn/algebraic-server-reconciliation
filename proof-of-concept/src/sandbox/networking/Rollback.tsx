import { GenericAction, GenericState } from "../game/game"
import { GenericMessage, MessageSymbol } from "./networking"

interface ServerMessage extends GenericMessage {
    type: typeof MessageSymbol

    state: GenericState
}

interface ClientMessage extends GenericMessage {
    type: typeof MessageSymbol

    action: GenericAction
}

/*
export class RollbackClientStrategy implements ClientStrategy {
    private _game: Game

    constructor(game: Game) {
        this._game = game
    }

    tick(genericMessage: GenericMessage): void {
        const message = genericMessage as Message

        this._game.setState(message.state)
    }
}

export class RollbackServerStrategy implements ServerStrategy {
    private _game: Game

    constructor(game: Game) {
        this._game = game
    }

    tick(): GenericMessage {
        const message: Message = {
            type: MessageSymbol,
            state: this._game.getState(),
        }

        return message
    }
}
*/
