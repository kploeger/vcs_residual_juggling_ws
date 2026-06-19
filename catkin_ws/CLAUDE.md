# Workspace Notes

This directory is mounted into Docker containers as /catkin_ws.

## Quick Context
- Build system: catkin build (ROS Noetic workspace)
- Source tree: src/
- Setup files: devel/setup.bash, devel/setup.zsh

## Agent Hints
- For generic ROS packages, warn if we introduce breaking changes. For application specific code (e.g. juggling), don't worry about backward compatibility and keep it clean instead.
- Compose code such that it can be easily reused in new projects.
- Deferred bugs go in `/catkin_ws/KNOWN_BUGS.md`. When we notice a bug but decide not to fix it right now (wrong scope, different branch, low priority, coincidentally harmless, etc.), add an entry with a file:line citation, a one-paragraph description, the proposed fix, and a "why deferred" note. Check this file opportunistically when touching related code.
