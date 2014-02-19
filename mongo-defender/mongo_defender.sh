#!/bin/bash

# Settings:
# HOSTS - array of remote hosts to check
# T - period of checks (seconds)
# t - ping timeout (seconds)
# V - number of failed checks in a row to consider remote network down
# PROTECTED - array of hosts to protect

declare -a HOSTS=( 'ya.ru' 'mail.ru' )
T=5
t=2
V=3

declare -a PROTECTED=( 'ec2-23-20-177-157.compute-1.amazonaws.com' )

# the host act function
# $1 - host name
# $2 - rule action (D/A)
#
host_act()
{
    for IP in ${HOSTS[@]}; do
        ssh -qt -i /Users/alexander/.ssh/CS7135.pem ec2-user@$1 "sudo /sbin/iptables -$2 OUTPUT -p tcp -d $IP -j REJECT --reject-with tcp-reset" 1>&2
    done
}

# the host block function
#
block_hosts()
{
    for PIP in ${PROTECTED[@]}; do
        host_act $PIP "A"
    done

    return 0
}

# the host unblock function
#
unblock_hosts()
{
    for PIP in ${PROTECTED[@]}; do
        host_act $PIP "D"
    done

    return 0
}


# the status report function
#
report_stats()
{
    echo "Status Code: $status" > /tmp/mongo-def-status

    echo "ping success count: $succ_count_inc" >> /tmp/mongo-def-status
    echo "ping fail count: $fail_count_inc" >> /tmp/mongo-def-status
    echo "total ping count: $[succ_count_inc+fail_count_inc]" >> /tmp/mongo-def-status
}

# reset incremental counters
#
on_usr()
{
    succ_count_inc=0
    fail_count_inc=0
}


# Execute function on_usr() receiving USR1 signal
#
trap 'on_usr' USR1

echo "Started mongo-defender with PID# $$"
echo "Monitoring hosts: ${HOSTS[@]}"
echo "T=$T, t=$t, V=$V"
echo "Protecting hosts: ${PROTECTED[@]}"
echo "------------------------------"

# Loop forever, checking the health of the system
#

track=0
STATE_GOOD=true

status="GOOD"
fail_count_inc=0
succ_count_inc=0

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

  if [[ $check_positive = true ]]; then
     succ_count_inc=$[succ_count_inc+1]
  else
     fail_count_inc=$[fail_count_inc+1]
  fi

  if [[ $check_positive = true && $track > 0 ]]; then
     track=0
     status="GOOD"
  fi 

  if [[ $check_positive = false && $STATE_GOOD = true ]]; then
     track=$[track+1]
     if [ $track -eq $V ]; then
         track=0
         `block_hosts` && STATE_GOOD=false && echo "Blocked!" && status="FAIL"
     else
         status="WARNING"
     fi
  elif [[ $check_positive = true && $STATE_GOOD = false ]]; then
      `unblock_hosts` && STATE_GOOD=true && echo "Released!" && status="GOOD"
  fi

  report_stats
 
  sleep $T
 
done

# We never get here.
exit 0
