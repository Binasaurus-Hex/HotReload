# Hot Reload
short example code for hot reloading in odin
contains an automatic serialization system, allowing for changes to data structures to be made at runtime
this system doesnt serialize
  - maps
  - dynamic arrays
  - pointers
and will instead just zero initialize the memory
