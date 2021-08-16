# For non-root users... This is redundant if you're already sshing through root.
function prepareRun() {
    for ip in "${ServerIps[@]}"
    do
        ssh -o StrictHostKeyChecking=no -i ${SSHKey} root@"$ip" "mkdir -p ${LogFolder}; rm -rf ${LogFolder}/*; cd ${EPaxosFolder} && chmod 777 runPaxos.sh" 2>&1
        sleep 0.3
    done
    for ip in "${ClientIps[@]}"
    do
        ssh -o StrictHostKeyChecking=no -i ${SSHKey} root@"$ip" "mkdir -p ${LogFolder}; rm -rf ${LogFolder}/*; cd ${EPaxosFolder} && chmod 777 runPaxos.sh" 2>&1
        sleep 0.3
    done
    wait
}

function runMaster() {
    "${EPaxosFolder}"/bin/master -N ${NumOfServerInstances} 2>&1 &
}

function runServersOneMachine() {
    for idx in $(seq 0 $(($NumOfServerInstances - 1)))
    do
        svrIpIdx=$((idx % ${#ServerIps[@]}))
        svrIp=${ServerIps[svrIpIdx]}
        svrPort=$((FirstServerPort + $idx))
        if [[ ${svrIpIdx} -eq ${EPMachineIdx} ]]
        then
            "${EPaxosFolder}"/bin/server -port ${svrPort} -maddr ${MasterIp} -addr ${svrIp} -p 4 -thrifty=${thrifty} 2>&1 &
        fi
    done
}

function runClientsOneMachine() {
    ulimit -n 65536
    mkdir -p ${LogFolder}
    for idx in $(seq 0 $((NumOfClientInstances - 1)))
    do
        cliIpIdx=$((idx % ${#ClientIps[@]}))
        cliIp=${ClientIps[cliIpIdx]}
        if [[ ${cliIpIdx} -eq ${EPMachineIdx} ]]
        then
            "${EPaxosFolder}"/bin/client -maddr ${MasterIp} -q ${reqsNb} -w ${writes} -r ${rounds} -p 30 -c ${conflicts} > ${LogFolder}/S${NumOfServerInstances}-C${NumOfClientInstances}-q${reqsNb}-w${writes}-r${rounds}-c${conflicts}--client${idx}.out 2>&1 &
        fi
    done
}

function runServersAllMachines() {
    runMaster
    sleep 2

    MachineIdx=0
    for ip in "${ServerIps[@]}"
    do
        ssh -o StrictHostKeyChecking=no -i ${SSHKey} root@"$ip" "cd ${EPaxosFolder} && EPScriptOption=StartServers EPMachineIdx=${MachineIdx} /bin/bash runPaxos.sh" 2>&1 &
        sleep 0.3
        ((MachineIdx++))
    done
}

function runClientsAllMachines() {
    MachineIdx=0
    for ip in "${ClientIps[@]}"
    do
        ssh -o StrictHostKeyChecking=no -i ${SSHKey} root@"$ip" "cd ${EPaxosFolder} && EPScriptOption=StartClients EPMachineIdx=${MachineIdx} /bin/bash runPaxos.sh" 2>&1 &
        sleep 0.3
        ((MachineIdx++))
    done
}

function runServersAndClientsAllMachines() {
    runServersAllMachines
    sleep 5 # TODO(highlight): add wait time here
    runClientsAllMachines
}

function SendEPaxosFolder() {
    for ip in "${ServerIps[@]}"
    do
        scp -o StrictHostKeyChecking=no -i ${SSHKey} -r ${EPaxosFolder} root@"$ip":~  2>&1 &
        sleep 0.3
    done
    for ip in "${ClientIps[@]}"
    do
        scp -o StrictHostKeyChecking=no -i ${SSHKey} -r ${EPaxosFolder} root@"$ip":~  2>&1 &
        sleep 0.3
    done
    wait
}

function SSHCheckClientProgress() {
    for ip in "${ClientIps[@]}"
    do
        ssh -o StrictHostKeyChecking=no -i ${SSHKey} root@"$ip" "ps -fe | grep bin/client" 2>&1 &
    done
}

function EpKillAll() {
    for ip in "${ServerIps[@]}"
    do
        ssh -o StrictHostKeyChecking=no -i ${SSHKey} root@"$ip" "cd ${EPaxosFolder} && chmod 777 kill.sh && /bin/bash kill.sh" 2>&1 &
        sleep 0.3
    done
    for ip in "${ClientIps[@]}"
    do
        ssh -o StrictHostKeyChecking=no -i ${SSHKey} root@"$ip" "cd ${EPaxosFolder} && chmod 777 kill.sh && /bin/bash kill.sh" 2>&1 &
        sleep 0.3
    done
    wait
}

function DownloadLogs() {
    mkdir -p ${LogFolder}

#    for ip in "${ServerIps[@]}"
#    do
#        scp -o StrictHostKeyChecking=no -i ${SSHKey} root@"$ip":${LogFolder}/*.out ${LogFolder} 2>&1 &
#        sleep 0.3
#    done

    for ip in "${ClientIps[@]}"
    do
        scp -o StrictHostKeyChecking=no -i ${SSHKey} root@"$ip":${LogFolder}/*.out ${LogFolder} 2>&1 &
        sleep 0.3
    done
    wait
}

function RemoveLogs(){
  for ip in "${ClientIps[@]}"
  do
        ssh -o StrictHostKeyChecking=no -i ${SSHKey} root@"$ip" "rm -rf ${LogFolder}/*" 2>&1 &
        sleep 0.3
  done

  for ip in "${ServerIps[@]}"
  do
        ssh -o StrictHostKeyChecking=no -i ${SSHKey} root@"$ip" "rm -rf ${LogFolder}/*" 2>&1 &
        sleep 0.3
  done
}

function Analysis() {
    sleep 3
#    cat ${LogFolder}/*.out  # for visual inspection
    python3.8 analysis_paxos.py ${LogFolder} print-title
}

function Main() {
    case ${EPScriptOption} in
        "StartServers")
            runServersOneMachine
            ;;
        "StartClients")
            runClientsOneMachine
            ;;
        "killall")
            EpKillAll
            ;;
        *)
            runServersAndClientsAllMachines
            ;;
    esac
    wait
}

function runOnce() {
  if [ $# -ne 0 ]; then # if there's a profile passed in
    . ${1}              # load it
  fi

  if [ $? -ne 0 ]; then # if there's an error
    return 1            # early exit
  fi

  Main
  DownloadLogs
  EpKillAll
}

ProfilesToRun=(~/go/src/epaxos/profile0.sh ~/go/src/epaxos/profile1.sh ~/go/src/epaxos/profile2.sh ~/go/src/epaxos/profile3.sh ~/go/src/epaxos/profile4.sh ~/go/src/epaxos/profile5.sh ~/go/src/epaxos/profile6.sh ~/go/src/epaxos/profile7.sh ~/go/src/epaxos/profile8.sh)

function runMultiple() {
  for profile in ${ProfilesToRun[@]}
  do
    runOnce $profile
    wait
  done
}

#RemoveLogs
#runOnce ~/go/src/epaxos/profile0.sh
runMultiple

