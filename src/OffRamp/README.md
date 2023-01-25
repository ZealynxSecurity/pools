# Off Ramp

The Off Ramp flows through 4 main functions, with some aggregegate helpers and setters to fill out the objective functional space. The main four functions are:

Distribute - Pumps value into the Off Ramp from the connected contract. For our use case this will almost always be a pool, but it can be an EOA in cases where
a third party or third party services aims to make good on a Pools accounting defficits. Functionally this increases the _buffer_ of funds to be distributed

Stake - 