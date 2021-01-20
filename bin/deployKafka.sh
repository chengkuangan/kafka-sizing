#!/bin/bash

########################################################################################################################
### 
### Installation script for Kafka Sizing.
### Contributed By: CK Gan (chgan@redhat.com)
### Complete setup guide and asset at https://github.com/chengkuangan/kafkasizing
### 
########################################################################################################################

APPS_NAMESPACE="kafka-sizing"
KAFKA_CLUSTER_NAME="kafka-cluster"
APPS_PROJECT_DISPLAYNAME="Kafka Sizing"
OC_USER=""
STRIMZI_SLACKAPI_URL="https:\/\/ssa-mr19696.slack.com"
STRIMZI_SLACK_CHANNEL="#paygate-strimzi"
PROCEED_INSTALL="no"
KAFKA_TEMPLATE_FILENAME="kafka-persistent-1.yaml"
PARTITION_REPLICA_NUM="3"
TOPIC_PARTITION_NUM="3"
KAFKA_TOPIC="kafka-sizing"

RED='\033[1;31m'
NC='\033[0m' # No Color
GREEN='\033[1;32m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
YELLOW='\033[1;33m'

function init(){
    
    set echo off
    OC_USER="$(oc whoami)"
    set echo on
    
    if [ $? -ne 0 ] || [ "$OC_USER" = "" ]; then
        echo
        printWarning "Please login to Openshift before proceed ..."
        echo
        exit 0
    fi
    echo
    printHeader "--> Creating temporary directory ../tmp"
    mkdir ../tmp

    printHeader "--> Create OpenShift required projects if not already created"

    oc new-project $APPS_NAMESPACE
    
}

function printTitle(){
    HEADER=$1
    echo -e "${RED}$HEADER${NC}"
}

function printHeader(){
    HEADER=$1
    echo -e "${YELLOW}$HEADER${NC}"
}

function printLink(){
    LINK=$1
    echo -e "${GREEN}$LINK${NC}"
}

function printCommand(){
    COMMAND=$1
    echo -e "${GREEN}$COMMAND${NC}"
}

function printWarning(){
    WARNING=$1
    echo -e "${RED}$WARNING${NC}"
}

function printVariables(){
    echo 
    printHeader "The following is the parameters enter..."
    echo
    echo "APPS_NAMESPACE = $APPS_NAMESPACE"
    echo "APPS_PROJECT_DISPLAYNAME = $APPS_PROJECT_DISPLAYNAME"
    echo "KAFKA_CLUSTER_NAME = $KAFKA_CLUSTER_NAME"
    echo "OC_USER = $OC_USER"
    echo

}

function preRequisitionCheck(){
    
    echo 
    printHeader "--> Checking on pre-requisitions ..."
    echo
    
    # checking whether jq command tool is installed.
    hash jq
    
    if [ $? -ne 0 ]; then
        echo
        printWarning "You will required jq command line JSON processor ... "
        echo
        echo "Please download and install the command line tool from here ... https://stedolan.github.io/jq/"
        echo
        removeTempDirs
        exit 0
    fi

    oc project $APPS_NAMESPACE

    if [ $? -ne 0 ]; then
        echo
        printWarning "Please ensure you have the following OpenShift projects created before proceed ... "
        echo
        echo "   * $APPS_NAMESPACE"
        echo
        removeTempDirs
        exit 0
    fi

    oc get sub --all-namespaces -o custom-columns=NAME:.metadata.name | grep 'amq-streams'
    if [ $? -ne 0 ]; then
        echo
        printWarning "Please ensure you have installed the following Operators ... "
        echo
        echo "   * AMQ Streams"
        echo
        removeTempDirs
        exit 0
    fi
    oc get sub -o custom-columns=NAME:.metadata.name -n $APPS_NAMESPACE | grep prometheus
    if [ $? -ne 0 ]; then
        echo
        printWarning "Please install Promethues Operator in namespace $APPS_NAMESPACE"
        echo
        removeTempDirs
        exit 0
    fi
}

function deployKafka(){
    echo
    printHeader "--> Modifying ../templates/$KAFKA_TEMPLATE_FILENAME"
    echo
    mkdir ../tmp
    cp ../templates/$KAFKA_TEMPLATE_FILENAME ../tmp/$KAFKA_TEMPLATE_FILENAME
    #sed -i -e "s/my-cluster/$APPS_NAMESPACE/" ../tmp/$KAFKA_TEMPLATE_FILENAME
    echo 
    printHeader "--> Deploying AMQ Streams (Kafka) Cluster now ... Using ../templates/$KAFKA_TEMPLATE_FILENAME ..."
    oc apply -f ../tmp/$KAFKA_TEMPLATE_FILENAME -n $APPS_NAMESPACE
    
}

function createKafkaTopic(){
    echo
    printHeader "--> Creating Kafka Topic ..."
    echo
    cp ../templates/kafka-topic.yaml ../tmp/kafka-topic.yaml
    sed -i -e "s/mytopic/$KAFKA_TOPIC/" ../tmp/kafka-topic.yaml
    sed -i -e "s/mycluster/$KAFKA_CLUSTER_NAME/" ../tmp/kafka-topic.yaml
    sed -i -e "s/partitions:.*/partitions: $TOPIC_PARTITION_NUM/" ../tmp/kafka-topic.yaml
    sed -i -e "s/replicas:.*/replicas: $PARTITION_REPLICA_NUM/" ../tmp/kafka-topic.yaml
    oc apply -f ../tmp/kafka-topic.yaml -n $APPS_NAMESPACE
    echo
}

function configurePrometheus(){

    echo
    printHeader "--> Configure User Project Prometheus for Kafka ... "
    echo
    
    echo
    echo "Creating the cluster-monitoring-config configmap ... "
    echo
    oc apply -f ../templates/cluster-monitoring-config.yaml  -n openshift-monitoring

    echo
    echo "Configuring Prometheus related services for namespace '$APPS_NAMESPACE' ... "
    echo
    
    mkdir -p ../tmp
    cp ../templates/strimzi-pod-monitor.yaml ../tmp/strimzi-pod-monitor.yaml
    
    sed -i -e "s/myproject/$APPS_NAMESPACE/" ../tmp/strimzi-pod-monitor.yaml
    
    oc apply -f ../tmp/strimzi-pod-monitor.yaml  -n $APPS_NAMESPACE
    oc apply -f ../templates/prometheus-rules.yaml  -n $APPS_NAMESPACE
    
    
    echo
    echo "Configuring Grafana for kafka ... "
    echo
    cp ../templates/grafana-sa.yaml ../tmp/grafana-sa.yaml
    sed -i -e "s/myproject/$APPS_NAMESPACE/" ../tmp/grafana-sa.yaml
    oc apply -f ../tmp/grafana-sa.yaml -n $APPS_NAMESPACE
    GRAFANA_SA_TOKEN="$(oc serviceaccounts get-token grafana-serviceaccount -n $APPS_NAMESPACE)"
    cp ../templates/datasource.yaml ../tmp/datasource.yaml
    sed -i -e "s/GRAFANA-ACCESS-TOKEN/$GRAFANA_SA_TOKEN/" ../tmp/datasource.yaml
    oc create configmap grafana-config --from-file=../tmp/datasource.yaml -n $APPS_NAMESPACE
    oc apply -f ../templates/grafana.yaml -n $APPS_NAMESPACE
    oc create route edge grafana --service=grafana -n $APPS_NAMESPACE
    
    echo
    printHeader "Please refer to the following for guide on enabling the Grafana dashboard for Kafka ... "
    echo
    printLink "https://access.redhat.com/documentation/en-us/red_hat_amq/7.6/html-single/using_amq_streams_on_openshift/index#proc-metrics-grafana-dashboard-str"
    echo
}

# ----- Remove all tmp content after completed.
function removeTempDirs(){
    echo
    printHeader "--> Removing ../tmp directory ... "
    echo
    rm -rf ../tmp
}

# ----- read user inputs for installation parameters
function readInput(){
    INPUT_VALUE=""
    echo
    printHeader "Please provides the following parameter values. (Enter q to quit)"
    echo
    while [ "$INPUT_VALUE" != "q" ]
    do  
    
        printf "Namespace [$APPS_NAMESPACE]:"
        read INPUT_VALUE
        if [ "$INPUT_VALUE" != "" ] && [ "$INPUT_VALUE" != "q" ]; then
            APPS_NAMESPACE="$INPUT_VALUE"
        fi

        if [ "$INPUT_VALUE" = "q" ]; then
            removeTempDirs
            exit 0
        fi        

        INPUT_VALUE="q"
    done
}

# Check if a resource exist in OCP
check_resource() {
  local kind=$1
  local name=$2
  oc get $kind $name -o name >/dev/null 2>&1
  if [ $? != 0 ]; then
    echo "false"
  else
    echo "true"
  fi
}

function printCmdUsage(){
    echo 
    echo "This is the Kafka Sizing installer."
    echo
    echo "Command usage: ./deployKafka.sh <options>"
    echo 
    echo "-h            Show this help."
    echo "-i            Install the Kafka sizing environment."
    echo 
}

function printHelp(){
    printCmdUsage
    printHeader "The following is a quick list of the installer requirements:"
    echo
    echo "    * The required OpenShift projects are created."
    echo "    * keytool is installed on your system."
    echo "    * jq is installed on your system."
    echo "    * An Openshift user with cluster-admin role."
    echo "    * The following Operators are installed:"
    echo "      - Red Hat AMQ Streams"
    echo "      - Prometheus"
    echo
    printHeader "Refer to the following website for the complete and updated guide ..."
    echo
    printLink "https://github.com/chengkuangan/kafka-sizing"
    echo
}

function printResult(){
    echo 
    echo "=============================================================================================================="
    echo 
    printTitle "KAFKA SIZING ENVIRONMENT INSTALLATION COMPLETED !!!"
    echo
    echo "=============================================================================================================="
    echo
}

function processArguments(){

    if [ $# -eq 0 ]; then
        printCmdUsage
        exit 0
    fi

    while (( "$#" )); do
      if [ "$1" == "-h" ]; then
        printHelp
        exit 0
      # Proceed to install
      elif [ "$1" == "-i" ]; then
        PROCEED_INSTALL="yes"
        shift
      else
        echo "Unknown argument: $1"
        printCmdUsage
        exit 0
      fi
      shift
    done
}

function showConfirmToProceed(){
    echo
    printWarning "Press ENTER (OR Ctrl-C to cancel) to proceed..."
    read bc
}

processArguments $@
readInput
init
# -- preRequisitionCheck
printVariables

if [ "$PROCEED_INSTALL" != "yes" ]; then
    removeTempDirs
    exit 0
fi

showConfirmToProceed
deployKafka
configurePrometheus
createKafkaTopic
removeTempDirs
printResult