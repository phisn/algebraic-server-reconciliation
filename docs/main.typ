#import "@preview/lemmify:0.1.8": *
#import "@preview/rubber-article:0.3.1": *

#show: article.with(
  show-header: true,
  header-titel: "Algebraic Server Reconciliation",
  eq-numbering: "(1.1)",
  eq-chapterwise: true,
)

#set math.equation(numbering: none)

#let (
  definition, theorem, rules: thm-rules
) = default-theorems("thm-group", lang: "en", thm-numbering: "left")

#maketitle(
  title: "Master Thesis Proposal \n Algebraic Server Reconciliation for Online Games",
  authors: ("Philipp Hinz \n Reviewed by Dr.-Ing. Guido Rößling", ),
  date: datetime.today().display("[day]. [month repr:long] [year]"),
)


= Introduction
Modern online games often involve multiple players interacting within a shared virtual world. This requires synchronizing game elements, referred to here as "entities," across all participants' systems.  To combat cheating, a common approach is server-authoritative architecture, where the central server dictates the game's logic and state. Clients transmit their inputs to the server and receive state updates in return.  However, network latency, due to physical limitations, introduces a delay in receiving these updates, hindering real-time responsiveness, especially in fast-paced games.

Client-side prediction helps mask this latency.  Each client simulates the game's progression based on its inputs, providing immediate feedback.  However, this can lead to discrepancies if the client's simulation deviates from the server's authoritative state.  Simply overwriting the client's state with the server's is problematic because the server's update reflects a past state.  Techniques to reconcile these past state updates with the present client state are known as "server reconciliation."

= Related Work
The prevalent server reconciliation method involves rolling back the client's simulation to the past state provided by the server and then reapplying the user's inputs that have occurred since that time.  This rollback can be achieved in two primary ways:  either the server transmits the complete game state with each update (increasing network load and potential synchronization problems) or, if the game physics are deterministic, the client stores past states and replays other players user inputs.

Both approaches are computationally demanding, as they require the game simulation to run at least twice per frame.  Optimizations that avoid full simulation replays often necessitate custom solutions, increasing development complexity and the risk of synchronization errors.  Furthermore, the deterministic approach requires each client to possess complete knowledge of the game state, which is not only resource-intensive for large worlds but also increases vulnerability to cheating.

Alternatives to server-authoritative models exist, such as client-authoritative architectures. In this approach, each player has direct control over their character or objects, sending state changes rather than inputs to the server. While easier to implement, this method is highly susceptible to cheating, as players can transmit manipulated state information. Server reconciliation also provides benefit in simulating other player inputs, allowing low-latency feedback.

#pagebreak()

= Problem Statement
This thesis introduces *Algebraic Server Reconciliation*, a novel approach to applying past state changes to the current game state.  This method aims to reduce computational overhead compared to traditional rollback methods while maintaining flexibility and avoiding the need for deterministic physics. It offers a more general framework than popular existing solutions like GGPO (Good Game Peace Out, a rollback-based networking library).

= Approach
Algebraic Server Reconciliation leverages the concept of an abelian group to model the game state.  This requires defining an associative and commutative addition operation $+$ for the game state, along with a zero element and an inverse (negative) for each state element. The server transmits state *changes* to the client; if no change has occurred, a zero element is sent. The client keeps track of state changes since the last server update.

Upon receiving a server update, the client identifies the corresponding past state change it made at the equivalent time.  It then calculates the difference between the server's change and its own past change. This difference represents the divergence between the client's prediction and the server's authoritative state.  This difference is then added to the client's current state, effectively correcting the discrepancy.  Over time, this process leads to convergence between the client and server states.

More formally:

Let $s^c_(t_0)$ and $s^s_(t_0)$ be the client and server states at time $t_0$, respectively.  Assume the client has simulated two steps forward, reaching state $s^c_(t_2) = s^c_(t_0) + x_(t_0) + x_(t_1)$, where $x_(t_0)$ and $x_(t_1)$ are the client's state changes at times $t_0$ and $t_1$.  The server then sends a state change $y_(t_0)$. The client updates its state by adding the difference $(y_(t_0) - x_(t_0))$:

$
  & s^c_(t_2) + (y_(t_0) - x_(t_0)) \
= & (s^c_(t_0) + x_(t_0) + x_(t_1)) + (y_(t_0) - x_(t_0)) \
= & (s^c_(t_0) + y_(t_0)) + x_(t_1) + (x_(t_0) - x_(t_0)) \
= & s^s_(t_1) + x_(t_1)
$
Assuming $s^c_(t_0) = s^s_(t_0)$

This demonstrates how applying the difference re-integrates the server's past state change without requiring a full rollback and re-simulation.

= Planned Steps
This thesis will investigate the feasibility and limitations of Algebraic Server Reconciliation, with a particular focus on identifying effective methods for representing game states as abelian groups. The research will explore both the benefits and potential drawbacks of this approach. Two development tracks are planned:

1.  Proof-of-Concept Simulation: A small-scale simulation will be developed, implementing both Algebraic Server Reconciliation and a conventional rollback-based method. This will enable a direct performance comparison and provide an initial demonstration of the proposed technique's viability.

2.  Full-Fledged Game Prototype: A more comprehensive game prototype will be constructed to explore the constraints and opportunities presented by a more realistic and complex game environment. This will facilitate the identification of potential limitations and allow for refinement of the approach for practical implementation.

= Additional Ideas

The core concept of Algebraic Server Reconciliation lends itself to several potential optimizations and refinements:

1. Entity Removal Handling:  When a client removes an entity (represented as a state change $-a$) before receiving server confirmation, the client must retain a copy of the original entity state ($a$).  This is necessary because the reconciliation process requires calculating $(y - x)$, where $x$ might be $-a$.  Therefore, the client needs to be able to compute $-(-a) = a$, effectively "undoing" the removal locally.  Crucially, this full entity data is only required for client-initiated removals.  Server-initiated removals, represented by $y$, only need to contain the entity's identifier, as the client never needs to compute the inverse of $y$. This asymmetry helps minimize the data the server needs to transmit.

2. Efficient Change Comparison with Merkle Trees:  To determine whether client and server state changes for a given entity and its components are identical, Merkle trees can be employed.  Instead of comparing the raw data of each change, the client and server can compare the Merkle roots (hashes) of their respective change sets.  A mismatch in the roots indicates a discrepancy, while matching roots provide high confidence that the changes are identical, significantly reducing the computational cost of comparison. This is especially beneficial for complex entities with numerous components.

= (WIP) Proposed solution

The client defines merkel trees over its state changes. Leafs are only needed for nodes where the node content is somewhat larger than the hash (not the case for position). For each sent input we also send the merkel-tree, that is the result of changes caused by this input. One can observe, that we do not lose any time by adding this information. Client side we can compute the merkel-tree in the same moment as the input is captured and server-side we process the input and can instantly compare it to the newly computed merkel-tree. Usually the client wants to send inputs as often as possible, this means, that the server is always very well aware how synced the client is component wise. 

The server now usually does not want to send updates each frame but bundeled, especially since we have reconciliation. Intuitively we might thing that we need reliable messages to not miss computations in the algebra, but we dont. The trick is, after sending an update to 

#pagebreak()
= Modelling

We define a game world using a game state $S$, an initial game state $s_0 in S$ and a progression function $f: (S, I) -> S$ as $G = (S, s_0, f)$ where $I$ is some external input. A game state at time $t$ can be progressed using some input $i_t in I$ to time $t + 1$ using the progression function: $s_(t + 1) = f(s_t, i_t)$. We can combine the input and state to a frame $r_t = (s_t, i_t)$. We say that a machine $m_t in M$ is running the game $G$ with state $s_t$ at time $t$. Clients are machines $c_t in S subset.eq M$ which contribute input $i^c_t in I^c$ to form the whole input $i^c_t in i_t$. We assume that a machine is designated as the host and all clients can only communicate with the host. The state in the host is the universal truth.

We have one host $h$ and $n$ clients $c_i$. Each client $c_i$ has a rount trip time of $t^r_i$. We define the rount trip time as the sum of the send and receive latency $t^r_i = t^s_i + t^e_i$ Every tick the server sends its state $s^h_t$ to each client, while each client sends their input $i^(c_i)_t$. The server applies the most recently received input, therefore each client will only be able to react with input $i^(c_i)_t$ to state $s^h_(t - t^r_i)$. We call this the naive model. 

This is not fair, as each player can only respond to a state $s^h_t$ with an input $t^r_i$ time later and $t^r_i$ is different for every player. We can make it fair by only processing input on the server, once we received input from all players. Every player is able to react to state $s^h_t$ with the same delay of $max_i t^r_i$. Intuitively we artificially delay delay what each player can see to the slowest player. We call this the fair naive model.

Every game is based on reaction, doing an action in response to an event. A major problem with the current method is that we can only always respond to past events, even if fair, wont feel natural to players. (Improve writing)

One common solution in slow strategy games where the times interval is not fixed, is for each player only to react to an input, when it is received. This means, that for every $s^h_t$ the player will respond with $i^c_t$ and the server will use all $i^c_t$ to generate $s^h_(t + 1)$. We now have a fair game while giving players the most recent information to react. This model is known as and called here the lockstep model. It is currently in use in strategy games like starcraft.

Unfortunately most real-time games require an fluent time interval, often around 30 updates per second or more. That would force the rount trip time to an unrealistic $max_i t^r_i < 33.3"ms"$, ignoring rendering and reacting to a frame by the user using an corresponding input. From here on out we assume that the latencies are larger in magnitude than the update interval of the state. 

We are also bound in the time a player is possible to react to other players inputs. One player has to first send their inputs and another player can only then receive them. Any changes to the state from player $c'$ will never be visible to an other player $c$ faster than $t^e_c + t^s_c'$.

While there is an limitation in seeing other players inputs, there is no limitation on seeing state changes to your own inputs sooner. We define a player progression function $f^c: I^c -> S -> S$ which only progresses the state based on one single client input $i^c_t$. Each client now receives state $s^h_t$ and directly applies their input to get predicted state $p^c_(t + 1) = f^c (i^c_t, s^h_t)$. This method is called client-side prediction and used most modern games. 

The difficulty with this method is to apply new host $s^h_(t + 1)$ state correctly. Given a client predicted $p^c_(t + 1)$, it will receive an response to input $i^c_t$ in at least $t^r_c$ time as $s^h_(t + t^r_c)$. An previous state change arriving as $s^h_(t + 1)$ would override our predicted state $p^c_(t + 1)$. The original solution to this problem is to not replace our current state but define a partial application function $f^"partial": S -> S -> S$ which compares the predicted state with the actual state and only replaces diverging parts. During normal operation, the prediction will be good enough causing only rare desynchronizations (desync). Some desync is bound to happen, for example, we never can accurately predict game state, that is only dependent on other player inputs or random. In these cases we use interpolation, to smooth movement out over multiple frames. 

One very popular game that is using slightly modified variation of this method is minecraft. In minecraft the game does not send its direct inputs, but its predicted state. Most important parts of the state to be predicted are breaking blocks and all character movement. The partial application does not happen at client side, but on server side. Therefore the server validates if the incoming input looks good enough and doesnt resimulate it if not necessary. Unfortunately this limits anti-cheat capabilities to how sophisticated the validation in the partial application function is.
