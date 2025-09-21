#import "@preview/athena-tu-darmstadt-thesis:0.1.1": *
#import "@preview/lilaq:0.5.0" as lq


// setup the template
#show: tudapub.with(
  title: [
    Algebraic Server Reconciliation for Online Games
  ],
  author: "Philipp Hinz",

  title_german: "Algebraische serverseitige Zustandskorrektur für Online-Spiele",

  // to deactivate the sub logo text set logo_sub_content_text: none,
  logo_sub_content_text: none,

  logo_tuda: image("logos/tuda_logo.svg"),
  accentcolor: "9c",

  abstract: [
    This is a template to write your thesis with the corporate design of #link("https://www.tu-darmstadt.de/")[TU Darmstadt].
  ],

  bib: bibliography("refs.bib", full: true),

  // Set the margins of the content pages.
  // The title page is not affected by this.
  // Some example margins are defined in 'common/props.typ':
  //  - tud_page_margin_small  // same as title page margin
  //  - tud_page_margin_big
  // E.g.   margin: tud_page_margin_small,
  // E.g.   margin: (
  //   top: 30mm,
  //   left: 31.5mm,
  //   right: 31.5mm,
  //   bottom: 56mm
  // ),
  margin: tud_page_margin_big,


  // outline_table_of_contents_style: "adapted",
  // reduce_heading_space_when_first_on_page: false
  // figure_numbering_per_chapter: false

  // Which pages to insert
  // Pages can be disabled individually.
  show_pages: (
    title_page: true,
    outline_table_of_contents: true,
    thesis_statement_pursuant: true,
  ),

  // Set this to true to add the page for the translation of the statement of pursuant
  thesis_statement_pursuant_include_english_translation: false,

  // pages after outline that will not be included in the outline
  additional_pages_after_outline_table_of_contents: [
  ],

  reviewer_names: (
    "Dr.-Ing. Guido Rößling",
  ),
)

#set math.equation(numbering: none)

= Introduction

/*
- short history of multiplayer games
- relevance of gaming in today world
- relevance of multiplayer games compared to gaming
- what is AR and VR =>
- how multiplayer capabilities are fundamental to the metaverse
*/

= Related Work

The challenge of maintaining a consistent and responsive shared reality across a distributed system is a foundational problem in computer science. In the domain of real-time networked multiplayer games, this challenge is amplified by stringent latency requirements and the demand for interactive fairness. 

This chapter reviews practical state-synchronization techniques for real-time games alongside relevant distributed-systems results. Academic work covers theory (consistency, replication, CRDTs), while many production details are documented in engine manuals, GDC talks @gdc-overview, and developer blogs. We therefore integrate peer-reviewed sources with primary industry material, citing each claim to a concrete talk or manual where possible.

The chapter begins by examining the foundational architectures for latency mitigation in the prevalent client-server model. It then contrasts this with the alternative paradigm of deterministic synchronization. Subsequently, it explores theoretical frameworks from distributed systems research, such as Conflict-Free Replicated Data Types (CRDTs) @crdt-shapiro, that offer alternative models for state convergence. Finally, it grounds these discussions in case studies of influential, real-world implementations.

== Foundational Architectures for Latency Mitigation

To mitigate perceived latency, modern games hide delay rather than remove it. We focus on three core strategies: client-side prediction (local responsiveness), reconciliation (correcting divergence), and server-side lag compensation (fair hit evaluation).

=== The Authoritative Server and the Challenge of Latency

The predominant architecture for modern multiplayer games is the client-server model, wherein a single server is designated as the authoritative source of truth for the game state. Clients send user inputs to the server and, in return, receive periodic updates, or "snapshots," of the world state. This model centralizes simulation and prevents many forms of cheating, as the client is never fully trusted with game-critical logic. However, it introduces the fundamental problem of network latency: the round-trip time (RTT), illustrated in @rttdiagram, which is the total time it takes for a client's input to reach the server and for the server's response to return. For fast-paced action games, where delays of even a few milliseconds can be perceptible, this latency renders a naive implementation unplayable, as there would be a significant delay between a player's action and its visual feedback. The following sections detail the primary techniques developed to conceal or compensate for this inherent latency.

#figure(
  image("diagrams/related-work-latency-diagram.svg", width: 80%),
  caption: [
    Illustration of network latency between a host and a client. The round-trip time (RTT) is the sum of the send and receive latencies.
  ],
) <rttdiagram>

=== Client-Side Prediction and Server Reconciliation

To combat the feeling of unresponsiveness, the most widely adopted technique is Client-Side Prediction. The client does not wait for the server's confirmation to execute a local player's command. Instead, it speculatively executes the input and simulates the outcome locally, providing immediate visual feedback. This creates the illusion of a zero-latency environment for the local player's movement and actions. The earliest known implementation in a first-person shooter was in Duke Nukem 3D (1996), as shown in @dukenukem, with the technique being popularized by id Software's QuakeWorld. @quakeworld-prediction

#figure(
  image("images/duke-nukem-3d.png", width: 80%),
  caption: [
    A screenshot from _Duke Nukem 3D_ (1996). The game is one of the earliest known first-person shooters to implement client-side prediction, providing players with immediate visual feedback for their movement to hide network latency.
  ],
) <dukenukem>

This speculative execution, however, introduces the problem of divergence. The client's predicted state may differ from the server's authoritative state, which has perfect information about the world, including the actions of other players and collision physics. This discrepancy is known as a prediction error. To resolve this, a process called Server Reconciliation is employed. When the client receives an authoritative state update from the server, it compares this state with its own predicted state. If a mismatch is detected, the client must correct its state to match the server's. A naive correction would result in a jarring visual "snap" as the player character is teleported to the correct position. To mitigate this, a crucial step is performed: the client replays all the inputs that were sent to the server but have not yet been acknowledged in the received server snapshot. By reapplying these inputs from the corrected server state, the client can re-simulate its way back to the present, often resulting in a correct final position and eliminating the visual artifact entirely in most cases. This process requires clients to send inputs with a sequence number and for the server to echo back the number of the last processed input.

=== Rollback Netcode

Rollback netcode can be understood as a more aggressive and generalized application of the principles of prediction and reconciliation, primarily developed to meet the stringent timing requirements of fighting games. While traditional client-side prediction is typically applied only to the local player, rollback netcode predicts the inputs of the remote player as well, often by assuming they will repeat their last known input. The game simulation for all players advances based on these local and predicted inputs. When an actual input from the remote player arrives, the game state is 'rolled back' to the frame before the prediction began, the correct input is inserted, and the simulation is 'fast-forwarded' back to the present time. This multi-step correction process is visualized in @rollbackcomparison. The entire rollback and re-simulation ideally occurs within a single frame, making the correction imperceptible to the user.

#figure(
  image("diagrams/related-rollback-diagram.svg", width: 90%),
  caption: [
    Illustration of the rollback netcode process.
    (a) The client's initial predicted state progression.
    (b) The server's authoritative state diverges (State G instead of B).
    (c) Upon receiving the authoritative State G, the client rolls back to State A, applies State G, and then re-simulates its subsequent inputs to reach States H and I.
  ],
) <rollbackcomparison>

The primary benefit is a highly responsive experience that feels akin to offline play, even under significant latency. However, the implementation is complex, requiring the ability to save and load the complete game state very rapidly for every frame and to re-simulate multiple frames' worth of logic in a fraction of a second. While rollbacks aim to be imperceptible, extreme cases or visual debuggers can reveal the momentary "snapping" as shown in @mortalcombatx. Michael Stallone of NetherRealm Studios noted that retrofitting rollback into Mortal Kombat X took approximately two man-years of effort, with significant challenges in optimizing serialization and ensuring non-deterministic elements like visual and audio effects were handled consistently during rollbacks. @mortal-kombat-rollback

#figure(
  image("images/mortal-kombat-x-rollback.png", width: 90%),
  caption: [
    A screenshot from the fighting game _Mortal Kombat X_ (2015). The genre's demand for frame-perfect inputs makes it extremely sensitive to latency, establishing fighting games as a primary driver for the adoption of rollback netcode. The challenges of retrofitting this technology into _Mortal Kombat X_ are a well-documented example of its implementation complexity.
  ],
) <mortalcombatx>

=== Server-Side Lag Compensation

While client-side prediction addresses the local player's sense of responsiveness, it does not solve the problem of interactional fairness. A player might fire at a target that is clearly visible on their screen, but due to latency, the target has already moved to a new position on the server's timeline by the time the shot command is processed. This fundamental time discrepancy is illustrated in @relatedlagcompensation. 

To solve this, servers employ Lag Compensation. The server maintains a short history of past player positions. When it receives a user command, such as a shot, it uses the packet's latency to estimate the time at which the command was actually executed on the client. It then temporarily "rewinds" the positions of other players in the world to where they were at that moment in the past. The hit detection is then performed against these historical positions. After the command is processed, the players are returned to their current positions.

#figure(
  image("diagrams/related-lag-compensation.svg", width: 80%),
  caption: [
    Visualizing the time discrepancy that necessitates server-side lag compensation. (a) The client performs an action, such as shooting, at Time 1 based on their local view of the game. (b) Due to network latency, the server receives this action at a later point, Time 2. Lag compensation allows the server to "rewind" the game state to evaluate the client's action as it occurred in the past, ensuring the outcome matches what the player saw.
  ],
) <relatedlagcompensation>

This technique, famously implemented in the Source Engine, is often described as "favor the shooter". @source-networking It ensures that if a player sees a valid target, their shot will register, creating a more reliable and fair experience for the attacker. However, it can lead to perceptual paradoxes for the victim, who may be hit after they have already taken cover on their own screen. This is an accepted trade-off in most modern shooters, prioritizing interactional consistency over strict temporal accuracy. 

The collection of these techniques reveals a core design duality in networked games. One branch of techniques, encompassing prediction, reconciliation, and rollback, is focused on optimizing the local player's subjective feeling of control and responsiveness. The other branch, exemplified by lag compensation, is focused on optimizing the acting player's objective sense of fairness during interactions. These two goals can be in direct conflict, and the specific balance chosen by a game's networking model defines much of its "feel".

== Deterministic Synchronization Models

In sharp contrast to sending frequent state updates, deterministic models synchronize only player inputs. This section explores architectures where every client runs an identical simulation. Provided each client processes the same inputs in the same order, their worlds remain perfectly synchronized. We will examine the classic lockstep model, its profound bandwidth advantages, and its demanding trade-offs, such as the strict requirement for perfect determinism.

=== The Deterministic Lockstep Architecture

In contrast to the state-synchronization model employed by authoritative servers, the deterministic lockstep model operates on a fundamentally different principle. Instead of transmitting game state, clients only transmit their inputs to one another, either through a peer-to-peer topology or relayed via a simple server. Each client runs an identical, fully deterministic simulation of the game world. Provided that every client starts from the same initial state and processes the exact same sequence of inputs in the exact same order (at the same "tick"), their game states are guaranteed to remain perfectly synchronized.

To ensure inputs are processed in the same order, the simulation proceeds in discrete turns. The game will not advance to the next turn until it has received the inputs from all players for that turn. As depicted in @relatedlockstep, this means the entire simulation is forced to pause and wait for the slowest or most delayed participant. To hide the latency of waiting for these inputs, games implementing this model often introduce a fixed input delay, buffering inputs for a short period before executing them. This model's primary advantage is its extraordinary bandwidth efficiency concerning the number of game entities. Since only small input packets are transmitted, the network load scales with the number of players, not the number of units on screen, making it ideal for genres with potentially thousands of entities, such as Real-Time Strategy (RTS) games. @deterministic-lockstep-rts

#figure(
  image("diagrams/related-lockstep.svg", width: 80%),
  caption: [
    Illustration of the lockstep model and its sensitivity to network conditions. (a) Client 1 processes its actions seamlessly. (b) Client 2 experiences a brief network interruption between Time 1 and Time 2, delaying its ability to provide input. (c) The server (or host) cannot advance its state (from State A to State B) until inputs from both Client 1 and Client 2 for the current frame are received. This forces the entire simulation to pause and wait for the slowest or most delayed participant.
  ],
) <relatedlockstep>

=== Analysis of Trade-Offs and Application

The benefits of the lockstep model come with severe trade-offs. The entire system is only as fast as the slowest participant; if one player's input packet is delayed, the simulation for all players must freeze until it arrives. This makes the model highly susceptible to players with high latency or unstable connections and limits its practical application to games with a relatively low player count.

Furthermore, the requirement of perfect determinism is a formidable software engineering challenge. The simulation must produce bit-identical results across different hardware, operating systems, and compiler settings. This precludes the use of common non-deterministic elements, most notably standard floating-point arithmetic, which can yield slightly different results on different processor architectures. Developers must rely on fixed-point math and carefully control sources of randomness and data structure ordering to prevent desynchronization, or "desyncs," which are catastrophic failures in this model. A modern evolution, deterministic rollback, combines this model with the rollback techniques described earlier, predicting inputs to avoid freezing and resimulating when the actual inputs arrive. @ggpo-rollback

The choice between an authoritative server model and a deterministic lockstep model represents a fundamental architectural decision to shift the primary burden of complexity. The authoritative server model places complexity in the network layer: managing high bandwidth, compressing state, interpolating between snapshots, and reconciling prediction errors. The deterministic lockstep model places complexity in the application layer: enforcing perfect determinism, managing fixed-point math, and dealing with the game design implications of input delay and simulation freezes. The state-sync model effectively says, "Let the application be complex and non-deterministic; we will solve the resulting inconsistencies at the network level with authority and correction." The input-sync model says, "Let's make the network problem trivial by enforcing extreme constraints on the application itself." The choice depends entirely on the game's genre and design priorities.

== Theoretical Frameworks for State Convergence

Beyond bespoke gaming solutions, the field of distributed systems provides formal frameworks for state synchronization. This section introduces these theoretical concepts, focusing on Strong Eventual Consistency (SEC) and a powerful data structure that enables it: the Conflict-Free Replicated Data Type (CRDT). We will explore how CRDTs mathematically guarantee that disparate clients will eventually reach the same state, offering a robust model for decentralized or peer-to-peer architectures.

=== Strong Eventual Consistency in Peer-to-Peer Gaming

Beyond the specific implementations in gaming, the field of distributed systems provides a theoretical foundation for reasoning about state convergence. A key concept is Strong Eventual Consistency (SEC), which guarantees that if a set of replicas has received the same set of updates, they will be in the same state. Unlike strong consistency models which may require coordination or locking before an operation can be performed, eventual consistency allows replicas to be updated independently and asynchronously, with convergence guaranteed over time. This model is highly relevant for decentralized or peer-to-peer (P2P) game architectures, which lack a central authoritative server to resolve conflicts. The challenge lies in designing data structures and operations that can guarantee this convergence property automatically.

=== Conflict-Free Replicated Data Types (CRDTs)

Conflict-Free Replicated Data Types (CRDTs) are a class of data structures designed to provide SEC. @crdt-shapiro They allow for concurrent updates on different replicas without coordination, and provide a mathematically proven guarantee that the replicas will converge. This is achieved by designing operations that possess specific algebraic properties.

There are two primary forms of CRDTs:
State-based CRDTs (Convergent Replicated Data Types, or CvRDTs): Each replica can send its entire state to another replica. The receiving replica merges the incoming state with its own using a merge function. To guarantee convergence, this merge function must be associative, commutative, and idempotent. A set of states and a merge function with these properties form a mathematical structure known as a join-semilattice.

Operation-based CRDTs (Commutative Replicated Data Types, or CmRDTs): Instead of shipping the full state, replicas broadcast the update operations themselves. To ensure convergence, these operations must be commutative, meaning they can be applied in any order and still yield the same result. This approach is more bandwidth-efficient but often requires more stringent guarantees from the network layer, such as ensuring that operations are not dropped or duplicated.


While CRDTs are successfully used in collaborative editing software and distributed databases, their application to complex game states is an active area of research. A primary challenge is that many game-world interactions are inherently non-commutative; for example, a Move operation followed by a Shoot operation has a different outcome than the reverse. This creates a significant "impedance mismatch" between the clean, algebraic properties required by simple CRDTs and the messy, stateful, and order-dependent nature of game logic. Applying CRDTs to gaming therefore requires either carefully designing game mechanics to be commutative or developing more complex data structures and algorithms that can handle these ordering constraints, which can erode the initial simplicity of the model. The complexity is not eliminated; it is moved from the network protocol into the data modeling of the game itself.

== Case Studies of Networking in Practice

To bridge the gap between theory and implementation, this section examines the networking models of influential, real-world games. By analyzing seminal titles, we can see how the previously discussed concepts are applied to solve practical challenges. We will dissect Valve's Source Engine as a canonical example of client-side prediction and lag compensation, and Blizzard's Overwatch as a modern hybrid that leverages determinism within an authoritative server to achieve high-fidelity competitive play.

=== Valve's Source Engine: A Canonical Implementation

The networking model of Valve's Source Engine, which powers titles like Half-Life 2 and Counter-Strike: Source, serves as a well-documented and highly influential example of the authoritative client-server architecture. @source-networking Its documentation, made widely available to the modding and development community, has codified many of the foundational techniques discussed in this chapter. The engine simulates the game in discrete "ticks" on an authoritative server. Clients run prediction for the local player's movement to mask latency, and the server performs lag compensation to ensure fairness in hit registration by rewinding player history. The client also performs interpolation between received server snapshots to produce smooth motion for remote entities, deliberately rendering the world slightly in the past to ensure it always has valid states to interpolate between. @source-networking The extensive set of user-configurable variables (cl_interp, cl_cmdrate, rate) allows for fine-tuning of the trade-offs between responsiveness and smoothness, exposing the underlying mechanics to the end-user. The Source Engine's networking model represents a robust, battle-tested blueprint for state synchronization in fast-paced first-person shooters. 

#figure(
  image("images/source-lag-compensation.png", width: 90%),
  caption: [
    A visual example of server-side lag compensation in the Source Engine. The red hitboxes represent a player's current (client-view) position, while the blue hitboxes show the rewound historical position that the server used for hit detection. This "favor the shooter" approach ensures that shots register based on what the attacker saw. 
  ],
)

=== Overwatch: Determinism in a High-Paced Shooter

Blizzard Entertainment's Overwatch presents a more modern and novel architecture, as detailed in a GDC 2017 presentation by Timothy Ford. @overwatch-netcode While it operates on an authoritative client-server model, it uniquely "leverages determinism to achieve responsiveness and precision". @overwatch-netcode This represents a hybrid approach that synthesizes principles from both the state-sync and input-sync paradigms. The server runs the simulation at a fixed tick rate (typically 60Hz for competitive play) and is the final authority on game state. However, the simulation logic itself is deterministic. The client is able to run the exact same simulation code as the server.

This design has significant benefits for client-side prediction. Because the client's simulation is identical to the server's, prediction errors are not caused by subtle divergences in physics or logic (e.g., floating-point inaccuracies). Instead, prediction errors arise only from a lack of information namely, the inputs of other players that have not yet been received. When the server sends a correction, the client can reconcile its state with high confidence, knowing that the underlying simulation logic is sound. This hybrid model aims to achieve the predictive accuracy of a deterministic system within the responsive, cheat-resistant framework of an authoritative server. This signifies a convergence of the two historically separate paradigms, demonstrating that determinism is not an all-or-nothing architectural choice but can be employed as a powerful tool within a traditional client-server framework to dramatically improve the quality of prediction and reconciliation. The game's netcode also features an "adaptive interpolation delay" system, which attempts to dynamically adjust the rendering buffer based on network conditions to keep gameplay smooth. @overwatch-netcode

= Network model <theory>

To rigorously discuss and analyze networking techniques for online games, particularly those involving state synchronization and reconciliation, it is essential to first establish a clear and formal understanding of the underlying concepts. This chapter lays the theoretical groundwork by defining fundamental components of a game from a networking perspective, such as game state, state progression, and the roles of clients and the server. Building upon these definitions, we will then explore several established network models, from naive approaches to more sophisticated techniques like client-side prediction and server reconciliation. This exploration will highlight the challenges inherent in achieving responsive and consistent gameplay in a networked environment. Finally, this chapter will introduce the core theoretical concepts behind delta states and culminate in the formal definition of algebraic server reconciliation, the novel method investigated in this thesis.

== Overview
We define a game world using a game state $S$, an initial game state $s_0 in S$ and a progression function $f: (S, I) -> S$ as $G = (S, s_0, f)$ where $I$ is some external input. A game state at time $t$ can be progressed using some input $i_t in I$ to time $t + 1$ using the progression function: $s_(t + 1) = f(s_t, i_t)$. We can combine the input and state to a frame $r_t = (s_t, i_t)$.

We say that a machine $m in M$ is running the game $G$ with state $s_t$ at some time $t$. Clients are machines $c in C subset.eq M$ which contribute input $i^c_t in I^c$ to form the whole input $i^c_t in i_t$. We assume that one machine is designated as the host and all clients can only communicate with the host. The state on the host is considered the truth if states between machines differ.

==== Example of a formal game definition

To illustrate the concepts introduced thus far, we consider a simplified game inspired by the mechanics of "agar.io". In this game, the world is viewed from a top-down perspective where each player is represented as a circle. While the original game features collision and consumption mechanics, our simplified version focuses solely on movement to clearly demonstrate the networking concepts. Each player is assigned a unique identifier to distinguish them within the game state.

We formally define this "top-down movement game" as follows:

$
&"Vector " & V & subset.eq RR times RR & \
&"Player " & P & = V \
&"State " & S & subset.eq "id" times P \
&"Input for a single player " & I_P & subset.eq BB^4 \
&"Input " & I & subset.eq "id" times I_P \
$

The input representation captures the four directional keys that can be pressed during a single frame. Assuming standard addition operations on boolean values and vectors, we define the progression function:

$
f^"transform" ((i_"up", i_"down", i_"left", i_"right")) & = ((i_"down" - i_"up", i_"right" - i_"left")) \
f^"find" ("id", S) & = x_P, ("id", x_P) in S \
f(s, i) & = {("id", s_p + f^"transform" (f^"find" ("id", i))) | ("id", s_p) in s}
$

Each player consists of a two-dimensional position vector. The game state comprises the set of all player positions indexed by their identifiers. The progression function operates in two stages: first, it extracts the appropriate input for each player from the combined input set, then it transforms these boolean directional inputs into velocity vectors that update the player positions.

Consider the following concrete example with two players:

$
s_0 & = { (p_0, (0, 0)), (p_1, (5, 5)) } \
i_0 & = {(p_0, (1, 0, 0, 1)), (p_1, (0, 0, 1, 0))} \
f (s_0, i_0) = s_1 & = { (p_0, (0 + 1, 0 + 1)), (p_1, (5 - 1, 5)) } \
& = { (p_0, (1, 1)), (p_1, (4, 5)) }
$

In this example, player $p_0$ moves diagonally (up and right) while player $p_1$ moves left, demonstrating how discrete boolean inputs translate into continuous position updates.

==== Example of client-host architecture

Consider a multiplayer session with two clients $c_0$ and $c_1$ connected to a host $h$. Using our previously defined movement game, we examine how inputs from multiple clients are processed and synchronized through the central host.

Client $c_0$ generates input $i^(c_0)_t = (1, 0, 0, 1)$, indicating upward and rightward movement. Simultaneously, client $c_1$ produces input $i^(c_1)_t = (0, 0, 1, 0)$, representing leftward movement. For multiplayer functionality to work correctly, each client must be aware of all other players' inputs, necessitating a mechanism for input distribution.

Our architecture employs a central host model for this distribution. Following the principle that client-side computation cannot be trusted for security reasons, only the host possesses the authority to evaluate the progression function and determine the canonical game state. This does not preclude clients from performing local predictions for responsiveness, as we shall explore in later sections.

The communication flow proceeds as follows: both clients continuously transmit their inputs to the host $h$. Upon receiving these inputs, the host updates its authoritative state using the progression function:

$
f(s_0, {(p_0, i^(c_0)_t), (p_1, i^(c_1)_t)}) = s_1
$

The host then distributes the updated state to all clients. While various optimization strategies exist for this distribution (such as sending only state deltas or relevant subsets), the simplest implementation transmits the complete state $s_1$ to ensure all clients maintain a consistent view of the game world.

=== Naive model

We have one host $h$ and $n$ clients $c_i$. Each client $c$ has a round trip time of $t^r_c$. We define the round trip time as the sum of the send $t^s_c$ and receive $t^e_c$ latency $t^r_c = t^s_c + t^e_c$. At each tick, the host sends its state $s_t$ to each client and each client sends input $i^c_t$.

Both the client and the host run with a fixed time interval $t^i$ which is usually smaller than $t^r_c$. Therefore the host cannot wait with processing all input $i^c_t$ and will use the most recent input instead. This means that each client will only be able to react with input $i^c_t$ to state $s_(t - t^r_c)$. We call this the naive model.

==== Example of naive model networking

To demonstrate the temporal challenges inherent in the naive model, we trace through a concrete execution scenario using our movement game. Consider two clients with asymmetric network conditions:

- Client $c_0$: round trip time $t^r_(c_0) = 50 "ms"$ (25 ms send, 25 ms receive)
- Client $c_1$: round trip time $t^r_(c_1) = 200 "ms"$ (100 ms send, 100 ms receive)  
- Fixed tick interval: $t^i = 50 "ms"$

Starting with initial state $s_0 = {(p_0, (0, 0)), (p_1, (5, 5))}$, the host broadcasts this state at tick 0. The following table traces the first 10 ticks of execution:

#table(
  columns: 7,
  align: (center, center, center, center, center, center, center),
  [*Tick*], [*Host State*], [*$c_0$ Sees*], [*$c_1$ Sees*], [*$c_0$ Input*], [*$c_1$ Input*], [*Inputs at Host*],
  [$0$], [$(0,0), (5,5)$], [—], [—], [—], [—], [None],
  [$1$], [$(0,0), (5,5)$], [—], [—], [—], [—], [None],
  [$2$], [$(0,0), (5,5)$], [$(0,0), (5,5)$], [—],[right], [—], [None],
  [$3$], [$(0,1), (5,5)$], [$(0,0), (5,5)$], [$(0,0), (5,5)$], [right], [—], [$c_0$: right],
  [$4$], [$(0,2), (5,5)$], [$(0,1), (5,5)$], [$(0,0), (5,5)$], [right], [up], [$c_0$: right],
  [$5$], [$(0,3), (5,5)$], [$(0,2), (5,5)$], [$(0,1), (5,5)$], [right], [up], [$c_0$: right],
  [$6$], [$(0,4), (6,5)$], [$(0,3), (5,5)$], [$(0,2), (5,5)$], [right], [up], [Both inputs],
  [$7$], [$(0,5), (7,5)$], [$(0,4), (6,5)$], [$(0,3), (5,5)$], [right], [up], [Both inputs],
  [$8$], [$(0,6), (8,5)$], [$(0,5), (7,5)$], [$(0,4), (6,5)$], [right], [up], [Both inputs],
  [$9$], [$(0,7), (9,5)$], [$(0,6), (8,5)$], [$(0,5), (7,5)$], [right], [up], [Both inputs],
)

The execution reveals two critical issues with the naive model. First, examining the input delay: client $c_0$ receives the initial state at tick 2 and immediately sends a "right" input. This input reaches the host at tick 3, where it gets processed and updates player $p_0$ to position $(0,1)$. However, $c_0$ doesn't observe this change until tick 4, a full round trip time of 50 ms after sending the input. 

Similarly, client $c_1$ receives the initial state at tick 3, sends an "up" input at tick 4, but the host doesn't process it until tick 6 due to the 100 ms transmission delay. Client $c_1$ finally sees their first movement at tick 8, experiencing a 200 ms delay between action and feedback.

The second, more subtle issue is the competitive unfairness in control responsiveness. Client $c_0$ observes their input taking effect at tick 4, allowing them to make informed decisions about their next move by tick 5. If they realize they're moving in the wrong direction, they can correct course with only a 50 ms feedback loop. In contrast, client $c_1$ doesn't see their first movement until tick 8, a 200 ms delay that severely hampers their ability to make tactical adjustments. 

Consider a scenario where both players accidentally move toward a hazard: client $c_0$ can recognize and correct their mistake within 2 ticks, while client $c_1$ continues blind movement for 4 ticks before seeing any feedback. This creates a fundamental inequality where the lower-latency player has superior control precision, faster error correction, and more responsive gameplay, advantages that compound over time and cannot be overcome through player skill alone.

=== Fair naive model

Each client $c$ can only respond to a state $s_t$ with an input arriving at the host $t^r_c$ time later. Since $t^r_c$ is different for every player, this is not fair. 

We define a fair model as: given a fixed delay $delta$, every client can respond to the same state $s_t$ with input $i^c_(t + delta)$. We can make the previous model fair by only processing input on the host, once we received input from all players. Every player is able to react to state $s_t$ with the same delay of $delta = max_i t^r_i$. Intuitively, we artificially delay what each player can see to the slowest player. We call this the fair naive model.

Many games are based on reaction, doing an action in response to an event. A major problem with the (fair) naive model is that player inputs in reaction to a present state will only be applied to a future state on the host.

==== Example of fair naive model networking

The fair naive model addresses the competitive inequality of the naive model by synchronizing all players to the slowest connection. Using the same network configuration and initial state:

- Client $c_0$: round trip time $t^r_(c_0) = 50 "ms"$ (25 ms send, 25 ms receive)
- Client $c_1$: round trip time $t^r_(c_1) = 200 "ms"$ (100 ms send, 100 ms receive)
- Fixed tick interval: $t^i = 50 "ms"$

Starting with initial state $s_0 = {(p_0, (0, 0)), (p_1, (5, 5))}$, the host broadcasts at tick 0. The key difference is that the host now buffers inputs until all players' commands for a given game state have arrived:

#table(
  columns: 7,
  align: (center, center, center, center, center, center, center),
  [*Tick*], [*Host State*], [*$c_0$ Sees*], [*$c_1$ Sees*], [*$c_0$ Input*], [*$c_1$ Input*], [*Host Buffers*],
  [$0$], [$(0,0), (5,5)$], [—], [—], [—], [—], [Empty],
  [$1$], [$(0,0), (5,5)$], [—], [—], [—], [—], [Empty],
  [$2$], [$(0,0), (5,5)$], [$(0,0), (5,5)$], [—], [right], [—], [Empty],
  [$3$], [$(0,0), (5,5)$], [$(0,0), (5,5)$], [$(0,0), (5,5)$], [right], [—], [$c_0$: right],
  [$4$], [$(0,0), (5,5)$], [$(0,0), (5,5)$], [$(0,0), (5,5)$], [right], [up], [$c_0$: right],
  [$5$], [$(0,0), (5,5)$], [$(0,0), (5,5)$], [$(0,0), (5,5)$], [right], [up], [$c_0$: right],
  [$6$], [$(0,1), (6,5)$], [$(0,0), (5,5)$], [$(0,0), (5,5)$], [right], [up], [Both active],
  [$7$], [$(0,2), (7,5)$], [$(0,0), (5,5)$], [$(0,0), (5,5)$], [right], [up], [Both active],
  [$8$], [$(0,3), (8,5)$], [$(0,1), (6,5)$], [$(0,0), (5,5)$], [right], [up], [Both active],
  [$9$], [$(0,4), (9,5)$], [$(0,2), (7,5)$], [$(0,1), (6,5)$], [right], [up], [Both active],
)

The fair naive model fundamentally changes how the host processes inputs. When client $c_0$'s input arrives at tick 3, the host does not immediately apply it. Instead, it stores this input in a buffer and continues waiting. The host maintains the game state at $(0,0), (5,5)$ for ticks 3, 4, and 5, despite having valid input from $c_0$. Only at tick 6, when client $c_1$'s input finally arrives after its 100 ms journey, does the host process both inputs simultaneously.

This buffering strategy creates perfect fairness in reaction timing. Both clients receive the initial state and have the opportunity to respond before any inputs are processed. When the host finally applies inputs at tick 6, it creates state $(0,1), (6,5)$ where both players have moved. Client $c_0$ sees this result at tick 8, while client $c_1$ sees it at tick 9. Critically, both players observe their inputs taking effect relative to the same initial state, eliminating the advantage that lower latency previously provided.

However, this fairness comes at a significant cost to responsiveness. Client $c_0$, who previously enjoyed a 50 ms feedback loop, now experiences a 200 ms delay between input and observation, matching the slowest player. The buffering essentially forces all players to experience the worst-case latency in the session. In our example, client $c_0$ sends their input at tick 2 but doesn't see the result until tick 8, a delay of 300 ms total. 

This artificial throttling makes the game feel sluggish for players with good connections, potentially driving them away from servers with high-latency participants. The fair naive model thus trades individual responsiveness for competitive balance, a compromise that works poorly for fast-paced action games where immediate feedback is crucial to the gameplay experience.

=== Lockstep

In the fair naive model, the host is applying old inputs because the interval time is fixed and usually faster than $t^r_c$. We can loosen this requirement and assume a dynamic interval time. Players only send input $i^c_t$, after receiving $s_t$. The host only progresses to state $s_(t + 1)$ when all $i^c_t$ have arrived. We now have a fair game while giving players the most recent information to react to.

This model is known as the lockstep model and popular in strategy games, where latency or a longer interval are not a big problem.

==== Example of lockstep model

The lockstep model ensures perfect synchronization by pausing the entire simulation after each state update until all clients have received and responded. Using the same network configuration:

- Client $c_0$: round trip time $t^r_(c_0) = 50 "ms"$ (25 ms send, 25 ms receive)
- Client $c_1$: round trip time $t^r_(c_1) = 200 "ms"$ (100 ms send, 100 ms receive)
- Fixed tick interval: $t^i = 50 "ms"$

Starting with initial state $s_0 = {(p_0, (0, 0)), (p_1, (5, 5))}$, the host initiates the first lockstep cycle at tick 0:

#table(
  columns: 7,
  align: (center, center, center, center, center, center, center),
  [*Tick*], [*Host State*], [*$c_0$ Sees*], [*$c_1$ Sees*], [*$c_0$ Input*], [*$c_1$ Input*], [*Host Action*],
  [$0$], [$(0,0), (5,5)$], [—], [—], [—], [—], [Broadcast $s_0$],
  [$1$], [Waiting], [$(0,0), (5,5)$], [—], [right], [—], [Wait for all],
  [$2$], [Waiting], [Sent right], [$(0,0), (5,5)$], [—], [up], [Wait for all],
  [$3$], [Waiting], [Waiting], [Sent up], [—], [—], [Wait for all],
  [$4$], [$(0,1), (6,5)$], [Waiting], [Waiting], [—], [—], [Process inputs],
  [$5$], [$(0,1), (6,5)$], [$(0,1), (6,5)$], [Waiting], [right], [—], [Broadcast $s_1$],
  [$6$], [Waiting], [Sent right], [$(0,1), (6,5)$], [—], [up], [Wait for all],
  [$7$], [Waiting], [Waiting], [Sent up], [—], [—], [Wait for all],
  [$8$], [$(0,2), (7,5)$], [Waiting], [Waiting], [—], [—], [Process inputs],
  [$9$], [$(0,2), (7,5)$], [$(0,2), (7,5)$], [Waiting], [right], [—], [Broadcast $s_2$],
)

The lockstep model operates in discrete, synchronized cycles that guarantee perfect consistency across all clients. Each cycle follows a rigid pattern: the host broadcasts a state, waits for all clients to receive it, waits for all clients to send their inputs based on that state, and only then processes those inputs to generate the next state. This creates natural synchronization points where the entire game pauses until the slowest participant catches up.

In our execution, the first cycle begins at tick 0 when the host broadcasts $s_0$. Client $c_0$ receives this state at tick 1 and immediately sends a "right" input that reaches the host at tick 2. However, the host cannot proceed because client $c_1$ only receives the state at tick 2 and sends an "up" input that doesn't arrive until tick 4. Only then can the host process both inputs together, updating the state to $(0,1), (6,5)$ and beginning the second cycle at tick 5.

The lockstep model achieves perfect fairness and eliminates all prediction or synchronization issues. Every client sees exactly the same game state before making decisions, and all inputs are processed simultaneously with no player gaining an advantage from lower latency. This makes it ideal for turn-based strategy games or scenarios where absolute consistency matters more than responsiveness.

However, the cost is severe: the game effectively runs at the speed of the slowest connection. With client $c_1$'s 200 ms round trip time, the game can only update every 4 ticks (200 ms), reducing the effective update rate from 20 Hz to 5 Hz. This dramatic slowdown makes the lockstep model unsuitable for any real-time game. Furthermore, if any client experiences a temporary network spike or packet loss, the entire game freezes for all players until that client recovers. The model essentially chains all players to the worst network conditions present in the session, making it impractical for modern action games where fluid, responsive gameplay is essential.

=== Player observation limitation

We are bound in the time a player is able to react to other players' inputs. One player has to first send their inputs and another player can only then receive them. Any changes to the state from player $c prime$ will never be visible to another player $c$ faster than $t^e_c + t^s_(c prime)$.

When the interval rate is fixed to a time $delta < t^e_c + t^s_(c prime)$, which is usually the case, a client $c$ will already have made an input $i^c_(t + 1)$ without there being a possibility of receiving input $i^(c prime)_t$ from client $c prime$. Therefore according to our definition, games with a fixed interval cannot be fair.

==== Example of player observation limitation

To illustrate this fundamental constraint, consider our two clients attempting to react to each other's movements. Assume optimal conditions with immediate processing and no artificial delays:

- Client $c_0$: send 25 ms, receive 25 ms
- Client $c_1$: send 100 ms, receive 100 ms
- Fixed tick interval: $t^i = 50 "ms"$

Suppose at tick 0, player $p_1$ suddenly moves to block a pathway at position $(3, 5)$. Client $c_1$ sends this input immediately, taking 100 ms to reach the host. The host processes it instantly and broadcasts the update, which takes another 25 ms to reach client $c_0$. Therefore, client $c_0$ cannot possibly see player $p_1$'s blocking move until 125 ms after $c_1$ initiated it.

This 125 ms minimum reaction window exists regardless of the networking model employed. During this time, if the tick interval is 50 ms, client $c_0$ will have already made at least two movement decisions without any possibility of knowing about the blocked path. If $c_0$ was moving toward position $(3, 5)$, they would continue moving toward it for at least two ticks before the blocking becomes visible.

This limitation becomes particularly problematic in competitive scenarios requiring split-second reactions. In a fighting game where a 100 ms reaction time separates amateur from professional players, this network-imposed delay makes true real-time interaction impossible. The only way to reduce this limitation is through better network infrastructure (lower latency), not through improved networking models. This physical constraint fundamentally shapes how we must design networked games, leading to the prediction and reconciliation techniques discussed in subsequent sections.

=== Client side prediction <client-side-prediction>

In the (fair) naive model, a client will only be able to apply their input $i^c_t$ to a state $s_(t - t^r_c)$. Therefore a client sees responses to their own input with a latency of $t^r_c$.

While we previously showed an absolute limitation in seeing other players' inputs, there is no such limitation on seeing state changes to your own inputs. We define a prediction function $f^p: I^c times S -> S$ which only progresses the state based on one single client input $i^c_t$. We write $p^c_(t,d)$ for a client $c$, predicting from timestamp $t$, $d$ ticks to the future. Each client now receives state $s_t$ and directly applies their input to get predicted state $p^c_(t, 1) = f^p (i^c_t, s_t)$. Since responses to $i^c_t$ will be received in $s_(t + t^r_c)$, we predict the state up to $p^c_(t, t^r_c)$. This method is called client-side prediction and used in most modern games as it provides the client with instantaneous feedback - making gameplay fluent.

The difficulty with this method is to apply new incoming host state $s_(t + 1)$ correctly. Given a client predicted $p^c_(t, t^r_c)$, it will receive a response to input $i^c_t$ in at least $t^r_c$ time as the state $s_(t + t^r_c)$. A previous state change arriving as $s_(t + 1)$ would override our predicted state $p^c_(t, t^r_c)$, making the game snap, caused by the time difference. The original solution to this problem is to not replace our current state but define a partial application function $f^"partial": S times S -> S$ which compares the predicted state with the actual state and only replaces diverging parts. During normal operation, the prediction will be close enough causing only rare desynchronizations, which will be visually visible as snapping. We observe, that some parts of the state will always diverge, if state changes are caused by other players or randomness.

One very popular game that is using a slightly modified variation of this method is Minecraft. In Minecraft, the game does not send its direct inputs, but its predicted state. @minecraft-netcode Most important parts of the state to be predicted are breaking blocks and all character movement. The partial application does not happen at client-side, but on host-side. Therefore the host validates if the incoming input looks good enough and doesn't resimulate it if not necessary. When detecting diverging state, the host sends state corrections. Unfortunately this limits anti-cheat capabilities to how sophisticated the validation in the partial application function is. @minecraft-netcode

One major problem with client-side reconciliation is that finding a good partial application function can be difficult. The reason is that we are looking at divergences between $s_(t + 1)$ and $p^c_(t, t^r_c)$, therefore a difference in time of $t^r_c - 1 approx t^r_c$. Therefore even a perfect prediction will diverge on the scale of the round trip time.

One alternative approach would be to not compare the current state for divergence, but memorize past states. Given an interval time of $t^i$, the client needs to memorize $n_"predict" = t^r_c slash t^i$ game states, which can be partial states. This solution unfortunately doesn't solve the snapping when divergences are found, since it forces the client from a predicted state in time $t + t^r_c$ to $t + 1$.

==== Example of client-side prediction

To demonstrate client-side prediction in our movement game, we first define a prediction function that allows a client to speculatively apply their own inputs without waiting for server confirmation. Given that we define clients as identifiers, we can formalize the prediction function as follows:

$
f^"transform" ((i_"up", i_"down", i_"left", i_"right")) & = ((i_"down" - i_"up", i_"right" - i_"left")) \
f^"find" ("id", S) & = x_P, quad x_P in {("id"', x') in S | "id" = "id"' } \
f^"update" ("id", s_p, S) & = {("id", s_p)} union {("id"', x') in S | "id" != "id"'} \
f^p (i_c, "id", s) & = f^"update" ("id", f^"find" ("id", s) + f^"transform" (i_c), s)
$

The prediction function $f^p$ takes a client's input $i_c$, the client's identifier, and the current state, then returns an updated state where only the predicting client's position has changed. Other players remain at their last known positions from the server's authoritative state.

Consider a scenario with client $c_0$ controlling player $p_0$, with a round trip time of 100 ms (50 ms each direction) and a tick interval of 25 ms. Without prediction, the client would experience a 100 ms delay between pressing a key and seeing their character move. With client-side prediction, the response becomes instantaneous:

#table(
  columns: 6,
  align: (center, center, center, center, center, center),
  [*Tick*], [*Server State*], [*Client Receives*], [*Client Input*], [*Predicted State*], [*Client Display*],
  [$0$], [$(0,0), (5,5)$], [—], [—], [—], [$(0,0), (5,5)$],
  [$1$], [$(0,0), (5,5)$], [—], [—], [—], [$(0,0), (5,5)$],
  [$2$], [$(0,0), (5,5)$], [$(0,0), (5,5)$], [right], [$(1,0), (5,5)$], [$(1,0), (5,5)$],
  [$3$], [$(0,0), (5,5)$], [$(0,0), (5,5)$], [right], [$(2,0), (5,5)$], [$(2,0), (5,5)$],
  [$4$], [$(1,0), (5,5)$], [$(0,0), (5,5)$], [right], [$(3,0), (5,5)$], [$(3,0), (5,5)$],
  [$5$], [$(2,0), (5,5)$], [$(0,0), (5,5)$], [right], [$(4,0), (5,5)$], [$(4,0), (5,5)$],
  [$6$], [$(3,0), (6,5)$], [$(1,0), (5,5)$], [stop], [$(4,0), (5,5)$], [$(4,0), (5,5)$],
  [$7$], [$(3,0), (7,5)$], [$(2,0), (5,5)$], [stop], [$(4,0), (5,5)$], [$(4,0), (5,5)$],
  [$8$], [$(3,0), (8,5)$], [$(3,0), (6,5)$], [stop], [$(3,0), (6,5)$], [$(3,0), (6,5)$],
  [$9$], [$(3,0), (9,5)$], [$(3,0), (7,5)$], [stop], [$(3,0), (7,5)$], [$(3,0), (7,5)$],
)

At tick 2, the client receives the initial state and immediately begins moving right. Without prediction, the client would display $(0,0)$ until tick 6. With prediction, the movement appears instantaneous: the client displays $(1,0)$ at tick 2, even though the server hasn't processed this input yet. The client continues predicting movement, reaching $(4,0)$ by tick 5.

The critical moment occurs at tick 6 when the client receives the server state $(1,0), (5,5)$. This confirms the client's first input was processed, but also reveals that player $p_1$ has moved to $(6,5)$ - information the client couldn't predict. At this point, the predicted position $(4,0)$ must be reconciled with the server's authoritative position $(1,0)$ plus the three additional predictions made since then.

Notice how the prediction creates a smooth experience for the controlling player: they press right and immediately see movement. However, it also introduces divergence between the predicted and authoritative states. In our example, the client predicted player $p_0$ at position $(4,0)$ at tick 6, while the server only had them at $(3,0)$. This divergence of one position unit represents the unconfirmed prediction still in transit to the server.

The prediction function must carefully handle state updates to avoid "snapping" - sudden position corrections that break immersion. When the server state arrives at tick 8 showing $(3,0), (6,5)$, the client has predicted $(4,0)$ but stopped sending input at tick 6. The reconciliation process must recognize that position $(3,0)$ represents the final authoritative position after processing all inputs, allowing the display to smoothly converge to the correct state.

This example demonstrates the fundamental trade-off of client-side prediction: immediate responsiveness at the cost of temporary divergence from the authoritative state. The prediction allows fluid gameplay even with 100 ms latency, transforming what would be a sluggish experience into one that feels instantaneous. However, it requires sophisticated reconciliation mechanisms to handle the inevitable corrections when predicted and authoritative states diverge, particularly when multiple players' actions interact in ways the client cannot predict locally.

=== Server reconciliation <theory-rollback>

When merging an update $s_(t + 1)$ with a diverged predicted state $p^c_(t, t^r_c)$, we previously overrode the state with state $s_(t + 1)$. This skip from $t + t^r_c$ to $t + 1$ causes snapping. What we can do alternatively is to memorize inputs $i^c_k: t + 1 <= k <= t + t^r_c$. We replace our state with $s_(t + 1)$ and then apply all memorized inputs to get an alternative predicted state $p^c_(t, t^r_c) prime$ which would have been reached if the divergence didn't happen. Since we now have a state in time $t + t^r_c$, we do not have snapping behavior. This method is called rollback server reconciliation and is one of the most fundamental techniques in modern games.

Server reconciliation is the process of combining a past received state $s_t$ with a present predicted state $p^c_(t, t^r_c)$. Our partial application function is a form of server reconciliation. The goal is to fix divergences in state without the client noticing.

Unfortunately, since we have to rollback to the last received state, we must memorize all predictions we made. In the worst case, we memorize the whole $s_t$. When receiving $s_t$, we apply the prediction function $n_"predict"$ times. Therefore an input $i^c_t$ is predicted for the first time at $t - n_"predict"$ and the last time at $t$. So each input is processed by the client $n_"predict"$ times. This means that especially clients with longer ping have to do more processing, increasing with a smaller tick interval.

==== Example of server reconciliation

To illustrate server reconciliation with rollback, we examine how a client corrects prediction errors when receiving authoritative updates from the server. Consider our movement game with client $c_0$ controlling player $p_0$, with a round trip time of 100 ms (50 ms each direction) and a tick interval of 25 ms. This means the client must predict 4 ticks ahead ($n_"predict" = 100 / 25 = 4$) to maintain responsive gameplay.

The client memorizes all inputs sent to the server that haven't been acknowledged yet. When a server update reveals a prediction error, the client rolls back to the last confirmed state and re-simulates all memorized inputs. This process is visualized in @model-rollback.

Consider the following execution where player $p_1$ (controlled by another client) moves in a way the client cannot predict:

#table(
  columns: 7,
  align: (center, center, center, center, center, center, center),
  [*Tick*], [*Server State*], [*Client Receives*], [*Client Input*], [*Memorized*], [*Predicted State*], [*Display*],
  [$0$], [$(0,0), (5,5)$], [—], [—], [[ ]], [—], [$(0,0), (5,5)$],
  [$1$], [$(0,0), (5,5)$], [—], [—], [[ ]], [—], [$(0,0), (5,5)$],
  [$2$], [$(0,0), (5,5)$], [$(0,0), (5,5)$], [right], [right], [$(1,0), (5,5)$], [$(1,0), (5,5)$],
  [$3$], [$(0,0), (5,5)$], [$(0,0), (5,5)$], [right], [right, right], [$(2,0), (5,5)$], [$(2,0), (5,5)$],
  [$4$], [$(1,0), (5,5)$], [$(0,0), (5,5)$], [up], [right, right, up], [$(2,1), (5,5)$], [$(2,1), (5,5)$],
  [$5$], [$(2,0), (5,5)$], [$(0,0), (5,5)$], [up], [right, right, up, up], [$(2,2), (5,5)$], [$(2,2), (5,5)$],
  [$6$], [$(2,1), (4,5)$], [$(1,0), (5,5)$], [stop], [right, up, up, stop], [*Rollback*], [—],
  [$*$], [—], [—], [—], [—], [$(1,0), (5,5)$], [State after rollback],
  [$*$], [—], [—], [—], [—], [$(2,0), (5,5)$], [Re-sim: right],
  [$*$], [—], [—], [—], [—], [$(2,1), (5,5)$], [Re-sim: up],
  [$*$], [—], [—], [—], [—], [$(2,2), (5,5)$], [Re-sim: up],
  [$*$], [—], [—], [—], [[stop]], [$(2,2), (5,5)$], [$(2,2), (5,5)$],
  [$7$], [$(2,2), (3,5)$], [$(2,0), (5,5)$], [stop], [up, up, stop, stop], [*Rollback*], [—],
  [$*$], [—], [—], [—], [—], [$(2,0), (5,5)$], [State after rollback],
  [$*$], [—], [—], [—], [—], [$(2,1), (5,5)$], [Re-sim: up],
  [$*$], [—], [—], [—], [—], [$(2,2), (5,5)$], [Re-sim: up],
  [$*$], [—], [—], [—], [—], [$(2,2), (5,5)$], [Re-sim: stop],
  [$7$], [—], [—], [—], [[stop]], [$(2,2), (5,5)$], [$(2,2), (5,5)$],
  [$8$], [$(2,2), (2,5)$], [$(2,1), (4,5)$], [left], [stop, stop, left], [*Rollback*], [—],
)

The table traces the execution of server reconciliation with rollback over 8 ticks, showing how the client maintains responsiveness through prediction while handling authoritative corrections from the server. The "Memorized" column tracks unacknowledged inputs retained for re-simulation, while rows marked with asterisks (\*) detail the internal rollback and re-simulation steps occurring within a single tick when discrepancies are detected.

The critical reconciliation occurs at tick 6. The client has predicted player $p_0$ at position $(2,2)$ based on its "right, right, up, up" sequence, but the server state $(1,0), (5,5)$ reveals that only the first "right" input has been processed server-side. The rollback process, illustrated in @model-rollback, begins by reverting to the server's authoritative state $(1,0), (5,5)$. From this baseline, the client reconstructs its predicted state by re-applying all unacknowledged inputs in sequence: the second "right" transforming $(1,0)$ to $(2,0)$, two "up" inputs advancing through $(2,1)$ to $(2,2)$, and finally "stop" maintaining the position. The acknowledged first "right" is then removed from the memorized buffer.

Following re-simulation, the client achieves state $(2,2), (5,5)$, where player $p_0$'s position matches the original prediction. This outcome is characteristic when prediction errors stem solely from other players' unpredictable movements. The reconciliation at tick 8 presents a more complex case where player $p_1$ has moved to $(4,5)$, introducing a persistent divergence.

The computational implications of this approach become evident when considering the frequency and scope of re-simulation. Each server update necessitates re-processing all unacknowledged inputs, which in our configuration amounts to 4 inputs per reconciliation event. For clients experiencing higher latency, such as 200 ms round trip time, the re-simulation burden increases to 8 or more inputs per server update. This computational overhead scales linearly with latency, presenting a significant performance challenge that motivates the investigation of alternative reconciliation methods, particularly our proposed algebraic reconciliation approach which aims to eliminate the need for repeated re-simulation entirely.

#figure(
  image("diagrams/model-rollback-diagram.svg", width: 90%),
  caption: [
    Illustration of the rollback netcode process.
    (a) The client's initial predicted state progression.
    (b) The server's authoritative state diverges (State G instead of B).
    (c) Upon receiving the authoritative State G, the client rolls back to State A, applies State G, and then re-simulates its subsequent inputs to reach States H and I.
    (d) The server again processes inputs and generates a new authoritative State B, which differs from the client's expectation (G).
    (e) The client performs another rollback, reverting to a prior known good state, applying the server's authoritative State B, and re-simulating all inputs to reach State C.
    This demonstrates how rollback continuously adjusts the client's timeline by repeatedly re-computing future states (e.g., the state at time point 4 is computed multiple times) based on new authoritative information, ensuring eventual consistency.
  ],
) <model-rollback>


=== Delta State <delta-state>
The host is sending the whole state $s_t$ each tick. This means we will send redundant data as the state rarely changes completely. We define delta states $Delta s_t in Delta S$ as changes in state which can be applied using a delta application function $f^A: S -> Delta S -> S$. We define an alternative progression function $f^Delta: I -> S -> Delta S$ returning a delta instead of the whole state and write $f^Delta (i_t, s_t) = Delta s_t$. We can derive the original progression function as $f(i_t, s_t) = f^A (s_t, f^Delta (i_t, s_t))$, therefore all our previous results hold true when using delta states. The other way around we can convert any normal state to delta state given progression function $f$ and state $S$ by defining $f^A = f$, $Delta S = S$ and $f^A (dot, s_t) = s_t$. This means, that in practice we can always implement delta state and use normal state on top.

The host will each tick send $Delta s_(t + 1)$ to the clients. In the (fair) naive or lockstep model, a client has currently loaded a state $s_t$ and can simply use the delta application function to progress the state. Using rollback reconciliation, the client can use the delta application function after the rollback to $s_t$ and predict the actual state afterwards. If delta state can be used with the partial application reconciliation depends on the state and cannot be generalized because it is not possible to get back to a state $s_t$.

==== Example of delta state

To illustrate delta states, we extend our movement game to represent state changes rather than absolute positions. Instead of transmitting complete player positions each tick, we transmit only the changes (deltas) that occurred. This approach significantly reduces bandwidth requirements when players remain stationary or move predictably.

We define delta states using the same vector space as our original game, but now representing position changes:

$
&"Vector " & V & subset.eq RR times RR & \
&"Delta Player " & Delta P & = V \
&"Delta State " & Delta S & subset.eq "id" times Delta P \
$

The delta application function combines a current state with a delta to produce the next state:

$
f^"find" ("id", s) & = cases(
  s_p & "if" ("id", s_p) in s,
  (0, 0) & "otherwise"
) \
f^A (s, Delta s) & = {("id", f^"find" ("id", s) + Delta p) | ("id", Delta p) in Delta s} \
& quad union {("id", s_p) | ("id", s_p) in s and ("id", dot) in.not Delta s}
$

The delta progression function generates deltas from inputs rather than complete states:

$
f^"transform" ((i_"up", i_"down", i_"left", i_"right")) & = ((i_"down" - i_"up", i_"right" - i_"left")) \
f^Delta (i, s) & = {("id", f^"transform" (i_p)) | ("id", i_p) in i}
$

Consider a concrete example where player $p_0$ moves diagonally while player $p_1$ remains stationary:

$
s_0 & = {(p_0, (3, 2)), (p_1, (5, 5))} \
i_0 & = {(p_0, (1, 0, 0, 1)), (p_1, (0, 0, 0, 0))} \
f^Delta (i_0, s_0) & = {(p_0, (1, 1)), (p_1, (0, 0))} = Delta s_0 \
f^A (s_0, Delta s_0) & = {(p_0, (3, 2) + (1, 1)), (p_1, (5, 5) + (0, 0))} \
& = {(p_0, (4, 3)), (p_1, (5, 5))} = s_1
$

The bandwidth advantage becomes apparent when examining the transmitted data. Without delta states, the server sends the complete state ${(p_0, (4, 3)), (p_1, (5, 5))}$ every tick. With delta states, it sends only ${(p_0, (1, 1))}$, omitting player $p_1$ entirely since their position unchanged (the zero delta $(0, 0)$ need not be transmitted). 

In our simplified example with just two players possessing only position data, the bandwidth improvement appears modest reducing transmission from two position vectors to one. However, this understates the significance of delta states in production games. Consider a typical real-time strategy game with thousands of units, each containing position, health, ammunition, animation states, and numerous other attributes. When only a handful of units move or engage in combat each tick while the vast majority remain idle at their posts, delta states eliminate the need to transmit any data for stationary units. A battlefield with 1000 units where only 50 are active reduces network traffic by 95%, transforming what would be an unmanageable bandwidth requirement into a feasible one. This optimization becomes even more critical for games with complex environmental objects, destructible terrain, or persistent world elements that rarely change but would otherwise require constant retransmission.

This delta representation also naturally supports the identity element required for algebraic operations. The zero vector $(0, 0)$ serves as the identity: $f^A(s, emptyset) = s$, where the empty delta set represents no changes. This property becomes crucial for our algebraic reconciliation method, as it allows us to compose and decompose state changes algebraically.

== Algebraic server reconciliation <algebraic-reconciliation>

The reconciliation methods examined thus far, particularly rollback reconciliation, reveal significant implementation challenges and computational costs that limit their practical applicability. Rollback reconciliation demands deterministic physics simulation to ensure correct results during re-simulation a requirement that imposes substantial engineering constraints on game development. The simulation must produce bit-identical results across all re-simulation passes, precluding the use of many standard optimizations and requiring careful control over floating-point operations, random number generation, and execution order. Even subtle implementation errors in state management or input ordering can manifest as visible artifacts: jittering movement, rubber-banding effects, or inconsistent collision resolution that degrades the player experience.

Beyond implementation complexity, the computational overhead of rollback reconciliation scales poorly with network latency. As demonstrated in our analysis, clients must re-simulate all unacknowledged inputs with each server update, performing $n_"predict"$ iterations of the progression function per reconciliation event. For clients with higher latency a common scenario in global multiplayer games this computational burden becomes prohibitive, particularly when multiple entities require prediction or when the progression function involves expensive physics calculations.

These limitations motivate the development of an alternative reconciliation method that eliminates the need for re-simulation while maintaining the responsiveness benefits of client-side prediction. We now introduce algebraic server reconciliation, a novel approach that leverages the mathematical structure of delta states to compute corrections directly, transforming reconciliation from an iterative re-simulation process into a single algebraic operation. This method not only reduces computational complexity from $O(n_"predict")$ to $O(1)$ per reconciliation event but also removes the strict determinism requirement, significantly simplifying implementation and enabling broader applicability across diverse game architectures.

=== Overview

The theoretical foundation for algebraic server reconciliation draws inspiration from Conflict-Free Replicated Data Types (CRDTs), a well-established technique in distributed systems for achieving eventual consistency without coordination. @crdt-shapiro CRDTs enable multiple replicas in a distributed system to independently modify shared data while guaranteeing convergence to a consistent state. This guarantee is achieved through carefully designed data structures and operations that possess specific algebraic properties particularly commutativity and associativity allowing updates to be applied in any order while producing the same final result. The merge function in CRDTs serves as a universal conflict resolver, automatically reconciling divergent states without requiring explicit coordination or consensus protocols.

However, the application context for networked games presents a fundamentally different topology than traditional CRDT deployments. In distributed databases or collaborative editing applications, CRDTs operate in a peer-to-peer model where any replica can generate updates and all replicas eventually converge through symmetric merge operations. In contrast, our client-server game architecture establishes an asymmetric relationship: the server maintains authoritative state while clients generate speculative predictions that must ultimately align with server decisions. This architectural distinction enables a more specialized approach than generic CRDTs would provide.

Our method exploits this asymmetry by recognizing that reconciliation is inherently a client-side concern. The server never needs to reconcile it simply progresses the authoritative state based on received inputs. Only clients face the challenge of aligning their predicted states with authoritative updates. This insight allows us to design a reconciliation mechanism tailored specifically to the temporal dynamics of client-side prediction, where the fundamental problem is correcting a present predicted state based on past authoritative information.

The core mechanism operates through two complementary algebraic operations. First, we define a difference operation that computes the discrepancy between the client's predicted delta and the server's authoritative delta for a given time period. This difference captures the prediction error in the form of a correction delta. Second, we employ a merge operation similar in spirit to CRDT merges but adapted for our temporal context that applies this correction delta to the client's current predicted state. Crucially, because of the inherent time delay between generating predictions and receiving authoritative updates, we cannot directly compare contemporaneous states. Instead, we compute corrections based on historical divergences and apply them to present states, relying on a key assumption about the temporal stability of predictions to ensure convergence.

This approach transforms reconciliation from the computationally expensive process of re-simulating multiple frames of game logic into a direct algebraic computation. Where rollback reconciliation must replay $n_"predict"$ frames of potentially complex physics simulation, algebraic reconciliation performs a single difference calculation followed by a single merge operation. The formal properties ensuring convergence under this simplified model will be established through the mathematical framework presented in the following definition.

=== Definition

An Abelian group is a set $A$, together with an operation $+: A times A -> A$ which is associative and commutative. Additionally, it has an identity element $a + e = a$ and for every element $a$ an inverse $a + a prime = e$.

We assume a delta state that defines an abelian group with $S = Delta S$, $e = s_e$ and $+ = f^A$, where $f^A$ satisfies the required properties. We can observe, that we still have advantages over non-delta state, since we do not need to transfer state, when $Delta s = s_e$.

We define a delta prediction function $f^(Delta p): I^c times S -> Delta S$ producing a delta $Delta p^c_(t,d) = f^(Delta p) (i^c_(t + d), p^c_(t,d))$ instead of the whole state when predicting the next state. Therefore $p^c_(t,d + 1) = p^c_(t,d) + Delta p^c_(t,d)$ and $p^c_(t,d) = s_t + sum^d_(k=0) Delta p^c_(t,k)$.

The client memorizes $n_"predicted"$ predicted deltas $Delta p^c_(t, k): 0 <= k <= t^r_c$. We define a new server reconciliation method as follows: For each incoming $Delta s_(t + 1)$, we add a correction update $epsilon.alt = Delta s_(t + 1) - Delta p^c_(t, 1)$ to our current state $p^c_(t + 1, t^r_c) = p^c_(t, t^r_c) + epsilon.alt$. Assuming that predictions are mostly uncorrelated $Delta p^c_(t,d) approx Delta p^c_(t + 1,d - 1)$, we can show convergence:
$
  & p^c_(t, t^r_c) + epsilon.alt \
  = & p^c_(t, t^r_c) + (Delta s_(t + 1) - Delta p^c_(t, 0)) \
  = & s_t + sum_(k = 0)^(t^r_c) Delta p^c_(t,k) + (Delta s_(t + 1) - Delta p^c_(t, 0)) \
  = & (s_t + Delta s_(t + 1)) + sum_(k = 1)^(t^r_c)Delta p^c_(t,k) + (Delta p^c_(t,0) - Delta p^c_(t,0)) \
  = & s_(t + 1) + sum_(k = 1)^(t^r_c)Delta p^c_(t, k) \
  approx & s_(t + 1) + sum_(k = 0)^(t^r_c - 1)Delta p^c_(t + 1, k) \
  = & p^c_(t + 1, t^r_c - 1)
$

Therefore we can reach any prediction $p^c_(t + d,t^r_c)$ over time. We call this reconciliation method algebraic server reconciliation.

==== Example of Abelian Server Reconciliation

To demonstrate algebraic server reconciliation in practice, we must first establish the Abelian group structure for our movement game. Unlike previous examples that focused on state progression and prediction, this example requires defining the algebraic operations that enable direct correction computation without re-simulation.

We define an Abelian group for our movement game using component-wise vector addition as the group operation. The identity element is the zero vector, and inverse elements are obtained through component-wise negation:

$
f^"find" ("id", s) & = cases(
  s_p & "if" ("id", s_p) in s,
  (0, 0) & "otherwise"
) \
f^"ids" (s) &= { "id" | ("id", *) in s} \
s + s' &= { ("id", f^"find" ("id", s) + f^"find" ("id", s')) | "id" in f^"ids" (s union s')} \
-s &= { ("id", -s_p) | ("id", s_p) in s} \
e &= emptyset \
$

Consider client $c_0$ controlling player $p_0$ with 100 ms round trip time. Starting from state $s_0 = {(p_0, (0,0)), (p_1, (5,5))}$, the client sends a "right" input and immediately predicts the delta:

$
Delta p^c_0 = {(p_0, (1,0)), (p_1, (0,0))} 
$

The client applies this to display $(1,0), (5,5)$ immediately. Due to the 100 ms round trip time, the server won't process this input for 50 ms, and the acknowledgment won't return for another 50 ms. During this time, the client continues predicting, accumulating deltas in its memorized buffer.

When the server's delta finally arrives, it might show:

$
Delta s = {(p_0, (1,0)), (p_1, (2,0))}
$

This confirms the client's prediction for $p_0$ but reveals that $p_1$ moved right by 2 units, information the client couldn't predict. The algebraic reconciliation computes the correction:

$
epsilon &= Delta s - Delta p^c_0 \
&= {(p_0, (1,0)), (p_1, (2,0))} - {(p_0, (1,0)), (p_1, (0,0))} \
&= {(p_0, (0,0)), (p_1, (2,0))}
$

This correction represents exactly what the client failed to predict: player $p_1$'s movement. The client applies this correction directly to its current predicted state without any re-simulation. If the client has since made additional predictions (say, moving up twice for a total displacement of $(0,2)$), its current displayed state might be $(1,2), (5,5)$. Applying the correction:

$
s_"corrected" &= s_"current" + epsilon \
&= {(p_0, (1,2)), (p_1, (5,5))} + {(p_0, (0,0)), (p_1, (2,0))} \
&= {(p_0, (1,2)), (p_1, (7,5))}
$

The key insight is that this correction happens in constant time through a single vector addition, regardless of how many predictions were made since the server state was generated. Rollback reconciliation would need to return to state $s_0$, apply the server's update to get $(1,0), (7,5)$, then re-simulate the two "up" inputs to reach $(1,2), (7,5)$. Algebraic reconciliation achieves the same result directly.

This efficiency gain becomes more pronounced with higher latency. A client with 200 ms round trip time would need to maintain and potentially re-simulate 8 ticks of predictions with rollback. With algebraic reconciliation, it still performs just one correction operation. Furthermore, the method tolerates non-deterministic physics, as long as the delta operations maintain their algebraic properties, the correction converges correctly even if the exact simulation differs between client and server.

=== Limitations

The convergence proof for algebraic server reconciliation relies on a critical assumption: $Delta p^c_(t,d) approx Delta p^c_(t+1,d-1)$. This assumption requires that predictions remain temporally stable, meaning the delta produced by predicting from state $s_t$ at time $d$ should closely match the delta produced by predicting from state $s_(t+1)$ at time $d-1$. In essence, this assumes that the prediction function exhibits minimal sensitivity to variations in the base state from which predictions originate.

This temporal stability assumption holds well for games where entities operate relatively independently and player control switches frequently between different entities. Consider a real-time strategy game where a player commands hundreds of units. Each unit's movement prediction depends primarily on its own state and the player's direct commands, with minimal influence from other units' positions. When the player issues a move command to unit A, then immediately switches attention to unit B, the predictions for unit A remain consistent regardless of minor corrections to unit B's state. The decorrelation between controlled entities ensures that prediction errors in one entity do not cascade into prediction errors for others.

However, this assumption breaks down in games with strong state dependencies and persistent entity control. Sandbox games exemplify this limitation through their fundamental design philosophy: every entity can interact with any other entity in complex, emergent ways. Consider a scenario where player $p_1$ pushes player $p_0$ off a ledge. The falling state fundamentally alters the prediction function's behavior: a falling player accelerates downward each tick, while a grounded player remains stationary. If the client fails to predict the initial push, it continues predicting $p_0$ as stationary while the server simulates falling. The algebraic correction $epsilon = Delta s - Delta p$ captures only the position discrepancy for that specific tick, not the change in falling state. Consequently, the client's prediction continues using the wrong dynamics, generating increasingly large errors that the algebraic correction cannot fully resolve. The system perpetually lags behind the true state until the falling motion ceases and both client and server return to similar dynamics.

This limitation extends to state-dependent dynamics. For projectiles, small initial mispredictions in velocity/angle cause trajectory divergence; a positional correction delta does not fix the velocity state, so error compounds until dynamics re-align or the object is removed.  Similarly, vehicle physics with momentum, sliding mechanics on ice, or even simple acceleration-based movement all violate the temporal stability assumption to varying degrees.

The severity of these limitations correlates inversely with the frequency of state-altering interactions. Games where velocity changes occur primarily through direct player control exhibit better convergence properties because the controlling player's inputs naturally align the predicted and actual dynamics. When a player accelerates their character, both client and server process the same acceleration input, maintaining synchronized dynamics despite potential position discrepancies. Problems arise when external forces, especially those from other players or environmental hazards, alter an entity's dynamic state in ways the client cannot predict.

These limitations do not render algebraic reconciliation unusable but rather define its domain of applicability. The method excels in games with discrete, position-based movement, sparse entity interactions, and minimal state-dependent dynamics. For games outside this domain, hybrid approaches that combine algebraic reconciliation for suitable state components with rollback reconciliation for problematic components may offer the best compromise between computational efficiency and correctness.

=== Abelian group for ECS games

Entity Component System (ECS) architectures have become the predominant method for organizing game state in modern engines. The compositional nature of ECS, where entities are defined by their collection of components rather than through inheritance hierarchies, naturally aligns with the algebraic structures required for our reconciliation method. We now demonstrate how to construct an Abelian group for arbitrary ECS-based games, providing a general framework that developers can adapt to their specific implementations.

In an ECS architecture, the game world consists of entities, each possessing a unique identifier. Entities are containers for components, where each component type stores specific data (position, health, inventory, etc.). Systems operate on entities possessing specific component combinations, but for state representation purposes, we focus solely on the entity-component data structure.

We formalize an ECS game state as a nested mapping with multiplicities:

$
"World" &: "EntityID" -> ("Entity", ZZ) \
"Entity" &: "ComponentTypeID" -> ("Component", ZZ)
$

The integer multiplicities serve a dual purpose. For entities, positive multiplicity indicates creation or presence, negative multiplicity indicates deletion, and zero represents either modification or an already-deleted entity. For components, multiplicities similarly track additions, removals, and modifications. This multiplicity-based representation naturally encodes state changes as part of the state structure itself.

The Abelian group operation combines worlds by summing multiplicities:

$
(W_1 + W_2)["id"_e] = cases(
  (E_1 + E_2, m_1 + m_2) & "if" "id"_e in W_1 "and" "id"_e in W_2,
  W_1["id"_e] & "if" "id"_e in W_1 "and" "id"_e in.not W_2,
  W_2["id"_e] & "if" "id"_e in.not W_1 "and" "id"_e in W_2,
  "undefined" & "otherwise"
)
$

Where entity addition is defined recursively through component addition:

$
(E_1 + E_2)["id"_c] = cases(
  (C_1 + C_2, m_1 + m_2) & "if" "id"_c in E_1 "and" "id"_c in E_2,
  E_1["id"_c] & "if" "id"_c in E_1 "and" "id"_c in.not E_2,
  E_2["id"_c] & "if" "id"_c in.not E_1 "and" "id"_c in E_2,
  "undefined" & "otherwise"
)
$

Component addition must be defined specifically for each component type. For vector positions, we use vector addition. For scalar health values, we use arithmetic addition. For discrete states, we might use replacement semantics where the component with higher absolute multiplicity takes precedence.

Consider a concrete example with two entity types in a simplified game:

$
"PositionComponent" &= RR times RR \
"HealthComponent" &= ZZ \
"Player" &= {"Position": "PositionComponent", "Health": "HealthComponent"} \
"Projectile" &= {"Position": "PositionComponent"}
$

A world state might be:

$
W_0 = {
  e_1: ({&"Position": ((5, 3), 1), \
       &"Health": (100, 1)}, 1), \
  e_2: ({&"Position": ((10, 7), 1)}, 1)
}
$

A delta representing player movement and damage might be:

$
Delta W = {
  e_1: ({&"Position": ((2, 0), 1), \
       &"Health": ((-10), 1)}, 0)
}
$

Applying this delta yields:

$
W_1 = W_0 + Delta W = {
  e_1: ({&"Position": ((7, 3), 1), \
       &"Health": (90, 1)}, 1), \
  e_2: ({&"Position": ((10, 7), 1)}, 1)
}
$

The identity element is the empty world mapping $emptyset$, and the inverse of any world is obtained by negating all multiplicities and component values. These operations satisfy the Abelian group axioms: closure (combining two ECS states yields another valid ECS state), associativity (the order of combining multiple deltas doesn't matter), commutativity (deltas can be applied in any order), identity (adding an empty delta changes nothing), and inverse (every delta can be undone).

This formalization provides a systematic approach to implementing algebraic reconciliation for any ECS-based game. Developers need only define appropriate addition operations for their specific component types, and the framework handles the compositional structure automatically. The multiplicity-based approach elegantly captures the full lifecycle of entities and components, from creation through modification to deletion, within a unified algebraic structure.

= Networking Architecture

The goal of a networking system is to provide a seamless interaction with other players inside a game. How to achieve a seamless interaction with other players was investigated in #ref(<theory>). The focus of systems architecture is on how to implement these models within the game's underlying system. Consequently, this chapter is of less concern to players and more pertinent to developers. Just as we aim for seamless interaction for players, we also strive for seamless game development for developers. The architecture here is only one possible approach to networking architecture, which will be different depending on needs and game architecture.

The architecture below shows how the networking layer implements earlier concepts in practice and how the proposed method integrates into an end-to-end stack. It also clarifies the runtime dataflow we evaluate later.

#pagebreak(weak: true)

== Overview

Our networking system is designed as an independent layer (the "networking layer") positioned beneath the game system (the "game layer"). The goal is to expose minimal complexity, making game development akin to creating a single-player game. The game system comprises a "world" (representing the game state), game logic that modifies this world, and events. These events facilitate communication between different logic elements and trigger user-facing indicators, such as animations.

This separation of concerns within the game system itself facilitates a cleaner interface with the underlying networking layer, as illustrated below.

#figure(
  pad(top: 20pt, bottom: 20pt, image("diagrams/design-game-network-layer.svg")),
  caption: [
    The fundamental division between the game layer, responsible for gameplay mechanics and presentation, and the network layer, responsible for communication.
  ],
)

#pagebreak(weak: true)

=== Four quadrants model

Visually, the game and networking layers can be divided into four quadrants. The horizontal axis differentiates between the server and the client. As in #ref(<theory>), we use the classic server/client model, where the server has authority over the game world. Clients can only interact with the game world by sending their inputs, where the server will send updates to the game world (called replication) and events (for example, to trigger animations). The version of the world maintained on the client, which is partially updated through replication, is referred to as the "world view."

#figure(
  pad(top: 20pt, bottom: 20pt, image("diagrams/design-four-server-client.svg", height: 50%)),
  caption: [
    Building on this client-server distinction, we now incorporate the differentiation between the game and network layers.
  ],
)

#pagebreak(weak: true)

=== Server and Client

The vertical axis, as previously introduced, differentiates between the game and network layers. Both the game and networking layers must serve two distinct scenarios: operating as a server or as a client. First, looking at the game layer, the server usually does not want to render the world. This independence not only boosts performance by avoiding unnecessary rendering overhead on the server but also simplifies porting the server logic to environments without graphical capabilities.

Most game logic is also only needed on the server, as changes are replicated authoritatively to the client. An exception could be user-controlled elements of the game world, such as the player character. However, similar to the approach in #ref(<theory>), we distinctly define this as "prediction logic" to improve cohesion. Additional event-based visuals, like animations, are typically only required on the client, as they do not impact the core game logic. This ensures that client-side presentation details do not impose constraints or unnecessary complexity on the authoritative server-side game simulation.

#figure(
  pad(top: 20pt, bottom: 20pt, image("diagrams/design-four-game.svg")),
  caption: [
    The server manages the authoritative World and Logic, while the client maintains a World View, handles Prediction Logic, Rendering, and event-based Animations.
  ],
)

#pagebreak(weak: true)

=== Game and Network

The networking layer must cater to the server logic by providing a list of player inputs each game tick. Before replication, the networking layer has to look for changes in the server world. As introduced with "delta state" in #ref(<theory>), the system aims to send only the changes in the game world (deltas) rather than the entire world state each time. The efficiency of this delta state transmission is crucial for minimizing bandwidth usage and server load.

#figure(
  pad(top: 0pt, bottom: 10pt, image("diagrams/design-four-all.svg")),
  caption: [
    The complete four-quadrant architecture, illustrating the interplay between Game and Network layers on both Server and Client, including data flows.
  ],
)

Depending on how the world in the server is structured, it might provide additional helpers to detect changes. When the client receives changes, it applies them to its local game world, provided these changes are not already predicted. Otherwise, we need to use reconciliation to update our world view. This continuous loop of input collection by the network layer, server processing, state replication, and client-side reconciliation (if necessary) forms the core of the real-time networked experience.

== Server networking layer

Previously, we explained an overview of our architecture and how components abstractly interact. Here, we want to dive deeper into the server-side dataflow. The following diagram displays all relevant components of the server-side networking layer, including their interaction with the game state.

#figure(
  pad(top: 20pt, bottom: 20pt, image("diagrams/design-detail-server.svg", height: 45%)),
  caption: [
    Server-side networking components and dataflow, illustrating the processing of incoming inputs and the generation of outgoing changes and events.
  ],
)

We have three primary communication channels with clients: incoming inputs from players, outgoing changes to replicate the game world, and outgoing events. Events are not strictly part of the game world but are needed for richer visual experiences on the client. The input tracker collects incoming inputs from players, providing a consolidated input to the game logic each tick. It is also responsible for providing stale or empty inputs if a new input has not arrived in time. The change detection mechanism is responsible for replicating the game world to all clients, ensuring each client has the same (or a consistent partial) world view by exchanging deltas.

The dataflow can be summarized by the following steps, which correspond to the numbered arrows in the diagram:

+ Users send their inputs to the server. The server receives these inputs, and the input tracker keeps track of them. Since inputs can be sent via unreliable communication methods, this component might also include logic for filtering inputs (e.g., processing only the most recent ones) or handling out-of-order packets.

+ Each tick, a set of all relevant inputs (one per player, potentially synthesized by the input tracker if an actual input is missing) is provided to the game logic. The game logic itself is fully defined in the game layer but is driven by inputs supplied by the networking layer.

+ Using these inputs, the game logic in the game layer modifies the world state. Optionally, the game logic may directly inform the change detection component about specific changes that have occurred.

+ Modifications to the world state need to be communicated to all clients. This is managed by the change detection component, which generates deltas representing these modifications. Since world state changes happen frequently and quickly, unreliable communication methods might be preferred for sending these deltas to clients. However, using unreliable transport for state updates adds complexity, such as the need for the server (or client) to track applied changes and potentially re-send missed updates to ensure eventual consistency.

+ Processing the game logic can also trigger occurrences that are not direct modifications of the persistent game world but are important for the player experience (e.g., sound effects, temporary visual effects). These are transmitted directly to the corresponding clients as events. Events are often sent reliably if they are critical, or unreliably if they are transient and missing one isn't detrimental.

This entire process is repeated each game tick while the game is running.
== Client networking layer

The overall structure and communication pathways of the client-side networking layer were introduced in the architectural overview. Having inspected the dataflow within the server-side networking layer, we now turn our attention to the client-side components. This part is particularly important for our discussion, as it is where our new algebraic reconciliation method integrates. The following diagram presents the client-side dataflow.

#pad(
  figure(
    pad(top: 15pt, bottom: 15pt, image("diagrams/design-detail-client.svg")),
    caption: [
      Client-side networking components and dataflow, detailing the processing of local player inputs, incoming server changes and events, and the interaction between prediction and reconciliation modules.
    ],
  ),
)

Similar to the server-side, the client has three primary communication channels: incoming events from the server, incoming state changes from the server, and outgoing player input. We will not focus extensively on event handling in this section, assuming that the world view component processes them (e.g., by triggering local visual or audio effects). The reconciliation, prediction, and prediction logic components collectively form the most interesting part of this architecture for our purposes. The interactions between these three elements differ depending on the specific reconciliation strategy employed, as will be detailed in the following subsections. We assume the client's representation of the game world is conceptually split into a "normal" part (the world view, reflecting acknowledged server state) and a predicted part (reflecting speculative local changes).

The dataflow can be summarized by the following steps, which correspond to the numbered arrows in the diagram:

+ Each tick, the server replicates state changes (deltas) to the client. These changes can correspond to either the predicted or non-predicted parts of the client's world representation. If a change affects a non-predicted part, it is directly applied to the world view. Otherwise, if it affects a predicted part, it is passed to the reconciliation module.

+ In parallel with receiving world state changes, the client also receives events from the server. As mentioned, we assume the world view handles these, for instance, by initiating animations or sound effects that do not alter the core game state logic.

+ Each tick, the game layer captures inputs from the player. These inputs are sent to the server as quickly as possible, often using an unreliable communication channel to minimize latency. Critically for client-side responsiveness, these inputs are also passed to the local prediction module.

+ After the prediction module receives inputs from the game layer, these inputs are fed into the game-specific prediction logic. If rollback reconciliation is being used (as detailed in #ref(<design-rollback>)), this prediction module is also responsible for memorizing these inputs for potential future re-simulation.

+ The game-layer defined prediction logic uses the local inputs to modify the predicted part of the world, most commonly affecting entities directly controlled by the player, such as their character. This immediate local modification provides the player with responsive feedback to their actions.

+ When incoming state changes from the server (received in step 1) affect parts of the world that have been locally predicted, these discrepancies must be handled by the reconciliation module. This module receives the authoritative server change and information about the current predicted state from the prediction module.

+ If rollback reconciliation is employed, the reconciliation module will use the memorized inputs (from step 4) and the authoritative server state to re-simulate the player's actions and compute a corrected predicted part of the world. For other reconciliation methods, like algebraic reconciliation (detailed in #ref(<design-algebraic>)), this step will differ. After processing, the reconciliation module updates the predicted part of the world to align it more closely with the authoritative server state, aiming to correct any mispredictions smoothly.

Similarly to the server-side dataflow, this entire process is repeated each game tick while the game is running.

#pagebreak()

=== Rollback reconciliation <design-rollback>

When an incoming authoritative state change (delta) from the server affects the predicted part of the client's game world, reconciliation is necessary to correct any mispredictions. The most common reconciliation method currently used in games is rollback reconciliation, which was introduced conceptually in #ref(<theory-rollback>). The core idea behind rollback reconciliation is to revert the client's game state to the last known authoritative state before the misprediction occurred, apply the incoming server correction, and then re-simulate all local player inputs that have occurred since that authoritative state.

The interactions for this process within our client-side architecture are illustrated below.

#pad(
  bottom: 20pt,
  figure(
    pad(
      top: 20pt,
      bottom: 20pt,
      image("diagrams/design-detail-rollback.svg"),
    ),
    caption: [
      Dataflow for rollback reconciliation on the client. Incoming changes trigger a rollback, replay of memorized inputs via the prediction module, and update of the predicted world.
    ],
  ),
)

The primary challenge in implementing rollback reconciliation lies in efficiently reverting the game state. When working with delta states (as discussed in #ref(<delta-state>)), two common approaches are:

+ *State Cloning*: Maintain at least two distinct copies (or snapshots) of the predicted part of the world. One copy represents the state before the latest batch of local predictions is applied. When an incoming server change necessitates a rollback, the current predicted world (with the mispredictions) is discarded, and the client reverts to the previous clean snapshot. The server change is applied to this snapshot, which then becomes the new baseline for re-applying subsequent local inputs.

+ *Storing Reverse Deltas*: For each local prediction applied to the predicted part of the world, store a corresponding "reverse delta" or "undo operation." To roll back, these reverse deltas are applied in reverse chronological order to the current predicted state, effectively reverting it step-by-step to the desired past authoritative state. Once rolled back, the server's delta is applied, and then local inputs are re-simulated.

After successfully rolling back the state to the point of divergence, the reconciliation module needs to re-apply the local inputs that the player has generated since that point. To facilitate this, the prediction module, as mentioned in the client-side dataflow (see step 4), memorizes these applied inputs in a buffer. The rollback reconciliation process accesses this buffer to retrieve the sequence of inputs that must be re-played by the prediction logic against the corrected state.

#pagebreak()

=== Algebraic reconciliation <design-algebraic>

A significant drawback of rollback reconciliation, as highlighted in #ref(<theory-rollback>), is the computational cost of re-simulating predictions. Each time an authoritative server update corrects the client's predicted state, the client might need to re-process multiple ticks of input. This re-simulation effort can increase with the client's network latency, potentially affecting performance, especially in games with many frequently predicted game objects or for players with higher ping times.

The dataflow for applying algebraic reconciliation within our client architecture is depicted in the figure below.

#pad(
  bottom: 20pt,
  figure(
    pad(top: 20pt, bottom: 20pt, image("diagrams/design-detail-algebraic.svg")),
    caption: [
      Dataflow for algebraic reconciliation on the client. Incoming server deltas are used by the reconciliation module to calculate a direct correction delta.
    ],
  ),
)

Our proposed algebraic server reconciliation method, whose theoretical basis was introduced in #ref(<algebraic-reconciliation>), offers an alternative designed to avoid this repetitive prediction overhead. This method relies on representing game state changes as "delta states." For algebraic reconciliation to work effectively, these delta states need to possess certain well-defined mathematical properties, specifically those of an Abelian group, as detailed in our theory section. In essence, this means the deltas can be reliably combined, effectively undone, and the sequence of their combination does not alter the final result, much like arithmetic operations on numbers. When these conditions are met, corrections to the client's predicted state can often be calculated and applied as a single, direct adjustment, rather than requiring a full re-simulation of past inputs.

The implementation of algebraic reconciliation within the client-side networking layer primarily modifies how the reconciliation module processes incoming server changes and updates the client's predicted part of the world. The client's prediction logic, when handling local player inputs, conceptualizes its effects as a series of "predicted deltas." The prediction module tracks the cumulative outcome of these locally generated deltas, effectively maintaining the client's speculative view of the game state built upon the last acknowledged server state.

Concurrently, the client receives authoritative state updates from the server, also in the form of deltas. When such an authoritative server delta arrives, the reconciliation module's task is to compute a "correction delta." This is achieved by comparing the server's authoritative delta for a given time period with the net predicted delta that the client had generated for that same period. The discrepancy between these two deltas isolates the misprediction. This "difference," which is itself a delta, forms the required correction. The ability to reliably calculate this correction delta hinges on the algebraic (Abelian group) properties of the delta states, which allow for a meaningful "subtraction" or "inversion" of the predicted deltas relative to the server's authoritative ones, as outlined in #ref(<algebraic-reconciliation>).

Once this single correction delta is determined, it is applied directly to the client's current predicted part of the world. This direct application adjusts the client's state to more accurately reflect the server's view, effectively integrating the server's information without the need to rewind and individually re-process past local inputs. This avoidance of extensive input re-simulation is a key advantage over the rollback method. While the re-simulation of old inputs is bypassed, the client naturally continues to apply new local inputs via the prediction logic to its newly corrected state to maintain immediate responsiveness. It's important to note that for this process to function, the prediction module must maintain a record of the predicted deltas it has generated, as this information is essential for calculating the correction delta. This is distinct from rollback reconciliation's requirement to store the raw inputs themselves for potential re-simulation.

By directly adjusting the predicted state through these well-behaved delta manipulations, the algebraic approach can offer a more computationally efficient reconciliation process. This is particularly beneficial when the game state can be effectively represented by deltas that adhere to the required algebraic properties, as this allows for the direct calculation and application of corrections.

= Experiments

The theoretical foundations and architectural designs presented in previous chapters establish algebraic server reconciliation as a promising alternative to traditional rollback-based methods. This chapter transitions from theory to empirical validation, demonstrating through controlled experiments that our proposed method achieves its intended goals: maintaining synchronization quality comparable to rollback reconciliation while eliminating the computational burden of repeated state re-simulation. We present a series of experiments designed to isolate and examine specific aspects of reconciliation behavior, beginning with fundamental movement scenarios and progressing to increasingly complex interactions that challenge our temporal stability assumptions.

== Methodology

Our experimental approach prioritizes observable behavioral characteristics over raw performance metrics, as the computational advantages of algebraic reconciliation are mathematically self-evident from the complexity analysis presented in Chapter 3. The critical question for practical adoption is not whether algebraic reconciliation reduces computational load, it demonstrably transforms O(n_predict) operations into O(1), but rather whether this efficiency comes at the cost of synchronization quality or player experience.

To enable rigorous comparison, we implemented three reconciliation strategies within a unified networking framework: rollback reconciliation representing the current industry standard, override reconciliation serving as a naive baseline, and our proposed algebraic reconciliation. Each strategy operates as an interchangeable module, ensuring that observed differences arise solely from the reconciliation method rather than implementation artifacts. The framework employs simulated network sockets with configurable round-trip delays, eliminating external network variability while maintaining realistic latency characteristics. This controlled environment enables reproducible experiments that isolate the specific behaviors we seek to understand.

The test scenarios utilize two custom-built games: a top-down movement game where players control circles in a 2D plane, and a side-scrolling game with gravity-based physics. Both games employ the Matter.js physics engine to ensure realistic collision dynamics that create the state interdependencies which challenge reconciliation methods. Throughout each experiment, we track three primary metrics: state divergence quantifying the overall difference between client and server states, specific observed values such as player positions tracked from multiple perspectives, and comparison metrics measuring the absolute difference between client-predicted and server-authoritative values. All experiments operate at 60 Hz, matching common game update frequencies, with network delays configured to represent typical internet latency conditions.

== Experiment 1: Isolated Movement Patterns

This initial experiment examines reconciliation behavior in a carefully controlled scenario designed to validate our fundamental theoretical predictions. By isolating player movement from complex interactions, we can observe how each reconciliation method handles the most common source of prediction errors in networked games: incomplete information about other players' actions. The experiment specifically tests whether algebraic reconciliation can match the synchronization quality of rollback reconciliation when the temporal stability assumption holds perfectly, that is, when predicted deltas remain consistent regardless of minor variations in the base state from which predictions originate.

=== Setup

The experiment employs our top-down movement game with two distinct player roles that create complementary observation perspectives. Player 1 executes a deterministic movement pattern designed to generate regular, predictable reconciliation events: 30 ticks of downward movement followed by 30 ticks of rightward movement, repeating throughout the 180-tick (3-second) experiment duration. This pattern ensures that velocity changes occur at known intervals, creating periodic challenges for the reconciliation system as the client must correct its predictions when these changes become known. Player 2 remains stationary at a fixed position, serving as an observer whose client must reconcile Player 1's movements without any local prediction of its own movement.

The network configuration simulates moderate latency conditions with a 30-tick delay in each direction, representing approximately 500ms round-trip time at 60 Hz, typical of intercontinental internet connections. This delay is substantial enough to create meaningful prediction windows where clients must operate on incomplete information, yet not so extreme as to represent unrealistic edge cases. The absence of collision interactions between players ensures that prediction errors arise solely from information delay rather than complex physical dependencies, allowing us to evaluate the pure reconciliation mechanics of each method.

=== Results

The experimental results reveal striking similarities between algebraic and rollback reconciliation, validating our theoretical predictions about convergence behavior when temporal stability assumptions are satisfied. We present three perspectives that collectively demonstrate the effectiveness of algebraic reconciliation in maintaining both state consistency and prediction responsiveness.

#let data_chart_1 = json("data/stationary-observed-player-2.json")
#figure(
  lq.diagram(
    width: 10cm,
    title: "Isolated movement from stationary perspective",
    legend: (position: bottom + left),

    lq.plot(
      data_chart_1.at("rollback_client_player-2.x"), data_chart_1.at("rollback_client_player-2.y"), label: "Rollback",
      mark: "none", stroke: (paint: blue, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("algebraic_client_player-2.x"), data_chart_1.at("algebraic_client_player-2.y"), label: "Algebraic", 
      mark: "none", stroke: (paint: purple, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("override_server.x"), data_chart_1.at("override_server.y"), label: "Server Truth",
      mark: "none", stroke: (paint: red, thickness: 2pt)
    ),
  ),
  caption: [Player 1's x-position as observed from Player 2's client perspective. The server's authoritative position (solid red) is compared with the client's synchronized view under algebraic (purple dashed), rollback (blue dashed), and override (red dashed) reconciliation strategies. The complete overlap of all three client lines demonstrates perfect convergence across all methods.]
) <fig:exp1-stationary>

Figure @fig:exp1-stationary presents the most fundamental test of reconciliation correctness: the ability to maintain consistent state for entities not under local control. From Player 2's stationary perspective, all three reconciliation methods successfully track Player 1's movement pattern, with the dashed lines representing client state perfectly overlapping across algebraic, rollback, and override strategies. This overlap is particularly significant for algebraic reconciliation, as it demonstrates that the correction term $epsilon = Delta s - Delta p$ accurately compensates for unpredicted movements without requiring state rollback or input re-simulation. The periodic shifts in the observed position correspond to Player 1's velocity changes, which propagate to Player 2's client after the network delay. The fact that algebraic reconciliation handles these discontinuous changes as effectively as rollback reconciliation validates our approach to direct algebraic correction.

#let data_chart_1 = json("data/stationary-observed-player-1.json")
#figure(
  lq.diagram(
    width: 10cm,
    title: "Isolated movement from moving perspective",
    legend: (position: bottom + left),

    lq.plot(
      data_chart_1.at("rollback_client_player-1.x"), data_chart_1.at("rollback_client_player-1.y"), label: "Rollback",
      mark: "none", stroke: (paint: blue, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("algebraic_client_player-1.x"), data_chart_1.at("algebraic_client_player-1.y"), label: "Algebraic", 
      mark: "none", stroke: (paint: purple, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("override_server.x"), data_chart_1.at("override_server.y"), label: "Server Truth",
      mark: "none", stroke: (paint: red, thickness: 2pt)
    ),
  ),
  caption: [Client-side prediction accuracy from Player 1's perspective. Both algebraic (purple dashed) and rollback (blue dashed) reconciliation produce identical predictions that maintain a consistent offset from the server's authoritative state (red solid), demonstrating equivalent prediction quality.]
) <fig:exp1-moving-comparison>

The perspective from Player 1's client, shown in Figure @fig:exp1-moving-comparison, reveals the prediction dynamics that make modern networked games playable despite latency. Both algebraic and rollback reconciliation maintain identical prediction trajectories, consistently leading the server's authoritative position by approximately 30 ticks, exactly the network delay period. This offset represents the fundamental characteristic of client-side prediction: the client shows where the player will be once the server processes their inputs, not where the server currently believes them to be. The perfect alignment between algebraic and rollback predictions confirms that our method preserves the essential responsiveness of client-side prediction while eliminating the computational overhead of repeated simulation. The smooth transitions at velocity change points (every 30 ticks) demonstrate that both methods handle prediction updates gracefully, without introducing additional artifacts or discontinuities.

#let data_chart_1 = json("data/stationary-observe-comparison.json")
#figure(
  lq.diagram(
    width: 10cm,
    title: "Isolated movement - strategy comparison",
    legend: (position: bottom + left),

    lq.plot(
      data_chart_1.at("algebraic_client_player-1.x"), data_chart_1.at("algebraic_client_player-1.y"), label: "Algebraic", 
      mark: "none", stroke: (paint: purple, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("override_client_player-1.x"), data_chart_1.at("override_client_player-1.y"), label: "Override",
      mark: "none", stroke: (paint: red, thickness: 2pt, dash: "dashed")
    ),
  ),
  caption: [Comparison of prediction responsiveness between algebraic (purple dashed) and override (red dashed) reconciliation from Player 1's perspective. The stair-step pattern in override reconciliation reflects the 30-tick delay between input and visible effect, while algebraic reconciliation provides immediate visual feedback.]
) <fig:exp1-override>

Figure @fig:exp1-override starkly illustrates why naive override reconciliation creates an unacceptable player experience in interactive games. The override method's characteristic stair-step pattern reveals the full network round-trip delay between player input and visual feedback: each movement command initiated by Player 1 only becomes visible after traveling to the server and back, creating a 60-tick (1-second) perceived lag. In contrast, algebraic reconciliation maintains smooth, immediate response to inputs, with position updates appearing instantaneously from the controlling player's perspective. The periodic convergence points where both lines intersect represent moments when the server state finally catches up to where the client was 30 ticks earlier, confirming that both methods eventually achieve consistency despite their radically different user experiences. This comparison underscores that algebraic reconciliation preserves the essential benefit of client-side prediction, responsive controls, while achieving it through direct algebraic operations rather than speculative simulation.

=== Analysis

The results from this foundational experiment provide strong empirical support for algebraic server reconciliation as a viable alternative to rollback-based methods. Several key observations emerge from the data that validate our theoretical framework and demonstrate practical applicability.

The complete convergence achieved by all three methods when observing non-controlled entities confirms that algebraic reconciliation correctly handles the most common case in multiplayer games: synchronizing the positions of other players. The mathematical elegance of the correction formula $epsilon = Delta s - Delta p$ translates directly into practical effectiveness, producing state updates indistinguishable from those achieved through the more computationally expensive rollback and re-simulation process. This equivalence holds even across discontinuous velocity changes, demonstrating robustness to the types of sudden state transitions common in interactive games.

From the controlling player's perspective, algebraic reconciliation achieves the critical goal of preserving prediction quality while eliminating re-simulation overhead. The identical prediction trajectories produced by algebraic and rollback methods confirm that our approach maintains the same subjective experience of responsiveness that makes client-side prediction essential for networked games. With a 30-tick network delay, rollback reconciliation would need to re-simulate up to 30 frames of game logic for each server update, a computational burden that algebraic reconciliation reduces to a single vector addition operation.

The stark contrast with override reconciliation reinforces the necessity of prediction-based approaches for interactive games. The one-second perceived lag demonstrated by override reconciliation would render most action games unplayable, yet this is precisely the experience players would have without some form of client-side prediction. Algebraic reconciliation achieves the same responsive feel as rollback methods while requiring significantly less computational resources, making it particularly attractive for mobile platforms or games with numerous predicted entities.

This experiment establishes that under conditions where the temporal stability assumption holds, such as simple movement without complex state interactions, algebraic server reconciliation performs identically to rollback reconciliation from a behavioral perspective while offering clear computational advantages. The next experiments will explore how this performance translates to scenarios involving physical collisions and state-dependent dynamics that challenge our foundational assumptions.

== Experiment 2: Collision Dynamics and State Dependencies

The previous experiment validated algebraic reconciliation under ideal conditions where state changes remain independent and predictable. Real-world game scenarios, however, frequently involve complex interactions between entities that create state dependencies and violate our temporal stability assumptions. This experiment introduces physical collisions between players to examine how algebraic reconciliation behaves when physics constraints force states to diverge from their predicted trajectories. By analyzing the reconciliation behavior during and after collision events, we can identify the practical limitations of our method and understand the error characteristics that emerge when mathematical assumptions encounter physical reality.

=== Setup

This experiment employs the same top-down movement game but introduces a direct collision scenario designed to maximally stress the reconciliation system. Two players are positioned to create an inevitable head-on collision: Player 1 starts at position (-200, 150) moving rightward at constant velocity, while Player 2 begins at (200, 140) moving leftward at the same speed. The slight vertical offset ensures the collision occurs at an angle, creating forces in both x and y dimensions that challenge the prediction system in multiple axes simultaneously.

The physics engine enforces a hard constraint that player collision volumes cannot overlap, forcing the simulation to resolve conflicts by pushing players apart when they attempt to occupy the same space. This constraint fundamentally violates our temporal stability assumption: when a client predicts its own movement without knowledge of the impending collision, it generates deltas that assume unimpeded motion. The server, processing both players' movements simultaneously, generates different deltas that account for the collision forces. This divergence between predicted and actual deltas provides an ideal test case for understanding how algebraic reconciliation handles state-dependent interactions.

We conduct the experiment at three different network delays, 15, 30, and 45 frames, to observe how latency affects the magnitude and duration of reconciliation errors. Each test runs for 180 frames (3 seconds at 60 Hz), sufficient to capture the complete collision event including approach, contact, separation, and post-collision reconciliation. The collision typically occurs around frame 60, allowing observation of both pre-collision prediction accuracy and post-collision error recovery.

=== Results

The experimental data reveals distinct behavioral patterns in how algebraic reconciliation handles collision-induced state dependencies, with notable differences between axis behavior and observation perspective. We present the results organized by axis to highlight the different error characteristics that emerge in the primary movement direction versus the perpendicular collision response direction.

==== X-Axis Behavior

The x-axis represents the primary movement direction for both players, where intentional inputs drive the motion and collisions directly oppose the intended movement. This axis best demonstrates how reconciliation methods handle the conflict between predicted motion and physics-constrained reality.

#let data_chart_1 = json("data/collision-x-observed-player-1.json")
#figure(
  lq.diagram(
    width: 10cm,
    title: "Players own X axis movement during collision",
    legend: (position: bottom + right),

    lq.plot(
      data_chart_1.at("rollback_client_player-1.x"), data_chart_1.at("rollback_client_player-1.y"), label: "Rollback", 
      mark: "none", stroke: (paint: blue, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("algebraic_client_player-1.x"), data_chart_1.at("algebraic_client_player-1.y"), label: "Algebraic", 
      mark: "none", stroke: (paint: purple, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("override_server.x"), data_chart_1.at("override_server.y"), label: "Server Truth",
      mark: "none", stroke: (paint: red, thickness: 2pt)
    ),
  ),
  caption: [Player 1's x-position observed from their own perspective during collision. Both algebraic (purple dashed) and rollback (blue dashed) reconciliation show similar overshooting behavior relative to the server state (red solid), indicating comparable prediction behavior when movement intentions conflict with physics constraints.]
) <fig:exp2-x-moving>

Figure @fig:exp2-x-moving demonstrates that from the controlling player's perspective, algebraic and rollback reconciliation produce nearly identical predictions along the primary movement axis. Both methods overshoot the server's position by approximately 40 units at the peak, reflecting the fundamental challenge of predicting through an unknown collision. The overshoot occurs because the client continues predicting rightward movement while the server has already processed the collision and stopped forward progress. The subsequent convergence shows both methods successfully reconciling to the server state once the collision information propagates through the network delay. The slight divergence between algebraic and rollback traces during the collision phase (frames 50-90) suggests minor differences in how the methods handle the rapid state changes, but these differences remain visually negligible from the controlling player's perspective.

#let data_chart_1 = json("data/collision-x-observed-player-2.json")
#figure(
  lq.diagram(
    width: 10cm,
    title: "Other players X axis movement during collision",
    legend: (position: bottom + right),

    lq.plot(
      data_chart_1.at("rollback_client_player-2.x"), data_chart_1.at("rollback_client_player-2.y"), label: "Rollback", 
      mark: "none", stroke: (paint: blue, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("algebraic_client_player-2.x"), data_chart_1.at("algebraic_client_player-2.y"), label: "Algebraic", 
      mark: "none", stroke: (paint: purple, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("override_server.x"), data_chart_1.at("override_server.y"), label: "Server Truth",
      mark: "none", stroke: (paint: red, thickness: 2pt)
    ),
  ),
  caption: [Player 1's x-position as observed from Player 2's perspective. The algebraic method (purple dashed) shows slightly greater deviation from the server state compared to rollback (blue dashed), revealing increased error when observing other players during collisions.]
) <fig:exp2-x-other>

The view from Player 2's perspective, shown in Figure @fig:exp2-x-other, reveals a subtle but important difference between the reconciliation methods. The algebraic approach produces slightly larger deviations from the server state when observing the other player's collision response. This increased error for non-controlled entities suggests that the algebraic correction term ε = Δs - Δp becomes less accurate when applied to states affected by multi-entity interactions, as the correction computed for one player's movement doesn't fully account for the coupled dynamics introduced by the collision.

#let data_chart_1 = json("data/collision-x-compare-player-1.json")
#figure(
  lq.diagram(
    width: 10cm,
    title: "Difference to server of \nplayers own X axis movement during collision",
    legend: (position: top + right),

    lq.plot(
      data_chart_1.at("override_client_player-1.x"), data_chart_1.at("override_client_player-1.y"), label: "Override", 
      mark: "none", stroke: (paint: red, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("algebraic_client_player-1.x"), data_chart_1.at("algebraic_client_player-1.y"), label: "Algebraic", 
      mark: "none", stroke: (paint: purple, thickness: 2pt, dash: "dashed")
    ),
  ),
  caption: [Absolute difference from server x-position for Player 1's own view. Algebraic reconciliation (purple dashed) maintains significantly lower error than override reconciliation (red dashed), though both methods struggle during the collision event.]
) <fig:exp2-x-diff-self>


#let data_chart_1 = json("data/collision-x-compare-player-2.json")
#figure(
  lq.diagram(
    width: 10cm,
    title: "Difference to server of \nother players X axis movement during collision",
    legend: (position: top + right),

    lq.plot(
      data_chart_1.at("override_client_player-2.x"), data_chart_1.at("override_client_player-2.y"), label: "Override", 
      mark: "none", stroke: (paint: red, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("algebraic_client_player-2.x"), data_chart_1.at("algebraic_client_player-2.y"), label: "Algebraic", 
      mark: "none", stroke: (paint: purple, thickness: 2pt, dash: "dashed")
    ),
  ),
  caption: [Absolute difference from server x-position when Player 2 observes Player 1. The algebraic method (purple dashed) shows periods of higher error than override (red dashed), particularly during collision resolution.]
) <fig:exp2-x-diff-other>

Figures @fig:exp2-x-diff-self and @fig:exp2-x-diff-other compare the absolute error magnitudes between algebraic and override reconciliation. From the controlling player's perspective, algebraic reconciliation achieves substantially lower error throughout most of the simulation, with peak errors during collision approximately 50% lower than override. However, when observing other players, algebraic reconciliation occasionally produces higher errors than override, particularly during the collision resolution phase. This asymmetry suggests that while algebraic reconciliation excels at maintaining responsive control for the local player, it may introduce artifacts when synchronizing observed entities during complex interactions.

==== Y-Axis Behavior  

The y-axis behavior provides unique insights into reconciliation accuracy because neither player intentionally moves along this axis, all y-displacement results from collision forces. This allows us to isolate the reconciliation of unpredicted, physics-induced state changes from the reconciliation of intended movements.

#let data_chart_1 = json("data/collision-y-observed-player-1.json")
#figure(
  lq.diagram(
    width: 10cm,
    title: "Players own X axis movement during collision",
    legend: (position: bottom + right),

    lq.plot(
      data_chart_1.at("rollback_client_player-1.x"), data_chart_1.at("rollback_client_player-1.y"), label: "Rollback", 
      mark: "none", stroke: (paint: blue, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("algebraic_client_player-1.x"), data_chart_1.at("algebraic_client_player-1.y"), label: "Algebraic", 
      mark: "none", stroke: (paint: purple, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("override_server.x"), data_chart_1.at("override_server.y"), label: "Server Truth",
      mark: "none", stroke: (paint: red, thickness: 2pt)
    ),
  ),
  caption: [Player 1's y-position during collision as seen from their own perspective. The algebraic method (purple dashed) exhibits characteristic overcorrection, overshooting the server position (red solid) more dramatically than rollback reconciliation (blue dashed).]
) <fig:exp2-y-moving>

Figure @fig:exp2-y-moving reveals the most distinctive characteristic of algebraic reconciliation under violated assumptions: systematic overcorrection. When the server's collision-induced y-displacement arrives at the client, the algebraic method applies this correction to a state that has already been predicting collision effects based on incomplete information. The result is a compounding of corrections that pushes the y-position beyond the server's value by approximately 20 units. This overcorrection gradually resolves as subsequent server updates arrive, but the pattern clearly shows the algebraic method struggling to handle state changes that depend on information not available during prediction.

#let data_chart_1 = json("data/collision-y-observed-player-2.json")
#figure(
  lq.diagram(
    width: 10cm,
    title: "Other players X axis movement during collision",
    legend: (position: top + right),

    lq.plot(
      data_chart_1.at("rollback_client_player-2.x"), data_chart_1.at("rollback_client_player-2.y"), label: "Rollback", 
      mark: "none", stroke: (paint: blue, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("algebraic_client_player-2.x"), data_chart_1.at("algebraic_client_player-2.y"), label: "Algebraic", 
      mark: "none", stroke: (paint: purple, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("override_server.x"), data_chart_1.at("override_server.y"), label: "Server Truth",
      mark: "none", stroke: (paint: red, thickness: 2pt)
    ),
  ),
  caption: [Absolute y-position error from Player 1's perspective. The algebraic method (purple dashed) shows a characteristic double-peak pattern, with the second peak representing the overcorrection artifact unique to this reconciliation approach.]
) <fig:exp2-y-diff-self>

The error analysis in Figure @fig:exp2-y-diff-self provides crucial insight into the overcorrection mechanism. Both methods exhibit an initial error peak when the collision occurs without prediction, but algebraic reconciliation uniquely produces a second, smaller peak approximately 30 frames later. This secondary peak corresponds to the overcorrection being resolved as the server state confirms the players have separated. The double-peak pattern is pathognomonic of algebraic reconciliation's response to state-dependent dynamics: the method first overcorrects when applying delayed corrections to an already-evolved state, then must correct the overcorrection once the dependency resolves.

#let data_chart_1 = json("data/collision-y-compare-player-1.json")
#figure(
  lq.diagram(
    width: 10cm,
    title: "Difference to server of \nplayers own Y axis movement during collision",
    legend: (position: top + right),

    lq.plot(
      data_chart_1.at("override_client_player-1.x"), data_chart_1.at("override_client_player-1.y"), label: "Override", 
      mark: "none", stroke: (paint: red, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("algebraic_client_player-1.x"), data_chart_1.at("algebraic_client_player-1.y"), label: "Algebraic", 
      mark: "none", stroke: (paint: purple, thickness: 2pt, dash: "dashed")
    ),
  ),
  caption: [Player 1's y-position observed from Player 2's perspective. The algebraic method (purple dashed) shows substantially larger deviation from the server state (red solid) compared to rollback (blue dashed).]
) <fig:exp2-y-other>

#let data_chart_1 = json("data/collision-y-compare-player-2.json")
#figure(
  lq.diagram(
    width: 10cm,
    title: "Difference to server of \nother players Y axis movement during collision",
    legend: (position: top + right),

    lq.plot(
      data_chart_1.at("override_client_player-2.x"), data_chart_1.at("override_client_player-2.y"), label: "Override", 
      mark: "none", stroke: (paint: red, thickness: 2pt, dash: "dashed")
    ),
    lq.plot(
      data_chart_1.at("algebraic_client_player-2.x"), data_chart_1.at("algebraic_client_player-2.y"), label: "Algebraic", 
      mark: "none", stroke: (paint: purple, thickness: 2pt, dash: "dashed")
    ),
  ),
  caption: [Y-position error magnitude when Player 2 observes Player 1. The algebraic method (purple dashed) produces errors more than twice as large as rollback reconciliation (blue dashed), highlighting the method's weakness in synchronizing observed collision dynamics.]
) <fig:exp2-y-diff-other>

The degradation of algebraic reconciliation becomes most apparent when examining y-axis synchronization from the observing player's perspective, shown in Figures @fig:exp2-y-other and @fig:exp2-y-diff-other. The error magnitude for algebraic reconciliation exceeds rollback by a factor of two or more during the collision event, with peak errors reaching nearly 50 units compared to rollback's 20-unit maximum. This dramatic difference indicates that algebraic reconciliation's assumptions break down severely when reconciling observed entities whose states depend on complex multi-body interactions.

=== Analysis

The collision experiment exposes both the capabilities and limitations of algebraic server reconciliation when faced with state-dependent dynamics that violate temporal stability assumptions. Several critical insights emerge from the data that inform practical deployment decisions.

The method demonstrates acceptable performance along axes where player input directly drives motion, maintaining prediction quality comparable to rollback reconciliation from the controlling player's perspective. This suggests that even during complex interactions, algebraic reconciliation can preserve the responsive feel essential for playability when the primary motion remains input-driven. The systematic overcorrection observed in the perpendicular axis, while visually detectable, remains within tolerable bounds for the controlling player and resolves within approximately one network round-trip time.

However, the significant error amplification when observing other players during collisions represents a serious limitation. The two-fold or greater increase in synchronization error compared to rollback reconciliation could produce visible artifacts in multiplayer scenarios with frequent player interactions. The root cause appears to be the fundamental assumption that predicted deltas remain stable regardless of base state variations, an assumption thoroughly violated when collision forces create coupled dynamics between multiple entities.

The asymmetric error characteristics, lower error for controlled entities, higher error for observed entities, suggest a hybrid deployment strategy might be optimal. Games could employ algebraic reconciliation for player-controlled entities where responsiveness is paramount and computational savings are valuable, while using rollback reconciliation for observing other players where accuracy matters more than computational efficiency. This selective application would leverage the strengths of each method while mitigating their respective weaknesses.

The temporal pattern of overcorrection and recovery provides guidance for potential improvements to the algebraic method. The predictable nature of the overcorrection, always occurring one network delay after the initial collision, suggests that adaptive correction factors or damping terms could reduce the artifact magnitude without sacrificing the method's computational advantages. Future work might explore such enhancements to extend algebraic reconciliation's applicability to more complex interaction scenarios.

= Discussion

// - we have seen that not only there exist many networking approaches but also variations
// - many networking approaches have oppurtunities for optimization. for example, if only small
// parts of world are static, then implementing rollback synchronization can be cheap. 
// - if state changes that need to be predicted are generally small enough, one can also go an approach
// like minecraft by sending the state from the client. This makes development cost cheaper.
// - in the end it is often a tradeoff between performance, consistency and security. As for example the
// minecraft approach lacks strong security mechanisms.
// - our introduced method uses techniques already widely known and used in the software industry, for example in 
// databases or user applications.
// - our method does not work in cases with strong dependencies between states or states with entities without
// identity. this is especially a problem in sandbox games but even more so in voxel games. the problem with voxel
// games as previously explained is that blocks by design do not have an identity but its position. This makes the 
// use of algebraic networking impossible
// - but the amount of multiplayer games who can benefit from algebraic reconciliation is still significant.
// - networking methods shouldnt be seen as absolute approaches but in combination. 
// - since mutliplayer games can employ specific opimizations depending on their world model, each game will most
// likely have their custom solution. while this might not make sense for small indie studios, this is especially
// relevant for big projects.
// - therefore we can say, that modern projects will use a hybrid approach, where the state is sliced into multiple parts.
// some parts of the state which does not directly depend on many other parts of the state, can easily be synchronized 
// using algebraic server reconciliation. this method can then be thought of an extension to CRDTs.
// - while crdts try to be commutative with everything, the idea behind algebraic server reconciliation is that we still
// have a central server. we exploit this fact when using them.
// - our contribution is not only a new apporach to game networking, but also in a possible way to formilize game networking in general
// and how to build abelian groups for almost any game.

= Future work

// - one of the core aspects we did not explore are hybrid models. approaches where we could use some reconciliation
// methods for one part of the state and others for other parts of the state.
// - we did not implement a full game based on the approaches presented here, which would be the next logical step
// to show that our method is relevant in the industry.
// - there are many possible optimizations which can be implemented to further enhance our method. for example one could
// be inspired by minecraft and send merkel trees of the state deltas to the server. the server can now decide which users
// actually need state updates. games with big states could thereof save state transmission, which is most commonly correctly
// predicted.

/*
- Since operating on deltas compared to full state has many advantages. Does operating on higher derivatives have even more advantages? This would solve the problem of falling or shooting things and the system would adjust.
- We could instead of just adding the computed epsilon on top of the present, use a PID regulator to add it. The idea would be to reduce the amount of oscilliation in the system which is caused by overshooting errors.
*/
