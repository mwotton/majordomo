#!/bin/bash

SERVER="tcp://127.0.0.1:5773"
./reference/mdbroker $@ 2>&1 & 
broker_pid=$! # | sed 's/^/broker/' & # 2>&1 >/dev/null &

sleep 1
./reference/mdworker $@ 2>&1 &
worker_pid=$!  # | sed 's/^/worker/' & # 2>&1 >/dev/null&


./dist/build/mdp_client/mdp_client $SERVER "echo" "hey there" > result
echo -n "hey there" | diff result - 
client_success=$?

echo "worker is $worker_pid"
echo "broker is $broker_pid"

kill $worker_pid
kill $broker_pid

if [ $client_success -ne 0 ]; then
  echo "echo client failed"
fi

./reference/mdbroker $@ 2>&1 & 
broker_pid=$! # | sed 's/^/broker/' & # 2>&1 >/dev/null &
sleep 1
./dist/build/echoworker/echoworker  &
my_worker_pid=$!

echo "running client"
./dist/build/mdp_client/mdp_client $SERVER echo toodles > worker_out
echo "done"
echo -n "hi there, 
toodles" | diff worker_out -
worker_success=$?
if [ $worker_success -ne 0 ]; then
  echo "echo worker failed"
fi
echo "finished, killing, aiting"
kill $my_worker_pid
kill $broker_pid
wait
[ $client_success -eq 0 ] && [ $worker_success -eq 0 ] && exit 0
exit 1
