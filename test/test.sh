#!/bin/bash
./reference/mdbroker $@ 2>&1 & 
broker_pid=$! # | sed 's/^/broker/' & # 2>&1 >/dev/null &

sleep 1
./reference/mdworker $@ 2>&1 &
worker_pid=$!  # | sed 's/^/worker/' & # 2>&1 >/dev/null&


echo -n "hey there" | ./dist/build/echoclient/echoclient > result
echo -n "hey there" | diff result - 
res=$?

echo "worker is $worker_pid"
echo "broker is $broker_pid"

kill $worker_pid
kill $broker_pid

if [ $res -ne 0 ]; then
  echo "echo client failed"
fi

./reference/mdbroker $@ 2>&1 & 
broker_pid=$! # | sed 's/^/broker/' & # 2>&1 >/dev/null &
sleep 1
./dist/build/echoworker/echoworker  &
my_worker_pid=$!


echo -n "toodles" | ./dist/build/echoclient/echoclient > worker_out
echo -n "toodles" | diff worker_out -
res2=$?
if [ $res -ne 0 ]; then
  echo "echo worker failed"
fi

kill $my_worker_pid
wait

exit $res && $res2


