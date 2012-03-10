./reference/mdbroker &
mdbroker=$!
./reference/mdclient2 &
mdclient=$!
./dist/build/echoworker/echoworker +RTS -p -N   &
worker=$!

sleep 10;
kill -s INT $worker
wait $worker
kill $mdclient
kill -9 $mdbroker
