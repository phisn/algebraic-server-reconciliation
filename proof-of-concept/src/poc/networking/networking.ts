import { JSX } from "react"
import { Game, GenericAction } from "../game/game"

export const MessageSymbol = Symbol("Message")

export interface GenericMessage {
    type: typeof MessageSymbol
}

export interface Socket {
    id(): string
    send(message: GenericMessage): void
    receive(): GenericMessage | undefined
    receiveLatest(): GenericMessage | undefined
}

export interface NetworkingStrategy {
    wrapServer(game: Game, sockets: Socket[]): ServerStrategy
    wrapClient(game: Game, socket: Socket): ClientStrategy
}

export interface ServerStrategy {
    render(): JSX.Element
    update(): void
}

export interface ClientStrategy {
    getInput(): GenericAction
    render(): JSX.Element
    update(): void
}
