#!/usr/bin/env bash

curl -X POST -u admin:admin 'http://localhost:8081/api/processManagement/cancel/DetectLargeTransactions'
curl -u admin:admin -X DELETE http://localhost:8081/api/processes/DetectLargeTransactions -v

main() {
  echo "Starting docker containers.."

  docker-compose -f docker-compose.yml -f docker-compose-env.yml kill
  docker-compose -f docker-compose.yml -f docker-compose-env.yml rm -f -v
  docker-compose -f docker-compose.yml -f docker-compose-env.yml build
  docker-compose -f docker-compose.yml -f docker-compose-env.yml up -d --no-recreate

  waitForOK "api/processes" "Checking Nussknacker API response.." "Nussknacker not started" "designer"
  waitForOK "api/processes/status" "Checking connect with Flink.." "Nussknacker not connected with flink" "designer"
  waitForOK "flink/" "Checking Flink response.." "Flink not started" "jobmanager"
  waitForOK "metrics" "Checking Grafana response.." "Grafana not started" "grafana"

  echo "Creating process"
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://admin:admin@localhost:8081/api/processes/DetectLargeTransactions/Default?isSubprocess=false")
  if [[ $CODE == 201 ]]; then
    echo "Scenario creation success"
  elif [[ $CODE == 400 ]]; then
    echo "Scenario has already exists in db."
  else
    echo "Scenario creation failed with $CODE"
    docker logs nussknacker_designer
    exit 1
  fi

  echo "Importing scenario"
  RESPONSE=$(curl -u admin:admin -F "process=@DetectLargeTransactions.json" -X POST http://admin:admin@localhost:8081/api/processes/import/DetectLargeTransactions)
  echo "Saving scenario"
  start='{"process":'
  end=',"comment": ""}'
  curl 'http://localhost:8081/api/processes/DetectLargeTransactions' -X PUT -u admin:admin -v \
      -H 'Accept: application/json, text/plain, */*' \
      -H 'Content-Type: application/json;charset=UTF-8' \
      --data-raw "${start}${RESPONSE}${end}"
  curl -u admin:admin -X POST 'http://localhost:8081/api/processManagement/deploy/DetectLargeTransactions' -v
}

waitTime=0
sleep=10
waitLimit=120
checkCode() {
 echo "$(curl -s -o /dev/null -w "%{http_code}" "http://admin:admin@localhost:8081/$1")"
}

waitForOK() {
  echo "$2"

  URL_PATH=$1
  STATUS_CODE=$(checkCode "$URL_PATH")
  CONTAINER_FOR_LOGS=$4

  while [[ $waitTime -lt $waitLimit && $STATUS_CODE != 200 ]]
  do
    sleep $sleep
    waitTime=$((waitTime+sleep))
    STATUS_CODE=$(checkCode "$URL_PATH")

    if [[ $STATUS_CODE != 200  ]]
    then
      echo "Service still not started within $waitTime sec and response code: $STATUS_CODE.."
    fi
  done
  if [[ $STATUS_CODE != 200 ]]
  then
    echo "$3"
    docker-compose -f docker-compose-env.yml -f docker-compose.yml logs --tail=200 $CONTAINER_FOR_LOGS
    exit 1
  fi
}

main;
exit;