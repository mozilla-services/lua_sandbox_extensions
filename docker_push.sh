#!/bin/bash

tag=""
if [[ $1 = "master" ]]; then
    tag="mozilla/lua_sandbox_extensions:master"
elif [[ $1 = "dev" ]]; then
    tag="mozilla/lua_sandbox_extensions:dev"
else
    exit 1
fi

docker tag mozilla/lua_sandbox_extensions $tag
docker login -u "$DOCKER_USER" -p "$DOCKER_PASS"
docker push $tag
