#!/bin/bash
sudo /usr/sbin/sshd

sudo chown -R gpadmin:gpadmin /var/lib/gpdb/data

source ${GPHOME}/greenplum_path.sh

if [ "$GP_NODE" == "master" ]
then
    echo 'Node type='$GP_NODE
    if [ ! -f $HOSTFILE ]; then
        echo 'hostfile not exist. Automatically generated it use environment variable GP_SEG_DOMAIN through DNS.'
        
        if [[ -z "$GP_SEG_DOMAIN" ]]; then
            GP_SEG_DOMAIN="tasks.db_seg"
        fi

        ./swarm_service_replicas_get.sh $GP_SEG_DOMAIN
        TAR_REPLICAS=$?
        if [[ $TAR_REPLICAS -ne 0 ]]; then
            echo "Need $TAR_REPLICAS hosts as clusters"
        else
            echo "WARNING: cant determine the number of hosts clusters. Continue when scanning more than 1 host."
            TAR_REPLICAS=1
        fi

        HOST_COUNT=0
        until [[ $HOST_COUNT -ge $TAR_REPLICAS ]]; do
            sleep 1
            echo "Scanning swarm service ip..."
            rm -f $HOSTFILE
            ./swarm_service_ip_scan.sh $GP_SEG_DOMAIN $HOSTFILE
            if [[ $? -ne 0 ]]; then
                echo "ERROR: create hostfile error."
                exit 1
            fi

            HOST_COUNT=$(cat $HOSTFILE | wc -l)
            HOST_COUNT=$((HOST_COUNT-1))
            echo "Scan result $HOST_COUNT IP of service."
        done
    fi

    if [ ! -f hostlist ]; then
        yes | cp $HOSTFILE hostlist
    fi

    if [ ! -d $MASTER_DATA_DIRECTORY ]; then
        echo 'Master directory does not exist. Initializing master from gpinitsystem_reflect.'
        
        # gpssh-exkeys -f hostlist
        # if [[ $? -ne 0 ]]; then
        #     echo "ERROR: gpssh-exkeys error."
        #     exit 1
        # fi
        # echo "Key exchange complete"

        if [[ -z "$GP_PASSWD" ]]; then
            echo "WARNING: missing password of gpdb gpadmin, use default 'dataroad'"
            GP_PASSWD="dataroad"
        fi

        gpinitsystem -a -c gpinitsys --su_password=$GP_PASSWD -h hostlist
        if [[ $? -ne 0 ]]; then
            echo "ERROR: gpinitsystem error."
            exit 1
        fi
        echo "Master node initialized"

        # receive connection from anywhere.. This should be changed!!
        echo "host all all 0.0.0.0/0 md5" >>$MASTER_DATA_DIRECTORY/pg_hba.conf
        echo 'pg_hba.conf changed. Reload config without restart gpdb.'
        gpstop -u
    else
        echo 'Master exists. Starting gpdb.'
        gpstart -a
    fi
    if [[ $? -ne 0 ]]; then
        echo "ERROR: gpdb start error."
        exit 1
    fi
else
    echo 'Node type='$GP_NODE
    echo "Ready."
fi
exec "$@"
