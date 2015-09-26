Order-Independent Transparency (OIT)
===

An order-independent transparency demo framework, including optimizations and benchmark support. With [published strategies](http://www.heuristic42.com/users/4/pknowles/about/) for fast sorting, this demo shows performance improvements over the basic per-pixel linked lists method of up to a factor of 5 or more.

NOTE: I haven't had time to prettify everything (I won't argue with people calling the code a mess).
There are makefiles for **gcc/Fedora 20** and solution/project files tested with **vs2013/Windows 7**.

A little description of OIT and this code is here: http://www.heuristic42.com/5/opengl/oit/

This code, and the LFB depndency, is the source code for
*Efficient Layered Fragment Buffer Techniques* (well, updated source),
*Backwards Memory Allocation and Improved OIT* and
*Fast Sorting for Exact OIT of Complex Scenes* found [here](http://www.heuristic42.com/users/4/pknowles/about/).

This project requires the following two to be in the same directory. I.e. `/path/oit/`, `/path/lfb/` and `/path/pyarlib`.

- https://github.com/pknowles/lfb
- https://github.com/pknowles/pyarlib

Methods in the layered fragment buffer (LFB) repository are also called Per-Pixel Linked Lists (PPLLs), the A-Buffer (at a stretch IMO), the Dynamic Fragment Buffer (DFB). The S "sparsity", L "multi-layered framebuffer condensation", D "deque" buffers are also quite closely related. See [http://en.wikipedia.org/wiki/Order-independent_transparency](http://en.wikipedia.org/wiki/Order-independent_transparency).

Models/meshes are not in the repository. Most can be found here: http://goanna.cs.rmit.edu.au/~pknowles/models.html.
The scenes are stored in xml files, and model search paths are specified in `config.cfg`.
Currently `obj`, [`ctm`](http://openctm.sourceforge.net/) and `3ds` are the main supported model formats.

## Controls

- \` - toggle HUD
- space - toggle camera lock to origin
- w/a/s/d - fly
- mouse drag - left/middle/right to rotate/pan/zoom
- 1-6 - load scene
- b - execute benchmark (must provide test xml file as argument)
- h - find maximum depth complexity
- z - rotate 360 degrees, recording times
- q - enable scene edit mode (very simple maya-like e/r/t move/rotate/scale)
