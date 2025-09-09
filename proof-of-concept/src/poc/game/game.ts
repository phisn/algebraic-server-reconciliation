import { createContext, JSX } from "react"

export const FocusContext = createContext<boolean>(false)

export const ActionSymbol = Symbol("Action")

export interface GenericAction {
    type: typeof ActionSymbol
}

export const StateSymbol = Symbol("State")

export interface GenericState {
    type: typeof StateSymbol
}

export interface AbelianGroup {
    add(left: GenericState, right: GenericState): GenericState
    neg(state: GenericState): GenericState
    zero(): GenericState
}

export interface VectorSpace extends AbelianGroup {
    scale(state: GenericState, scalar: number): GenericState
}

export interface GenericCompoundAction {
    actions: Record<string, GenericAction>
}

export interface Game {
    render(): JSX.Element

    getInput(): GenericAction

    setState(state: GenericState): void
    getState(): GenericState

    predict(action: GenericCompoundAction): void
    update(action: GenericCompoundAction): void

    spawnPlayer(playerId: string): void

    abelianGroup(): AbelianGroup
    vectorSpace(): VectorSpace
}

export interface Experiment {
    name: string

    inputs: Record<string, GenericAction[]>
    length: number
    observe: string
    state: GenericState
}
