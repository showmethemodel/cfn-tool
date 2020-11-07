#!/usr/bin/env bash

abort() { exec 1>&2; [ $# -gt 0 ] && echo "$@"; exit 1; }

for i in USER_HOME USER_NAME USER_GID USER_UID INFRA_BASE_DIR; do
  [[ ${!i} ]] || abort "required env var not set: $i"
done

echo "%$USER_NAME ALL=NOPASSWD: ALL" >> /etc/sudoers

groupadd -g $USER_GID $USER_NAME
useradd -M -d $USER_HOME -g $USER_GID -u $USER_UID -c $USER_NAME $USER_NAME

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
  usermod -aG $docker_host_grp $USER_NAME
fi

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

cd "$INFRA_BASE_DIR"

su $USER_NAME
