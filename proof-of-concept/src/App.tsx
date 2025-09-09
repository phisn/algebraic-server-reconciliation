import { Navigate, Route, BrowserRouter as Router, Routes } from "react-router"
import { Experiments } from "./poc/Experiments"
import { Sandbox } from "./poc/Sandbox"

function App() {
    return (
        <Router>
            <Routes>
                <Route path="/" element={<Navigate to="/sandbox" replace />} />
                <Route path="/sandbox" element={<Sandbox />} />
                <Route path="/experiments" element={<Experiments />} />
            </Routes>
        </Router>
    )
}

export default App
