#!/usr/bin/env bash
# Run INSIDE the container:  docker exec -it ros2-humble-tb3 bash /tmp/diagnose.sh
# Copy it in first:          docker cp diagnose.sh ros2-humble-tb3:/tmp/diagnose.sh

hr() { printf '\n=== %s ===\n' "$1"; }

hr "1. Display"
echo "DISPLAY=${DISPLAY:-<unset>}"
if xdpyinfo >/dev/null 2>&1; then
    echo "OK: X server on ${DISPLAY} is reachable"
    xdpyinfo | grep -E "dimensions|depth of root" | head -2
else
    echo "FAIL: no X server on ${DISPLAY}. Nothing graphical can start."
    echo "      -> is the VNC desktop actually up? check: docker compose logs"
fi

hr "2. OpenGL / renderer"
echo "LIBGL_ALWAYS_SOFTWARE=${LIBGL_ALWAYS_SOFTWARE:-<unset>}"
if command -v glxinfo >/dev/null 2>&1; then
    glxinfo -B 2>&1 | grep -Ei "renderer|OpenGL version|core profile version" | head -5 \
        || echo "FAIL: glxinfo produced no renderer info"
else
    echo "glxinfo missing (install mesa-utils)"
fi

hr "3. Versions installed"
echo -n "Gazebo Classic: "; gazebo --version 2>/dev/null | head -1 || echo "NOT INSTALLED"
echo -n "Ignition:       "; ign gazebo --version 2>/dev/null | head -1 || echo "NOT INSTALLED"

hr "4. Model paths"
echo "GAZEBO_MODEL_PATH=${GAZEBO_MODEL_PATH:-<unset>}"
echo "IGN_GAZEBO_RESOURCE_PATH=${IGN_GAZEBO_RESOURCE_PATH:-<unset>}"
echo "TURTLEBOT3_MODEL=${TURTLEBOT3_MODEL:-<unset>}"
for d in ${GAZEBO_MODEL_PATH//:/ }; do
    [ -d "$d" ] && echo "OK:   $d ($(ls "$d" | wc -l) models)" || echo "MISSING: $d"
done

hr "5. Headless server only (no GUI, isolates rendering from physics)"
timeout 25 gzserver --verbose /usr/share/gazebo-11/worlds/empty.world 2>&1 | head -20
echo "[exit: $? — 124 means it ran until timeout, which is SUCCESS here]"

hr "6. Ignition headless"
timeout 25 ign gazebo -s -r -v 4 shapes.sdf 2>&1 | head -20
echo "[exit: $? — 124 = ran fine until timeout]"

hr "7. Ignition GUI with software-safe render engine"
echo "If step 6 passed but this fails, it is purely a rendering problem."
timeout 20 ign gazebo --render-engine ogre -v 4 shapes.sdf 2>&1 | head -25
echo "[exit: $?]"

hr "done"
