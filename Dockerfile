# =============================================================================
#  Ubuntu 22.04 + ROS 2 Humble (desktop / RViz2) + Ignition Gazebo Fortress
#  + TurtleBot3 (built from source) + browser-based desktop (noVNC)
#
#  Works on: macOS (Intel + Apple Silicon) and Windows (Docker Desktop / WSL2)
#  Build natively on each machine -> amd64 on Windows/Intel Mac, arm64 on M-series
# =============================================================================
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG ROS_DISTRO=humble
ARG USERNAME=ros
ARG UID=1000
ARG GID=1000
# Lower this to 1 if your Docker Desktop has < 8 GB RAM assigned
ARG PARALLEL_JOBS=2

ENV ROS_DISTRO=${ROS_DISTRO} \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=Etc/UTC \
    TB3_WS=/opt/turtlebot3_ws \
    TURTLEBOT3_MODEL=burger \
    DISPLAY=:1

# Every RUN uses bash with -e and pipefail so a failing command aborts the
# build instead of being masked by a later successful command in the chain.
SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

# -----------------------------------------------------------------------------
# 1. Base system + locale
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        locales tzdata ca-certificates curl wget gnupg2 lsb-release \
        software-properties-common sudo git nano vim less \
        build-essential python3-pip \
 && locale-gen en_US en_US.UTF-8 \
 && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
 && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# 2. Apt repositories: ROS 2 + OSRF (Gazebo)
# -----------------------------------------------------------------------------
RUN add-apt-repository -y universe \
 && curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" \
        > /etc/apt/sources.list.d/ros2.list \
 && curl -sSL https://packages.osrfoundation.org/gazebo.gpg \
        -o /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] \
http://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/gazebo-stable.list

# -----------------------------------------------------------------------------
# 3. ROS 2 Humble desktop (includes RViz2) + dev tools
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ros-${ROS_DISTRO}-desktop \
        ros-dev-tools \
        python3-colcon-common-extensions \
        python3-rosdep \
        python3-vcstool \
        python3-argcomplete \
 && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# 4. Ignition Gazebo Fortress (the version paired with Humble) + ros_gz bridge
#    Gazebo Classic 11 is also installed because the official TurtleBot3
#    simulation worlds on Humble target Classic (see README).
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ignition-fortress \
        ros-${ROS_DISTRO}-ros-gz \
        ros-${ROS_DISTRO}-ros-gz-sim \
        ros-${ROS_DISTRO}-ros-gz-bridge \
        ros-${ROS_DISTRO}-gazebo-ros-pkgs \
 && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# 5. TurtleBot3 runtime dependencies (Nav2, Cartographer, drivers)
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ros-${ROS_DISTRO}-navigation2 \
        ros-${ROS_DISTRO}-nav2-bringup \
        ros-${ROS_DISTRO}-cartographer \
        ros-${ROS_DISTRO}-cartographer-ros \
        ros-${ROS_DISTRO}-dynamixel-sdk \
        ros-${ROS_DISTRO}-hls-lfcd-lds-driver \
        ros-${ROS_DISTRO}-teleop-twist-keyboard \
        ros-${ROS_DISTRO}-teleop-twist-joy \
        ros-${ROS_DISTRO}-rqt* \
 && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# 6. Lightweight XFCE desktop + TigerVNC + noVNC + software OpenGL
#    Split into separate RUNs on purpose. Chaining these with `&& ... || true`
#    makes the `|| true` apply to the WHOLE chain (equal precedence, left
#    associative), which silently swallows apt failures. Do not re-merge.
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        xfce4 \
        xfce4-terminal \
        xterm \
        dbus-x11

RUN apt-get install -y --no-install-recommends \
        tigervnc-standalone-server \
        tigervnc-common \
        tigervnc-tools

RUN apt-get install -y --no-install-recommends \
        novnc \
        websockify \
        python3-numpy

RUN apt-get install -y --no-install-recommends \
        mesa-utils libgl1-mesa-dri libglu1-mesa \
        x11-utils x11-xserver-utils xauth xfonts-base \
 && rm -rf /var/lib/apt/lists/*

# Purge is genuinely optional -- isolated so its failure cannot mask anything.
RUN apt-get purge -y xfce4-screensaver || true
RUN apt-get purge -y xfce4-power-manager || true

# noVNC landing page
RUN test -d /usr/share/novnc \
 && ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

# Fail the BUILD, not the container, if any runtime binary is missing.
RUN for b in vncpasswd vncserver Xvnc websockify xfce4-session dbus-launch; do \
        command -v "$b" >/dev/null 2>&1 \
            || { echo "FATAL: required binary '$b' is missing"; exit 1; }; \
        echo "ok: $b -> $(command -v $b)"; \
    done

# -----------------------------------------------------------------------------
# 7. Build the TurtleBot3 workspace from source
# -----------------------------------------------------------------------------
# NOTE: ROBOTIS renamed their release branches — it is plain "humble" now,
# NOT the old "humble-devel". Verified against git ls-remote.
RUN mkdir -p ${TB3_WS}/src && cd ${TB3_WS}/src \
 && git clone --depth 1 -b ${ROS_DISTRO} https://github.com/ROBOTIS-GIT/turtlebot3_msgs.git \
 && git clone --depth 1 -b ${ROS_DISTRO} https://github.com/ROBOTIS-GIT/turtlebot3.git \
 && git clone --depth 1 -b ${ROS_DISTRO} https://github.com/ROBOTIS-GIT/turtlebot3_simulations.git

RUN rosdep init 2>/dev/null || true \
 && rosdep update --rosdistro ${ROS_DISTRO} \
 && apt-get update \
 && rosdep install --from-paths ${TB3_WS}/src --ignore-src -y -r \
        --rosdistro ${ROS_DISTRO} \
 && rm -rf /var/lib/apt/lists/*

RUN . /opt/ros/${ROS_DISTRO}/setup.sh \
 && cd ${TB3_WS} \
 && MAKEFLAGS="-j${PARALLEL_JOBS}" colcon build \
        --symlink-install \
        --parallel-workers ${PARALLEL_JOBS} \
        --cmake-args -DCMAKE_BUILD_TYPE=Release

# -----------------------------------------------------------------------------
# 8. Non-root user
# -----------------------------------------------------------------------------
RUN groupadd -g ${GID} ${USERNAME} 2>/dev/null || true \
 && useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME} \
 && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
 && chmod 0440 /etc/sudoers.d/${USERNAME} \
 && chown -R ${USERNAME}:${USERNAME} ${TB3_WS}

# VNC session startup
RUN mkdir -p /home/${USERNAME}/.vnc \
 && printf '%s\n' \
      '#!/bin/sh' \
      'unset SESSION_MANAGER' \
      'unset DBUS_SESSION_BUS_ADDRESS' \
      'exec dbus-launch --exit-with-session xfce4-session' \
      > /home/${USERNAME}/.vnc/xstartup \
 && chmod +x /home/${USERNAME}/.vnc/xstartup \
 && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.vnc

# -----------------------------------------------------------------------------
# 9. Environment for every shell
# -----------------------------------------------------------------------------
RUN printf '%s\n' \
      "source /opt/ros/${ROS_DISTRO}/setup.bash" \
      "source ${TB3_WS}/install/setup.bash" \
      "export TURTLEBOT3_MODEL=\${TURTLEBOT3_MODEL:-burger}" \
      "export GAZEBO_MODEL_PATH=\$GAZEBO_MODEL_PATH:${TB3_WS}/src/turtlebot3_simulations/turtlebot3_gazebo/models" \
      "export IGN_GAZEBO_RESOURCE_PATH=\$IGN_GAZEBO_RESOURCE_PATH:${TB3_WS}/src/turtlebot3_simulations/turtlebot3_gazebo/models" \
      "export ROS_DOMAIN_ID=\${ROS_DOMAIN_ID:-30}" \
      "export LIBGL_ALWAYS_SOFTWARE=1" \
      "export QT_X11_NO_MITSHM=1" \
      > /etc/profile.d/ros_env.sh \
 && cat /etc/profile.d/ros_env.sh >> /home/${USERNAME}/.bashrc

ENV GAZEBO_MODEL_PATH=${TB3_WS}/src/turtlebot3_simulations/turtlebot3_gazebo/models \
    IGN_GAZEBO_RESOURCE_PATH=${TB3_WS}/src/turtlebot3_simulations/turtlebot3_gazebo/models \
    LIBGL_ALWAYS_SOFTWARE=1 \
    QT_X11_NO_MITSHM=1 \
    ROS_DOMAIN_ID=30 \
    VNC_RESOLUTION=1600x900 \
    VNC_PASSWORD=turtlebot3

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER ${USERNAME}
WORKDIR /home/${USERNAME}

EXPOSE 5901 6080

# websockify runs in the FOREGROUND as PID 1's child, so the container's
# lifetime is tied to the thing you actually connect to. No tty required.
# Interactive shells come from `docker exec`.
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
    CMD bash -c '(echo > /dev/tcp/127.0.0.1/6080) >/dev/null 2>&1 || exit 1'

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["websockify", "--web=/usr/share/novnc", "6080", "localhost:5901"]
