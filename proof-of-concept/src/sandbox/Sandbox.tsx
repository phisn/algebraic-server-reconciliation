import { JSX } from "react"
import { PocClient, PocServer } from "./Poc"

export function Sandbox() {
    return (
        <div className="flex max-h-screen justify-stretch space-x-2 p-2">
            <Viewport className="flex aspect-[1/1] flex-grow">
                <PocClient />
            </Viewport>
            <Viewport className="flex flex-grow">
                <PocServer />
            </Viewport>
        </div>
    )
}

export function Viewport(props: { children: JSX.Element; className?: string }) {
    return (
        <div className={`relative border ${props.className}`}>
            <div className="absolute inset-0">{props.children}</div>
        </div>
    )
}
