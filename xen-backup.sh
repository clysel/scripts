#!/bin/bash

# @Christian E. Lysel
# 
# Requirements
# GNU parallel on the backup server
# nc - netcat on all hosts for sysloging
#    use "yum -y --enablerepo=base,extras install nc" to install nc on the Citrix XEN hosts.
# NFS server on the backup server
# The backup clients hostnames includes "xen"

function configuration {
	# Client settings
	client_job=2 # the number of parallel backup jobs per client
	client_user=root
	client_path=/root/backup 
	client_nfsserver=192.168.1.2:/backup/xen

	# Server settings
	server_hostname=backup
	server_user=xen-backup
	server_path=/backup/

	umask 0000
}


function error_exit {
  message=$1

  log "ERR: $1"
  exit 1
}


function log {
  message=$1

  echo $(date +'%F %T') "$1"
}


function backup_host {

	# This is running on the backup server,
	# and calling the XEN hosts via parallel,
	# to distribute the load even.

	# first argument
	host=$1 

	# check requrements
	hostname | grep -v $server_hostname > /dev/null && error_exit "Must run on host $server_hostname"
	whoami | grep -v $server_user > /dev/null && error_exit "Must run as user $server_user"

	[ ! -d $server_path ]  && error_exit "Backup directory $server_path not found"
	date=$(date --rfc-3339=date)
	server_path=$server_path/$date/$(hostname)/
	mkdir -p $server_path
	[ ! -d $server_path ]  && error_exit "Backup directory $server_path not found"

	# mount NFS from backup server on backup clients
	parallel --nonall -S $hosts mount -t nfs $client_nfsserver $client_path

	# get uuid list
	parallel -S $hosts  > $server_path/$host.uuid <<EOF
xe vm-list is-control-domain=false is-a-snapshot=false params=all | awk '/^uuid/ {print \$5}'
EOF
	# run backup, stop if we detect a failure
	parallel --halt 1 -S $hosts_ncpu $client_path/backup.sh < $server_path/$host.uuid 

	# Look for backup-snapshots ... if there is any left, it's a error
	parallel -S $hosts <<EOF && error_exit "Error BACKUP-SNAPSHOT found"
xe template-list is-a-snapshot=true params=all | grep -v BACKUP-SNAPSHOT > /dev/null
EOF
	# umount NFS on backup clients
	parallel --nonall -S $hosts umount $client_path
}


function backup_pool {

	# This is running on the backup server,
	# and calling the XEN hosts via parallel,
	# to distribute the load even.

	# first argument
	pool=$1 

	# check requrements
	hostname | grep -v $server_hostname > /dev/null && error_exit "Must run on host $server_hostname"
	whoami | grep -v $server_user > /dev/null && error_exit "Must run as user $server_user"

  #	mkdir -p /root/backup

	[ ! -d $server_path ]  && error_exit "Backup directory $server_path not found"
	date=$(date --rfc-3339=date)
	server_path=$server_path/$date/$(hostname)/
	mkdir -p $server_path
	[ ! -d $server_path ]  && error_exit "Backup directory $server_path not found"

	# mount NFS from backup server on backup clients
	parallel --nonall -S $hosts mount -t nfs $client_nfsserver $client_path

	# get uuid list
	parallel -S $hosts > $server_path/$pool.uuid <<EOF
xe vm-list is-control-domain=false is-a-snapshot=false params=all | awk '/^uuid/ {print \$5}'
EOF
	# run backup, stop if we detect a failure
	parallel --halt 1 -S $hosts_ncpu $client_path/backup.sh < $server_path/$pool.uuid 

# Look for backup-snapshots ... if there is any left, it's a error
	parallel -S $hosts <<EOF && error_exit "Error BACKUP-SNAPSHOT found"
xe template-list is-a-snapshot=true params=all | grep -v BACKUP-SNAPSHOT > /dev/null
EOF
	# backup pool database
	parallel -S $hosts <<EOF || error_exit "Error with pool database backup $pool.pool.database"
xe pool-dump-database file-name="$client_path/$date/$(hostname)/$pool.pool.database" 
EOF

	# umount NFS on backup clients
	parallel --nonall -S $hosts umount $client_path
}


function backup_uuid {

	# This is running on the XEN hosts as they are the backup clients

	vmuuid=$1 # first argument
	[ -s $vmuuid ]  && error_exit "No arguments. Please provide UUID of VM to backup"

	hostname | grep -i backup > /dev/null && error_exit "Must run on a XEN host"
	whoami | grep -v root > /dev/null && error_exit "Must run as user root"

	[ ! -d $client_path ]  && error_exit "Backup directory $client_path not found"
	date=$(date --rfc-3339=date)
	client_path=$client_path/$date/$(hostname)/
	mkdir -p $client_path
	[ ! -d $client_path ]  && error_exit "Backup directory $client_path not found"

	vmname=$(xe vm-list uuid=$vmuuid params=name-label --minimal)

	[ ! -n "$vmname" ] && error_exit "Empty VM name"	

	log "Exporting $vmname"
	snapuuid=$(xe vm-snapshot uuid=$vmuuid new-name-label="BACKUP-SNAPSHOT-$vmuuid-$date")
	
	xe template-param-set is-a-template=false ha-always-run=false uuid=$snapuuid
	xe vm-export compress=true vm=$snapuuid filename="$client_path/$vmname.xva" 
	xe vm-uninstall uuid=$snapuuid force=true > /dev/null || error_exit "Can't delete snapshot for $vmname"
        
	[ ! -s "$client_path/$vmname.xva" ] && error_exit "Backup file $client_path/$vmname.xva not found or empty"
	log "Export completed for $vmname"
}


# We require 1 argument
argument=$1

configuration

log "Starting $(hostname) $0 $argument"

case $argument in
	linux )
		hosts="1/root@xenlinux1,1/root@xenlinux2,1/root@xenlinux3"
		hosts_ncpu="$client_job/root@xenlinux1,$client_job/root@xenlinux2,$client_job/root@xenlinux3"
    		backup_pool linux
		;;

	windows )
		hosts="1/root@xenwin1/root@xenwin22,1/root@xenwin3"
		hosts_ncpu="$client_job/root@xenwin1,$client_job/root@xenwin2,$client_job/root@xenwin3"
        	backup_pool windows
		;;
	xen? )
		hosts="1/root@$argument"
		hosts_ncpu="$client_job/root@$argument"
		backup_host $argument
		;;


	????????-????-????-????-????????????)
		vmuuid=$argument
		backup_uuid  $vmuuid
		;;

	*)
		error_exit "Unknown argument, please provide a pool name (linux or windows) or a hostname (xen1 or xen5) or a VM UUID"
		;;
esac
