while true; do curl -vX POST http://127.0.0.1:9400 -d @./replicas.json --header "Content-Type: application/json"; sleep 1;done
