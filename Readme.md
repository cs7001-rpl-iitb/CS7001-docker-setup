# ROS 2 Humble + Ignition Fortress + TurtleBot3 — Docker (Mac & Windows)

Ubuntu 22.04 · ROS 2 Humble Desktop (RViz2) · Ignition Gazebo Fortress · Gazebo Classic 11 · TurtleBot3 built from source · XFCE desktop in your browser via noVNC.

GUI works identically on macOS (Intel and Apple Silicon) and Windows — **no XQuartz, no VcXsrv, no X11 setup**. You open a browser tab.

---

## 1. Prerequisites

- Docker Desktop (Mac or Windows). On Windows use the **WSL2 backend**.
- Docker Desktop → Settings → Resources: give it at least **8 GB RAM** and **40 GB disk**. The final image is roughly 8–10 GB.

## 2. Layout

```
ros2-humble-tb3-docker/
├── Dockerfile
├── entrypoint.sh
├── docker-compose.yml
├── README.md
└── workspace/          # created on first run; mounted at /home/ros/ws
```

## 3. Build

```bash
cd ros2-humble-tb3-docker
mkdir -p workspace
docker compose build          # 30–60 min on first build
```

If Docker Desktop has less than 8 GB RAM, build with one job so colcon doesn't get OOM-killed:

```bash
docker compose build --build-arg PARALLEL_JOBS=1
```

## 4. Run

```bash
docker compose up -d
```

Then open **http://localhost:6080/vnc.html** — password `turtlebot3`.

Get a terminal inside the container:

```bash
docker exec -it ros2-humble-tb3 bash
```

Stop / remove:

```bash
docker compose down
```

## 5. Quick checks

Inside the container (or in the XFCE terminal in the browser):

```bash
ros2 topic list
rviz2

# Gazebo Classic — official TurtleBot3 worlds
export TURTLEBOT3_MODEL=waffle
ros2 launch turtlebot3_gazebo turtlebot3_world.launch.py

# Teleop in a second terminal
ros2 run turtlebot3_teleop teleop_keyboard

# SLAM + Nav2
ros2 launch turtlebot3_cartographer cartographer.launch.py use_sim_time:=True
ros2 launch turtlebot3_navigation2 navigation2.launch.py use_sim_time:=True
```

Ignition Gazebo Fortress:

```bash
ign gazebo --render-engine ogre shapes.sdf
# or via ros_gz
ros2 launch ros_gz_sim gz_sim.launch.py gz_args:="-r shapes.sdf"
```

**Important:** the container has no GPU passthrough, so rendering is software (llvmpipe). Ignition's default `ogre2` engine needs a real GL 3.3 driver and will usually fail — always pass `--render-engine ogre`. RViz2 and Gazebo Classic work fine on software rendering, just slowly.

## 6. About TurtleBot3 + Ignition

ROBOTIS's official `turtlebot3_simulations` on the `humble` branch declares `<depend>gazebo_ros_pkgs</depend>` and ships `.world` files for **Gazebo Classic 11**, which is why Classic is installed alongside Fortress. (Their Ignition/gz port lives on an unreleased `feature-gazebo-sim-migration` branch — not used here.) Fortress + `ros_gz` are installed and ready, but if you want the TurtleBot3 in Ignition you'll need to either use an SDF/model port of the robot or bridge topics yourself with `ros_gz_bridge`. Both simulators coexist in the image without conflict — pick per launch.

## 7. Apple Silicon notes

Build natively (arm64). ROS 2 Humble, Fortress and Gazebo Classic all have arm64 jammy packages, so `docker compose build` just works on M-series Macs.

Do **not** force `--platform linux/amd64` unless you have a specific reason: x86 emulation on Apple Silicon makes Gazebo and RViz unusably slow and frequently crashes on OpenGL calls.

## 8. Persisting your own work

Anything you put in `./workspace` on the host shows up at `/home/ros/ws` in the container and survives rebuilds. Build your own packages there:

```bash
cd ~/ws && colcon build --symlink-install && source install/setup.bash
```

Everything else in the container is disposable.

## 9. Common issues

| Symptom | Fix |
|---|---|
| Black screen at :6080 | Wait ~10 s after `up`, then reload. Or `docker compose restart`. |
| "Cannot open display" for a GUI app | `export DISPLAY=:1` in that shell. |
| Ignition GUI segfaults | Add `--render-engine ogre`. |
| colcon killed during build | Raise Docker RAM, or `--build-arg PARALLEL_JOBS=1`. |
| Port 6080 already in use | Change the left side of the mapping in `docker-compose.yml`. |
| ROS nodes on host can't see container nodes | Multicast DDS doesn't cross Docker Desktop's VM on Mac/Windows. Keep all nodes inside the container, or configure a Fast DDS discovery server. |

## 10. Optional: native X11 instead of noVNC

If you prefer host-side GUI (XQuartz on Mac, VcXsrv on Windows), run with `START_VNC=false`, set `DISPLAY=host.docker.internal:0`, and allow connections on your X server. It's faster but needs per-OS setup — the browser desktop is the portable default.
