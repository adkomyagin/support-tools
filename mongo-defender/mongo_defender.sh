#!/bin/bash

# Settings:
# HOSTS - array of remote hosts to check
# T - period of checks (seconds)
# t - ping timeout (seconds)
# V - number of failed checks in a row to consider remote network down
# R - number of failed checks that defines a period with wich we reinforce the blocking rules
# PROTECTED - array of hosts to protect

declare -a HOSTS=( 'ya.ru' 'mail.ru' )
T=5
t=2
V=3
R=10

declare -a PROTECTED=( 'ec2-23-20-177-157.compute-1.amazonaws.com' )

# the host block function
# $1 - host name
#
host_block()
{
ssh -qt -i /Users/alexander/.ssh/CS7135.pem ec2-user@$1 <<'ENDSSH'
#commands to run on remote host
for IP in ${HOSTS[@]}; do
   ! sudo /sbin/iptables -C OUTPUT -p tcp -d $IP -j REJECT --reject-with tcp-reset &>/dev/null  && sudo /sbin/iptables -A OUTPUT -p tcp -d $IP -j REJECT --reject-with tcp-reset 1>&2
done
ENDSSH
}

# the host unblock function
# $1 - host name
#
host_unblock()
{
ssh -qt -i /Users/alexander/.ssh/CS7135.pem ec2-user@$1 <<'ENDSSH'
#commands to run on remote host
for IP in ${HOSTS[@]}; do
   sudo /sbin/iptables -D OUTPUT -p tcp -d $IP -j REJECT --reject-with tcp-reset 1>&2
done
ENDSSH
}

# the host block function
#
block_hosts()
{
    for PIP in ${PROTECTED[@]}; do
        host_block $PIP
    done

    return 0
}

# the host unblock function
#
unblock_hosts()
{
    for PIP in ${PROTECTED[@]}; do
        host_unblock $PIP
    done

    return 0
}


# the status report function
#
report_stats()
{
    if [ $status -eq "0" ]; then
        echo "$status\tAll good" > /tmp/mongo-def-status
    else
        echo "$status\tNumber of failures: $track (limit: $V)" > /tmp/mongo-def-status
    fi
}

echo "Started mongo-defender with PID# $$"
echo "Monitoring hosts: ${HOSTS[@]}"
echo "T=$T, t=$t, V=$V"
echo "Protecting hosts: ${PROTECTED[@]}"
echo "------------------------------"

# Loop forever, checking the health of the system
#

track=0
STATE_GOOD=true

status="0" #0 for good, 1 for warning, 2 for fail

echo -n "Initial host unblock... "
if `unblock_hosts`; then
    echo "Success"
else
    echo "Fail"
fi

while true ; do

  check_positive=false
 
  for IP in ${HOSTS[@]}; do
     if ping -c 1 -W $t $IP >/dev/null; then
          echo "Check on $IP success"
          check_positive=true
          break
     else
          echo "Check on $IP fail"
     fi
  done;

  if [[ $check_positive = true && $track > 0 ]]; then
     track=0
     status="0"
  fi 

  if [[ $check_positive = false ]]; then
     track=$[track+1]
     if [ $track -ge $V && `echo "($track - $V)%$R" | bc` -eq "0" ]; then
         `block_hosts` && STATE_GOOD=false && echo "Blocked!" && status="2"
     elif [ $track -lt $V ]
         status="1"
     fi
  elif [[ $check_positive = true && $STATE_GOOD = false ]]; then
      `unblock_hosts` && STATE_GOOD=true && echo "Released!" && status="0"
  fi

  report_stats
 
  sleep $T
 
done

# We never get here.
exit 0
