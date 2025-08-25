import "@react-three/fiber"
import deepcopy from "deepcopy"
import { JSX } from "react"
import {
    AbelianGroup,
    ActionSymbol,
    Game,
    GenericAction,
    GenericCompoundAction,
    StateSymbol,
} from "./game"

export interface Action {
    type: typeof ActionSymbol
    press?: boolean
}

export interface State {
    type: typeof StateSymbol
    players: Record<string, Player>
}

export interface Player {
    value: number
}

export class ButtonGame implements Game {
    private _input: Action
    private _state: State
    private _tick: number

    public constructor(
        private props: {
            stepValue: number
            maxSumValue: number
        },
    ) {
        this._input = { type: ActionSymbol, press: true }
        this._state = {
            type: StateSymbol,
            players: {},
        }
        this._tick = 0
    }

    public spawnPlayer(playerId: string) {
        if (this._state.players[playerId]) {
            throw new Error(`Player ${playerId} already exists`)
        }

        this._state.players[playerId] = {
            value: 0,
        }
    }

    public getInput(): GenericAction {
        return deepcopy(this._input)
    }

    public render(): JSX.Element {
        return <></>
    }

    public getState(): State {
        return deepcopy(this._state)
    }

    public setState(state: State) {
        this._state = deepcopy(state as State)
        this._tick++
    }

    public update(action: GenericCompoundAction) {
        this.handleCompoundAction(action)

        console.log(JSON.stringify(this._state.players))

        this._tick++
    }

    public predict(action: GenericCompoundAction) {
        this.update(action)
    }

    public abelianGroup(): AbelianGroup {
        return {
            add(_left, _right) {
                const left = _left as State
                const right = _right as State
                const result: State = {
                    type: StateSymbol,
                    players: deepcopy(left.players),
                }

                for (const id in right.players) {
                    const player = right.players[id]

                    if (result.players[id] === undefined) {
                        result.players[id] = deepcopy(player)
                        continue
                    }

                    result.players[id].value += player.value
                }

                return result
            },
            neg(_state) {
                const state = _state as State
                const result: State = deepcopy(state)

                for (const id in state.players) {
                    result.players[id].value *= -1
                }

                return result
            },
        }
    }

    private handleCompoundAction(action: GenericCompoundAction) {
        for (const playerId in action.actions) {
            this.handleAction(playerId, action.actions[playerId])
        }
    }

    private handleAction(playerId: string, _action: GenericAction) {
        const action = _action as Action
        const player = this._state.players[playerId]

        const sum = Object.values(this._state.players)
            .map(x => x.value)
            .reduce((l, r) => l + r, 0)
        const left = this.props.maxSumValue - sum

        if (left <= 0) {
            return
        }

        if (action.press && player) {
            player.value += Math.min(left, this.props.stepValue)
        }
    }
}
