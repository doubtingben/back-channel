#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

docker run -v $(pwd)../logstash/pipeline/:/usr/share/logstash/pipeline/ --rm -ti backchannel_logstash logstash --config.test_and_exit
