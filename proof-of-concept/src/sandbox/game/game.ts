import { JSX } from "react"

export const ActionSymbol = Symbol("Action")

export interface GenericAction {
    type: typeof ActionSymbol
}

export const StateSymbol = Symbol("State")

export interface GenericState {
    type: typeof StateSymbol
}

export interface GenericCompoundAction {
    actions: Record<string, GenericAction>
}

export interface Game {
    render(): JSX.Element

    getInput(): GenericAction

    setState(state: GenericState): void
    getState(): GenericState

    predict(playerId: string, action: GenericAction): void
    update(action: GenericCompoundAction): void

    spawnPlayer(playerId: string): void
}
