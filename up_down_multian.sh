#!/bin/bash
pri_port="wan"
next_port="wlan"

function print_msg {
    echo
    echo "=> $1"
}

function wifi_up {
    print_msg "wlan UP" 
    ifup wlan
}

function wifi_down {
    print_msg "wlan DOWN"
    ifdown wlan
}

function eth_up {
    print_msg "wan UP"
    ifup wan
}

function eth_down {
    print_msg "wan DOWN"
    ifdown wan
}

checking_gateway()
{
    nic=$1
    nics=`uci show multiwan| grep "=interface"| cut -d"=" -f 1|cut -d"." -f 2`
    for nic in $nics
    do
        active_nic=""
        ifstatus $nic | grep -w "\"up\"" | grep "true" &> /dev/null
        if [ $? = 0 ]; then
            if [ X"$pri_port" = X"$nic" ]; then
                active_nic=$nic
                break       
            elif [ X"$next_port" = X"$nic" ];then
                active_nic=$nic
            fi
        else
    #        if [ X"$pri_port" = X"$nic" ]; then
    #            next_port=`uci show multiwan| grep "=interface"| cut -d"=" -f 1|cut -d"." -f 2|grep -v $nic|head -1` 
    #        fi
            continue
        fi
    done
    [ -z "$nic" ] && nic=$active_nic
    echo "route -n"
    route -n 
    real_gw=`route -n | grep "^0.0.0.0"| awk -F' ' '{print $2}'`
    expected_gw=`ifstatus $nic| grep nexthop| awk -F'"' '{print $4}'`
    if [ -z "$real_gw" ];then
        echo "Warning:No default route found"
        echo "DEBUG++++++++START"
        echo "ifstaus wan"
        ifstatus wan
        echo "++++++++"
        echo "ifstatus wlan"
        ifstatus wlan
        echo "++++++++"
        echo "systemctl status netifd"
        systemctl status netifd -l
        echo "++++++++"
        echo "systemctl status multiwan"
        systemctl status multiwan -l
        echo "DEBUG++++++++END"
        break
    elif [ -z "$expected_gw" ];then
        echo "Warning: No expected gateway on $nic"
    else
        if [ X"$real_gw" == X"$expected_gw" ];then
            echo "Good gateway for $nic"
        else
            echo "Bad gateway for $nic,multiwan service did not update it?!?"
            break
        fi
    fi

}
function net_status {
    print_msg "STATUS"
    print_msg "sleep for $1 seconds..."
    sleep $1
    route -n
    ping -c 4 8.8.8.8
}

function clear_log {
    echo > /var/log/multiwan.log
}

time=15

clear_log
net_status 0

loop_n=1
while true
do
     echo "***************$loop_n*******************"
     eth_up
     net_status $time
     checking_gateway
     
     eth_down
     net_status $time
     checking_gateway

     wifi_up
     net_status $time
     checking_gateway
     
     wifi_down
     net_status $time
     checking_gateway
     let loop_n+=1
done

print_msg "Done."
