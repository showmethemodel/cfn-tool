#!/usr/bin/env bash

abort() { exec 1>&2; [ $# -gt 0 ] && echo "$@"; exit 1; }

for i in CFN_TOOLS_USER_HOME CFN_TOOLS_USER_NAME CFN_TOOLS_USER_GID CFN_TOOLS_USER_UID CFN_TOOLS_BASE_DIR; do
  [[ ${!i} ]] || abort "required env var not set: $i"
done

echo "%$CFN_TOOLS_USER_NAME ALL=NOPASSWD: ALL" >> /etc/sudoers

groupadd -g $CFN_TOOLS_USER_GID $CFN_TOOLS_USER_NAME
useradd -M -d $CFN_TOOLS_USER_HOME -g $CFN_TOOLS_USER_GID -u $CFN_TOOLS_USER_UID -c $CFN_TOOLS_USER_NAME $CFN_TOOLS_USER_NAME

# setup user to use "docker run" inside this container
if [ -S /var/run/docker.sock ]; then
  docker_host_gid=$(stat --format=%g /var/run/docker.sock)
  docker_host_grp=$(getent group |awk -F: "\$3 == $docker_host_gid {print \$1}")
  if [ -z "$docker_host_grp" ]; then
    for i in $(seq 2 100); do
      docker_host_grp=docker$i
      getent group |cut -d: -f1 |grep -q $docker_host_grp || break
    done
    groupadd -g $docker_host_gid $docker_host_grp
  fi
  usermod -aG $docker_host_grp $CFN_TOOLS_USER_NAME
fi

cd "$CFN_TOOLS_BASE_DIR"

[ -z "$CFN_TOOLS_CMD" ] || exec su -c "$CFN_TOOLS_CMD" $CFN_TOOLS_USER_NAME

echo -e "\033[1;36m"
cat << 'EOT'
  ______   _______ ______ __ _______     _______ _______ ______  ___ _______
 |   _  \ |   _   |   _  |  |       |   |   _   |   _   |   _  \|   |   _   |
 |.  |   \|.  |   |.  |   |_|.|   | |   |.  1   |.  1   |.  |   |.  |.  1___|
 |.  |    |.  |   |.  |   | `-|.  |-'   |.  ____|.  _   |.  |   |.  |.  |___
 |:  1    |:  1   |:  |   |   |:  |     |:  |   |:  |   |:  |   |:  |:  1   |
 |::.. . /|::.. . |::.|   |   |::.|     |::.|   |::.|:. |::.|   |::.|::.. . |
 `------' `-------`--- ---'   `---'     `---'   `--- ---`--- ---`---`-------'

EOT
echo -e "\033[0m"

su $CFN_TOOLS_USER_NAME
