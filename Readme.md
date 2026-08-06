# ROS 2 Humble + Ignition Gazebo + TurtleBot3 — Docker

A single container image that runs identically on **Windows**, **macOS** and **Ubuntu/Linux**.

| Component | Version |
|---|---|
| Base OS | Ubuntu 22.04 (Jammy) |
| ROS 2 | Humble Hawksbill — `ros-humble-desktop`, includes RViz2 |
| Ignition Gazebo | Fortress (+ `ros_gz` bridge) |
| Gazebo Classic | 11 (required by the official TurtleBot3 worlds) |
| TurtleBot3 | built from source, `humble` branch |
| Extras | Nav2, Cartographer, teleop, rqt |
| GUI | XFCE desktop in your web browser via noVNC |

The GUI runs **inside** the container and is served to your browser. No XQuartz,
no VcXsrv, no X11 configuration on any platform.

---

## Contents

```
.
├── Dockerfile
├── docker-compose.yml
├── entrypoint.sh            # starts VNC + noVNC
├── .gitattributes           # forces LF endings (critical on Windows)
├── setup-windows.ps1        # Windows only: finds Docker, fixes PATH
├── fix-line-endings.ps1     # Windows only: CRLF -> LF
├── diagnose.sh              # troubleshooting, run inside the container
└── workspace/               # your code; mounted at /home/ros/ws
```

---

## Requirements (all platforms)

- Docker with Compose v2
- **8 GB RAM** available to Docker, **40 GB** free disk
- The finished image is roughly 8–10 GB; first build takes 30–60 minutes

---

## Setup

### Windows

1. Install Docker Desktop:

   ```powershell
   winget install -e --id Docker.DockerDesktop
   ```

   Reboot afterwards, then launch Docker Desktop from the Start menu and wait
   for the whale icon to stop animating.

2. Run the setup script. It locates `docker.exe` wherever it was installed
   (per-user and system-wide installs both work), fixes your PATH, selects the
   right Docker context, and verifies the daemon:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1
   ```

3. Normalise line endings. **Do not skip this** — Windows writes shell scripts
   with CRLF, and the container then fails with
   `/usr/bin/env: 'bash\r': No such file or directory`:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\fix-line-endings.ps1
   ```

4. In Docker Desktop → Settings → Resources, confirm at least 8 GB memory.

> **Build location matters.** Building from `C:\Users\...` is noticeably slower
> because Docker reaches Windows paths through a filesystem translation layer.
> It works fine, just expect a longer first build.

### macOS

1. Install Docker Desktop — [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/)
   or `brew install --cask docker`. Launch it and wait for the whale icon.
2. Settings → Resources → at least 8 GB memory.
3. **Apple Silicon (M1–M4): build natively.** ROS 2 Humble, Fortress and Gazebo
   Classic all ship arm64 packages, so the normal build just works. Do *not*
   force `--platform linux/amd64` — emulated Gazebo is unusably slow and
   crashes on OpenGL calls.

### Ubuntu / Linux

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

Log out and back in so the group change applies, then check with `docker ps`.

---

## Build and run

Identical on every platform:

```bash
docker compose build
docker compose up -d
docker compose logs -f
```

Open **<http://localhost:6080/vnc.html>** — password `turtlebot3`.

Get a shell:

```bash
docker exec -it ros2-humble-tb3 bash
```

Stop:

```bash
docker compose down
```

If Docker has under 8 GB of RAM, build with one compile job so `colcon` isn't
OOM-killed:

```bash
docker compose build --build-arg PARALLEL_JOBS=1
```

---

## Verifying it works

Inside the container, or in the browser desktop's terminal:

```bash
ros2 topic list
rviz2
```

TurtleBot3 in Gazebo Classic (the officially supported simulation):

```bash
export TURTLEBOT3_MODEL=waffle
ros2 launch turtlebot3_gazebo turtlebot3_world.launch.py

# second terminal
ros2 run turtlebot3_teleop teleop_keyboard
```

SLAM and navigation:

```bash
ros2 launch turtlebot3_cartographer cartographer.launch.py use_sim_time:=True
ros2 launch turtlebot3_navigation2 navigation2.launch.py use_sim_time:=True
```

Ignition Gazebo Fortress:

```bash
ign gazebo --render-engine ogre -v 4 shapes.sdf
ros2 launch ros_gz_sim gz_sim.launch.py gz_args:="-r shapes.sdf"
```

---

## Rendering: read this before reporting Gazebo problems

The container has **no GPU access**, so all rendering is software (llvmpipe).

- **Always pass `--render-engine ogre` to Ignition.** Fortress defaults to
  `ogre2`, which needs a real GL 3.3+ driver and dies with no useful message
  under software rendering. Add `-v 4` to see actual errors.
- RViz2 and Gazebo Classic work on llvmpipe, but slowly. A few frames per
  second in Gazebo is expected, not a fault.
- If Gazebo Classic seems to hang on first launch, it may be reaching for the
  online model database. Test with `GAZEBO_MODEL_DATABASE_URI="" gazebo --verbose`.

**Linux users can do much better.** You have a real GPU, and mounting the X11
socket with GPU passthrough makes Gazebo genuinely fast. That setup is
Linux-only and is why this image defaults to software rendering — the default
has to work on Windows and macOS too.

---

## TurtleBot3 and Ignition

ROBOTIS's `turtlebot3_simulations` on the `humble` branch declares
`gazebo_ros_pkgs` and ships `.world` files for **Gazebo Classic 11**, which is
why Classic is installed alongside Fortress. Their Ignition port lives on an
unreleased feature branch and is not used here.

Fortress and `ros_gz` are installed and ready for your own work. Both
simulators coexist in the image without conflict — choose per launch.

Note also that ROBOTIS renamed their release branches: it is `humble`, **not**
the older `humble-devel`.

---

## Your own code

Anything in `./workspace` on the host appears at `/home/ros/ws` in the
container and survives rebuilds:

```bash
cd ~/ws
colcon build --symlink-install
source install/setup.bash
```

Everything outside that directory is disposable.

---

## Troubleshooting

### Windows

| Symptom | Cause and fix |
|---|---|
| `docker : The term 'docker' is not recognized` | Not on PATH. Run `setup-windows.ps1`. A PowerShell window opened *before* Docker was installed will never see the new PATH — open a fresh one. |
| `Test-Path` on Program Files returns `False` but winget says installed | Per-user install under `%LOCALAPPDATA%\Programs\DockerDesktop`. `setup-windows.ps1` finds both layouts. |
| `failed to connect to the docker API at npipe:////./pipe/docker_engine` | Either Docker Desktop isn't running, or the CLI is on the legacy `default` context. Run `docker context use desktop-linux`. |
| `/usr/bin/env: 'bash\r': No such file or directory` | CRLF line endings. Run `fix-line-endings.ps1`, then rebuild. |
| winget says "already installed" but files are missing | Ghost registry entry. `winget uninstall -e --id Docker.DockerDesktop`, then reinstall with `--force`. |

### All platforms

| Symptom | Cause and fix |
|---|---|
| Nothing on `localhost:6080` | `docker compose ps` — a container that keeps restarting is crash-looping. `docker compose logs` shows why. |
| Container restarts forever | Read the `[entrypoint]` lines in the logs; a failed `vncserver` prints its Xvnc log before exiting. |
| Black screen in browser | Wait ~10 s after `up`, then reload. |
| `Cannot open display` | `export DISPLAY=:1` in that shell. |
| Ignition exits immediately | Missing `--render-engine ogre`. |
| `colcon` killed mid-build | Raise Docker's memory, or `--build-arg PARALLEL_JOBS=1`. |
| Port 6080 in use | Change the left-hand side of the mapping in `docker-compose.yml`. |
| Host ROS nodes can't see container nodes | Multicast DDS doesn't cross Docker's VM on Windows/macOS. Keep all nodes inside the container, or run a Fast DDS discovery server. |

Deeper diagnosis:

```bash
docker cp diagnose.sh ros2-humble-tb3:/tmp/diagnose.sh
docker exec -it ros2-humble-tb3 bash /tmp/diagnose.sh
```

It checks the X server, the OpenGL renderer, both Gazebo versions, model paths,
and runs headless then GUI simulations to isolate rendering from physics.

---

## Notes on line endings

`.gitattributes` forces LF for `*.sh`, the Dockerfile and YAML files, so a
`git clone` on Windows gets correct endings automatically. The Dockerfile also
strips CRLF and any UTF-8 BOM after copying `entrypoint.sh`, and asserts the
shebang is intact — so a bad checkout fails the *build* with a clear message
rather than producing an image that crash-loops at runtime.

`fix-line-endings.ps1` is for files transferred by other means: downloaded
individually, copied over RDP, or edited in Notepad.
