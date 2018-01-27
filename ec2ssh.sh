#!/usr/bin/env bash
#
# Wrapper for CSSH running instances by tag

usage(){
  cat << EOF >&2
  usage: $0 options

  This script Gathers instances from AWS and runs ClusterSSH to them

  OPTIONS:
  -p AWS Profile
  -t AWS Tags to Search the machines Name=Value space separated
  -s Single mode: ssh only to one machine
  -e (external) Use PublicIpAddress to connect. Default: PrivateIpAddress
EOF
}

while getopts "p: t: o: s e l" OPTION; do
  case $OPTION in
    p)
      PROFILE=$OPTARG
    ;;
    t)
      TAGS=$OPTARG
    ;;
    o)
      OPTIONS=$OPTARG
    ;;
    s)
      mode='single'
    ;;
    e)
      EP='PublicIpAddress'
    ;;
    l)
      LIST_ONLY=true
    ;;
    ?)
      usage
      exit
    ;;
  esac
done

if [[ -z $PROFILE ]]; then
  PROFILE="default"
fi

if [[ -z $EP ]]; then
  EP=PrivateIpAddress
fi

if [[ -z $TAGS ]]; then
  echo "No Tags provided" >&2
  usage
  exit 1
fi

FILTERS=""
LENGTH=$(echo "$TAGS" | awk '{print NF}')
for i in $(eval echo "{1..$LENGTH}"); do 
  FILTERS+=$(echo -n "$TAGS" | awk "{print \$$i}" | awk -F "=" '{print " \"Name=tag:"$1",Values="$2"\""}')
done

BASE_QUERY="aws ec2 describe-instances \
  --profile $PROFILE \
  --query Reservations[].Instances[].${EP} \
  --output text \
  --filters \"Name=instance-state-name,Values=running\"" 

BASE_QUERY+=$FILTERS  

AWS_ANSWER=$(eval $BASE_QUERY)

HOST_COUNT=$(echo $AWS_ANSWER | awk '{print NF}')

if [[ $HOST_COUNT -lt 1 ]]; then
  echo "No machines found, check the query" >&2
  exit
fi

if [[ $LIST_ONLY == true ]]; then
  echo $AWS_ANSWER
  exit 0
fi

if [[ "$mode" == "single" ]]; then
  FIRST_MACHINE=$(echo $AWS_ANSWER | awk '{print $1}')
  ssh $OPTIONS $FIRST_MACHINE
else
  cssh -o "$OPTIONS" $AWS_ANSWER
fi