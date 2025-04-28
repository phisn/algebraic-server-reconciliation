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
  title: "Master Thesis \n Algebraic Server Reconciliation for Online Games",
  authors: ("Philipp Hinz \n Supervised by Dr.-Ing. Guido Rößling", ),
  date: datetime.today().display("[day]. [month repr:long] [year]"),
)

#pagebreak()
= Modelling

We define a game world using a game state $S$, an initial game state $s_0 in S$ and a progression function $f: (S, I) -> S$ as $G = (S, s_0, f)$ where $I$ is some external input. A game state at time $t$ can be progressed using some input $i_t in I$ to time $t + 1$ using the progression function: $s_(t + 1) = f(s_t, i_t)$. We can combine the input and state to a frame $r_t = (s_t, i_t)$. 

We say that a machine $m in M$ is running the game $G$ with state $s_t$ at some time $t$. Clients are machines $c in C subset.eq M$ which contribute input $i^c_t in I^c$ to form the whole input $i^c_t in i_t$. We assume that one machine is designated as the host and all clients can only communicate with the host. The state on the host is considered the truth if states between machines differ.

== Naive model

We have one host $h$ and $n$ clients $c_i$. Each client $c$ has a round trip time of $t^r_c$. We define the round trip time as the sum of the send $t^s_c$ and receive $t^e_c$ latency $t^r_c = t^s_c + t^e_c$. At each tick, the host sends its state $s_t$ to each client and each client sends input $i^c_t$. 

Both the client and the host run with a fixed time interval $t^i$ which is usually smaller than $t^r_c$. Therefore the host can not wait with processing all input $i^c_t$ and will use the most recent input instead. This means that each client will only be able to react with input $i^c_t$ to state $s_(t - t^r_c)$. We call this the naive model. 

== Fair naive model

Each client $c$ can only respond to a state $s_t$ with an input arriving at the host $t^r_c$ time later. Since $t^r_c$ is different for every player, this is not fair. We define a fair model as: given a fixed delay $delta$ every client can respond to the same state $s_t$ with input $i^c_(t + delta)$. We can make the previous model fair by only processing input on the host, once we received input from all players. Every player is able to react to state $s_t$ with the same delay of $delta = max_i t^r_i$. Intuitively, we artificially delay what each player can see to the slowest player. We call this the fair naive model.

Many games are based on reaction, doing an action in response to an event. A major problem with the (fair) naive model is that player inputs in reaction to a present state will only be applied to a future state one the host.

== Lockstep

In the fair naive model the host is applying old inputs because the interval time is fixed and usually faster than $t^r_c$. We can loosen this requirement and assume a dynamic interval time. Players only send input $i^c_t$, after receiving $s_t$. The host only progresses to state $s_(t + 1)$ when all $i^c_t$ arrived. We now have a fair game while giving players the most recent information to react. 

This model is known as the lockstep model and popular in strategy games, where latency or a longer interval are not a big problem.

== Player observation limitation

We are bound in the time a player is able to react to other players inputs. One player has to first send their inputs and another player can only then receive them. Any changes to the state from player $c'$ will never be visible to an other player $c$ faster than $t^e_c + t^s_c'$.

When the interval rate is fixed to a time $delta < t^e_c + t^s_c'$, which is usually the case, a client $c$ will already have made an input $i^c_(t + 1)$ without there beeing a possibility of receving input $i^c'_t$ from client $c'$. Therefore according to our defintion, games with a fixed interval can not be fair. 

== Client side prediction

In the (fair) naive model, a client will only be able to apply their input $i^c_t$ to a state $s_(t - t^r_c)$. Therefore a client sees responses to their own input with a latency of $t^r_c$.

While we previously showed an absolute limitation in seeing other players inputs, there is no such limitation on seeing state changes to your own inputs. We define a prediction function $f^p: I^c times S -> S$ which only progresses the state based on one single client input $i^c_t$. Each client now receives state $s_t$ and directly applies their input to get predicted state $p^c_(t + 1) = f^p  (i^c_t, s_t)$. Since responses to $i^c_t$ will be received in $s_(t + t^r_c)$, we predict the state up to $p^c_(t + t^r_c)$. This method is called client-side prediction and used in most modern games as it provides the user with instantous feedback - making gameplay fluent. 

The difficulty with this method is to apply new incoming host state $s_(t + 1)$ correctly. Given a client predicted $p^c_(t + t^r_c)$, it will receive an response to input $i^c_t$ in at least $t^r_c$ time as the state $s_(t + t^r_c)$. An previous state change arriving as $s_(t + 1)$ would override our predicted state $p^c_(t + t^r_c)$ making the game snap caused by the time difference. The original solution to this problem is to not replace our current state but define a partial application function $f^"partial": S times S -> S$ which compares the predicted state with the actual state and only replaces diverging parts. During normal operation, the prediction will be close enough causing only rare desynchronizations which will be visually visible as snapping. We observe, that some parts of the state will always diverge, if state changes are caused by other players or randomness. 

One very popular game that is using slightly modified variation of this method is minecraft. In minecraft the game does not send its direct inputs, but its predicted state. Most important parts of the state to be predicted are breaking blocks and all character movement. The partial application does not happen at client side, but on host side. Therefore the host validates if the incoming input looks good enough and doesnt resimulate it if not necessary. When detecting diverging state, the host sends state correction. Unfortunately this limits anti-cheat capabilities to how sophisticated the validation in the partial application function is.

One major problem with client side reconciliation is that finding a good partial application function can be difficult. The reason is that we are looking at divergences between $s_(t + 1)$ and $p^c_(t + t^r_c)$, therefore a difference in time of $t^r_c - 1 approx t^r_c$. Therefore even a perfect prediction will divergence in scale of the round trip time. 

One alternative approach would be to not compare the current state for divergence, but memorize past states. Given a interval time of $t^i$, the client needs to memorize $n_"predict" = t^r_c slash t^i$ gamestates, which can be partial states. This solution unfortunately doesnt solve the snapping when divergences are found, since it forces the client from a predicted state in time $t + t^r_c$ to $t + 1$.

== Server reconciliation
When merging an update $s_(t + 1)$ with an diverged predicted state $p^c_(t + t^r_c)$, we previously overrode the state with current state $s_(t + 1)$. This skip from $t + t^r_c$ to $t + 1$ causes snapping. What we can do alternatively is to memorize inputs $i^c_k: t + 1 <= k <= t + t^r_c$. We replace our state with $s_(t + 1)$ and then apply all memorized inputs to get an alternative predicted state $p^c_(t + t^r_c) '$, which would have been reached, if the divergence didnt happen. Since we now have a state in time $t + t^r_c$ we do not have snapping behavior. This method is called rollback server reconciliation and one of the most fundamental techniques in modern games.

Server reconciliation is the process of combining a past received state $s_t$ to a present predicted state $p^c_(t + t^r_c)$. Our partial application function is a form of server reconciliation. The goal is to fix divergences in state without the user noticing.

Unforutnately since we have to rollback to the last received state, we must memorize all predicitions we made. In the worst case we memorize the whole $s_t$. When receiving $s_t$ we apply the prediction function $n_"predict"$ times. Therefore an input $i^c_t$ is the first time predicted at $t - n_"predict"$ and the last time at $t$. So the each input is processed by the client $n_"predict"$ times. This means that especially clinets with longer ping have to do more processing, increasing with smaller tick interval.

== Delta State
The host is sending the whole state $s_t$ each tick. This means we will send redundant data as the state changes rarely completely. We define delta states $Delta s_t in Delta S$ as changes in state which can be applied using a delta application function $f^A: S -> Delta S -> S$. We define a alternative progression function $f^Delta: I -> S -> Delta S$ retuning an delta instead of the whole state. We can derive the original progression function as $f = f^A (s_t, f^Delta (i_t, s_t))$, therefore all our previous results hold true when using delta state. The host will each tick send $Delta s_t$ to the clients. A client still has currently loaded a state $s$. 

== Algebraic server reconciliation
