#!/usr/bin/env bash

# update Go

release=$(curl --silent https://golang.org/doc/devel/release.html | grep -Eo 'go[0-9]+(\.[0-9]+)+' | sort -V | uniq | tail -1)
os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(case "$(uname -m)" in i*) echo '386' ;; x*) echo 'amd64' ;; *) echo 'armv61'; esac)
where=$(dirname $(dirname $(which go)))
echo "installing Go for $os-$arch-$release in $where"
rm -rf $where && mkdir -p $where
curl --silent https://storage.googleapis.com/golang/$release.$os-$arch.tar.gz \
  | tar -vxz --strip-components 1 -C $where