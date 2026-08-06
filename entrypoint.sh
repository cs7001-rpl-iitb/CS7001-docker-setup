#!/usr/bin/env bash
set -eo pipefail

log() { echo "[entrypoint] $*"; }

source /opt/ros/${ROS_DISTRO}/setup.bash
if [ -f "${TB3_WS}/install/setup.bash" ]; then
    source "${TB3_WS}/install/setup.bash"
fi

if [ "${START_VNC:-true}" = "true" ]; then
    mkdir -p "${HOME}/.vnc"

    log "writing VNC password"
    echo "${VNC_PASSWORD:-turtlebot3}" | vncpasswd -f > "${HOME}/.vnc/passwd"
    chmod 600 "${HOME}/.vnc/passwd"

    # A restarted container keeps its old /tmp, so stale locks must go or
    # Xvnc refuses to claim :1 and we crash-loop.
    log "clearing stale X locks"
    vncserver -kill :1 >/dev/null 2>&1 || true
    rm -rf /tmp/.X1-lock /tmp/.X11-unix/X1 "${HOME}/.vnc/"*.pid || true
    rm -f "${HOME}/.vnc/"*.log || true

    log "starting Xvnc on :1 (${VNC_RESOLUTION:-1600x900})"
    # NOT silenced: if this fails we want to see why.
    if ! vncserver :1 \
            -geometry "${VNC_RESOLUTION:-1600x900}" \
            -depth 24 \
            -localhost no \
            -rfbauth "${HOME}/.vnc/passwd"; then
        log "!! vncserver failed to start. Xvnc log follows:"
        cat "${HOME}/.vnc/"*.log 2>/dev/null || log "(no log written)"
        exit 1
    fi

    # Confirm 5901 is actually accepting connections before fronting it.
    for i in $(seq 1 20); do
        if (echo > /dev/tcp/127.0.0.1/5901) >/dev/null 2>&1; then
            log "Xvnc is listening on 5901"
            break
        fi
        [ "$i" = "20" ] && { log "!! 5901 never came up"; cat "${HOME}/.vnc/"*.log 2>/dev/null; exit 1; }
        sleep 0.5
    done

    echo "-----------------------------------------------------------"
    echo "  Desktop:   http://localhost:6080/vnc.html"
    echo "  Password:  ${VNC_PASSWORD:-turtlebot3}"
    echo "  Shell:     docker exec -it ros2-humble-tb3 bash"
    echo "-----------------------------------------------------------"
fi

exec "$@"
