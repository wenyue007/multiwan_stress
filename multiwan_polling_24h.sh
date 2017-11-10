#!/bin/bash -
#Author: Jianwei Hu
#Date:2015/9/11
#Version: v0.4

#stability testing time, unit is minute
time=$1
time=${time:-1440}

#clean log file and restart multiwan service
echo "Restart multiwan service before running stability testing."
> /var/log/multiwan.log
systemctl restart multiwan

sleep 5
m_pid=`ps aux | grep "/usr/bin/multiwan"| grep -v grep |awk -F " " '{print $2}'`
s_pid=$$

#Setup before running stability testing
setup ()
{
    file="/etc/config/multiwan"
    sub_index=`cat $file | grep interface | awk -F "'" '{print $(NF-1)}'|wc -l`
    sub_index_t=$(($sub_index + 1))
    
    #fetch Interface from config file
    index=0
    all_nic=`cat $file | grep interface | awk -F "'" '{print $(NF-1)}'`
    for nic in $all_nic
    do
        Interface[$index]=$nic
        index=$(($index + 1 ))
    done
    
    #sum of all interval in config file
    sum=0
    all_interval=`cat $file | grep interval | awk -F "'" '{print $(NF-1)}'`
    for e_time in $all_interval
    do
        sum=$(($sum + $e_time))
    done
    
    #Up all Interfaces, even if already up 
    for j in ${Interface[@]}
    do
        echo "Uping $j"
        ifup $j
        gw_count=0
        expected_gw=`ifstatus $j| grep nexthop| awk -F'"' '{print $4}'`
        echo "waiting for $j's gateway..."
        while [ -z $expected_gw ]
        do 
            sleep 1
            expected_gw=`ifstatus $j| grep nexthop| awk -F'"' '{print $4}'`
            gw_count=$(($gw_count + 1 ))
            if [ $gw_count -ge 50 ];then echo "Can not obtion $j's gateway in preset-time(50s).";kill -9 $$; fi
        done
        echo "$j's gateway is $expected_gw"
    done
}

#generate the priority chain for interface
chain ()
{
    nics=`uci show multiwan| grep "=interface"| cut -d"=" -f 1|cut -d"." -f 2`
    Interface[0]=`uci show multiwan|grep priority|cut -d"=" -f 2`
    index=1

    for nic in $nics
    do
        if [ $nic == ${Interface[0]} ]; then
            continue
        fi
        Interface[$index]=$nic
        index=$(($index + 1 ))
    done
    
    c_index=1
    chain[0]=${Interface[0]}
    nic=${Interface[0]}
    
    while true
    do
        chain[$c_index]=`uci show multiwan | grep "\.${nic}\."| grep "failover_to"|cut -d"=" -f 2`
        if [ x${chain[$c_index]} == x${chain[0]} -o x${chain[$c_index]} == x"disable" -o x$nic == x${chain[$c_index]} ];then
           chain[$c_index]=
           nic=
           break
        fi
        nic=${chain[$c_index]}
        c_index=$(($c_index + 1 ))
    done
}

setup
chain
interval=$sum
f_count=0

#set priority for all interfaces
pri1=${chain[0]}
pri2=${chain[1]}
pri3=${chain[2]}

#guess the expected next default route
get_gw()
{
    unset pri1_gw
    unset pri2_gw
    unset pri3_gw
    unset expected_gw
    unset nic

    if [ $max == 0 ]; then 
        echo "No interface will be down this loop"
        expected_gw=`ifstatus $pri1| grep nexthop| awk -F'"' '{print $4}'`
    elif [ $max == 1 ]; then 
        nic=${Interface[$(($RANDOM%${sub_index}))]}
        echo "Downing $nic"
        ifdown $nic
        if [ x$nic == x$pri1 ];then
        pri2_gw=`ifstatus $pri2| grep nexthop| awk -F'"' '{print $4}'`
        pri3_gw=`ifstatus $pri3| grep nexthop| awk -F'"' '{print $4}'`
        elif [ x$nic == x$pri2 ];then
        pri1_gw=`ifstatus $pri1| grep nexthop| awk -F'"' '{print $4}'`
        pri3_gw=`ifstatus $pri3| grep nexthop| awk -F'"' '{print $4}'`
        elif [ x$nic == x$pri3 ];then
        pri1_gw=`ifstatus $pri1| grep nexthop| awk -F'"' '{print $4}'`
        pri2_gw=`ifstatus $pri2| grep nexthop| awk -F'"' '{print $4}'`
        fi

        if [ -n "$pri1_gw" ]; then
            expected_gw=$pri1_gw
        elif [ -n "$pri2_gw" ]; then
            expected_gw=$pri2_gw
        elif [ -n "$pri3_gw" ]; then
            expected_gw=$pri3_gw
        fi
    elif [ $max == 2 ]; then
        nic1=${Interface[$(($RANDOM%${sub_index}))]}
        nic2=${Interface[$(($RANDOM%${sub_index}))]}
        while [ $nic1 == $nic2 ];
        do
            nic2=${Interface[$(($RANDOM%${sub_index}))]}
        done
        echo "Downing $nic1"
        ifdown $nic1 
        echo "Downing $nic2"
        ifdown $nic2 
        for l_nic in ${Interface[@]}
        do
           if [ $l_nic != $nic1 -a $l_nic != $nic2 ]; then
              expected_gw=`ifstatus $l_nic| grep nexthop| awk -F'"' '{print $4}'`
           fi
        done
    elif [ $max == 3 ]; then
        echo "All interface down, expected_gw is null"
        for e_nic in ${Interface[@]}
        do
            echo "Downing $e_nic"
            ifdown $e_nic
        done
        expected_gw=
    fi

    if [ -z $expected_gw ];then
        echo "Expected gateway is NULL"
    else
        echo "Expected gateway is $expected_gw"
    fi
}

#Check whether the default gateway is equal to expected gw.
check_gw()
{
    #calculate the migration time
    time1=`date +%s%N`
    real_gw=`route -n | grep "^0.0.0.0"| awk -F' ' '{print $2}'`
    time2=`date +%s%N`
    time4=$(($(($time2 - $time1))/1000000))
    while [ x$real_gw != x$expected_gw ]
    do 
        date
        sleep 1
        #echo "$real_gw is not equal to real $expected_gw in this loop."
        real_gw=`route -n | grep "^0.0.0.0"| awk -F' ' '{print $2}'`
        time2=`date +%s%N`
        time4=$(($(($time2 - $time1))/1000000))
        if [ $(($time4/1000)) -ge $interval ];then 
	    echo -e "\033[31mWarning, maybe expected $expected_gw is not equal to real $real_gw in $time4 ms.\033[0m"
            f_count=$(($f_count + 1 ))
            break
        fi
    done

    if [ $f_count -ge 20 ];then echo "Break, more than threshold value 20 times.";break; fi

    if [ -z $expected_gw ];then
        if [ x$real_gw == x$expected_gw ]; then
            echo "Passed in $time4 ms, Default gateway and expected gateway are NULL."
        else
            echo "Failed in $time4 ms, default gateway is $real_gw, expected gateway is NULL"
            break
        fi
    else
        if [ x$real_gw == x$expected_gw ]; then
            echo "Default gateway is $real_gw"
            echo "Passed in $time4 ms, $expected_gw is equal to real $real_gw."
        else
            if [ -z $real_gw ];then
                echo "Failed in $time4 ms, default gateway is NULL, expected gateway is $expected_gw"
            else
                echo "Failed in $time4 ms, $expected_gw is not equal to real $real_gw."
            fi
            break
        fi
    fi
}

#recovery the interfaces before next loop
recovery_nic()
{
    for nic in ${Interface[@]}
    do
        #echo "Checking $nic's status..."
        ifstatus $nic | grep "\"up\"" | grep true > /dev/null
        if [ $? -eq 0 ]; then 
            echo "$nic already up"
        else
            echo "Uping $nic"
            ifup $nic
        fi
        gw_count=0
        expected_gw=`ifstatus $nic| grep nexthop| awk -F'"' '{print $4}'`
        echo "waiting for $nic's gateway..."
        while [ -z $expected_gw ]
        do 
            sleep 1
            expected_gw=`ifstatus $nic| grep nexthop| awk -F'"' '{print $4}'`
            gw_count=$(($gw_count + 1 ))
        if [ $gw_count -ge 50 ];then echo "Can not obtion $nic's gateway in preset-time(50s).";kill -9 $$; fi
        done
        echo "$nic's gateway is $expected_gw"
    done

}

start_time=`date +%s`
end_time=0

#main process for running stability testing
while [ $end_time -le $time ]
do
    echo "++++++++++++++++++++++++++++++Elapsed $end_time minutes++++++++++++++++++++++++++++++"
    ps up $m_pid
    ps up $s_pid
    free -m
    echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
  
    unset max
    date
    date1=`date +%s%N`
    route -n
    max=$(($RANDOM%${sub_index_t}))
    echo "$max interface(s) will be down..." 
    get_gw
    date2=`date +%s%N`
    date3=$(($date2-$date1))
    echo "Extra elapsed time is $(($date3/1000000)) ms!!!"

    date 
    check_gw
    date
    route -n

    recovery_nic
    route -n
    date
   
    expected_gw=`ifstatus $pri1| grep nexthop| awk -F'"' '{print $4}'`
    check_gw
    
    end_time=`date +%s`
    end_time=$(($end_time - $start_time))
    end_time=$(($end_time / 60 ))
done

#Finish the script
echo "<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>"
if [ $time -lt $end_time ]; then
    echo "Done!!!"
else
    echo "Failed!!!"
    sleep 60
    echo "sleep 60 seconds"
    route -n
    echo "stop multiwan service"
    systemctl stop multiwan
fi
recovery_nic
echo "<><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><>"

