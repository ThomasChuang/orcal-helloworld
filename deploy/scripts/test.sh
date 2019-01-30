#!/bin/bash

set -e

IMG=$(grep FROM Dockerfile | awk '{print $2; exit}')

echo "running tests in image: ${IMG}"

sudo docker run \
    --rm \
    -e TZ='Asia/Singapore' \
    -v /etc/localtime:/etc/localtime \
    -v $PWD:/app \
    -w /app \
    $IMG \
    bash -c "date && npm install && npm run test"
