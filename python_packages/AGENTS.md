# Workspace Notes

This directory is mounted into Docker containers as /python_packages.

## Quick Context
- Any required dependencies or tools can be installed globally into the Docker container, but if we need them long term we'll want to add them to the Dockerfile and rebuild the container.

## Agent Hints
- For generic Python packages, warn if we introduce breaking changes. For application specific code (e.g. juggling), don't worry about backward compatibility and keep it clean instead.
- Compose code such that it can be easily reused in new projects.
