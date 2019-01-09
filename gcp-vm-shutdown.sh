#!/bin/bash

# Get creds
source creds.txt


# Initialise logging
logfile="gcp-clearup-log.txt"
exec &>> $logfile
now="$(date)"
printf "\n\n\n\n\n\n*** Clearing up GCP Running Instances on `date` ***\n\n" >> $logfile


# Ensure we're in the right place in GCP
gcloud config set project auto-hack-cloud
gcloud config set compute/zone europe-west2-b


# Get currently list of instances
INSTANCES=`gcloud compute instances list --format='table(name,zone,networkInterfaces[0].accessConfigs[0].natIP,status,labels.list())'`


# Log the instances currently present
printf "\nCurrent list of instances:\n" >> $logfile
printf "$INSTANCES" >> $logfile


# Cycle through all running instances...
for vm in `printf "$INSTANCES" | grep RUNNING | grep "created-by=demo" | awk '{print $1}'`; do
	printf "\n\nGoing to shut down $vm\n" >> $logfile
	#. ..and shut them down
	gcloud compute instances stop $vm
done


# Deregister firewalls
for vm in `printf "$INSTANCES" | grep TERMINATED | grep "created-by=demo" | grep fw- | awk '{print $1}'`; do
	printf "\n\nGoing to deregister $vm\n" >> $logfile
	# Start-up firewall
	gcloud compute instances start $vm
	# Get the mgmt IP address
	INSTANCES=`gcloud compute instances list --format='table(name,zone,networkInterfaces[0].accessConfigs[0].natIP,status,labels.list())'`
	ip=`printf "$INSTANCES" | grep $vm | awk '{print $3}'`
	url="https://"$ip
	# Wait until it's up
	printf "Waiting for firewall mgmt GUI ($url) page to be up... - $(date)\n" >> $logfile
	sleep 60s
	while [ `curl --write-out "%{http_code}\n" -m 2 -k --silent --output /dev/null $url` -eq 000 ]
	do
		printf "Waiting for firewall mgmt GUI page to be up...\n" >> $logfile
		sleep 5s
	done
	printf "Firewall is still booting, but web server component is up now - $(date)\n"
	sleep 60s
	printf "Waited 1 minute, gonna try de-registering now..."
	# Set firewall API key variable
	FWKEY=LUFRPT1ldHZXYkk1aFJ0TnY1T09MR0pMWmR3TUtQQTQ9OVRHaEpLZW90Y2lkOHgyVFRuRmp0dCs3akZWRnNDa0h4QW5wZlh6cDdHRT0=
	# Add CSP licencing API key
	SETLICENCEAPIKEY=`curl -k -X GET 'https://'$ip'/api/?type=op&cmd=<request><license><api-key><set><key>6a85f78e5cd9a7eccae9333361f3cbd798ee1e8c70bad9dfeb027f345e562d2d</key></set></api-key></license></request>&key='$FWKEY`
	# Deactive licences
	DEREGISTER=`curl -k -X GET 'https://'$ip'/api/?type=op&cmd=<request><license><deactivate><VM-Capacity><mode>auto</mode></VM-Capacity></deactivate></license></request>&key='$FWKEY`
	# Check if licence de-registration happened successfully
	printf "$DEREGISTER" >> $logfile
	if [[ ${DEREGISTER} == *"Successfully deactivated old keys"* ]];then
    	# Seems it worked, so delete the instance
		printf "\nGoing to delete $vm\n" >> $logfile
		gcloud -q compute instances delete $vm

		#
		#
		# THEN DELETE SUBNETWORKS AND ROUTES ETC
		#
		#

	else
		# De-registration failed, send an email notification
		EMAILADDRESS=jholland@paloaltonetworks.com
		MSG=$'Hi, '"$vm"' on '"$url"' did not de-register!'
		curl -s --user 'api:'"$MAILGUN"'' https://api.mailgun.net/v3/demo.panw.co.uk/messages -F from='Palo Alto Networks <demo@demo.panw.co.uk>' -F to=$EMAILADDRESS -F subject='AUTOCLOUD' -F html=' '"$MSG"' '
	fi
done


# Cycle through all NON-FIREWALL terminated instances... (these were shutdown manually, or automatically shut down 24 hours prior, by the above for-loop)
for vm in `printf "$INSTANCES" | grep TERMINATED | grep "created-by=demo" | grep -E "kali-|linux-|db-" | awk '{print $1}'`; do
	printf "\nGoing to delete $vm\n" >> $logfile
	# ...and delete them
	gcloud -q compute instances delete $vm
done



# Get updated list of instances
INSTANCES=`gcloud compute instances list --format='table(name,zone,networkInterfaces[0].accessConfigs[0].natIP,status,labels.list())'`


# Log another note of all the instances, to compare against before the script started
printf "\nUpdated list of instances:\n" >> $logfile
printf "$INSTANCES" >> $logfile
printf "\n\n\n\n" >> $logfile
