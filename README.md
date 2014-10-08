oit
===

An order-independent transparency demo framework, including optimizations and benchmark support.

NOTE: I haven't had time to prettify everything (I won't argue with people calling the code a mess)
or test windows (currently using fedora). However, I do plan to at some point.

A little description of OIT and this code is here: http://heuristic42.com/opengl/oit/

This code, and the LFB depndency, is the source code for
*Efficient Layered Fragment Buffer Techniques* (well, updated source),
*Backwards Memory Allocation and Improved OIT* and
*Fast Sorting for Exact OIT of Complex Scenes* found [here](http://heuristic42.com/research/).

This project requires the following two to be in the same directory. I.e. `/path/oit/`, `/path/lfb/` and `/path/pyarlib`.

- https://github.com/pknowles/lfb
- https://github.com/pknowles/pyarlib

Models/meshes are not in the repository. Most can be found here: http://goanna.cs.rmit.edu.au/~pknowles/models.html.
The scenes are stored in xml files, and model search paths are specified in `config.cfg`.
Currently `obj`, [`ctm`](http://openctm.sourceforge.net/) and `3ds` are the main supported model formats.
