#!/bin/bash
# Author: surpassmebyme@gmail.com
# Date:   2024-03-22

KUBECTL_PATH=$(readlink -f $(which kubectl))
TMP_FILENAME="/tmp/tmpPodImage.txt"

function printMessage(){
   dt=$(date '+%F %T')
   type=$([ -z "$1" ] && echo "INFO" || echo "$1" | tr [:lower:] [:upper:])
   message=$([ -z "$2" ] && echo "NONE" || echo "$2")

   if [ "${type}" == "INFO" ]
      then
       echo -e "\033[32m${dt} ${type} ${message}\033[0m"
   elif [ "${type}" == "WARNING" ]
      then
        echo -e "\033[33m${dt} ${type} ${message}\033[0m"
   elif [ "${type}" == "ERROR" ]
      then
       echo -e "\033[31m${dt} ${type} ${message}\033[0m"
   else
      echo -e "\033[34m${dt} ${type} or ${message} error \033[0m"
   fi
}

function getKubernetesContainerRuntime(){
    containerRuntime=$(${KUBECTL_PATH} get node -o jsonpath={"$.items[0].status.nodeInfo.containerRuntimeVersion"} | awk -F ":" '{print $1}')
    echo ${containerRuntime}
}

function getContainerRuntimeCommand(){
   containerRuntime=$(getKubernetesContainerRuntime)
   CONTAINER_RUNTIME=""
   if [ "${containerRuntime}" == "docker" ];then
	  DOCKER_PATH=$(readlink -f $(which docker))
	  ${DOCKER_PATH} version 1>/dev/null 2>/dev/null
      if [ "$?" == "0" ];then
		CONTAINER_RUNTIME="docker"
	  else
		CONTAINER_RUNTIME="sudo docker"
		fi
    elif [ "${containerRuntime}" == "containerd" ];then
	  CONTAINERD_PATH=$(readlink -f $(which crictl))
	  ${CONTAINERD_PATH} images 1>/dev/null 2>/dev/null
      if [ "$?" == "0" ];then
		CONTAINER_RUNTIME="crictl"
	  else
		CONTAINER_RUNTIME="sudo crictl"
		fi
    else
	  CONTAINER_RUNTIME=""
	fi
    echo ${CONTAINER_RUNTIME}
}

function getCustomColumns(){
  echo "" > "${TMP_FILENAME}"
  echo -n "POD_NAME IMAGE IMAGE_ID STATUS NodeName " | awk '{printf "%-50s %-100s %-30s %-10s %-10s\n",$1,$2,$3,$4,$5}' > ${TMP_FILENAME}
  ns=$( [ -z "$1" ] && echo "-n kube-system" || echo "-n $1")
  CONTAINER_RUNTIME=$(getContainerRuntimeCommand)
  printMessage "INFO" "Current namespace is ${ns},container command is ${CONTAINER_RUNTIME}"
  pods=$(${KUBECTL_PATH} get pods ${ns} -o custom-columns=POD_NAME:.metadata.name
  )
  for item in ${pods}
    do  
	    if [ "${item}" == "POD_NAME" ];then
		  continue
		fi
		kubectlRet=$(${KUBECTL_PATH} get pods ${ns} ${item} -o custom-columns=POD_NAME:.metadata.name,IMAGE:.spec.containers[*].image,STATUS:.status.phase,NodeName:.spec.nodeName --sort-by=.metadata.name | grep -v POD_NAME )
		if [ "$?" -ne "0" ];then
			continue
		else
		     podName=$(echo ${kubectlRet} | awk '{print $1}')
			 podImages=$(echo ${kubectlRet} | awk '{print $2}' | awk -F "," '{print $1 " " $2}')
			 podStatus=$(echo ${kubectlRet} | awk '{print $3}')
			 nodeName=$(echo ${kubectlRet} | awk '{print $4}')
			 #echo "podImages is ${podImages}"
			 for image in ${podImages}
			   do
			     containerRuntime=$(getKubernetesContainerRuntime)
				 if [ "${containerRuntime}" == "docker" ];then
					imageID=$(${CONTAINER_RUNTIME} images ${image} --format '{{.ID}}' 2>/dev/null )
					if [ -z "${imageID}" ];then
						imageID="Unknown"
					fi
					echo -e "${podName} ${image} ${imageID} ${podStatus} ${nodeName}" >> ${TMP_FILENAME}
				 elif [ "${containerRuntime}" == "containerd" ];then
				    sha=$(${CONTAINER_RUNTIME} inspecti -q ${image} 2>/dev/null | jq  .status.id | awk -F ":" '{print $2}')
					imageID=${sha:0:12}
					if [ -z "${imageID}" ];then
						imageID="Unknown"
					fi
					echo -e "${podName} ${image} ${imageID} ${podStatus} ${nodeName}" >> ${TMP_FILENAME}
				 else
				    printMessage WARNING "Unknown container runtime for kubernetes!!!"
				 fi
			   done 
		fi	
		#sleep 10000
	done

	while read line
	  do 
        echo -n "${line}" | awk '{printf "%-50s %-125s %-15s %-8s %-8s\n",$1,$2,$3,$4,$5}'
	  done < ${TMP_FILENAME}
}


getCustomColumns "$1"
