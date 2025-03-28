export interface Connection {
    receive(): Packet[]
    send(packet: Packet): void
}

export interface Packet {}
