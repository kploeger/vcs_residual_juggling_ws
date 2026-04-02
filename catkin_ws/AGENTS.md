# Workspace Notes

This directory is mounted into Docker containers as /catkin_ws.

## Quick Context
- Build system: catkin build (ROS Noetic workspace)
- Source tree: src/
- Setup files: devel/setup.bash, devel/setup.zsh

## Agent Hints
- For generic ROS packages, warn if we introduce breaking changes. For application specific code (e.g. juggling), don't worry about backward compatibility and keep it clean instead.
- Compose code such that it can be easily reused in new projects.
