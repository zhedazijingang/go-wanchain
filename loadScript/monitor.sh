#!/bin/bash


SYSLOG_SERVER="log.wanchain.org"

SYSLOG_PORT=$1
LOG_NAME="system_metrics_pos_node"
HOSTNAME=""
if [ $SYSLOG_PORT -eq 1514 ]; then
	HOSTNAME=`ps -ef | grep gwan | grep -v grep | awk  '{print $19}' | awk -F ':' '{print $1}'`
else
	HOSTNAME=`ps -ef | grep gwan | grep -v grep | awk  '{print $20}' | awk -F ':' '{print $1}'`
fi

collect_metrics() {

    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    CPU_CORES=$(nproc)

    MEM_TOTAL=$(free -m | grep Mem | awk '{print $2}')
    MEM_USED=$(free -m | grep Mem | awk '{print $3}')
    MEM_FREE=$(free -m | grep Mem | awk '{print $4}')

    DISK_TOTAL=$(df -h / | tail -1 | awk '{print $2}')
    DISK_USED=$(df -h / | tail -1 | awk '{print $3}')
    DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')


    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')

    MESSAGE="hostname=$HOSTNAME cpu_usage=${CPU_USAGE}% cpu_cores=${CPU_CORES} mem_total=${MEM_TOTAL}MB mem_used=${MEM_USED}MB mem_free=${MEM_FREE}MB disk_total=${DISK_TOTAL} disk_used=${DISK_USED} disk_usage=${DISK_USAGE}% load_avg=${LOAD_AVG}"

    logger -n "$SYSLOG_SERVER" -P "$SYSLOG_PORT" -t "$LOG_NAME" -p "user.info" "$MESSAGE"
}

while true; do
	collect_metrics
	sleep 3600
done


