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

export class PIDNetworking implements NetworkingStrategy {
    wrapServer(game: Game, sockets: Socket[]): ServerStrategy {
        return new PIDServerStrategy(game, sockets)
    }

    wrapClient(game: Game, socket: Socket): ClientStrategy {
        return new PIDClientStrategy(game, socket)
    }
}

export class PIDServerStrategy implements ServerStrategy {
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

// PID Controller for smoothing state corrections
class PIDController {
    private _accumulatedError: GenericState // Total error we still need to apply
    private _previousError: GenericState
    private _kp: number = 1.0 // Proportional gain
    private _ki: number = 0.0 // Integral gain
    private _kd: number = 0.0 // Derivative gain

    constructor(
        private _game: Game,
        private _abelian: AbelianGroup,
    ) {
        this._accumulatedError = this._abelian.zero()
        this._previousError = this._abelian.zero()
    }

    // Setters for tuning parameters
    setKp(kp: number): void {
        this._kp = Math.max(0, Math.min(1, kp))
    }

    setKi(ki: number): void {
        this._ki = Math.max(0, Math.min(1, ki))
    }

    setKd(kd: number): void {
        this._kd = Math.max(0, Math.min(1, kd))
    }

    // Reset the controller state
    reset(): void {
        this._accumulatedError = this._abelian.zero()
        this._previousError = this._abelian.zero()
    }

    // Add new error to be applied over time
    addError(error: GenericState): void {
        // Add the new error to what we haven't applied yet
        this._accumulatedError = this._abelian.add(this._accumulatedError, error)
    }

    // Calculate how much correction to apply this frame
    calculateCorrection(): GenericState {
        const vectorSpace = this._game.vectorSpace()

        // Proportional term: apply a portion of the accumulated error
        const pTerm = vectorSpace.scale(this._accumulatedError, this._kp)

        // Integral term: apply extra based on persistent error
        // (accumulated error already represents integral, so we just scale it)
        const iTerm = vectorSpace.scale(this._accumulatedError, this._ki)

        // Derivative term: based on how error is changing
        const errorDelta = this._abelian.add(
            this._accumulatedError,
            this._abelian.neg(this._previousError),
        )
        const dTerm = vectorSpace.scale(errorDelta, this._kd)

        // Combine all terms for this frame's correction
        let correction = pTerm
        correction = this._abelian.add(correction, iTerm)
        correction = this._abelian.add(correction, dTerm)

        // Subtract what we're applying from the accumulated error
        this._accumulatedError = this._abelian.add(
            this._accumulatedError,
            this._abelian.neg(correction),
        )

        // Store for derivative calculation
        this._previousError = this._accumulatedError

        return correction
    }

    // Get remaining error
    getRemainingError(): GenericState {
        return this._accumulatedError
    }
}

export class PIDClientStrategy implements ClientStrategy {
    private _states: { [id: number]: GenericState }
    private _abelian: AbelianGroup
    private _tick: number
    private _pidController: PIDController

    constructor(
        private _game: Game,
        private _socket: Socket,
    ) {
        this._states = {}
        this._abelian = _game.abelianGroup()
        this._tick = 0
        this._pidController = new PIDController(this._game, this._abelian)

        // Default tuning - start with instant correction
        this._pidController.setKp(1.0) // Apply all error immediately (like original)
        this._pidController.setKi(0.0) // No integral boost
        this._pidController.setKd(0.0) // No derivative damping
    }

    // Public setters for PID tuning
    setPIDGains(kp: number, ki: number, kd: number): void {
        this._pidController.setKp(kp)
        this._pidController.setKi(ki)
        this._pidController.setKd(kd)
    }

    setProportionalGain(kp: number): void {
        this._pidController.setKp(kp)
    }

    setIntegralGain(ki: number): void {
        this._pidController.setKi(ki)
    }

    setDerivativeGain(kd: number): void {
        this._pidController.setKd(kd)
    }

    resetPID(): void {
        this._pidController.reset()
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

        // Process all pending server messages
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

            // Add the error to the PID controller's accumulator
            this._pidController.addError(epsilon)
        }

        // Apply smoothed correction from PID controller
        const correction = this._pidController.calculateCorrection()
        state = this._abelian.add(state, correction)

        this._game.setState(state)
        this._game.predict({ actions: { [this._socket.id()]: this._game.getInput() } })
        this._states[this._tick] = this._abelian.add(
            this._game.getState(),
            this._abelian.neg(state),
        )
    }
}
