import deepcopy from "deepcopy"
import { GenericMessage, Socket } from "./networking"

export interface MemorySocketModifiers {
    // Delay in number of packets
    delay: number
    id?: string
}

export class MemorySocket implements Socket {
    private _buffer: GenericMessage[]

    constructor(
        private _id: string,
        private _receive: GenericMessage[],
        private _send: GenericMessage[],
        private _modifiers: MemorySocketModifiers,
    ) {
        this._buffer = []
    }

    static pair(modifiers: MemorySocketModifiers): [Socket, Socket] {
        const id = modifiers.id ?? Math.random().toString(36).substring(2, 15)

        const l: GenericMessage[] = []
        const r: GenericMessage[] = []

        return [new MemorySocket(id, l, r, modifiers), new MemorySocket(id, r, l, modifiers)]
    }

    public id(): string {
        return this._id
    }

    public send(message: GenericMessage) {
        this._buffer.push(deepcopy(message))

        if (this._buffer.length > this._modifiers.delay) {
            this._send.push(this._buffer.shift()!)
        }
    }

    public receive(): GenericMessage | undefined {
        return this._receive.shift()
    }

    public receiveLatest(): GenericMessage | undefined {
        if (this._receive.length > 0) {
            const result = this._receive[this._receive.length - 1]
            this._receive.length = 0
            return result
        }

        return undefined
    }
}
