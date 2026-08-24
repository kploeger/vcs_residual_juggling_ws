# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Context

- Build system: `catkin build` (ROS Noetic workspace)
- Source tree: `src/`
- Setup files: `devel/setup.bash`, `devel/setup.zsh`
- Mounted into Docker containers as `/catkin_ws`; `/python_packages` is a second mount with non-ROS Python packages (auto-pip-installed on container start)

## Build & Run

```bash
# Build the workspace
catkin build

# Build a single package
catkin build <package_name>

# Source the workspace (required in every new shell)
source /catkin_ws/devel/setup.bash

# Simulate a single WAM
roslaunch wam_bringup wam.launch sim:=mujoco

# Real WAM (CAN port 0, 4-DOF by default)
reset_can.sh
roslaunch wam_bringup wam.launch

# Dual WAM (real or sim)
roslaunch wam_bringup double_wam.launch sim:=mujoco
```

Key `wam.launch` arguments: `sim:=real/mujoco`, `port:=0/1`, `robot_name:=wam/wam29/wam73/wam79`, `dof:=4/7`, `controller`, `urdf_xacro`, `mj_xml_file`, `render:=true/false`.

## Tests

```bash
# ROS/catkin tests for a package
catkin test <package_name>

# Run a specific Python test node directly
python3 src/robot_controllers/wam_controllers/tests/test_observer.py
```

## Architecture

### Hardware abstraction
`wam_driver` (real hardware via libbarrett/CAN) and `wam_mujoco_driver` (MuJoCo physics) expose identical `ros_control` hardware interfaces. Swap between them via `sim:=real/mujoco` in launch files — application code is unaware of which is active.

### Controller framework
ROS-control based. Controllers are loaded from YAML configs in `wam_control/config/` and `wam_controllers/config/`. The `wam_controllers` package adds WAM-specific controllers (torque, position, trajectory). Default controller: `motor_enc_joint_trajectory_controller`.

### Double encoder support
Real WAMs have motor encoders + joint encoders on joints 1–4. Select fusion strategy via `hw_interface_joint_state_fusion_strategy` param (e.g. `joint_pos_motor_vel` is default). Extra virtual joints can be exposed via `hw_interface_offer_joints_*` flags.

### MuJoCo driver plugin system
`wam_mujoco_driver` uses pluginlib — custom simulation logic (sensors, disturbances, object interactions) is implemented as plugins, decoupled from the driver itself. See `example_juggling_wam_mujoco_driver_with_plugin.launch` for an example.

### Robot descriptions
Three ROS param variants published per robot:
- `robot_description` — full scene (for rviz)
- `[robot_name]/robot_description` — single robot
- `[robot_name]/robot_description_simple` — without dummy encoder joints

Custom URDFs: use `urdf_xacro` arg pointing to your xacro. Use `wam_description/xacro/robots/wam.urdf.xacro` as a starting point.

### Juggling application stack
`juggling_demos` nodes orchestrate the full juggling pipeline:
- Trajectory planning via `/python_packages/trajectory_planning` (CasADi + Pinocchio)
- Ball state estimation via `optitrack-ball-tracker` (NatNet → Kalman filter → ROS topics)
- Physical ball launch via `ball_launcher` (Arduino serial interface)
- Controllers in `wam_controllers` execute the planned trajectories

### OptiTrack ball tracker
C++ node, high-frequency. Supports multi-ball data association (GREEDY / HUNGARIAN / ID_THEN_GREEDY / ID_THEN_HUNGARIAN). Covariance matrices can be serialized to YAML for reuse.

## Agent Hints
- For generic ROS packages (`wam_core`, `robot_controllers`, `optitrack-ball-tracker`), warn before introducing breaking changes. For application-specific code (juggling packages), prioritize clean code over backward compatibility.
- Compose code for reuse in new projects.
- Deferred bugs go in `/catkin_ws/KNOWN_BUGS.md`. When we notice a bug but decide not to fix it right now (wrong scope, different branch, low priority, coincidentally harmless, etc.), add an entry with a file:line citation, a one-paragraph description, the proposed fix, and a "why deferred" note. Check this file opportunistically when touching related code.
- When writing your own launch file that wraps `wam.launch`, use `<include file="$(find wam_bringup)/launch/wam.launch">` and pass only the args you need to override.
