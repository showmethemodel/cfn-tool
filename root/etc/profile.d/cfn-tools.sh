# aws cli command completion
complete -C $(which aws_completer) aws

# setup terminal colors
eval "$(dircolors -b)"
export LS_COLORS

# add bin dir to PATH
export PATH=$INFRA_BASE_DIR/bin:$PATH:$HOME/bin

# stack command completion
_cfn_stack_complete() {
  local cur=${COMP_WORDS[COMP_CWORD]} ses
  if [ -d infra -a -d config ]; then
    ses=$(join -t, -j 9999 -o 1.1,2.1 \
      <(find infra/ -maxdepth 1 -mindepth 1 -type f -name '*.yml' \
        |sed -e 's@^[^/]*/\(.*\).yml@\1@') \
      <(find config -mindepth 1 -maxdepth 1 -type f -name '*.yml' \
        |sed 's@^.*/\(.*\).yml$@\1@') \
      |tr [,] [\\t] \
      |awk -F\\t '{print $2 "-" $1}' \
      |sort)
  fi
  COMPREPLY=( $(compgen -W "$ses" -- $cur) )
}
for i in $(cd "/usr/bin" ; ls stack-*); do
  complete -F _cfn_stack_complete $i
done

_cfn_prompt_command() {
  local ret=$? status region gitbranch gitsha gitdirty gitinfo curdir host symbol
  local none='\033[0m'
  local red='\033[1;31m'
  local green='\033[1;32m'
  local yellow='\033[1;33m'
  local blue='\033[1;34m'
  local orange='\033[1;35m'
  local cyan='\033[1;36m'

  status=$([ $ret -eq 0 ] && echo "${green}OK${none} " || echo "${red}ERR${none} ")
  region=${AWS_DEFAULT_REGION:+$blue$AWS_DEFAULT_REGION$none }
  gitbranch=
  gitbranch=$(git symbolic-ref --short -q HEAD)
  gitsha="${gitbranch:+${gitbranch}@}$(git rev-parse --short HEAD)"
  gitdirty=$(git diff-files --quiet && echo $cyan || echo $orange)
  gitinfo=${gitsha:+${gitdirty}${gitsha}${none} }
  curdir="${yellow}${PWD/#$HOME/~}${none}"
  host=${HOSTNAME%%.*}
  symbol=$([ $UID -eq 0 ] && echo '#' || echo '$')

  PS1=$(echo -ne "\n${status}${region}${gitinfo}${curdir}\n${host} $symbol ")
}

export PS1=
export PROMPT_COMMAND=_cfn_prompt_command
