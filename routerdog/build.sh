#!/bin/sh

MODULE="routerdog"
VERSION="1.0"
TITLE="路由狗"
DESCRIPTION="路由狗，路由看家好帮手~"
HOME_URL="Module_routerdog.asp"

# Check and include base
DIR="$( cd "$( dirname "$BASH_SOURCE[0]" )" && pwd )"

# now include build_base.sh
. $DIR/../softcenter/build_base.sh

# change to module directory
cd $DIR

# do something here
do_build_result
