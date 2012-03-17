

from http://rfc.zeromq.org/spec:7
"The Majordomo Protocol (MDP) defines a reliable service-oriented
request-reply dialog between a set of client applications, a broker
and a set of worker applications. MDP covers presence, heartbeating,
and service-oriented request-reply processing. It originated from the
Majordomo pattern defined in Chapter 4 of the Guide."

This is an implementation for Haskell.
Examples of use can be found in echo_worker.hs and mdp_client.hs
(which doubles as a helpful command line tool for issuing MDP commands)
