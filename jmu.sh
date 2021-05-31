#!/bash/sh 

. /etc/profile
mucUrl="https://github.com/siruslan/java-memory-usage/raw/master/dist/MemoryUsageCollector.jar"

run () {

	user=${1:-$USER}
	if [ -z "$user" ]; then
		user="user$RANDOM"
	fi

	testId=${2:-$TESTID}
	if [ -z "$testId" ]; then
		testId="Test $(date)"
	fi

	debug=${3:-$DEBUG}
	if [ "$debug" != "0" -a "$debug" != "false" ]; then
		debug=1
	else
		debug=0
	fi

	echo "***"
	hostId=$(hostname)
	echo $hostId
	os=$(cat /etc/*-release)
	[ $debug -ne 0 ] && echo $os
	nodeType=""
	meta="/etc/jelastic/metainf.conf"
	if [ -f $meta ]; then
		nodeType=$(cat $meta | grep TYPE)
		[ $debug -ne 0 ] && echo $nodeType
	fi 
	mem=$(free -m | grep -v +)
	[ $debug -ne 0 ] && echo $mem

	osMemTotal=$(echo $mem | cut -d' ' -f8)
	osMemUsed=$(echo $mem | cut -d' ' -f9)
	osMemFree=$(echo $mem | cut -d' ' -f10)
	osMemShared=$(echo $mem | cut -d' ' -f11)
	osMemBuffCache=$(echo $mem | cut -d' ' -f12)
	osMemAvail=$(echo $mem | cut -d' ' -f13)
	swapTotal=$(echo $mem | cut -d' ' -f15)
	swapUsed=$(echo $mem | cut -d' ' -f16)
	swapFree=$(echo $mem | cut -d' ' -f17)
	if [ $(command -v docker) ]; then
		dockerVersion=$(docker -v)
		if [ $(command -v kubeadm) ]; then
			$dockerVersion=$(echo -e "$dockerVersion\n$(kubeadm version | tr -d '&')")
		fi
	    	[ $debug -ne 0 ] && echo $dockerVersion
	fi
	port=10239
	#Very useful JVM Dynamic Attach utility - all-in-one jmap + jstack + jcmd + jinfo functionality in a single tiny program
	#No installed JDK required, works with just JRE, supports Linux containers. 
	#Credits to Andrei Pangin https://github.com/apangin
	if [ -f /etc/alpine-release ]; then
        	apk add --no-cache jattach --repository http://dl-cdn.alpinelinux.org/alpine/edge/community/
        	apk add --no-cache procps
		jattach="jattach"		
	else
		curl -sLo /tmp/jattach https://github.com/apangin/jattach/releases/download/v1.5/jattach
		chmod +x /tmp/jattach
		jattach="/tmp/jattach"
	fi
	#Simple collector of Java memory usage metrics   
    curl -sLo /tmp/app.jar $mucUrl
	jar=/tmp/app.jar

	for pid in $(pgrep -l java | awk '{print $1}'); do
		echo -e "---\npid=$pid"
		[ $debug -ne 0 ] && echo "$jattach $pid jcmd VM.version"
		javaVersion=$($jattach $pid jcmd VM.version | grep -v "Connected to remote JVM" | grep -v "Response code = 0")
		result=$?
		if [ $result -ne 0 ]; then
			javaVersion="Java on Host: $(java -version 2>&1)"
			result=$?
		fi

        [ $(command -v docker) ] && util=docker || util=crictl    


        if [ $(command -v docker) ] | [ $(command -v kubectl) ] ; then
			[ $debug -ne 0 ] && echo "Collecting info about docker container limits..."
			ctid=$(getCtInfo $pid id)
			[ $debug -ne 0 ] && echo "ctid=$ctid"
			st=$($util stats $ctid --no-stream --format "{{.MemUsage}}")
			dockerUsed=$(echo $st | cut -d'/' -f1 | tr -s " " | xargs)
			dockerLimit=$(echo $st | cut -d'/' -f2 | tr -s " " | xargs)
			if [ $result -ne 0 ]; then
				javaVersion=$($util exec $ctid java -version 2>&1) 
			fi
		fi

		[ $debug -ne 0 ] && echo $javaVersion

		if [[ "$javaVersion" == *"JDK 7."* || "$javaVersion" == *"1.7."* ]]; then
			echo "ERROR: Java 7 is not supported"
		else
			[ $debug -ne 0 ] && echo "$jattach $pid jcmd VM.flags"
			jvmFlags=$($jattach $pid jcmd VM.flags | grep -v "Connected to remote JVM" | grep -v "Response code = 0")
			[ $debug -ne 0 ] && echo $jvmFlags

			s=":InitialHeapSize="
			initHeap=$(toMB $(echo ${jvmFlags#*$s} | cut -d' ' -f1))
			s=":MaxHeapSize="
			maxHeap=$(toMB $(echo ${jvmFlags#*$s} | cut -d' ' -f1))
			s=":MaxNewSize="
			maxNew=$(toMB $(echo ${jvmFlags#*$s} | cut -d' ' -f1))
			s=":MinHeapDeltaBytes="
			minHeapDelta=$(toMB $(echo ${jvmFlags#*$s} | cut -d' ' -f1))
			s=":NewSize="
			newSize=$(toMB $(echo ${jvmFlags#*$s} | cut -d' ' -f1))
			s=":OldSize="
			oldSize=$(toMB $(echo ${jvmFlags#*$s} | cut -d' ' -f1))


			currentPort=$($jattach $pid jcmd ManagementAgent.status | grep -v "Connected to remote JVM" | grep -v "Response code = 0" | grep jmxremote.port | cut -d'=' -f2 | tr -s " " | xargs)
			if [ -z "$currentPort" ]; then
				s="jmxremote.port="
				proc=$(ps ax | grep $pid | grep $s)
				currentPort=$(echo ${proc#*$s} | cut -d'=' -f1)
			fi			
			if [ -z "$currentPort" ]; then
				start="ManagementAgent.start jmxremote.port=$port jmxremote.rmi.port=$port jmxremote.ssl=false jmxremote.authenticate=false"
				[ $debug -ne 0 ] && echo "$jattach $pid jcmd \"$start\""
				resp=$($jattach $pid jcmd "$start" 2>&1 | grep -v "Connected to remote JVM" | grep -v "Response code = 0")
				result=$?
				[ $debug -ne 0 ] && echo $resp
				p=$port
			else 
				result=0
				[ $debug -ne 0 ] && echo "Connecting to running JMX at port $currentPort"
				p=$currentPort
			fi
			

			if [ $result -eq 0 ]; then
				[ $debug -ne 0 ] && echo "java -jar $jar -p=$p 2>&1"
				resp=$(java -jar $jar -p=$p 2>&1)
				result=$?
				[ $debug -ne 0 ] && echo $resp

                if [ $(command -v docker) ] | [ $(command -v kubectl) ] ; then
                    ip=$(getCtInfo $pid)
					if [[ "$resp" == *"Failed to retrieve RMIServer stub"* ]]; then
						[ $debug -ne 0 ] && echo "java -jar $jar -h=$ip -p=$p"
						resp=$(java -jar $jar -h=$ip -p=$p)
						result=$?
						[ $debug -ne 0 ] && echo $resp
					fi
					# If previous attempts failed then execute java -jar app.jar inside docker cotainer 
                    # If K8s, then we have to use CRIO tools to execute command, also crictl doesn't have cp command implemented
					if [ $result -ne 0 ]; then
					   [ $(command -v docker)] && docker cp $jar $ctid:$jar || $util exec $ctid wget -qO /tmp/app.jar $mucUrl
						resp=$($util exec $ctid java -jar $jar -p=$p) 
						result=$?
						$util exec -u 0 $ctid rm -rf $jar 
						[ $debug -ne 0 ] && echo $resp
					fi
				fi

				options=$(echo $resp | cut -d'|' -f1)
				if [ $result -eq 0 ]; then
					xms=$(echo $resp | cut -d'|' -f2)
					heapUsed=$(echo $resp | cut -d'|' -f3)
					heapCommitted=$(echo $resp | cut -d'|' -f4)
					xmx=$(echo $resp | cut -d'|' -f5)
					nonHeapInit=$(echo $resp | cut -d'|' -f6)
					nonHeapUsed=$(echo $resp | cut -d'|' -f7)
					nonHeapCommitted=$(echo $resp | cut -d'|' -f8)
					nonHeapMax=$(echo $resp | cut -d'|' -f9)
					gcType=$(echo $resp | cut -d'|' -f10)
					nativeMemory=$(echo $resp | cut -d'|' -f11)
				fi
				if [ -z "$currentPort" ]; then
					[ $debug -ne 0 ] && echo "$jattach $pid jcmd ManagementAgent.stop"
					$jattach $pid jcmd ManagementAgent.stop | grep -v "Connected to remote JVM" | grep -v "Response code = 0"
				fi
				echo "Done"
			else
                if [ $(command -v docker) ] | [ $(command -v kubectl) ] ; then
					if [[ "$resp" == *"Failed to retrieve RMIServer stub"* ]]; then
						ip=$(getCtInfo $pid)	
						[ $debug -ne 0 ] && echo "java -jar $jar -h=$ip"
						resp=$(java -jar $jar -h=$ip)
						result=$?
						[ $debug -ne 0 ] && echo $resp
					fi
					#If previous attempts failed then execute java -jar app.jar inside docker cotainer 
					if [ $result -ne 0 ]; then
						ctid=$(getCtInfo $pid id)
                        [ $(command -v docker)] && docker cp $jar $ctid:$jar || $util exec $ctid wget -qO /tmp/app.jar $mucUrl
                        resp=$($util exec $ctid java -jar $jar)
						result=$?
                        $util exec -u 0 $ctid rm -rf $jar
						[ $debug -ne 0 ] && echo $resp
					fi

				fi
				options="$resp"
				echo "ERROR: can't enable JMX for pid=$pid"
			fi
		fi

		curl -fsSL -d "user=$user&testId=$testId&hostId=$hostId&os=$os&nodeType=$nodeType&pid=$pid&osMemTotal=$osMemTotal&osMemUsed=$osMemUsed&osMemFree=$osMemFree&osMemShared=$osMemShared&osMemBuffCache=$osMemBuffCache&osMemAvail=$osMemAvail&swapTotal=$swapTotal&swapUsed=$swapUsed&swapFree=$swapFree&javaVersion=$javaVersion&options=$options&gcType=$gcType&xmx=$xmx&heapCommitted=$heapCommitted&heapUsed=$heapUsed&xms=$xms&nonHeapMax=$nonHeapMax&nonHeapCommitted=$nonHeapCommitted&nonHeapUsed=$nonHeapUsed&nonHeapInit=$nonHeapInit&nativeMemory=$nativeMemory&jvmFlags=$jvmFlags&initHeap=$initHeap&maxHeap=$maxHeap&minHeapDelta=$minHeapDelta&maxNew=$maxNew&newSize=$newSize&oldSize=$oldSize&dockerVersion=$dockerVersion&dockerUsed=$dockerUsed&dockerLimit=$dockerLimit" -X POST "https://cs.demo.jelastic.com/1.0/development/scripting/rest/eval?script=stats&appid=cc492725f550fcd637ab8a7c1f9810c9"
		echo ""
	done
	if [ -f /etc/alpine-release ]; then
		apk del jattach
		rm -rf $jar
	else 
		rm -rf $jar $jattach
	fi
}

getCtInfo () {
	local pid="$1"

	if [[ -z "$pid" ]]; then
		echo "Missing host PID argument."
		exit 1
	fi

	if [ "$pid" -eq "1" ]; then
		echo "Unable to resolve host PID to a container name."
		exit 2
	fi
    if [ $(command -v docker) ]; then
    #ps returns values potentially padded with spaces, so we pass them as they are without quoting.
        local parentPid="$(ps -o ppid= -p $pid)"
        local ct="$(ps -o args= -f -p $parentPid | grep containerd-shim)"
        m="moby/"
        if [[ -n "$ct" ]]; then
  	        local ctid=$(echo ${ct#*$m} | cut -d' ' -f1)
  	        if [ "$2" == "id" ]; then
  		        echo $ctid
  	        else
  		        docker inspect $ctid | grep IPAddress | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"
  	        fi
        else
  	        getCtInfo "$parentPid" $2
        fi
    fi
    if [ $(command -v kubectl) ]; then
            ct_hostname=$(nsenter -t $(pidof java | awk '{print $1}') -u hostname)
            pod_id=$(crictl pods --name $ct_hostname | tail -1 | awk '{print $1}')
            local ctid=$(crictl ps -a | grep $pod_id | awk '{print $1}')
            if [ "$2" == "id" ]; then
                echo $ctid
            else
            crictl inspectp --output table $pod_id |  grep "IP Addresses" |  grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"
            fi
    fi
}

toMB () {
	local mb=1048576
	local value=$1

	if echo "$value" | grep -qE '^[0-9]+$' ; then
		echo $(($value/$mb))
	else
		echo ""
	fi	
}

run $1 $2 $3
